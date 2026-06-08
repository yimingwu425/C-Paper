import XCTest
@testable import CPaperNativeApp

final class SubjectPickerLogicTests: XCTestCase {
    private let subjects = [
        Subject(code: "9709", name: "Mathematics"),
        Subject(code: "9701", name: "Chemistry"),
        Subject(code: "0610", name: "Biology")
    ]

    func testFilterSubjectsMatchesCode() {
        let result = SubjectPickerLogic.filteredSubjects(subjects, query: "97")

        XCTAssertEqual(result.map(\.code), ["9701", "9709"])
    }

    func testFilterSubjectsMatchesDisplayName() {
        let result = SubjectPickerLogic.filteredSubjects(subjects, query: "math")

        XCTAssertEqual(result.map(\.code), ["9709"])
    }

    func testFilterSubjectsReturnsCodeSortedListForEmptyQuery() {
        let result = SubjectPickerLogic.filteredSubjects(subjects, query: "")

        XCTAssertEqual(result.map(\.code), ["0610", "9701", "9709"])
    }

    func testFilterSubjectsReturnsEmptyListForNoMatches() {
        let result = SubjectPickerLogic.filteredSubjects(subjects, query: "physics")

        XCTAssertTrue(result.isEmpty)
    }

    func testSelectingSubjectClearsManualCode() {
        let selectedSubject = Subject(code: "9709", name: "Mathematics")
        let state = SubjectPickerLogic.subjectSelectionState(
            for: selectedSubject,
            manualCode: "0610"
        )

        XCTAssertEqual(state.selection, selectedSubject)
        XCTAssertEqual(state.manualCode, "")
    }

    func testValidManualSubjectCodeClearsSelection() {
        let state = SubjectPickerLogic.manualCodeState(
            for: "9709",
            selection: Subject(code: "0610", name: "Biology")
        )

        XCTAssertNil(state.selection)
        XCTAssertEqual(state.manualCode, "9709")
    }
}
