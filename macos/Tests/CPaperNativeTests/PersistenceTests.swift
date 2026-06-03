import XCTest
@testable import CPaperNativeApp

final class PersistenceTests: XCTestCase {
    func testCorruptJSONIsBackedUpAndDefaultReturned() throws {
        let root = try makeTemporaryDirectory()
        let url = root.appendingPathComponent("numbers.json")
        try Data("{".utf8).write(to: url)

        let store = JSONFileStore<[Int]>(
            url: url,
            defaultValue: [],
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        XCTAssertEqual(store.read(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: "\(url.path).corrupt.1700000000")
        )
    }

    func testSettingsRoundTrip() throws {
        let paths = try makeStoragePaths()
        let store = SettingsStore(paths: paths)
        let settings = DownloadSettings(
            theme: "dark",
            saveDirectory: "/tmp/cpaper",
            includeMarkSchemes: false,
            rate: 8,
            threads: 6,
            mergeFolders: true,
            proxyURL: "http://127.0.0.1:7890",
            lastSubject: "9709",
            lastMode: "batch",
            duplicateMode: .missing
        )

        try store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testFavoritesAreDedupedByCode() throws {
        let paths = try makeStoragePaths()
        let store = FavoritesStore(paths: paths)

        try store.add(Subject(code: "9709", name: "Mathematics"))
        try store.add(Subject(code: "9709", name: "Different name"))
        try store.add(Subject(code: "9701", name: "Chemistry"))

        let favorites = store.load()
        XCTAssertEqual(favorites.map(\.code), ["9709", "9701"])
        XCTAssertEqual(favorites.first?.name, "Mathematics")
    }

    func testDownloadHistoryMaxItemsAndContains() throws {
        let paths = try makeStoragePaths()
        let store = DownloadHistoryStore(paths: paths, maxItems: 3)

        try store.record(filename: "a.pdf")
        try store.record(filename: "b.pdf")
        try store.record(filename: "c.pdf")
        try store.record(filename: "d.pdf")

        XCTAssertFalse(store.contains(filename: "a.pdf"))
        XCTAssertTrue(store.contains(filename: "d.pdf"))
        XCTAssertEqual(store.load().map(\.filename), ["b.pdf", "c.pdf", "d.pdf"])
    }

    func testSearchCacheHonorsTTL() throws {
        let paths = try makeStoragePaths()
        var currentDate = Date(timeIntervalSince1970: 100)
        let store = SearchCacheStore(
            paths: paths,
            ttl: 10,
            now: { currentDate }
        )
        let payload = CachedPayload(value: "fresh")

        try store.save(payload, source: .frankcie, key: "9709/2024/Jun")

        XCTAssertEqual(
            store.load(CachedPayload.self, source: .frankcie, key: "9709/2024/Jun"),
            payload
        )

        currentDate = Date(timeIntervalSince1970: 111)
        XCTAssertNil(store.load(CachedPayload.self, source: .frankcie, key: "9709/2024/Jun"))
    }

    func testLegacyMigrationCopiesWithoutOverwritingNewFiles() throws {
        let paths = try makeStoragePaths()
        let legacyDirectory = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: paths.appSupportDirectory,
            withIntermediateDirectories: true
        )

        let existingSettings = #"{"theme":"existing"}"#
        let legacySettings = #"{"theme":"legacy"}"#
        let legacyFavorites = #"[{"code":"9709","name":"Mathematics"}]"#
        let legacyHistory = #"{"items":[{"filename":"paper.pdf"}]}"#

        try Data(existingSettings.utf8).write(to: paths.settingsURL)
        try Data(legacySettings.utf8).write(to: legacyDirectory.appendingPathComponent("settings.json"))
        try Data(legacyFavorites.utf8).write(to: legacyDirectory.appendingPathComponent("favorites.json"))
        try Data(legacyHistory.utf8).write(to: legacyDirectory.appendingPathComponent("download_history.json"))

        let migrator = LegacyCacheMigrator(paths: paths, legacyDirectory: legacyDirectory)
        try migrator.migrateIfNeeded()

        XCTAssertEqual(try String(contentsOf: paths.settingsURL), existingSettings)
        XCTAssertEqual(try String(contentsOf: paths.favoritesURL), legacyFavorites)
        XCTAssertEqual(try String(contentsOf: paths.downloadHistoryURL), legacyHistory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.migrationMarkerURL.path))
    }

    private struct CachedPayload: Codable, Equatable {
        let value: String
    }

    private func makeStoragePaths() throws -> AppStoragePaths {
        try AppStoragePaths(rootURL: makeTemporaryDirectory())
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
