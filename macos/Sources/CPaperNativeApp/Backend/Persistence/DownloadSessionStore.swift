import Foundation

struct DownloadSessionDocument: Codable, Equatable {
    var tasks: [DownloadDestinationTask] = []
    var items: [DownloadTaskItem] = []
    var snapshot = DownloadStatusSnapshot(
        phase: .idle,
        done: 0,
        total: 0,
        success: 0,
        message: "Ready",
        failed: nil,
        cancelled: nil,
        skipped: nil
    )
    var options: DownloadOptions?
    var proxyURL = ""
}

struct RestoredDownloadSession {
    let document: DownloadSessionDocument
    let cleanedPartialCount: Int
    let resumedFailureCount: Int
}

struct DownloadSessionRecoverySummary: Equatable, Sendable {
    let cleanedPartialCount: Int
    let resumedFailureCount: Int
}

struct DownloadSessionStore: @unchecked Sendable {
    private let store: JSONFileStore<DownloadSessionDocument>
    private let fileManager: FileManager

    init(paths: AppStoragePaths, fileManager: FileManager = .default) {
        self.store = JSONFileStore(
            url: paths.downloadSessionURL,
            defaultValue: DownloadSessionDocument(),
            fileManager: fileManager
        )
        self.fileManager = fileManager
    }

    init(store: JSONFileStore<DownloadSessionDocument>, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    func load() -> DownloadSessionDocument {
        store.read()
    }

    func save(_ document: DownloadSessionDocument) throws {
        try store.write(document)
    }

    func clear() throws {
        try store.write(DownloadSessionDocument())
    }

    func restoreInterruptedSession() throws -> RestoredDownloadSession {
        var document = load()
        guard document.snapshot.phase == .running else {
            return RestoredDownloadSession(document: document, cleanedPartialCount: 0, resumedFailureCount: 0)
        }

        var cleanedPartialCount = 0
        var resumedFailureCount = 0
        var itemsByID = Dictionary(uniqueKeysWithValues: document.items.map { ($0.id, $0) })

        for task in document.tasks {
            guard let item = itemsByID[task.id],
                  item.status == .pending || item.status == .downloading else {
                continue
            }

            cleanedPartialCount += removePartialFiles(for: task.saveURL)
            resumedFailureCount += 1
            itemsByID[task.id] = DownloadTaskItem(
                id: item.id,
                filename: item.filename,
                ftype: item.ftype,
                label: item.label,
                year: item.year,
                savePath: item.savePath,
                status: .failed,
                error: "上次下载在应用退出前中断，请重试",
                errorType: .interrupted,
                progressFraction: nil
            )
        }

        document.items = itemsByID.values.sorted { $0.id < $1.id }
        document.snapshot = normalizedSnapshot(
            from: document.snapshot,
            items: document.items,
            resumedFailureCount: resumedFailureCount
        )

        try save(document)
        return RestoredDownloadSession(
            document: document,
            cleanedPartialCount: cleanedPartialCount,
            resumedFailureCount: resumedFailureCount
        )
    }

    private func normalizedSnapshot(
        from snapshot: DownloadStatusSnapshot,
        items: [DownloadTaskItem],
        resumedFailureCount: Int
    ) -> DownloadStatusSnapshot {
        let done = items.filter { $0.status == .done }.count
        let failed = items.filter { $0.status == .failed }.count
        let cancelled = items.filter { $0.status == .cancelled }.count
        let skipped = items.filter { $0.status == .skipped }.count
        let completed = done + failed + cancelled + skipped
        let total = max(snapshot.total, items.count)
        let message: String
        if resumedFailureCount > 0 {
            message = "上次下载在退出时中断，可重试失败项"
        } else {
            message = snapshot.message
        }

        return DownloadStatusSnapshot(
            phase: .done,
            done: completed,
            total: total,
            success: done,
            message: message,
            failed: failed,
            cancelled: cancelled,
            skipped: skipped
        )
    }

    private func removePartialFiles(for destinationURL: URL) -> Int {
        let directoryURL = destinationURL.deletingLastPathComponent()
        let prefix = destinationURL.lastPathComponent + ".part."
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }

        var removed = 0
        for entry in entries where entry.lastPathComponent.hasPrefix(prefix) {
            do {
                try fileManager.removeItem(at: entry)
                removed += 1
            } catch {
                continue
            }
        }
        return removed
    }
}
