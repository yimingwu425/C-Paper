import Foundation

struct AppStoragePaths: Sendable {
    let appSupportDirectory: URL
    let cacheDirectory: URL
    let settingsURL: URL
    let favoritesURL: URL
    let downloadHistoryURL: URL
    let migrationMarkerURL: URL

    init(rootURL: URL? = nil, fileManager: FileManager = .default) throws {
        let root = try rootURL ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("C-Paper", isDirectory: true)

        appSupportDirectory = root
        cacheDirectory = root.appendingPathComponent("cache", isDirectory: true)
        settingsURL = root.appendingPathComponent("settings.json")
        favoritesURL = root.appendingPathComponent("favorites.json")
        downloadHistoryURL = root.appendingPathComponent("download_history.json")
        migrationMarkerURL = root.appendingPathComponent("legacy_migration.json")
    }
}
