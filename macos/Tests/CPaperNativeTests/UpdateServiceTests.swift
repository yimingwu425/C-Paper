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
    }

    func testLatestReleaseWithSameVersionReturnsUpToDate() async throws {
        let service = UpdateService(
            currentVersion: "6.0.2",
            networkClientFactory: { _ in
                MockUpdateNetworkClient(data: Self.releaseJSON(tag: "v6.0.2"))
            }
        )

        let result = try await service.checkForUpdate(proxyURL: "")

        XCTAssertEqual(result, .upToDate(current: "6.0.2", latest: "6.0.2"))
    }

    func testLatestReleaseWithNewerDMGReturnsAvailableRelease() async throws {
        let service = UpdateService(
            currentVersion: "6.0.2",
            networkClientFactory: { _ in
                MockUpdateNetworkClient(data: Self.releaseJSON(tag: "v6.0.3"))
            }
        )

        let result = try await service.checkForUpdate(proxyURL: "")

        guard case let .available(release) = result else {
            return XCTFail("Expected available update")
        }
        XCTAssertEqual(release.version, "6.0.3")
        XCTAssertEqual(release.tagName, "v6.0.3")
        XCTAssertEqual(release.assetName, "C-Paper-Native-6.0.3-standalone-20260604.dmg")
        XCTAssertEqual(release.downloadURL.absoluteString, "https://github.com/yimingwu425/C-Paper/releases/download/v6.0.3/C-Paper-Native-6.0.3-standalone-20260604.dmg")
    }

    func testLatestReleaseWithoutDMGThrowsClearError() async throws {
        let json = """
        {
          "tag_name": "v6.0.3",
          "name": "C-Paper Native 6.0.3",
          "html_url": "https://github.com/yimingwu425/C-Paper/releases/tag/v6.0.3",
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
            currentVersion: "6.0.2",
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
            version: "6.0.3",
            tagName: "v6.0.3",
            name: "C-Paper Native 6.0.3",
            htmlURL: URL(string: "https://github.com/yimingwu425/C-Paper/releases/tag/v6.0.3")!,
            assetName: "C-Paper-Native-6.0.3-standalone-20260604.dmg",
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
            currentVersion: "6.0.2",
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("\(release.assetName).part").path))
        let progressValues = await progress.compactValues()
        XCTAssertEqual(try XCTUnwrap(progressValues.first), 0, accuracy: 0.0001)
        XCTAssertTrue(progressValues.contains(where: { $0 > 0 && $0 < 1 }))
        XCTAssertEqual(try XCTUnwrap(progressValues.last), 1, accuracy: 0.0001)
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
            currentVersion: "6.0.2",
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

        let partialURL = tempDirectory.appendingPathComponent("\(release.assetName).part")
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent(release.assetName).path))
    }

    func testDownloadUpdateRemovesPartialFileWhenTransferFailsAfterWriting() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperUpdateServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let release = makeRelease()

        let service = UpdateService(
            currentVersion: "6.0.2",
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

        let partialURL = tempDirectory.appendingPathComponent("\(release.assetName).part")
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
    }

    private func makeRelease() -> AppUpdateRelease {
        AppUpdateRelease(
            version: "6.0.3",
            tagName: "v6.0.3",
            name: "C-Paper Native 6.0.3",
            htmlURL: URL(string: "https://github.com/yimingwu425/C-Paper/releases/tag/v6.0.3")!,
            assetName: "C-Paper-Native-6.0.3-standalone-20260604.dmg",
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
