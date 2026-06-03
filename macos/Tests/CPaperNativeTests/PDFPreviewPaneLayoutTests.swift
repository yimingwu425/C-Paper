import XCTest
@testable import CPaperNativeApp

final class PDFPreviewPaneLayoutTests: XCTestCase {
    func testUsesListOnlyWhenNoPreviewIsSelected() {
        XCTAssertEqual(PDFPreviewPaneLayout.mode(for: 200, hasPreview: false), .listOnly)
    }

    func testUsesPreviewOnlyWhenSideBySideWouldOverflow() {
        let narrowWidth = PDFPreviewPaneLayout.sideBySideMinimumWidth - 1
        XCTAssertEqual(PDFPreviewPaneLayout.mode(for: narrowWidth, hasPreview: true), .previewOnly)
    }

    func testUsesSideBySideWhenBothPanesFit() {
        let fittingWidth = PDFPreviewPaneLayout.sideBySideMinimumWidth
        XCTAssertEqual(PDFPreviewPaneLayout.mode(for: fittingWidth, hasPreview: true), .sideBySide)
    }
}
