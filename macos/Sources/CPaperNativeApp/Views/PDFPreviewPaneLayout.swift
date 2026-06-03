import SwiftUI

enum PDFPreviewPaneMode: Equatable {
    case listOnly
    case sideBySide
    case previewOnly
}

struct PDFPreviewPaneLayout {
    static let listMinimumWidth: CGFloat = 320
    static let previewMinimumWidth: CGFloat = 360
    static let previewIdealWidth: CGFloat = 410
    static let previewMaximumWidth: CGFloat = 460
    static let spacing: CGFloat = 14

    static var sideBySideMinimumWidth: CGFloat {
        listMinimumWidth + previewMinimumWidth + spacing
    }

    static func mode(for availableWidth: CGFloat, hasPreview: Bool) -> PDFPreviewPaneMode {
        guard hasPreview else { return .listOnly }
        return availableWidth >= sideBySideMinimumWidth ? .sideBySide : .previewOnly
    }
}

struct AdaptivePDFPreviewPane<ListContent: View, PreviewContent: View>: View {
    private let hasPreview: Bool
    private let listContent: ListContent
    private let previewContent: PreviewContent

    init(
        hasPreview: Bool,
        @ViewBuilder list: () -> ListContent,
        @ViewBuilder preview: () -> PreviewContent
    ) {
        self.hasPreview = hasPreview
        self.listContent = list()
        self.previewContent = preview()
    }

    var body: some View {
        GeometryReader { geometry in
            let mode = PDFPreviewPaneLayout.mode(for: geometry.size.width, hasPreview: hasPreview)

            content(for: mode)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for mode: PDFPreviewPaneMode) -> some View {
        switch mode {
        case .listOnly:
            listContent
        case .sideBySide:
            HStack(alignment: .top, spacing: PDFPreviewPaneLayout.spacing) {
                listContent

                previewContent
                    .frame(
                        minWidth: PDFPreviewPaneLayout.previewMinimumWidth,
                        idealWidth: PDFPreviewPaneLayout.previewIdealWidth,
                        maxWidth: PDFPreviewPaneLayout.previewMaximumWidth,
                        maxHeight: .infinity
                    )
                    .pdfPreviewPaneChrome()
            }
        case .previewOnly:
            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .pdfPreviewPaneChrome()
        }
    }
}

private struct PDFPreviewPaneChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: CPDesign.Radius.floating, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CPDesign.Radius.floating, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
            }
    }
}

private extension View {
    func pdfPreviewPaneChrome() -> some View {
        modifier(PDFPreviewPaneChrome())
    }
}
