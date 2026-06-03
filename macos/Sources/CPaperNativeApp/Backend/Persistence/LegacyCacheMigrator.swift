import Foundation

struct LegacyCacheMigrator {
    private let paths: AppStoragePaths
    private let legacyDirectory: URL
    private let fileManager: FileManager
    private let now: () -> Date

    init(
        paths: AppStoragePaths,
        legacyDirectory: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.legacyDirectory = legacyDirectory
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".cie_cache", isDirectory: true)
        self.now = now
    }

    func migrateIfNeeded() throws {
        guard !fileManager.fileExists(atPath: paths.migrationMarkerURL.path) else {
            return
        }

        try fileManager.createDirectory(
            at: paths.appSupportDirectory,
            withIntermediateDirectories: true
        )

        try copyLegacyFile(named: "settings.json", to: paths.settingsURL)
        try copyLegacyFile(named: "favorites.json", to: paths.favoritesURL)
        try copyLegacyFile(named: "download_history.json", to: paths.downloadHistoryURL)
        try writeMigrationMarker()
    }

    private func copyLegacyFile(named filename: String, to destinationURL: URL) throws {
        let sourceURL = legacyDirectory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return
        }
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            return
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func writeMigrationMarker() throws {
        let store = JSONFileStore(
            url: paths.migrationMarkerURL,
            defaultValue: LegacyMigrationMarker(migratedAt: now(), legacyPath: legacyDirectory.path),
            fileManager: fileManager
        )
        try store.write(LegacyMigrationMarker(migratedAt: now(), legacyPath: legacyDirectory.path))
    }
}

private struct LegacyMigrationMarker: Codable {
    let migratedAt: Date
    let legacyPath: String

    enum CodingKeys: String, CodingKey {
        case migratedAt = "migrated_at"
        case legacyPath = "legacy_path"
    }
}
