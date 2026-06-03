import Foundation

struct SearchCacheStore {
    private let paths: AppStoragePaths
    private let ttl: TimeInterval
    private let fileManager: FileManager
    private let now: () -> Date

    init(
        paths: AppStoragePaths,
        ttl: TimeInterval = BackendConstants.cacheTTL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.paths = paths
        self.ttl = ttl
        self.fileManager = fileManager
        self.now = now
    }

    func load<Payload: Codable>(
        _ type: Payload.Type = Payload.self,
        source: PaperSourceID,
        key: String
    ) -> Payload? {
        let url = cacheURL(source: source, key: key)
        let store = JSONFileStore<SearchCacheEntry<Payload>>(
            url: url,
            defaultValue: SearchCacheEntry(storedAt: .distantPast, payload: nil),
            fileManager: fileManager
        )
        let entry = store.read()

        guard now().timeIntervalSince(entry.storedAt) <= ttl else {
            try? fileManager.removeItem(at: url)
            return nil
        }

        return entry.payload
    }

    func save<Payload: Codable>(
        _ payload: Payload,
        source: PaperSourceID,
        key: String
    ) throws {
        let store = JSONFileStore<SearchCacheEntry<Payload>>(
            url: cacheURL(source: source, key: key),
            defaultValue: SearchCacheEntry(storedAt: .distantPast, payload: nil),
            fileManager: fileManager
        )
        try store.write(SearchCacheEntry(storedAt: now(), payload: payload))
    }

    private func cacheURL(source: PaperSourceID, key: String) -> URL {
        paths.cacheDirectory
            .appendingPathComponent(source.rawValue, isDirectory: true)
            .appendingPathComponent(Self.safeFilename(for: key))
    }

    private static func safeFilename(for key: String) -> String {
        Data(key.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
            + ".json"
    }
}

private struct SearchCacheEntry<Payload: Codable>: Codable {
    let storedAt: Date
    let payload: Payload?

    enum CodingKeys: String, CodingKey {
        case storedAt = "stored_at"
        case payload
    }
}
