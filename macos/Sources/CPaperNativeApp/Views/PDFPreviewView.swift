import AppKit
import PDFKit
import SwiftUI

struct PDFPreviewView: View {
    let model: AppModel
    let file: PaperFile?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.sm) {
            if let file {
                previewHeader(for: file)
                    .padding([.horizontal, .top], CPDesign.Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))

                ZStack {
                    if model.previewLoadState.isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .accessibilityLabel("正在缓存试卷预览")
                            Text("正在缓存试卷预览...")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let localURL = model.previewLoadState.localURL {
                        PDFKitContainer(url: localURL)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let failure = model.previewLoadState.failureState {
                        previewFailureView(failure: failure)
                    }
                }
                .frame(minHeight: 300, maxHeight: .infinity)
                .background(.background.opacity(0.86), in: RoundedRectangle(cornerRadius: CPDesign.Radius.panel, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: CPDesign.Radius.panel, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: CPDesign.Radius.panel, style: .continuous)
                        .stroke(.quaternary.opacity(0.65), lineWidth: 1)
                }
                .padding(.horizontal, CPDesign.Spacing.sm)
                .padding(.bottom, CPDesign.Spacing.sm)
            } else {
                ContentUnavailableView(
                    "PDF 预览",
                    systemImage: "doc.richtext",
                    description: Text("选择一份试卷后在这里预览。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .nativeContentBackground()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: file)
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.previewLoadState)
        .task(id: model.previewLoadRequest) {
            await model.loadSelectedPreviewIfNeeded()
        }
    }

    @ViewBuilder
    private func previewFailureView(failure: PreviewFailureState) -> some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                "无法加载预览",
                systemImage: "exclamationmark.triangle",
                description: Text(failure.diagnostic.message + "\n您也可以直接点击右上角「下载」或「浏览器打开」。")
            )

            HStack(spacing: 10) {
                Button("重试预览") {
                    model.retryPreview()
                }
                .buttonStyle(GlassButtonStyle(.primary))
                .controlSize(.small)

                if failure.suggestsRedownload {
                    Button("重新下载文件") {
                        Task { await model.redownloadSelectedPreviewFile() }
                    }
                    .buttonStyle(GlassButtonStyle(.subtle))
                    .controlSize(.small)
                }

                Button("复制诊断") {
                    model.copyDiagnostic(failure.diagnostic)
                }
                .buttonStyle(GlassButtonStyle(.subtle))
                .controlSize(.small)

                Button("显示支持文件夹") {
                    model.revealSupportDirectory()
                }
                .buttonStyle(GlassButtonStyle(.subtle))
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewHeader(for file: PaperFile) -> some View {
        HStack(spacing: CPDesign.Spacing.sm) {
            Image(systemName: file.paperType == "MS" ? "checklist" : "doc.text")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(file.filename)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: CPDesign.Spacing.xs)

            HStack(spacing: 6) {
                PreviewToolbarButton(title: "关闭预览", systemImage: "xmark") {
                    model.closePreview()
                }

                if model.previewLoadState.localURL != nil {
                    PreviewToolbarButton(title: "在访达中显示", systemImage: "folder") {
                        model.revealPreviewFile()
                    }
                }

                Link(destination: file.url) {
                    PreviewToolbarIcon(systemImage: "safari", title: "浏览器打开")
                }
                .buttonStyle(.plain)

                PreviewToolbarButton(title: "下载", systemImage: "arrow.down.circle", isPrimary: true) {
                    Task {
                        await model.startSingleFileDownload(file)
                    }
                }
            }
        }
        .padding(10)
        .liquidGlassSurface(.floating, strokeOpacity: 0.50)
    }
}

private struct PreviewToolbarButton: View {
    let title: String
    let systemImage: String
    var isPrimary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PreviewToolbarIcon(systemImage: systemImage, title: title, isPrimary: isPrimary)
        }
        .buttonStyle(.plain)
    }
}

private struct PreviewToolbarIcon: View {
    let systemImage: String
    let title: String
    var isPrimary = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isPrimary ? Color.accentColor : .secondary)
            .frame(width: 30, height: 30)
            .background {
                RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                    .fill(isPrimary ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                    .stroke(isPrimary ? Color.accentColor.opacity(0.24) : Color.secondary.opacity(0.13), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
            .help(title)
            .accessibilityLabel(title)
    }
}

struct PDFKitContainer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = AutoScalingPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
        nsView.autoScales = true
        nsView.layoutDocumentView()
    }
}

private final class AutoScalingPDFView: PDFView {
    private var isRefreshingLayout = false

    override func layout() {
        super.layout()

        guard document != nil, !isRefreshingLayout else { return }
        isRefreshingLayout = true
        autoScales = true
        layoutDocumentView()
        isRefreshingLayout = false
    }
}
