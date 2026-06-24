import Foundation

enum SourceRegistryMode: Equatable {
    case automatic
    case manual(PaperSourceID)
}

final class SourceRegistry {
    static let automaticOrder: [PaperSourceID] = [.frankcie, .easyPaper, .pastPapers, .papaCambridge]

    private let sources: [PaperSourceID: any PaperSource]
    private let automaticOrder: [PaperSourceID]
    private let nowProvider: @Sendable () -> Date
    private let automaticAttemptTimeout: TimeInterval?

    init(
        sources: [any PaperSource] = [
            FrankcieSource(),
            PapaCambridgeSource(),
            PastPapersSource(),
            EasyPaperSource()
        ],
        automaticOrder: [PaperSourceID] = SourceRegistry.automaticOrder,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        automaticAttemptTimeout: TimeInterval? = 12
    ) {
        self.sources = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        self.automaticOrder = automaticOrder
        self.nowProvider = nowProvider
        self.automaticAttemptTimeout = automaticAttemptTimeout
    }

    func source(for sourceID: PaperSourceID) -> (any PaperSource)? {
        sources[sourceID]
    }

    func fetchSubjects(mode: SourceRegistryMode = .automatic) async throws -> [Subject] {
        switch mode {
        case .automatic:
            var attempts: [SourceAttempt] = []
            for sourceID in automaticOrder {
                guard let source = sources[sourceID] else { continue }
                let startedAt = nowProvider()
                do {
                    let subjects = try await runAutomaticAttempt(
                        sourceID: sourceID,
                        operationLabel: "科目列表加载"
                    ) {
                        try await source.fetchSubjects()
                    }
                    attempts.append(
                        .success(
                            sourceID,
                            count: subjects.count,
                            durationMilliseconds: elapsedMilliseconds(since: startedAt)
                        )
                    )
                    if !subjects.isEmpty {
                        return SubjectNormalizer.deduplicate(subjects)
                    }
                } catch {
                    attempts.append(
                        .failure(
                            sourceID,
                            error: error,
                            durationMilliseconds: elapsedMilliseconds(since: startedAt)
                        )
                    )
                }
            }
            throw PaperSourceError.allSourcesUnavailable(attempts)
        case let .manual(sourceID):
            guard let source = sources[sourceID] else {
                throw PaperSourceError.unsupportedSource(sourceID)
            }
            let subjects = try await source.fetchSubjects()
            guard !subjects.isEmpty else {
                throw PaperSourceError.sourceUnavailable("\(sourceID.title) 暂不可用或没有暴露科目目录")
            }
            return SubjectNormalizer.deduplicate(subjects)
        }
    }

    func search(_ query: PaperSourceQuery, mode: SourceRegistryMode = .automatic) async throws -> SourceSearchResult {
        switch mode {
        case .automatic:
            return try await searchAutomatically(query)
        case let .manual(sourceID):
            guard let source = sources[sourceID] else {
                throw PaperSourceError.unsupportedSource(sourceID)
            }
            let startedAt = nowProvider()
            var result = try await source.search(query)
            guard !result.components.isEmpty else {
                throw PaperSourceError.sourceUnavailable("\(sourceID.title) 暂不可用或没有暴露可下载试卷；该数据源需要重新适配")
            }
            result.attempts = [
                .success(
                    sourceID,
                    count: result.components.count,
                    durationMilliseconds: elapsedMilliseconds(since: startedAt)
                )
            ]
            return result
        }
    }

    private func searchAutomatically(_ query: PaperSourceQuery) async throws -> SourceSearchResult {
        var attempts: [SourceAttempt] = []

        for sourceID in automaticOrder {
            guard let source = sources[sourceID] else { continue }
            let startedAt = nowProvider()

            do {
                var result = try await runAutomaticAttempt(
                    sourceID: sourceID,
                    operationLabel: "搜索"
                ) {
                    try await source.search(query)
                }
                attempts.append(
                    .success(
                        sourceID,
                        count: result.components.count,
                        durationMilliseconds: elapsedMilliseconds(since: startedAt)
                    )
                )
                if !result.components.isEmpty {
                    result.attempts = attempts
                    return result
                }
            } catch {
                attempts.append(
                    .failure(
                        sourceID,
                        error: error,
                        durationMilliseconds: elapsedMilliseconds(since: startedAt)
                    )
                )
            }
        }

        throw PaperSourceError.allSourcesUnavailable(attempts)
    }

    private func elapsedMilliseconds(since start: Date) -> Int {
        max(0, Int(nowProvider().timeIntervalSince(start) * 1000))
    }

    private func runAutomaticAttempt<T: Sendable>(
        sourceID: PaperSourceID,
        operationLabel: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard let automaticAttemptTimeout else {
            return try await operation()
        }
        let timeoutNanoseconds = timeoutNanoseconds(for: automaticAttemptTimeout)
        let timeoutDescription = formattedTimeoutDescription(automaticAttemptTimeout)

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw PaperSourceError.sourceUnavailable(
                    "\(operationLabel)超时（超过 \(timeoutDescription)）"
                )
            }

            do {
                let result = try await group.next()
                group.cancelAll()
                guard let result else {
                    throw PaperSourceError.sourceUnavailable("\(operationLabel)失败")
                }
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func timeoutNanoseconds(for timeout: TimeInterval) -> UInt64 {
        guard timeout.isFinite, timeout > 0 else { return 0 }
        let nanoseconds = timeout * 1_000_000_000
        if nanoseconds >= Double(UInt64.max) {
            return UInt64.max
        }
        return UInt64(nanoseconds.rounded(.towardZero))
    }

    private func formattedTimeoutDescription(_ timeout: TimeInterval) -> String {
        if timeout.rounded(.towardZero) == timeout {
            return "\(Int(timeout)) 秒"
        }
        return String(format: "%.1f 秒", timeout)
    }
}
