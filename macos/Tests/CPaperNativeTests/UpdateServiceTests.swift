import Foundation
import XCTest
@testable import CPaperNativeApp

final class UpdateServiceTests: XCTestCase {
    override func tearDown() {
        MockTransferURLProtocol.reset()
        super.tearDown()
    }

    func testAppVersionComparesSemverTags() throws {
        XCTAssertLessThan(try AppVersion("6.0.2"), try AppVersion("6.0.10"))
        XCTAssertLessThan(try AppVersion("v6.0.2"), try AppVersion("6.1.0"))
        XCTAssertEqual(try AppVersion("6.0"), try AppVersion("6.0.0"))
        XCTAssertEqual(try AppVersion("6.0.1+5"), try AppVersion("6.0.1"))
        XCTAssertEqual(try AppVersion("6.0.1-rc1"), try AppVersion("6.0.1"))
    }

    func testAppVersionRejectsMalformedVersions() {
        XCTAssertThrowsError(try AppVersion("6..1"))
        XCTAssertThrowsError(try AppVersion("6.x.4"))
        XCTAssertThrowsError(try AppVersion("6."))
    }

    func testLatestReleaseWithSameVersionReturnsUpToDate() async throws {
        let service = UpdateService(
            currentVersion: "6.0.3",
            networkClientFactory: { _ in
                MockUpdateNetworkClient(data: Self.releaseJSON(tag: "v6.0.3"))
            }
        )

        let result = try await service.checkForUpdate(proxyURL: "")

        XCTAssertEqual(result, .upToDate(current: "6.0.3", latest: "6.0.3"))
    }

    func testLatestReleaseWithNewerDMGReturnsAvailableRelease() async throws {
        let service = UpdateService(
            currentVersion: "6.0.3",
            networkClientFactory: { _ in
                MockUpdateNetworkClient(data: Self.releaseJSON(tag: "v6.0.4"))
            }
        )

        let result = try await service.checkForUpdate(proxyURL: "")

        guard case let .available(release) = result else {
            return XCTFail("Expected available update")
        }
        XCTAssertEqual(release.version, "6.0.4")
        XCTAssertEqual(release.tagName, "v6.0.4")
        XCTAssertEqual(release.assetName, "C-Paper-Native-6.0.4-standalone-20260604.dmg")
        XCTAssertEqual(release.downloadURL.absoluteString, "https://github.com/yimingwu425/C-Paper/releases/download/v6.0.4/C-Paper-Native-6.0.4-standalone-20260604.dmg")
    }

    func testLatestReleaseWithoutDMGThrowsClearError() async throws {
        let json = """
        {
          "tag_name": "v6.0.4",
          "name": "C-Paper Native 6.0.4",
          "html_url": "https://github.com/yimingwu425/C-Paper/releases/tag/v6.0.4",
          "assets": [
            {
              "name": "source.zip",
              "content_type": "application/zip",
              "browser_download_url": "https://example.test/source.zip"
            }
          ]
        }
        """.data(using: .utf8)!
        let service = UpdateService(
            currentVersion: "6.0.3",
            networkClientFactory: { _ in MockUpdateNetworkClient(data: json) }
        )

        do {
            _ = try await service.checkForUpdate(proxyURL: "")
            XCTFail("Expected invalid release error")
        } catch let error as UpdateServiceError {
            XCTAssertEqual(error, .noCompatibleDMGAsset)
        }
    }

    func testDownloadUpdateStreamsThroughSharedTransferAndAtomicallyReplacesExistingFile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperUpdateServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let release = AppUpdateRelease(
            version: "6.0.4",
            tagName: "v6.0.4",
            name: "C-Paper Native 6.0.4",
            htmlURL: URL(string: "https://github.com/yimingwu425/C-Paper/releases/tag/v6.0.4")!,
            assetName: "C-Paper-Native-6.0.4-standalone-20260604.dmg",
            downloadURL: URL(string: "https://example.test/update.dmg")!
        )
        let existingURL = tempDirectory.appendingPathComponent(release.assetName)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: existingURL)
        let requests = RequestRecorder()
        let progress = ProgressRecorder()

        MockTransferURLProtocol.setHandler { request in
            await requests.record(request)
            return MockTransferResponse(
                response: HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "8"]
                )!,
                chunks: [Data("new-".utf8), Data("dmg!".utf8)]
            )
        }

        let service = UpdateService(
            currentVersion: "6.0.3",
            updatesDirectory: tempDirectory,
            transferClientFactory: { proxyURL in
                XCTAssertEqual(proxyURL, "http://127.0.0.1:7890")
                return HTTPFileTransferClient(session: makeTransferSession(), chunkSize: 4)
            }
        )

        let destinationURL = try await service.downloadUpdate(release, proxyURL: "http://127.0.0.1:7890") { value in
            await progress.record(value)
        }

        let firstRequest = await requests.first()
        let request = try XCTUnwrap(firstRequest)
        XCTAssertEqual(request.url?.absoluteString, release.downloadURL.absoluteString)
        XCTAssertEqual(destinationURL.lastPathComponent, release.assetName)
        XCTAssertEqual(try String(contentsOf: destinationURL), "new-dmg!")
        let remainingPartials = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("\(release.assetName).part.") }
        XCTAssertTrue(remainingPartials.isEmpty)
        let progressValues = await progress.compactValues()
        XCTAssertEqual(try XCTUnwrap(progressValues.first), 0, accuracy: 0.0001)
        XCTAssertTrue(progressValues.contains(where: { $0 > 0 && $0 < 1 }))
        XCTAssertEqual(try XCTUnwrap(progressValues.last), 1, accuracy: 0.0001)
    }

    func testDownloadUpdateUsesUniquePartialFilesForConcurrentRequests() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperUpdateServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let release = makeRelease()
        let partialRecorder = PartialDestinationRecorder()
        let gate = UpdateDownloadGate()

        let service = UpdateService(
            currentVersion: "6.0.3",
            updatesDirectory: tempDirectory,
            downloadWriter: { _, destinationURL, _, _ in
                await partialRecorder.record(destinationURL)
                await gate.recordStart()
                await gate.waitForRelease()
                try Data(UUID().uuidString.utf8).write(to: destinationURL)
            }
        )

        async let firstURL = service.downloadUpdate(release, proxyURL: "") { _ in }
        async let secondURL = service.downloadUpdate(release, proxyURL: "") { _ in }

        try await gate.waitForStarts(count: 2)
        await gate.release()

        let resolvedFirstURL = try await firstURL
        let resolvedSecondURL = try await secondURL
        let partialURLs = await partialRecorder.urls()

        XCTAssertEqual(Set(partialURLs).count, 2)
        XCTAssertTrue(partialURLs.allSatisfy { $0.lastPathComponent.hasPrefix("\(release.assetName).part.") })
        XCTAssertEqual(resolvedFirstURL, resolvedSecondURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolvedFirstURL.path))
    }

    func testDestinationURLUsesSanitizedAssetNameInsideUpdatesDirectory() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperUpdateServiceTests-\(UUID().uuidString)", isDirectory: true)
        let service = UpdateService(
            currentVersion: "6.0.3",
            updatesDirectory: tempDirectory
        )
        let release = AppUpdateRelease(
            version: "6.0.4",
            tagName: "v6.0.4",
            name: "C-Paper Native 6.0.4",
            htmlURL: URL(string: "https://github.com/yimingwu425/C-Paper/releases/tag/v6.0.4")!,
            assetName: "C Paper: Native 6.0.4 Final?.dmg",
            downloadURL: URL(string: "https://example.test/update.dmg")!
        )

        let destinationURL = service.destinationURL(for: release)

        XCTAssertEqual(destinationURL.deletingLastPathComponent(), tempDirectory)
        XCTAssertEqual(destinationURL.lastPathComponent, "C-Paper--Native-6.0.4-Final-.dmg")
    }

    func testDownloadUpdateThrowsForErrorResponseAndRemovesPartialFile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperUpdateServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let release = makeRelease()

        MockTransferURLProtocol.setHandler { request in
            MockTransferResponse(
                response: HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "4"]
                )!,
                chunks: [Data("nope".utf8)]
            )
        }

        let service = UpdateService(
            currentVersion: "6.0.3",
            updatesDirectory: tempDirectory,
            transferClientFactory: { _ in
                HTTPFileTransferClient(session: makeTransferSession(), chunkSize: 2)
            }
        )

        do {
            _ = try await service.downloadUpdate(release, proxyURL: "") { _ in }
            XCTFail("Expected HTTP status error")
        } catch let error as NetworkClientError {
            XCTAssertEqual(error, .httpStatus(404))
        }

        let remainingPartials = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("\(release.assetName).part.") }
        XCTAssertTrue(remainingPartials.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent(release.assetName).path))
    }

    func testDownloadUpdateRemovesPartialFileWhenTransferFailsAfterWriting() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperUpdateServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let release = makeRelease()

        let service = UpdateService(
            currentVersion: "6.0.3",
            updatesDirectory: tempDirectory,
            downloadWriter: { _, destinationURL, _, _ in
                try Data("partial".utf8).write(to: destinationURL)
                throw URLError(.networkConnectionLost)
            }
        )

        do {
            _ = try await service.downloadUpdate(release, proxyURL: "") { _ in }
            XCTFail("Expected transfer failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .networkConnectionLost)
        }

        let remainingPartials = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("\(release.assetName).part.") }
        XCTAssertTrue(remainingPartials.isEmpty)
    }

    func testDownloadUpdateDoesNotMoveFileIntoFinalLocationAfterCancellation() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperUpdateServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let release = makeRelease()
        let gate = UpdateDownloadGate()

        let service = UpdateService(
            currentVersion: "6.0.3",
            updatesDirectory: tempDirectory,
            downloadWriter: { _, destinationURL, _, _ in
                try Data("partial".utf8).write(to: destinationURL)
                await gate.recordStart()
                await gate.waitForRelease()
            }
        )

        let task = Task {
            try await service.downloadUpdate(release, proxyURL: "") { _ in }
        }

        try await gate.waitForStarts(count: 1)
        task.cancel()
        await gate.release()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }

        let destinationURL = service.destinationURL(for: release)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        let remainingPartials = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("\(release.assetName).part.") }
        XCTAssertTrue(remainingPartials.isEmpty)
    }

    private func makeRelease() -> AppUpdateRelease {
        AppUpdateRelease(
            version: "6.0.4",
            tagName: "v6.0.4",
            name: "C-Paper Native 6.0.4",
            htmlURL: URL(string: "https://github.com/yimingwu425/C-Paper/releases/tag/v6.0.4")!,
            assetName: "C-Paper-Native-6.0.4-standalone-20260604.dmg",
            downloadURL: URL(string: "https://example.test/update.dmg")!
        )
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

private final class MockUpdateNetworkClient: NetworkClientProtocol, @unchecked Sendable {
    let data: Data

    init(data: Data) {
        self.data = data
    }

    func data(for request: URLRequest) async throws -> Data {
        data
    }
}

private actor PartialDestinationRecorder {
    private var recorded: [URL] = []

    func record(_ url: URL) {
        recorded.append(url)
    }

    func urls() -> [URL] {
        recorded
    }
}

private actor UpdateDownloadGate {
    private var starts = 0
    private var released = false
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    func recordStart() {
        starts += 1
    }

    func waitForStarts(count: Int) async throws {
        for _ in 0..<100 {
            if starts >= count {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for update download starts.")
    }

    func waitForRelease() async {
        guard !released else { return }
        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
    }

    func release() {
        released = true
        releaseContinuations.forEach { $0.resume() }
        releaseContinuations.removeAll()
    }
}
