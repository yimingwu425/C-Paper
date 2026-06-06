import Foundation
import XCTest
@testable import CPaperNativeApp

final class NativeBackendServicePreviewTests: XCTestCase {
    func testPreviewURLReturnsExistingDownloadedFileBeforeUsingSharedTransfer() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperPreviewTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = try AppStoragePaths(rootURL: root)
        let saveDirectory = root.appendingPathComponent("Downloads", isDirectory: true)
        let localFileURL = saveDirectory
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("QP", isDirectory: true)
            .appendingPathComponent("9709_s24_qp_12.pdf")
        try FileManager.default.createDirectory(at: localFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("downloaded".utf8).write(to: localFileURL)

        let transferCalls = PreviewTransferRecorder()
        let backend = try NativeBackendService(
            paths: paths,
            previewTransfer: { sourceURL, destinationURL, proxyURL in
                await transferCalls.record(sourceURL: sourceURL, destinationURL: destinationURL, proxyURL: proxyURL)
                try Data("preview".utf8).write(to: destinationURL)
            }
        )

        let resolvedURL = try await backend.previewURL(
            for: PaperFile(
                filename: "9709_s24_qp_12.pdf",
                url: URL(string: "https://example.test/original.pdf")!,
                year: 2024,
                season: "Jun",
                paperType: "QP",
                subjectCode: "9709",
                number: "12",
                label: "Paper 1",
                sourceID: .frankcie
            ),
            settings: DownloadSettings(saveDirectory: saveDirectory.path)
        )

        let didRecordTransfer = await transferCalls.didRecordTransfer()
        XCTAssertEqual(resolvedURL, localFileURL)
        XCTAssertFalse(didRecordTransfer)
    }

    func testPreviewURLUsesResolvedEasyPaperURLProxyAndCacheReuse() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperPreviewTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = try AppStoragePaths(rootURL: root)
        let transferCalls = PreviewTransferRecorder()
        let backend = try NativeBackendService(
            paths: paths,
            previewTransfer: { sourceURL, destinationURL, proxyURL in
                await transferCalls.record(sourceURL: sourceURL, destinationURL: destinationURL, proxyURL: proxyURL)
                try Data("preview".utf8).write(to: destinationURL)
            }
        )

        let originalURL = URL(string: "https://easypaper.com/paper/9709_s24_qp_12.pdf")!
            .withEasyPaperFilePath("CAIE|AS and A Level|9709|2024|Summer|9709_s24_qp_12.pdf")
        let file = PaperFile(
            filename: "9709_s24_qp_12.pdf",
            url: originalURL,
            year: 2024,
            season: "Jun",
            paperType: "QP",
            subjectCode: "9709",
            number: "12",
            label: "Paper 1",
            sourceID: .easyPaper
        )
        let settings = DownloadSettings(
            saveDirectory: root.appendingPathComponent("Downloads", isDirectory: true).path,
            proxyURL: "http://127.0.0.1:7890"
        )

        let firstURL = try await backend.previewURL(for: file, settings: settings)
        let secondURL = try await backend.previewURL(for: file, settings: settings)
        let calls = await transferCalls.calls()

        XCTAssertEqual(firstURL, secondURL)
        XCTAssertEqual(try String(contentsOf: firstURL), "preview")
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].proxyURL, "http://127.0.0.1:7890")
        XCTAssertEqual(calls[0].sourceURL.host, "easypaper.com")
        XCTAssertTrue(calls[0].sourceURL.path.contains("/paperdownload/dir_v3/"))
        XCTAssertNotEqual(calls[0].sourceURL.absoluteString, originalURL.absoluteString)
    }
}

private actor PreviewTransferRecorder {
    typealias Call = (sourceURL: URL, destinationURL: URL, proxyURL: String)

    private var recordedCalls: [Call] = []

    func record(sourceURL: URL, destinationURL: URL, proxyURL: String) {
        recordedCalls.append((sourceURL, destinationURL, proxyURL))
    }

    func calls() -> [Call] {
        recordedCalls
    }

    func didRecordTransfer() -> Bool {
        !recordedCalls.isEmpty
    }
}
