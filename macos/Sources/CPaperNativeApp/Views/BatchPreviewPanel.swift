import SwiftUI

struct BatchPreviewPanel: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassSurface(role: .base, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                ResultPanelToolbar(
                    title: "预览清单",
                    subtitle: model.batchPreview.isEmpty ? "等待生成批量清单" : "即将写入下载队列",
                    symbolName: "list.bullet.rectangle"
                ) {
                    if !model.batchGroups.isEmpty {
                        Text("\(model.batchGroups.count) 组")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 2)

                AdaptivePDFPreviewPane(hasPreview: model.selectedPreview != nil) {
                    previewList
                } preview: {
                    if let selectedPreview = model.selectedPreview {
                        PDFPreviewView(model: model, file: selectedPreview)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewList: some View {
        List(selection: $model.selectedPreview) {
            ForEach(model.batchPreview) { file in
                PaperRow(
                    file: file,
                    onPreview: {
                        model.selectedPreview = file
                    },
                    onDownload: {
                        Task { await model.startSingleFileDownload(file) }
                    }
                )
                .tag(Optional(file))
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.58))
                .overlay {
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.accentColor.opacity(0.055)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
        }
        .overlay {
            if model.batchPreview.isEmpty {
                WorkflowEmptyState(
                    title: "暂无预览",
                    systemImage: "tray.and.arrow.down",
                    steps: [
                        "选择科目和年份",
                        "勾选考季与 Paper",
                        "预览清单后下载"
                    ]
                )
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
            }
        }
        .frame(minWidth: PDFPreviewPaneLayout.listMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
    }
}
