import XCTest
@testable import CPaperNativeApp

@MainActor
final class ModelTests: XCTestCase {
    func testRouteMetadata() {
        XCTAssertEqual(AppRoute.search.title, "搜索")
        XCTAssertEqual(AppRoute.batch.symbolName, "square.stack.3d.down.right")
    }

    func testDownloadCounts() {
        let model = try! makeBasicModel()
        model.downloads = [
            DownloadTaskItem(id: 0, filename: "a.pdf", ftype: "QP", label: "Paper 1", year: "2023", savePath: "/tmp/a.pdf", status: .done, error: "", errorType: ""),
            DownloadTaskItem(id: 1, filename: "b.pdf", ftype: "MS", label: "Paper 1", year: "2023", savePath: "/tmp/b.pdf", status: .failed, error: "boom", errorType: "network"),
            DownloadTaskItem(id: 2, filename: "c.pdf", ftype: "QP", label: "Paper 2", year: "2023", savePath: "/tmp/c.pdf", status: .downloading, error: "", errorType: "")
        ]

        XCTAssertEqual(model.completedDownloadCount, 1)
        XCTAssertEqual(model.failedDownloadCount, 1)
        XCTAssertEqual(model.activeDownloadCount, 1)
    }

    func testManualSubjectCodeActsAsFallbackWhenSubjectListIsUnavailable() {
        let model = try! makeBasicModel()
        model.selectedSubject = nil
        model.manualSubjectCode = "9709"

        XCTAssertTrue(model.hasSearchSubject)
        XCTAssertEqual(model.activeSubject?.code, "9709")
        XCTAssertEqual(model.activeSubject?.name, "手动输入 9709")
    }

    func testSelectedSubjectTakesPriorityOverManualSubjectCode() {
        let model = try! makeBasicModel()
        model.selectedSubject = Subject(code: "9701", name: "Chemistry")
        model.manualSubjectCode = "9709"

        XCTAssertEqual(model.activeSubject?.code, "9701")
    }

    func testSettingsCodingKeysRoundTrip() throws {
        let settings = DownloadSettings(
            theme: "light",
            saveDirectory: "/tmp/cpaper",
            includeMarkSchemes: false,
            rate: 6,
            threads: 3,
            mergeFolders: true,
            proxyURL: "http://127.0.0.1:7890",
            lastSubject: "9709",
            lastMode: "batch",
            duplicateMode: .missing,
            sourceMode: .pastPapers
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DownloadSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    func testEditingSettingsDraftDoesNotMutateModelOrPersistenceUntilCommitted() async throws {
        let initialSettings = DownloadSettings(
            theme: "light",
            saveDirectory: "/tmp/original",
            includeMarkSchemes: true,
            rate: 5,
            threads: 4,
            mergeFolders: false,
            proxyURL: "",
            lastSubject: "9701",
            lastMode: AppRoute.search.rawValue,
            duplicateMode: .overwrite,
            sourceMode: .automatic
        )
        let model = try await makePersistentModel(initialSettings: initialSettings)

        var draft = model.settings
        draft.saveDirectory = "/tmp/updated"
        draft.proxyURL = "http://127.0.0.1:7890"
        draft.rate = 8
        draft.threads = 7
        draft.sourceMode = .easyPaper

        XCTAssertEqual(model.settings, initialSettings)
        XCTAssertEqual(model.backend.loadSettings(), initialSettings)
    }

    func testSavingSettingsDraftCommitsToModelAndPersistence() async throws {
        let initialSettings = DownloadSettings(
            theme: "light",
            saveDirectory: "/tmp/original",
            includeMarkSchemes: true,
            rate: 5,
            threads: 4,
            mergeFolders: false,
            proxyURL: "",
            lastSubject: "",
            lastMode: AppRoute.search.rawValue,
            duplicateMode: .overwrite,
            sourceMode: .automatic
        )
        let model = try await makePersistentModel(initialSettings: initialSettings)
        model.route = .batch
        model.selectedSubject = Subject(code: "9709", name: "Mathematics")

        var draft = model.settings
        draft.saveDirectory = "/tmp/updated"
        draft.proxyURL = "http://127.0.0.1:7890"
        draft.rate = 8
        draft.threads = 7
        draft.sourceMode = .easyPaper

        await model.saveSettings(draft)

        var expectedSettings = draft
        expectedSettings.lastSubject = "9709"
        expectedSettings.lastMode = AppRoute.batch.rawValue

        XCTAssertEqual(model.settings, expectedSettings)
        XCTAssertEqual(model.backend.loadSettings(), expectedSettings)
    }

    func testStartupUpdateCheckRunsOnlyOnceAndDoesNotPromptWhenUpToDate() async throws {
        let counter = UpdateCallCounter()
        let model = try makeModel(
            currentVersion: "6.0.2",
            releaseJSON: Self.releaseJSON(tag: "v6.0.2"),
            counter: counter
        )

        await model.checkForUpdates(source: .startup)
        await model.checkForUpdates(source: .startup)

        let callCount = await counter.value()
        XCTAssertEqual(callCount, 1)
        XCTAssertNil(model.pendingUpdatePrompt)
        XCTAssertEqual(model.updateStatus, .upToDate(current: "6.0.2", latest: "6.0.2"))
    }

    func testStartupUpdateCheckPromptsWhenNewVersionExistsWithoutDownloading() async throws {
        let counter = UpdateCallCounter()
        let model = try makeModel(
            currentVersion: "6.0.2",
            releaseJSON: Self.releaseJSON(tag: "v6.0.3"),
            counter: counter
        )

        await model.checkForUpdates(source: .startup)

        let callCount = await counter.value()
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(model.pendingUpdatePrompt?.version, "6.0.3")
        XCTAssertEqual(model.updateStatus.availableRelease?.version, "6.0.3")
    }

    func testDownloadAvailableUpdateClearsPromptAndStoresDownloadedURL() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let model = try makeModel(
            currentVersion: "6.0.2",
            releaseJSON: Self.releaseJSON(tag: "v6.0.3"),
            updatesDirectory: tempDirectory
        )
        await model.checkForUpdates(source: .startup)

        await model.downloadAvailableUpdate()

        XCTAssertNil(model.pendingUpdatePrompt)
        guard let downloadedURL = model.updateStatus.downloadedURL else {
            return XCTFail("Expected downloaded update URL")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloadedURL.path))
        XCTAssertEqual(try String(contentsOf: downloadedURL), "update")
    }

    private func makeModel(
        currentVersion: String,
        releaseJSON: Data,
        updatesDirectory: URL? = nil,
        counter: UpdateCallCounter = UpdateCallCounter()
    ) throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let updateService = UpdateService(
            currentVersion: currentVersion,
            updatesDirectory: updatesDirectory,
            networkClientFactory: { _ in
                CountedUpdateNetworkClient(data: releaseJSON, counter: counter)
            },
            downloadWriter: { _, destinationURL, _, progress in
                await progress(0.5)
                try Data("update".utf8).write(to: destinationURL)
            }
        )
        let backend = try NativeBackendService(paths: paths, updateService: updateService)
        return AppModel(backend: backend)
    }

    private func makeBasicModel() throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperBasicModelTests-\(UUID().uuidString)", isDirectory: true)
        let backend = try NativeBackendService(paths: AppStoragePaths(rootURL: pathsRoot))
        return AppModel(backend: backend)
    }

    private func makePersistentModel(initialSettings: DownloadSettings) async throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperSettingsModelTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        let backend = try NativeBackendService(paths: paths)
        try backend.saveSettings(initialSettings)

        let model = AppModel(backend: backend)
        await model.loadSettings()
        return model
    }

    private static func releaseJSON(tag: String) -> Data {
        let version = tag.replacingOccurrences(of: "v", with: "")
        return """
        {
          "tag_name": "\(tag)",
          "name": "C-Paper Native \(version)",
          "html_url": "https://github.com/yimingwu425/C-Paper/releases/tag/\(tag)",
          "assets": [
            {
              "name": "C-Paper-Native-\(version)-standalone-20260604.dmg",
              "content_type": "application/x-apple-diskimage",
              "browser_download_url": "https://github.com/yimingwu425/C-Paper/releases/download/\(tag)/C-Paper-Native-\(version)-standalone-20260604.dmg"
            }
          ]
        }
        """.data(using: .utf8)!
    }
}

private actor UpdateCallCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private final class CountedUpdateNetworkClient: NetworkClientProtocol, @unchecked Sendable {
    let data: Data
    let counter: UpdateCallCounter

    init(data: Data, counter: UpdateCallCounter) {
        self.data = data
        self.counter = counter
    }

    func data(for request: URLRequest) async throws -> Data {
        await counter.increment()
        return data
    }
}
