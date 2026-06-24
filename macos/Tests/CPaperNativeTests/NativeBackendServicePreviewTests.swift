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

    func testPreviewURLRejectsUnsafeFilenameBeforeDownloading() async throws {
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

        do {
            _ = try await backend.previewURL(
                for: PaperFile(
                    filename: "../settings.json",
                    url: URL(string: "https://example.test/original.pdf")!,
                    year: 2024,
                    season: "Jun",
                    paperType: "QP",
                    subjectCode: "9709",
                    number: "12",
                    label: "Paper 1",
                    sourceID: .frankcie
                ),
                settings: DownloadSettings(saveDirectory: root.appendingPathComponent("Downloads", isDirectory: true).path)
            )
            XCTFail("Expected invalid filename error")
        } catch let error as BackendError {
            XCTAssertEqual(error, .invalidFilename("../settings.json"))
        }

        let didRecordTransfer = await transferCalls.didRecordTransfer()
        XCTAssertFalse(didRecordTransfer)
    }

    func testPreviewURLReusesSingleInFlightTransferForConcurrentRequests() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperPreviewTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = try AppStoragePaths(rootURL: root)
        let transferCalls = PreviewTransferRecorder()
        let gate = PreviewTransferGate()
        let backend = try NativeBackendService(
            paths: paths,
            previewTransfer: { sourceURL, destinationURL, proxyURL in
                await transferCalls.record(sourceURL: sourceURL, destinationURL: destinationURL, proxyURL: proxyURL)
                await gate.recordStart()
                await gate.waitForRelease()
                try Data("preview".utf8).write(to: destinationURL)
            }
        )

        let file = PaperFile(
            filename: "9709_s24_qp_12.pdf",
            url: URL(string: "https://example.test/original.pdf")!,
            year: 2024,
            season: "Jun",
            paperType: "QP",
            subjectCode: "9709",
            number: "12",
            label: "Paper 1",
            sourceID: .frankcie
        )
        let settings = DownloadSettings(saveDirectory: root.appendingPathComponent("Downloads", isDirectory: true).path)

        async let firstURL = backend.previewURL(for: file, settings: settings)
        async let secondURL = backend.previewURL(for: file, settings: settings)

        try await gate.waitForStarts(count: 1)
        try await Task.sleep(nanoseconds: 50_000_000)
        await gate.release()

        let resolvedFirstURL = try await firstURL
        let resolvedSecondURL = try await secondURL
        let calls = await transferCalls.calls()

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(resolvedFirstURL, resolvedSecondURL)
        XCTAssertEqual(try String(contentsOf: resolvedFirstURL), "preview")
    }

    func testPreviewURLDoesNotLeaveFinalCacheFileWhenTransferFailsAfterWritingPartialData() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperPreviewTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = try AppStoragePaths(rootURL: root)
        let backend = try NativeBackendService(
            paths: paths,
            previewTransfer: { _, destinationURL, _ in
                try Data("preview".utf8).write(to: destinationURL)
                throw URLError(.networkConnectionLost)
            }
        )
        let file = PaperFile(
            filename: "9709_s24_qp_12.pdf",
            url: URL(string: "https://example.test/original.pdf")!,
            year: 2024,
            season: "Jun",
            paperType: "QP",
            subjectCode: "9709",
            number: "12",
            label: "Paper 1",
            sourceID: .frankcie
        )

        do {
            _ = try await backend.previewURL(
                for: file,
                settings: DownloadSettings(saveDirectory: root.appendingPathComponent("Downloads", isDirectory: true).path)
            )
            XCTFail("Expected transfer failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .networkConnectionLost)
        }

        let cacheURL = paths.cacheDirectory
            .appendingPathComponent("preview", isDirectory: true)
            .appendingPathComponent("9709_s24_qp_12.pdf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testPreviewURLCancelsInFlightTransferBeforeFinalCacheCommit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperPreviewTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = try AppStoragePaths(rootURL: root)
        let gate = PreviewTransferGate()
        let backend = try NativeBackendService(
            paths: paths,
            previewTransfer: { _, destinationURL, _ in
                try Data("preview".utf8).write(to: destinationURL)
                await gate.recordStart()
                await gate.waitForRelease()
            }
        )
        let file = PaperFile(
            filename: "9709_s24_qp_12.pdf",
            url: URL(string: "https://example.test/original.pdf")!,
            year: 2024,
            season: "Jun",
            paperType: "QP",
            subjectCode: "9709",
            number: "12",
            label: "Paper 1",
            sourceID: .frankcie
        )

        let task = Task {
            try await backend.previewURL(
                for: file,
                settings: DownloadSettings(saveDirectory: root.appendingPathComponent("Downloads", isDirectory: true).path)
            )
        }

        await gate.waitForStart()
        task.cancel()
        await gate.release()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }

        let cacheURL = paths.cacheDirectory
            .appendingPathComponent("preview", isDirectory: true)
            .appendingPathComponent("9709_s24_qp_12.pdf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
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

private actor PreviewTransferGate {
    private var starts = 0
    private var released = false
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    func recordStart() {
        starts += 1
    }

    func waitForStart() async {
        for _ in 0..<100 {
            if starts > 0 {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for preview transfer start.")
    }

    func waitForStarts(count: Int) async throws {
        for _ in 0..<100 {
            if starts >= count {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for preview transfer starts.")
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
