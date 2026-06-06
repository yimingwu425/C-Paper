import SwiftUI

struct BatchView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ProductBackdrop()

            ScrollableWorkflowPage { size in
                VStack(alignment: .leading, spacing: 22) {
                    BatchHeader(model: model)
                    HStack(alignment: .top, spacing: 28) {
                        GlassSurface(role: .content, padding: 20) {
                            BatchFilterPanel(model: model)
                        }
                        .frame(width: 322)
                        BatchPreviewPanel(model: model)
                    }
                    .frame(minHeight: max(460, size.height - 220), alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.batchPreview)
                    .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.selectedPreview)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

private struct BatchHeader: View {
    @Bindable var model: AppModel

    var body: some View {
        PageHero(
            eyebrow: "Batch Queue",
            title: "批量下载",
            subtitle: "组合年份、考季和 Paper，先生成清单，再一次性写入目录。",
            symbolName: "tray.and.arrow.down"
        ) {
            HeaderCount(value: model.batchPreview.count, unit: "个文件")
        }
    }
}
