import PDFKit
import SwiftUI

struct PDFPreviewView: View {
    let file: PaperFile?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.md) {
            if let file {
                GlassSurface(role: .floating, padding: CPDesign.Spacing.md) {
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
                        .buttonStyle(GlassButtonStyle(.normal))
                    }
                }
                .padding([.horizontal, .top], CPDesign.Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))

                PDFKitContainer(url: file.url)
                    .background(.background.opacity(0.78), in: RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
                    .padding(.horizontal, CPDesign.Spacing.md)
                    .padding(.bottom, CPDesign.Spacing.md)
            } else {
                ContentUnavailableView(
                    "PDF 预览",
                    systemImage: "doc.richtext",
                    description: Text("选择一份试卷后在这里预览。")
                )
            }
        }
        .nativeContentBackground()
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: file)
    }
}

struct PDFKitContainer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(url: url)
    }
}
