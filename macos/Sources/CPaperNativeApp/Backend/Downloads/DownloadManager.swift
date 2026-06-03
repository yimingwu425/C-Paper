import Foundation

typealias DownloadWriter = @Sendable (_ sourceURL: URL, _ partialURL: URL) async throws -> Void

actor DownloadManager {
    private var queue = DownloadQueue<Int>()
    private var workItems: [Int: DownloadDestinationTask] = [:]
    private var downloadItems: [Int: DownloadTaskItem] = [:]
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
    private var runnerTask: Task<Void, Never>?
    private var rateLimiter: RateLimiter
    private var circuitBreaker: CircuitBreaker
    private let download: DownloadWriter
    private let fileManager: FileManager
    private let maxRetries = 3

    init(
        download: @escaping DownloadWriter = DownloadManager.defaultDownload,
        fileManager: FileManager = .default
    ) {
        self.download = download
        self.fileManager = fileManager
        self.rateLimiter = RateLimiter(rate: 5)
        self.circuitBreaker = CircuitBreaker()
    }

    @discardableResult
    func start(groups: [NativePaperGroup], saveDirectory: URL, options: DownloadOptions) throws -> DownloadStartResult {
        runnerTask?.cancel()
        isCancelled = false
        queue.removeAll()
        workItems.removeAll()
        downloadItems.removeAll()

        let plan = try DownloadDestinationBuilder.build(
            groups: groups,
            saveDirectory: saveDirectory,
            options: options,
            fileManager: fileManager
        )

        for task in plan.tasks {
            workItems[task.id] = task
            downloadItems[task.id] = task.displayItem
            queue.enqueue(task.id)
        }

        rateLimiter = RateLimiter(rate: max(1, min(options.rate, 20)))
        circuitBreaker = CircuitBreaker()
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
            runnerTask = Task { [weak self] in
                await self?.run(workers: workers)
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
        isCancelled = true
        runnerTask?.cancel()
        queue.removeAll()

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
    }

    private func run(workers: Int) async {
        var retryRound = 0

        while !isCancelled {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<workers {
                    group.addTask { [weak self] in
                        await self?.workerLoop()
                    }
                }
            }

            if isCancelled || Task.isCancelled {
                cancel()
                return
            }

            let failed = downloadItems.values
                .filter { $0.status == .failed }
                .sorted { $0.id < $1.id }

            if !failed.isEmpty && retryRound < maxRetries {
                retryRound += 1
                for item in failed {
                    setStatus(id: item.id, status: .pending, error: "", errorType: "")
                    queue.enqueue(item.id)
                }
                updateProgress(message: "\(failed.count) 个失败任务自动重试 (第 \(retryRound) 轮)")
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

    private func workerLoop() async {
        while !Task.isCancelled {
            guard !isCancelled, let id = queue.dequeue(), let task = workItems[id] else {
                return
            }
            await download(task)
            updateProgress(message: "下载中... (\(snapshot.done)/\(snapshot.total))")
        }
    }

    private func download(_ task: DownloadDestinationTask) async {
        setStatus(id: task.id, status: .downloading, error: "", errorType: "")

        do {
            try await circuitBreaker.allowRequest()
            try await rateLimiter.acquire()
            try Task.checkCancellation()
            try fileManager.createDirectory(at: task.saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            let partialURL = task.saveURL.deletingLastPathComponent()
                .appendingPathComponent("\(task.saveURL.lastPathComponent).part.\(UUID().uuidString)")
            defer {
                try? fileManager.removeItem(at: partialURL)
            }

            try await download(task.component.url, partialURL)
            try Task.checkCancellation()
            try atomicReplace(partialURL: partialURL, destinationURL: task.saveURL)
            await circuitBreaker.recordSuccess()
            setStatus(id: task.id, status: .done, error: "", errorType: "")
        } catch is CancellationError {
            setStatus(id: task.id, status: .cancelled, error: "用户取消", errorType: "cancelled")
        } catch CircuitBreakerError.open {
            await circuitBreaker.recordFailure()
            setStatus(id: task.id, status: .failed, error: CircuitBreakerError.open.localizedDescription, errorType: "rate_limit")
        } catch {
            await circuitBreaker.recordFailure()
            setStatus(id: task.id, status: .failed, error: error.localizedDescription, errorType: errorType(for: error))
        }
    }

    private func atomicReplace(partialURL: URL, destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: partialURL)
        } else {
            try fileManager.moveItem(at: partialURL, to: destinationURL)
        }
    }

    private func setStatus(id: Int, status: DownloadStatus, error: String, errorType: String) {
        guard let current = downloadItems[id] else { return }
        downloadItems[id] = DownloadTaskItem(
            id: current.id,
            filename: current.filename,
            ftype: current.ftype,
            label: current.label,
            year: current.year,
            savePath: current.savePath,
            status: status,
            error: error,
            errorType: errorType
        )
    }

    private func updateProgress(message: String) {
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
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "network"
        }
        return "unknown"
    }

    private static func defaultDownload(sourceURL: URL, partialURL: URL) async throws {
        let (data, response) = try await URLSession.shared.data(from: sourceURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw NSError(
                domain: "DownloadManager.HTTP",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
            )
        }
        try data.write(to: partialURL, options: .atomic)
    }
}
