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
            DownloadTaskItem(id: 2, filename: "c.pdf", ftype: "QP", label: "Paper 2", year: "2023", savePath: "/tmp/c.pdf", status: .downloading, error: "", errorType: ""),
            DownloadTaskItem(id: 3, filename: "d.pdf", ftype: "QP", label: "Paper 3", year: "2023", savePath: "/tmp/d.pdf", status: .cancelled, error: "", errorType: ""),
            DownloadTaskItem(id: 4, filename: "e.pdf", ftype: "QP", label: "Paper 4", year: "2023", savePath: "/tmp/e.pdf", status: .skipped, error: "", errorType: "")
        ]

        XCTAssertEqual(model.completedDownloadCount, 2)
        XCTAssertEqual(model.failedDownloadCount, 1)
        XCTAssertEqual(model.cancelledDownloadCount, 1)
        XCTAssertEqual(model.skippedDownloadCount, 1)
        XCTAssertEqual(model.activeDownloadCount, 1)
    }

    func testDownloadTaskProgressUsesFractionWhenAvailable() {
        let inFlight = DownloadTaskItem(
            id: 1,
            filename: "paper.pdf",
            ftype: "QP",
            label: "Paper 1",
            year: "2024",
            savePath: "/tmp/paper.pdf",
            status: .downloading,
            error: "",
            errorType: "",
            progressFraction: 0.42
        )
        let belowRange = DownloadTaskItem(
            id: 2,
            filename: "low.pdf",
            ftype: "QP",
            label: "Paper 2",
            year: "2024",
            savePath: "/tmp/low.pdf",
            status: .downloading,
            error: "",
            errorType: "",
            progressFraction: -0.5
        )
        let aboveRange = DownloadTaskItem(
            id: 3,
            filename: "high.pdf",
            ftype: "QP",
            label: "Paper 3",
            year: "2024",
            savePath: "/tmp/high.pdf",
            status: .downloading,
            error: "",
            errorType: "",
            progressFraction: 1.5
        )
        let legacyStyle = DownloadTaskItem(
            id: 4,
            filename: "legacy.pdf",
            ftype: "QP",
            label: "Paper 4",
            year: "2024",
            savePath: "/tmp/legacy.pdf",
            status: .downloading,
            error: "",
            errorType: ""
        )

        XCTAssertEqual(inFlight.progress, 0.42, accuracy: 0.0001)
        XCTAssertEqual(belowRange.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(aboveRange.progress, 1, accuracy: 0.0001)
        XCTAssertEqual(legacyStyle.progress, 0.55, accuracy: 0.0001)
    }

    func testDownloadQueueSummaryMarksAllSkippedFilesAsProcessed() {
        let summary = DownloadQueueSummary(
            total: 3,
            processed: 3,
            success: 0,
            failed: 0,
            cancelled: 0,
            skipped: 3
        )

        XCTAssertEqual(summary.subtitle, "已处理 3/3 个文件，成功 0 个，失败 0 个，跳过 3 个")
    }

    func testDownloadQueueSummaryMarksAllFailedFilesAsProcessed() {
        let summary = DownloadQueueSummary(
            total: 4,
            processed: 4,
            success: 0,
            failed: 4,
            cancelled: 0,
            skipped: 0
        )

        XCTAssertEqual(summary.subtitle, "已处理 4/4 个文件，成功 0 个，失败 4 个")
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

    func testLoadSubjectsDoesNotSelectFirstSubjectWhenNoSavedSubjectExists() async throws {
        let subjects = [
            Subject(code: "9231", name: "Further Mathematics"),
            Subject(code: "9709", name: "Mathematics")
        ]
        let model = try makeModelWithCachedSubjects(subjects)

        await model.loadSubjects()

        XCTAssertEqual(model.subjects.map(\.code), ["9231", "9709"])
        XCTAssertNil(model.selectedSubject)
        XCTAssertEqual(model.manualSubjectCode, "")
        XCTAssertFalse(model.hasSearchSubject)
    }

    func testLoadSubjectsRestoresSavedSubjectWhenAvailable() async throws {
        let subjects = [
            Subject(code: "9231", name: "Further Mathematics"),
            Subject(code: "9709", name: "Mathematics")
        ]
        let model = try makeModelWithCachedSubjects(subjects)
        model.settings.lastSubject = "9709"

        await model.loadSubjects()

        XCTAssertEqual(model.selectedSubject, Subject(code: "9709", name: "Mathematics"))
        XCTAssertEqual(model.manualSubjectCode, "")
        XCTAssertTrue(model.hasSearchSubject)
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

    func testDownloadingUpdateStatusPreservesDestinationURLBeforeCompletion() {
        let url = URL(fileURLWithPath: "/tmp/C-Paper/Updates/C-Paper-Native.dmg")
        let status = UpdateStatus.downloading(progress: 0.5, destinationURL: url)

        XCTAssertEqual(status.destinationURL, url)
        XCTAssertNil(status.downloadedURL)
        XCTAssertEqual(status.message, "正在下载更新 50%")
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

    func testUsableSaveDirectoryURLExpandsTildeForExistingDirectory() throws {
        let model = try makeBasicModel()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRevealDirectoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .standardizedFileURL
        let standardizedDirectory = directory.standardizedFileURL
        let relativePath = standardizedDirectory.path.replacingOccurrences(
            of: homeDirectory.path,
            with: "~",
            options: [.anchored]
        )
        model.settings.saveDirectory = relativePath

        let usableDirectory = try XCTUnwrap(model.usableSaveDirectoryURL())

        XCTAssertEqual(usableDirectory.standardizedFileURL, standardizedDirectory)
    }

    func testRevealSaveDirectorySetsChineseErrorWhenPathDoesNotExist() throws {
        let model = try makeBasicModel()
        model.settings.saveDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperMissingDirectory-\(UUID().uuidString)", isDirectory: true)
            .path

        model.revealSaveDirectory()

        XCTAssertEqual(model.errorMessage, "下载文件夹不存在，请先在设置中选择有效的保存目录。")
    }

    func testRevealSaveDirectorySetsChineseErrorWhenPathIsAFile() throws {
        let model = try makeBasicModel()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperRevealDirectoryFile-\(UUID().uuidString).txt", isDirectory: false)
        try Data("test".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        model.settings.saveDirectory = fileURL.path

        model.revealSaveDirectory()

        XCTAssertEqual(model.errorMessage, "下载文件夹不存在，请先在设置中选择有效的保存目录。")
    }

    func testBackendErrorsCreateRedactedSupportDiagnosticReport() throws {
        let model = try makeBasicModel()
        let home = NSHomeDirectory()

        model.handleBackendError(
            DiagnosticTestError(
                message: "Preview failed at \(home)/Downloads/file.pdf via http://alice:secret@127.0.0.1:7890/paperdownload/dir_v3/raw-token?token=abc123"
            ),
            context: .preview,
            details: [
                SupportDiagnosticDetail(label: "Proxy", value: "http://alice:secret@127.0.0.1:7890"),
                SupportDiagnosticDetail(label: "Path", value: "\(home)/Downloads/file.pdf")
            ]
        )

        let diagnostic = try XCTUnwrap(model.lastDiagnostic)
        let reportURL = try XCTUnwrap(diagnostic.reportURL)
        let report = try String(contentsOf: reportURL)

        XCTAssertEqual(diagnostic.context, .preview)
        XCTAssertEqual(model.errorMessage, diagnostic.message)
        XCTAssertFalse(diagnostic.reportText.contains("alice:secret"))
        XCTAssertFalse(diagnostic.reportText.contains("raw-token"))
        XCTAssertFalse(diagnostic.reportText.contains("abc123"))
        XCTAssertFalse(diagnostic.reportText.contains(home))
        XCTAssertTrue(report.contains("Area: 预览"))
        XCTAssertTrue(report.contains("http://<redacted>@127.0.0.1:7890"))
        XCTAssertTrue(report.contains("~/Downloads/file.pdf"))
    }

    func testStartupUpdateCheckRunsOnlyOnceAndDoesNotPromptWhenUpToDate() async throws {
        let counter = UpdateCallCounter()
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.3"),
            counter: counter
        )

        await model.checkForUpdates(source: .startup)
        await model.checkForUpdates(source: .startup)

        let callCount = await counter.value()
        XCTAssertEqual(callCount, 1)
        XCTAssertNil(model.pendingUpdatePrompt)
        XCTAssertEqual(model.updateStatus, .upToDate(current: "6.0.3", latest: "6.0.3"))
    }

    func testStartupUpdateCheckPromptsWhenNewVersionExistsWithoutDownloading() async throws {
        let counter = UpdateCallCounter()
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            counter: counter
        )

        await model.checkForUpdates(source: .startup)

        let callCount = await counter.value()
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(model.pendingUpdatePrompt?.version, "6.0.4")
        XCTAssertEqual(model.updateStatus.availableRelease?.version, "6.0.4")
    }

    func testDownloadAvailableUpdateClearsPromptAndStoresDownloadedURL() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
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

    func testDownloadAvailableUpdateStatusPreservesDestinationURLWhileDownloading() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateProgressTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let coordinator = UpdateDownloadCoordinator()
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory,
            downloadWriter: { _, destinationURL, _, progress in
                await progress(0.5)
                await coordinator.recordProgress()
                await coordinator.waitForFinishPermission()
                try Data("update".utf8).write(to: destinationURL)
            }
        )
        await model.checkForUpdates(source: .startup)

        let downloadTask = Task {
            await model.downloadAvailableUpdate()
        }
        await coordinator.waitForProgress()

        guard case let .downloading(progress, destinationURL) = model.updateStatus else {
            await coordinator.allowFinish()
            await downloadTask.value
            return XCTFail("Expected update status to stay downloading while transfer is in flight.")
        }
        XCTAssertEqual(progress, 0.5)
        XCTAssertEqual(destinationURL, tempDirectory.appendingPathComponent("C-Paper-Native-6.0.4-standalone-20260604.dmg"))

        await coordinator.allowFinish()
        await downloadTask.value
    }

    func testDownloadAvailableUpdateAutomaticallyOpensDownloadedDMG() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateOpenTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let recorder = URLRecorder()
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory,
            openDownloadedFile: { url in
                recorder.record(url)
                return true
            }
        )
        await model.checkForUpdates(source: .startup)
        await model.downloadAvailableUpdate()

        let downloadedURL = try XCTUnwrap(model.updateStatus.downloadedURL)
        XCTAssertEqual(recorder.values(), [downloadedURL])
        XCTAssertNil(model.errorMessage)
    }

    func testOpenDownloadedUpdateFileUsesInjectedOpenDownloadedFileClosure() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelManualUpdateOpenTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let recorder = URLRecorder()
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory,
            openDownloadedFile: { url in
                recorder.record(url)
                return true
            }
        )
        await model.checkForUpdates(source: .startup)
        await model.downloadAvailableUpdate()

        let didOpen = model.openDownloadedUpdateFile()

        XCTAssertTrue(didOpen)
        let openedURL = recorder.lastValue()
        XCTAssertEqual(openedURL, model.updateStatus.downloadedURL)
        XCTAssertEqual(openedURL?.pathExtension, "dmg")
        XCTAssertEqual(recorder.values().count, 2)
    }

    func testDownloadAvailableUpdateOpenFailureKeepsDownloadedURLAndShowsGuidance() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperModelUpdateOpenFailureTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let model = try makeModel(
            currentVersion: "6.0.3",
            releaseJSON: Self.releaseJSON(tag: "v6.0.4"),
            updatesDirectory: tempDirectory,
            openDownloadedFile: { _ in false }
        )
        await model.checkForUpdates(source: .startup)
        await model.downloadAvailableUpdate()
        let downloadedURL = try XCTUnwrap(model.updateStatus.downloadedURL)

        XCTAssertEqual(model.errorMessage, "更新 DMG 已下载，但自动打开失败，请在设置中手动打开。")

        let didOpen = model.openDownloadedUpdateFile()

        XCTAssertFalse(didOpen)
        XCTAssertEqual(model.updateStatus.downloadedURL, downloadedURL)
    }

    private func makeModel(
        currentVersion: String,
        releaseJSON: Data,
        updatesDirectory: URL? = nil,
        counter: UpdateCallCounter = UpdateCallCounter(),
        openDownloadedFile: @escaping (URL) -> Bool = { _ in true },
        downloadWriter: UpdateService.DownloadWriter? = nil
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
            downloadWriter: downloadWriter ?? { _, destinationURL, _, progress in
                await progress(0.5)
                try Data("update".utf8).write(to: destinationURL)
            }
        )
        let backend = try NativeBackendService(paths: paths, updateService: updateService)
        return AppModel(backend: backend, openDownloadedFile: openDownloadedFile)
    }

    private func makeBasicModel() throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperBasicModelTests-\(UUID().uuidString)", isDirectory: true)
        let backend = try NativeBackendService(paths: AppStoragePaths(rootURL: pathsRoot))
        return AppModel(backend: backend)
    }

    private func makeModelWithCachedSubjects(_ subjects: [Subject]) throws -> AppModel {
        let pathsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperSubjectLoadModelTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppStoragePaths(rootURL: pathsRoot)
        try SearchCacheStore(paths: paths).save(subjects, source: .automatic, key: "subjects")
        let backend = try NativeBackendService(paths: paths)
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

private struct DiagnosticTestError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
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

private final class URLRecorder {
    private var recordedURLs: [URL] = []

    func record(_ url: URL) {
        recordedURLs.append(url)
    }

    func lastValue() -> URL? {
        recordedURLs.last
    }

    func values() -> [URL] {
        recordedURLs
    }
}

private actor UpdateDownloadCoordinator {
    private var didReportProgress = false
    private var progressWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func recordProgress() {
        didReportProgress = true
        let waiters = progressWaiters
        progressWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForProgress() async {
        if didReportProgress {
            return
        }

        await withCheckedContinuation { continuation in
            progressWaiters.append(continuation)
        }
    }

    func waitForFinishPermission() async {
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }

    func allowFinish() {
        let continuation = finishContinuation
        finishContinuation = nil
        continuation?.resume()
    }
}
