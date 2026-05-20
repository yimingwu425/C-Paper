import PDFKit
import SwiftUI

struct PDFPreviewView: View {
    let file: PaperFile?

    var body: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.md) {
            if let file {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.filename)
                            .font(.headline)
                            .lineLimit(1)
                        Text(file.url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Link(destination: file.url) {
                        Label("打开", systemImage: "safari")
                    }
                }
                .padding([.horizontal, .top], CPDesign.Spacing.md)

                PDFKitContainer(url: file.url)
            } else {
                ContentUnavailableView(
                    "PDF 预览",
                    systemImage: "doc.richtext",
                    description: Text("选择一份试卷后在这里预览。")
                )
            }
        }
    }
}

struct PDFKitContainer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(url: url)
    }
}
