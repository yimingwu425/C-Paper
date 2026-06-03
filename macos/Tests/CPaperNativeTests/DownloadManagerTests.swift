import Foundation
import XCTest
@testable import CPaperNativeApp

final class DownloadManagerTests: XCTestCase {
    func testDestinationBuilderSplitsQuestionPapersAndMarkSchemesByYearWhenNotMerged() throws {
        let root = temporaryDirectory()
        let options = options(merge: false)
        let group = paperGroup(sy: "s23")

        let plan = try DownloadDestinationBuilder.build(groups: [group], saveDirectory: root, options: options)

        XCTAssertEqual(plan.tasks.count, 2)
        XCTAssertEqual(plan.tasks[0].saveURL.path, root.appendingPathComponent("2023/QP/9709_s23_qp_12.pdf").path)
        XCTAssertEqual(plan.tasks[1].saveURL.path, root.appendingPathComponent("2023/MS/9709_s23_ms_12.pdf").path)
    }

    func testDestinationBuilderWritesToRootWhenMerged() throws {
        let root = temporaryDirectory()
        let options = options(merge: true)

        let plan = try DownloadDestinationBuilder.build(groups: [paperGroup(sy: "s23")], saveDirectory: root, options: options)

        XCTAssertEqual(plan.tasks.map(\.saveURL.path), [
            root.appendingPathComponent("9709_s23_qp_12.pdf").path,
            root.appendingPathComponent("9709_s23_ms_12.pdf").path
        ])
    }

    func testDestinationBuilderExcludesMarkSchemesWhenDisabled() throws {
        let root = temporaryDirectory()
        let options = options(includeMarkSchemes: false)

        let plan = try DownloadDestinationBuilder.build(groups: [paperGroup(sy: "s23")], saveDirectory: root, options: options)

        XCTAssertEqual(plan.tasks.count, 1)
        XCTAssertEqual(plan.tasks[0].ftype, "QP")
    }

    func testDestinationBuilderRejectsPathTraversalAndNonPDFComponents() throws {
        let root = temporaryDirectory()
        let options = options()
        let group = NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: "s23",
            number: "12",
            paperGroup: 1,
            qp: nil,
            ms: nil,
            extras: [
                component(filename: "../evil.pdf", type: "QP"),
                component(filename: "notes.txt", type: "QP", url: URL(string: "https://example.test/notes.txt")!),
                component(filename: "safe.pdf", type: "QP", url: URL(string: "https://example.test/safe.bin")!),
                component(filename: "9709_s23_qp_12.pdf", type: "QP")
            ]
        )

        let plan = try DownloadDestinationBuilder.build(groups: [group], saveDirectory: root, options: options)

        XCTAssertEqual(plan.tasks.map(\.filename), ["9709_s23_qp_12.pdf"])
    }

    func testDuplicateSkipAndMissingModesSkipExistingFiles() throws {
        let root = temporaryDirectory()
        let existing = root.appendingPathComponent("2023/QP/9709_s23_qp_12.pdf")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: existing)
        let group = NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: "s23",
            number: "12",
            paperGroup: 1,
            qp: component(filename: "9709_s23_qp_12.pdf", type: "QP"),
            ms: nil,
            extras: []
        )

        let skipPlan = try DownloadDestinationBuilder.build(
            groups: [group],
            saveDirectory: root,
            options: options(duplicateMode: .skip)
        )
        let missingPlan = try DownloadDestinationBuilder.build(
            groups: [group],
            saveDirectory: root,
            options: options(duplicateMode: .missing)
        )
        let overwritePlan = try DownloadDestinationBuilder.build(
            groups: [group],
            saveDirectory: root,
            options: options(duplicateMode: .overwrite)
        )

        XCTAssertEqual(skipPlan.tasks.count, 0)
        XCTAssertEqual(skipPlan.skipped, 1)
        XCTAssertEqual(missingPlan.tasks.count, 0)
        XCTAssertEqual(missingPlan.skipped, 1)
        XCTAssertEqual(overwritePlan.tasks.count, 1)
        XCTAssertEqual(overwritePlan.skipped, 0)
    }

    func testDownloadManagerCancelsPendingAndActiveItems() async throws {
        let root = temporaryDirectory()
        let manager = DownloadManager { _, partialURL in
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try Data("late".utf8).write(to: partialURL)
        }
        let group = NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: "s24",
            number: "12",
            paperGroup: 1,
            qp: component(filename: "a.pdf", type: "QP", sy: "s24"),
            ms: nil,
            extras: [
                component(filename: "b.pdf", type: "QP", sy: "s24"),
                component(filename: "c.pdf", type: "QP", sy: "s24")
            ]
        )

        try await manager.start(groups: [group], saveDirectory: root, options: options(threads: 1))
        try await Task.sleep(nanoseconds: 50_000_000)
        await manager.cancel()
        let snapshot = await manager.status()
        let items = await manager.items()

        XCTAssertEqual(snapshot.phase, "done")
        XCTAssertEqual(snapshot.cancelled, 3)
        XCTAssertTrue(items.allSatisfy { $0.status == .cancelled })
    }

    func testDownloadManagerRetriesFailuresBeforeSucceeding() async throws {
        let root = temporaryDirectory()
        let attempts = AttemptCounter()
        let manager = DownloadManager { _, partialURL in
            let current = await attempts.next()

            if current < 3 {
                throw NSError(domain: "DownloadManagerTests", code: current, userInfo: [NSLocalizedDescriptionKey: "temporary"])
            }

            try Data("ok".utf8).write(to: partialURL)
        }

        try await manager.start(
            groups: [NativePaperGroup(
                sourceID: .frankcie,
                subjectCode: "9709",
                sy: "s24",
                number: "12",
                paperGroup: 1,
                qp: component(filename: "retry.pdf", type: "QP", sy: "s24"),
                ms: nil,
                extras: []
            )],
            saveDirectory: root,
            options: options(threads: 1)
        )
        let snapshot = try await waitForCompletion(manager)

        XCTAssertEqual(snapshot.success, 1)
        XCTAssertEqual(snapshot.failed, 0)
        let attemptCount = await attempts.value
        XCTAssertEqual(attemptCount, 3)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("2024/QP/retry.pdf")), "ok")
    }

    func testDownloadManagerStatusCountsDoneAndFailedItems() async throws {
        let root = temporaryDirectory()
        let manager = DownloadManager { sourceURL, partialURL in
            if sourceURL.lastPathComponent == "bad.pdf" {
                throw NSError(domain: "DownloadManagerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "permanent"])
            }
            try Data("ok".utf8).write(to: partialURL)
        }
        let group = NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: "s25",
            number: "12",
            paperGroup: 1,
            qp: component(filename: "good.pdf", type: "QP", sy: "s25", url: URL(string: "https://example.test/good.pdf")!),
            ms: nil,
            extras: [
                component(filename: "bad.pdf", type: "QP", sy: "s25", url: URL(string: "https://example.test/bad.pdf")!)
            ]
        )

        try await manager.start(groups: [group], saveDirectory: root, options: options(threads: 2))
        let snapshot = try await waitForCompletion(manager)
        let items = await manager.items()

        XCTAssertEqual(snapshot.total, 2)
        XCTAssertEqual(snapshot.done, 2)
        XCTAssertEqual(snapshot.success, 1)
        XCTAssertEqual(snapshot.failed, 1)
        XCTAssertEqual(items.filter { $0.status == .done }.count, 1)
        XCTAssertEqual(items.filter { $0.status == .failed }.count, 1)
    }

    private func paperGroup(sy: String) -> NativePaperGroup {
        NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: sy,
            number: "12",
            paperGroup: 1,
            qp: component(filename: "9709_s23_qp_12.pdf", type: "QP", label: "Paper 1", sy: sy),
            ms: component(filename: "9709_s23_ms_12.pdf", type: "MS", label: "Mark Scheme 1", sy: sy),
            extras: []
        )
    }

    private func component(
        filename: String,
        type: String,
        label: String? = "Paper",
        sy: String = "s23",
        url: URL? = nil
    ) -> PaperComponent {
        PaperComponent(
            sourceID: .frankcie,
            filename: filename,
            url: url ?? URL(string: "https://example.test/\(filename)")!,
            paperType: type,
            subjectCode: "9709",
            sy: sy,
            number: "12",
            label: label
        )
    }

    private func options(
        rate: Double = 20,
        threads: Int = 2,
        merge: Bool = false,
        duplicateMode: DuplicateMode = .overwrite,
        includeMarkSchemes: Bool = true
    ) -> DownloadOptions {
        DownloadOptions(
            rate: rate,
            threads: threads,
            merge: merge,
            duplicateMode: duplicateMode,
            includeMarkSchemes: includeMarkSchemes
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperDownloadManagerTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func waitForCompletion(_ manager: DownloadManager) async throws -> DownloadStatusSnapshot {
        for _ in 0..<200 {
            let snapshot = await manager.status()
            if !snapshot.isRunning {
                return snapshot
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Timed out waiting for download manager completion.")
        return await manager.status()
    }
}

private actor AttemptCounter {
    private var count = 0

    var value: Int {
        count
    }

    func next() -> Int {
        count += 1
        return count
    }
}
