import XCTest
@testable import CPaperNativeApp

final class PaperParsingTests: XCTestCase {
    func testParsesValidQuestionPaperFilename() {
        let parsed = PaperFilenameParser.parse("9701_s23_qp_12.pdf")

        XCTAssertEqual(parsed?.subject, "9701")
        XCTAssertEqual(parsed?.sy, "s23")
        XCTAssertEqual(parsed?.type, "qp")
        XCTAssertEqual(parsed?.number, "12")
    }

    func testRejectsUnsafeFilenames() {
        XCTAssertNil(PaperFilenameParser.parse("../9701_s23_qp_12.pdf"))
        XCTAssertNil(PaperFilenameParser.parse("9701/s23_qp_12.pdf"))
        XCTAssertNil(PaperFilenameParser.parse("readme.txt"))
    }

    func testYearAndSeasonFromSY() {
        XCTAssertEqual(PaperFilenameParser.year(fromSY: "m24"), 2024)
        XCTAssertEqual(PaperFilenameParser.year(fromSY: "s21"), 2021)
        XCTAssertEqual(PaperFilenameParser.year(fromSY: "w23"), 2023)
        XCTAssertEqual(PaperFilenameParser.seasonName(fromSY: "m24"), "Mar")
        XCTAssertEqual(PaperFilenameParser.seasonName(fromSY: "s21"), "Jun")
        XCTAssertEqual(PaperFilenameParser.seasonName(fromSY: "w23"), "Nov")
    }

    func testSubjectNormalizerParsesDirectoryNamesFromFallbackSources() {
        XCTAssertEqual(
            SubjectNormalizer.subject(fromDirectoryName: "Mathematics (9709)"),
            Subject(code: "9709", name: "Mathematics")
        )
        XCTAssertEqual(
            SubjectNormalizer.subject(fromDirectoryName: "Chemistry-0620"),
            Subject(code: "0620", name: "Chemistry")
        )
    }

    func testGroupsQuestionPaperAndMarkSchemePairs() {
        let groups = PaperGrouper.groups(from: [
            component("9701_s23_qp_12.pdf"),
            component("9701_s23_ms_12.pdf")
        ])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].qp?.filename, "9701_s23_qp_12.pdf")
        XCTAssertEqual(groups[0].ms?.filename, "9701_s23_ms_12.pdf")
        XCTAssertEqual(groups[0].paperGroup, 1)
    }

    func testKeepsStandaloneComponentsAsExtras() {
        let groups = PaperGrouper.groups(from: [
            component("9701_s23_ci_3.pdf")
        ])

        XCTAssertEqual(groups.count, 1)
        XCTAssertNil(groups[0].qp)
        XCTAssertNil(groups[0].ms)
        XCTAssertEqual(groups[0].extras.first?.paperType, "ci")
    }

    private func component(_ filename: String) -> PaperComponent {
        let parsed = PaperFilenameParser.parse(filename)!
        return PaperComponent(
            sourceID: .frankcie,
            filename: filename,
            url: URL(string: "https://example.com/\(filename)")!,
            paperType: parsed.type,
            subjectCode: parsed.subject,
            sy: parsed.sy,
            number: parsed.number,
            label: nil
        )
    }
}
