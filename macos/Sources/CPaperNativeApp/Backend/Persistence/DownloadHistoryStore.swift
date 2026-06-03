import Foundation

struct DownloadHistoryItem: Codable, Equatable {
    let filename: String
    let label: String
    let year: String
    let savePath: String
    let downloadedAt: String

    enum CodingKeys: String, CodingKey {
        case filename
        case label
        case year
        case savePath = "save_path"
        case downloadedAt = "downloaded_at"
    }
}

struct DownloadHistoryDocument: Codable, Equatable {
    var items: [DownloadHistoryItem] = []
}

struct DownloadHistoryStore {
    private let store: JSONFileStore<DownloadHistoryDocument>
    private let maxItems: Int
    private let now: () -> Date

    init(
        paths: AppStoragePaths,
        maxItems: Int = BackendConstants.historyMaxItems,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        store = JSONFileStore(
            url: paths.downloadHistoryURL,
            defaultValue: DownloadHistoryDocument(),
            fileManager: fileManager
        )
        self.maxItems = maxItems
        self.now = now
    }

    init(
        store: JSONFileStore<DownloadHistoryDocument>,
        maxItems: Int = BackendConstants.historyMaxItems,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.maxItems = maxItems
        self.now = now
    }

    func load() -> [DownloadHistoryItem] {
        store.read().items
    }

    func contains(filename: String) -> Bool {
        load().contains { $0.filename == filename }
    }

    func record(
        filename: String,
        label: String = "",
        year: String = "",
        savePath: String = ""
    ) throws {
        var document = store.read()
        guard !document.items.contains(where: { $0.filename == filename }) else {
            return
        }

        document.items.append(
            DownloadHistoryItem(
                filename: filename,
                label: label,
                year: year,
                savePath: savePath,
                downloadedAt: Self.formatTimestamp(now())
            )
        )

        if document.items.count > maxItems {
            document.items = Array(document.items.suffix(maxItems))
        }

        try store.write(document)
    }

    func clear() throws {
        try store.write(DownloadHistoryDocument())
    }

    private static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
