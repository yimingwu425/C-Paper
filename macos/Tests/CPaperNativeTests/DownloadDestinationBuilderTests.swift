import Foundation
import XCTest
@testable import CPaperNativeApp

final class DownloadDestinationBuilderTests: XCTestCase {
    func testDestinationBuilderRejectsNonFileSaveDirectoryWithLocalizedError() {
        XCTAssertThrowsError(
            try DownloadDestinationBuilder.build(
                groups: [makeDownloadPaperGroup(sy: "s23")],
                saveDirectory: URL(string: "https://example.test/downloads")!,
                options: makeDownloadOptions()
            )
        ) { error in
            XCTAssertEqual(error as? DownloadDestinationError, .invalidSaveDirectory)
            XCTAssertEqual(error.localizedDescription, "保存目录无效。")
        }
    }

    func testDestinationBuilderSplitsQuestionPapersAndMarkSchemesByYearWhenNotMerged() throws {
        let root = makeTemporaryDownloadDirectory()
        let options = makeDownloadOptions(merge: false)
        let group = makeDownloadPaperGroup(sy: "s23")

        let plan = try DownloadDestinationBuilder.build(groups: [group], saveDirectory: root, options: options)

        XCTAssertEqual(plan.tasks.count, 2)
        XCTAssertEqual(plan.tasks[0].saveURL.path, root.appendingPathComponent("2023/QP/9709_s23_qp_12.pdf").path)
        XCTAssertEqual(plan.tasks[1].saveURL.path, root.appendingPathComponent("2023/MS/9709_s23_ms_12.pdf").path)
    }

    func testDestinationBuilderWritesToRootWhenMerged() throws {
        let root = makeTemporaryDownloadDirectory()
        let options = makeDownloadOptions(merge: true)

        let plan = try DownloadDestinationBuilder.build(groups: [makeDownloadPaperGroup(sy: "s23")], saveDirectory: root, options: options)

        XCTAssertEqual(plan.tasks.map(\.saveURL.path), [
            root.appendingPathComponent("9709_s23_qp_12.pdf").path,
            root.appendingPathComponent("9709_s23_ms_12.pdf").path
        ])
    }

    func testDestinationBuilderExcludesMarkSchemesWhenDisabled() throws {
        let root = makeTemporaryDownloadDirectory()
        let options = makeDownloadOptions(includeMarkSchemes: false)

        let plan = try DownloadDestinationBuilder.build(groups: [makeDownloadPaperGroup(sy: "s23")], saveDirectory: root, options: options)

        XCTAssertEqual(plan.tasks.count, 1)
        XCTAssertEqual(plan.tasks[0].ftype, "QP")
    }

    func testDestinationBuilderRejectsPathTraversalAndNonPDFComponents() throws {
        let root = makeTemporaryDownloadDirectory()
        let options = makeDownloadOptions()
        let group = NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: "s23",
            number: "12",
            paperGroup: 1,
            qp: nil,
            ms: nil,
            extras: [
                makeDownloadComponent(filename: "../evil.pdf", type: "QP"),
                makeDownloadComponent(filename: "notes.txt", type: "QP", url: URL(string: "https://example.test/notes.txt")!),
                makeDownloadComponent(filename: "safe.pdf", type: "QP", url: URL(string: "ftp://example.test/safe.pdf")!),
                makeDownloadComponent(filename: "9709_s23_qp_12.pdf", type: "QP")
            ]
        )

        let plan = try DownloadDestinationBuilder.build(groups: [group], saveDirectory: root, options: options)

        XCTAssertEqual(plan.tasks.map(\.filename), ["9709_s23_qp_12.pdf"])
    }

    func testDuplicateSkipAndMissingModesFollowDownloadHistoryLikePythonBackend() throws {
        let root = makeTemporaryDownloadDirectory()
        let existing = root.appendingPathComponent("2023/QP/9709_s23_qp_12.pdf")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: existing)
        let group = NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: "s23",
            number: "12",
            paperGroup: 1,
            qp: makeDownloadComponent(filename: "9709_s23_qp_12.pdf", type: "QP"),
            ms: nil,
            extras: []
        )

        let skipPlan = try DownloadDestinationBuilder.build(
            groups: [group],
            saveDirectory: root,
            options: makeDownloadOptions(duplicateMode: .skip),
            downloadedFilenames: ["9709_s23_qp_12.pdf"]
        )
        let missingPlan = try DownloadDestinationBuilder.build(
            groups: [group],
            saveDirectory: root,
            options: makeDownloadOptions(duplicateMode: .missing),
            downloadedFilenames: ["9709_s23_qp_12.pdf"]
        )
        let overwritePlan = try DownloadDestinationBuilder.build(
            groups: [group],
            saveDirectory: root,
            options: makeDownloadOptions(duplicateMode: .overwrite)
        )

        XCTAssertEqual(skipPlan.tasks.count, 0)
        XCTAssertEqual(skipPlan.skipped, 1)
        XCTAssertEqual(missingPlan.tasks.count, 0)
        XCTAssertEqual(missingPlan.skipped, 1)
        XCTAssertEqual(overwritePlan.tasks.count, 1)
        XCTAssertEqual(overwritePlan.skipped, 0)
    }

    func testDuplicateMissingDownloadsExistingFileWhenHistoryDoesNotContainIt() throws {
        let root = makeTemporaryDownloadDirectory()
        let existing = root.appendingPathComponent("2023/QP/9709_s23_qp_12.pdf")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("manual".utf8).write(to: existing)
        let group = NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: "s23",
            number: "12",
            paperGroup: 1,
            qp: makeDownloadComponent(filename: "9709_s23_qp_12.pdf", type: "QP"),
            ms: nil,
            extras: []
        )

        let plan = try DownloadDestinationBuilder.build(
            groups: [group],
            saveDirectory: root,
            options: makeDownloadOptions(duplicateMode: .missing),
            downloadedFilenames: []
        )

        XCTAssertEqual(plan.tasks.count, 1)
        XCTAssertEqual(plan.skipped, 0)
    }

    func testDestinationBuilderAcceptsEasyPaperDownloadEndpointWhenFilenameIsPDF() throws {
        let root = makeTemporaryDownloadDirectory()
        let filePath = "CAIE|AS and A Level|Mathematics (9709)|2023|Summer|9709_s23_qp_12.pdf"
        let easyPaperURL = URL(string: "https://server.easy-paper.com/paperdownload/dir_v3/stale-token")!
            .withEasyPaperFilePath(filePath)
        let group = NativePaperGroup(
            sourceID: .easyPaper,
            subjectCode: "9709",
            sy: "s23",
            number: "12",
            paperGroup: 1,
            qp: PaperComponent(
                sourceID: .easyPaper,
                filename: "9709_s23_qp_12.pdf",
                url: easyPaperURL,
                paperType: "QP",
                subjectCode: "9709",
                sy: "s23",
                number: "12",
                label: nil
            ),
            ms: nil,
            extras: []
        )

        let plan = try DownloadDestinationBuilder.build(groups: [group], saveDirectory: root, options: makeDownloadOptions())

        XCTAssertEqual(plan.tasks.count, 1)
        XCTAssertEqual(plan.tasks.first?.saveURL.path, root.appendingPathComponent("2023/QP/9709_s23_qp_12.pdf").path)
    }

    func testExistingDownloadURLFindsMergedAndSplitDestinations() throws {
        let root = makeTemporaryDownloadDirectory()
        let file = PaperFile(
            filename: "9709_s24_qp_12.pdf",
            url: URL(string: "https://example.test/9709_s24_qp_12.pdf")!,
            year: 2024,
            season: "Jun",
            paperType: "QP",
            subjectCode: "9709",
            number: "12",
            label: nil,
            sourceID: .frankcie
        )
        let mergedURL = root.appendingPathComponent("9709_s24_qp_12.pdf")
        let splitURL = root.appendingPathComponent("2024/QP/9709_s24_qp_12.pdf")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("merged".utf8).write(to: mergedURL)

        XCTAssertEqual(
            DownloadDestinationBuilder.existingDownloadURL(for: file, saveDirectory: root),
            mergedURL
        )

        try FileManager.default.removeItem(at: mergedURL)
        try FileManager.default.createDirectory(at: splitURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("split".utf8).write(to: splitURL)

        XCTAssertEqual(
            DownloadDestinationBuilder.existingDownloadURL(for: file, saveDirectory: root),
            splitURL
        )
    }
}
