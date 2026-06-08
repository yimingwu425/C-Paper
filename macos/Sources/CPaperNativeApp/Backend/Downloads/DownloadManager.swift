import Foundation

typealias DownloadWriter = @Sendable (_ sourceURL: URL, _ partialURL: URL) async throws -> Void
typealias SharedTransferWriter = @Sendable (
    _ sourceURL: URL,
    _ partialURL: URL,
    _ proxyURL: String,
    _ progress: @escaping FileTransferProgressHandler
) async throws -> Void
typealias DownloadCompletionRecorder = @Sendable (_ task: DownloadDestinationTask) async -> Void

actor DownloadManager {
    private let clock = ContinuousClock()
    private var queue = DownloadQueue<Int>()
    private var workItems: [Int: DownloadDestinationTask] = [:]
    private var downloadItems: [Int: DownloadTaskItem] = [:]
    private var nextAllowedRequestAt: ContinuousClock.Instant?
    private var requestGateRevision = 0
    private var snapshot = DownloadStatusSnapshot(
        phase: "idle",
        done: 0,
        total: 0,
        success: 0,
        message: "Ready",
        failed: nil,
        cancelled: nil,
        skipped: nil
    )
    private var isCancelled = false
    private var runID = 0
    private var runnerTask: Task<Void, Never>?
    private let download: DownloadWriter?
    private let sharedTransfer: SharedTransferWriter
    private let completionRecorder: DownloadCompletionRecorder
    private let fileManager: FileManager
    private let circuitBreakerRecoveryTimeout: Duration
    private let defaultRateLimitCooldown: Duration
    private let minimumRateLimitCooldown: Duration
    private let maximumRateLimitCooldown: Duration
    private let maxRetries = 3

    init(
        download: DownloadWriter? = nil,
        sharedTransfer: @escaping SharedTransferWriter = DownloadManager.defaultDownload,
        completionRecorder: @escaping DownloadCompletionRecorder = { _ in },
        fileManager: FileManager = .default,
        circuitBreakerRecoveryTimeout: Duration = .seconds(30),
        defaultRateLimitCooldown: Duration = .seconds(30),
        minimumRateLimitCooldown: Duration = .seconds(5),
        maximumRateLimitCooldown: Duration = .seconds(120)
    ) {
        self.download = download
        self.sharedTransfer = sharedTransfer
        self.completionRecorder = completionRecorder
        self.fileManager = fileManager
        self.circuitBreakerRecoveryTimeout = circuitBreakerRecoveryTimeout

        let normalizedMinimum = max(.zero, minimumRateLimitCooldown)
        let normalizedMaximum = max(normalizedMinimum, maximumRateLimitCooldown)
        self.minimumRateLimitCooldown = normalizedMinimum
        self.maximumRateLimitCooldown = normalizedMaximum
        self.defaultRateLimitCooldown = min(max(defaultRateLimitCooldown, normalizedMinimum), normalizedMaximum)
    }

    @discardableResult
    func start(
        groups: [NativePaperGroup],
        saveDirectory: URL,
        options: DownloadOptions,
        downloadedFilenames: Set<String> = [],
        proxyURL: String = ""
    ) throws -> DownloadStartResult {
        runnerTask?.cancel()
        runID += 1
        let currentRunID = runID
        isCancelled = false
        queue.removeAll()
        workItems.removeAll()
        downloadItems.removeAll()
        nextAllowedRequestAt = nil
        requestGateRevision = 0

        let plan = try DownloadDestinationBuilder.build(
            groups: groups,
            saveDirectory: saveDirectory,
            options: options,
            downloadedFilenames: downloadedFilenames,
            fileManager: fileManager
        )

        for task in plan.tasks {
            workItems[task.id] = task
            downloadItems[task.id] = task.displayItem
            queue.enqueue(task.id)
        }

        snapshot = DownloadStatusSnapshot(
            phase: plan.tasks.isEmpty ? "done" : "running",
            done: 0,
            total: plan.tasks.count,
            success: 0,
            message: plan.tasks.isEmpty ? "完成 (0/0 成功)" : "准备下载...",
            failed: 0,
            cancelled: 0,
            skipped: plan.skipped
        )

        if !plan.tasks.isEmpty {
            let workers = max(1, min(options.threads, 16))
            let rateLimiter = RateLimiter(rate: max(1, min(options.rate, 20)))
            let circuitBreaker = CircuitBreaker(recoveryTimeout: circuitBreakerRecoveryTimeout)
            runnerTask = Task { [weak self] in
                await self?.run(
                    workers: workers,
                    runID: currentRunID,
                    proxyURL: proxyURL,
                    rateLimiter: rateLimiter,
                    circuitBreaker: circuitBreaker
                )
            }
        }

        return DownloadStartResult(ok: true, total: plan.tasks.count, skipped: plan.skipped)
    }

    func status() -> DownloadStatusSnapshot {
        snapshot
    }

    func items() -> [DownloadTaskItem] {
        downloadItems.values.sorted { $0.id < $1.id }
    }

    func cancel() {
        guard snapshot.phase == "running" else { return }
        let cancelledRunID = runID
        isCancelled = true
        runnerTask?.cancel()
        runnerTask = nil
        queue.removeAll()
        nextAllowedRequestAt = nil
        requestGateRevision = 0

        for item in downloadItems.values where item.status == .pending || item.status == .downloading {
            setStatus(id: item.id, status: .cancelled, error: "用户取消", errorType: "cancelled")
        }
        updateProgress(message: "已取消")
        snapshot = DownloadStatusSnapshot(
            phase: "done",
            done: snapshot.done,
            total: snapshot.total,
            success: snapshot.success,
            message: "已取消",
            failed: snapshot.failed,
            cancelled: snapshot.cancelled,
            skipped: snapshot.skipped
        )
        if runID == cancelledRunID {
            runID += 1
        }
    }

    private func run(
        workers: Int,
        runID: Int,
        proxyURL: String,
        rateLimiter: RateLimiter,
        circuitBreaker: CircuitBreaker
    ) async {
        var retryRound = 0

        while isActive(runID) && !isCancelled {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<workers {
                    group.addTask { [weak self] in
                        await self?.workerLoop(
                            runID: runID,
                            proxyURL: proxyURL,
                            rateLimiter: rateLimiter,
                            circuitBreaker: circuitBreaker
                        )
                    }
                }
            }

            guard isActive(runID) else {
                return
            }

            if isCancelled || Task.isCancelled {
                return
            }

            let failed = downloadItems.values
                .filter { $0.status == .failed }
                .sorted { $0.id < $1.id }

            if !failed.isEmpty && retryRound < maxRetries {
                retryRound += 1
                if let retryDelay = await circuitBreaker.retryDelayBeforeNextRequest() {
                    updateProgress(runID: runID, message: "熔断器恢复中，等待后重试...")
                    do {
                        try await Task.sleep(for: retryDelay)
                    } catch {
                        return
                    }
                }
                for item in failed {
                    setStatus(runID: runID, id: item.id, status: .pending, error: "", errorType: "")
                    queue.enqueue(item.id)
                }
                updateProgress(runID: runID, message: "\(failed.count) 个失败任务自动重试 (第 \(retryRound) 轮)")
                continue
            }

            let counts = counts()
            snapshot = DownloadStatusSnapshot(
                phase: "done",
                done: counts.completed,
                total: snapshot.total,
                success: counts.done,
                message: completionMessage(success: counts.done, total: snapshot.total, retryRound: retryRound),
                failed: counts.failed,
                cancelled: counts.cancelled,
                skipped: snapshot.skipped
            )
            return
        }
    }

    private func workerLoop(
        runID: Int,
        proxyURL: String,
        rateLimiter: RateLimiter,
        circuitBreaker: CircuitBreaker
    ) async {
        while !Task.isCancelled {
            guard await waitForSafeRequestInstant(runID: runID, circuitBreaker: circuitBreaker) else {
                return
            }
            guard isActive(runID), !isCancelled, let id = queue.dequeue(), let task = workItems[id] else {
                return
            }
            await download(
                task,
                runID: runID,
                proxyURL: proxyURL,
                rateLimiter: rateLimiter,
                circuitBreaker: circuitBreaker
            )
            updateProgress(runID: runID, message: "下载中... (\(snapshot.done)/\(snapshot.total))")
        }
    }

    private func download(
        _ task: DownloadDestinationTask,
        runID: Int,
        proxyURL: String,
        rateLimiter: RateLimiter,
        circuitBreaker: CircuitBreaker
    ) async {
        guard await waitForSafeRequestInstant(runID: runID, circuitBreaker: circuitBreaker) else {
            return
        }

        do {
            try await circuitBreaker.allowRequest()
            let gateRevision = requestGateRevision
            try await rateLimiter.acquire()
            try Task.checkCancellation()
            if gateRevision != requestGateRevision {
                guard await waitForSafeRequestInstant(runID: runID, circuitBreaker: circuitBreaker) else {
                    return
                }
            }
            setStatus(runID: runID, id: task.id, status: .downloading, error: "", errorType: "")
            try fileManager.createDirectory(at: task.saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            let partialURL = task.saveURL.deletingLastPathComponent()
                .appendingPathComponent("\(task.saveURL.lastPathComponent).part.\(UUID().uuidString)")
            defer {
                try? fileManager.removeItem(at: partialURL)
            }

            let sourceURL = try DownloadSourceURLResolver.resolvedSourceURL(for: task.component)
            if let download {
                try await download(sourceURL, partialURL)
            } else {
                try await sharedTransfer(sourceURL, partialURL, proxyURL) { [taskID = task.id] progress in
                    await self.updateTransferProgress(runID: runID, id: taskID, progress: progress)
                }
            }
            try Task.checkCancellation()
            try ensureActive(runID)
            try atomicReplace(partialURL: partialURL, destinationURL: task.saveURL)
            try ensureActive(runID)
            await circuitBreaker.recordSuccess()
            setStatus(runID: runID, id: task.id, status: .done, error: "", errorType: "")
            if isActive(runID) {
                await completionRecorder(task)
            }
        } catch is CancellationError {
            setStatus(runID: runID, id: task.id, status: .cancelled, error: "用户取消", errorType: "cancelled")
        } catch CircuitBreakerError.open {
            await circuitBreaker.recordFailure()
            setStatus(
                runID: runID,
                id: task.id,
                status: .failed,
                error: CircuitBreakerError.open.localizedDescription,
                errorType: "rate_limit"
            )
        } catch {
            if case let NetworkClientError.rateLimited(_, retryAfter) = error {
                updateRateLimitCooldown(retryAfter: retryAfter)
            }
            await circuitBreaker.recordFailure()
            setStatus(
                runID: runID,
                id: task.id,
                status: .failed,
                error: error.localizedDescription,
                errorType: errorType(for: error)
            )
        }
    }

    private func atomicReplace(partialURL: URL, destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: partialURL)
        } else {
            try fileManager.moveItem(at: partialURL, to: destinationURL)
        }
    }

    private func setStatus(runID: Int? = nil, id: Int, status: DownloadStatus, error: String, errorType: String) {
        if let runID, !isActive(runID) {
            return
        }
        guard let current = downloadItems[id] else { return }
        let progressFraction: Double? = switch status {
        case .downloading:
            current.progressFraction
        case .done:
            1
        case .pending, .failed, .cancelled, .skipped:
            nil
        }
        downloadItems[id] = DownloadTaskItem(
            id: current.id,
            filename: current.filename,
            ftype: current.ftype,
            label: current.label,
            year: current.year,
            savePath: current.savePath,
            status: status,
            error: error,
            errorType: errorType,
            progressFraction: progressFraction
        )
    }

    private func updateTransferProgress(runID: Int, id: Int, progress: Double?) {
        guard isActive(runID), let current = downloadItems[id], current.status == .downloading else {
            return
        }

        downloadItems[id] = DownloadTaskItem(
            id: current.id,
            filename: current.filename,
            ftype: current.ftype,
            label: current.label,
            year: current.year,
            savePath: current.savePath,
            status: current.status,
            error: current.error,
            errorType: current.errorType,
            progressFraction: progress
        )
    }

    private func updateProgress(runID: Int? = nil, message: String) {
        if let runID, !isActive(runID) {
            return
        }
        let counts = counts()
        snapshot = DownloadStatusSnapshot(
            phase: snapshot.phase,
            done: counts.completed,
            total: snapshot.total,
            success: counts.done,
            message: message,
            failed: counts.failed,
            cancelled: counts.cancelled,
            skipped: snapshot.skipped
        )
    }

    private func isActive(_ runID: Int) -> Bool {
        self.runID == runID
    }

    private func ensureActive(_ runID: Int) throws {
        guard isActive(runID) else {
            throw CancellationError()
        }
    }

    private func counts() -> (done: Int, failed: Int, cancelled: Int, skipped: Int, completed: Int) {
        let values = downloadItems.values
        let done = values.filter { $0.status == .done }.count
        let failed = values.filter { $0.status == .failed }.count
        let cancelled = values.filter { $0.status == .cancelled }.count
        let skipped = values.filter { $0.status == .skipped }.count
        return (done, failed, cancelled, skipped, done + failed + cancelled + skipped)
    }

    private func completionMessage(success: Int, total: Int, retryRound: Int) -> String {
        var message = "完成 (\(success)/\(total) 成功)"
        if retryRound > 0 {
            message += " (经过 \(retryRound) 轮重试)"
        }
        return message
    }

    private func errorType(for error: Error) -> String {
        if error is CircuitBreakerError {
            return "rate_limit"
        }
        if case NetworkClientError.rateLimited = error {
            return "rate_limit"
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "network"
        }
        return "unknown"
    }

    private func waitForSafeRequestInstant(runID: Int, circuitBreaker: CircuitBreaker) async -> Bool {
        while isActive(runID), !isCancelled, !Task.isCancelled {
            let cooldownDelay = rateLimitDelay()
            let circuitBreakerDelay = await circuitBreaker.retryDelayBeforeNextRequest()
            let waitDelay = max(cooldownDelay ?? .zero, circuitBreakerDelay ?? .zero)

            guard waitDelay > .zero else {
                return isActive(runID) && !isCancelled && !Task.isCancelled
            }

            let message = cooldownDelay != nil
                ? "服务器限流，等待后自动重试..."
                : "熔断器恢复中，等待后重试..."
            updateProgress(runID: runID, message: message)

            do {
                try await clock.sleep(for: waitDelay)
            } catch {
                return false
            }
        }

        return false
    }

    private func rateLimitDelay() -> Duration? {
        guard let nextAllowedRequestAt else {
            return nil
        }

        let now = clock.now
        guard nextAllowedRequestAt > now else {
            self.nextAllowedRequestAt = nil
            return nil
        }

        return now.duration(to: nextAllowedRequestAt)
    }

    private func updateRateLimitCooldown(retryAfter: TimeInterval?) {
        let requestedCooldown = retryAfter.map(Self.duration(from:)) ?? defaultRateLimitCooldown
        let cooldown = min(max(requestedCooldown, minimumRateLimitCooldown), maximumRateLimitCooldown)
        let nextAllowed = clock.now.advanced(by: cooldown)

        if let current = nextAllowedRequestAt, current > nextAllowed {
            return
        }
        nextAllowedRequestAt = nextAllowed
        requestGateRevision += 1
    }

    private static func duration(from seconds: TimeInterval) -> Duration {
        .nanoseconds(Int64((seconds * 1_000_000_000).rounded()))
    }

    private static func defaultDownload(
        sourceURL: URL,
        partialURL: URL,
        proxyURL: String,
        progress: @escaping FileTransferProgressHandler
    ) async throws {
        let client = HTTPFileTransferClient(proxy: ProxyConfiguration(rawValue: proxyURL))
        try await client.transfer(from: sourceURL, to: partialURL, progress: progress)
    }
}
