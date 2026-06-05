import Foundation
import XCTest
@testable import CPaperNativeApp

final class UpdateServiceTests: XCTestCase {
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

    func testDownloadUpdateWritesPartFileThenMovesToUpdatesDirectory() async throws {
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
        let service = UpdateService(
            currentVersion: "6.0.2",
            updatesDirectory: tempDirectory,
            downloadWriter: { sourceURL, destinationURL, proxyURL, progress in
                XCTAssertEqual(sourceURL.absoluteString, "https://example.test/update.dmg")
                XCTAssertEqual(proxyURL, "")
                await progress(0.5)
                try Data("dmg".utf8).write(to: destinationURL)
            }
        )

        let destinationURL = try await service.downloadUpdate(release, proxyURL: "") { _ in }

        XCTAssertEqual(destinationURL.lastPathComponent, release.assetName)
        XCTAssertEqual(try String(contentsOf: destinationURL), "dmg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("\(release.assetName).part").path))
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
