import Foundation
import XCTest
@testable import CPaperNativeApp

final class StagedFileSystemTests: XCTestCase {
    func testStagedWriteMovesNewFileIntoPlaceAndCleansPartial() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperStagedFileSystemTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileSystem = StagedFileSystem(fileManager: .default)
        let destinationURL = root.appendingPathComponent("nested/output.pdf")

        try await fileSystem.stagedWrite(to: destinationURL) { partialURL in
            try Data("ok".utf8).write(to: partialURL)
        }

        XCTAssertEqual(try String(contentsOf: destinationURL), "ok")
        let remaining = try FileManager.default.contentsOfDirectory(at: destinationURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("output.pdf.part.") }
        XCTAssertTrue(remaining.isEmpty)
    }

    func testStagedWriteRemovesPartialWhenCancelledBeforeFinalize() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperStagedFileSystemTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileSystem = StagedFileSystem(fileManager: .default)
        let destinationURL = root.appendingPathComponent("output.pdf")
        let gate = StagedFileGate()

        let task = Task {
            try await fileSystem.stagedWrite(to: destinationURL, beforeFinalize: {
                await gate.reachedFinalize()
                await gate.waitForRelease()
            }) { partialURL in
                try Data("partial".utf8).write(to: partialURL)
            }
        }

        await gate.waitForFinalize()
        task.cancel()
        await gate.release()

        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        let remaining = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("output.pdf.part.") }
        XCTAssertTrue(remaining.isEmpty)
    }
}

private actor StagedFileGate {
    private var reached = false
    private var released = false
    private var finalizeContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    func reachedFinalize() {
        reached = true
        let waiters = finalizeContinuations
        finalizeContinuations.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForFinalize() async {
        if reached {
            return
        }
        await withCheckedContinuation { continuation in
            finalizeContinuations.append(continuation)
        }
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
