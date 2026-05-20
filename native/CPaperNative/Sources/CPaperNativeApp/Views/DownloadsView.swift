import SwiftUI

struct DownloadsView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.lg) {
            header
            summary
            table
        }
        .padding(28)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("下载队列")
                    .font(.title.weight(.semibold))
                Text(model.downloadSnapshot.message)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.downloadSnapshot.isRunning {
                Button {
                    Task { await model.cancelDownloads() }
                } label: {
                    Label("取消", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var summary: some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: CPDesign.Spacing.md) {
                HStack(spacing: CPDesign.Spacing.md) {
                    summaryBlock(title: "总数", value: "\(model.downloadSnapshot.total)", symbol: "tray.full")
                    summaryBlock(title: "完成", value: "\(model.completedDownloadCount)", symbol: "checkmark.circle")
                    summaryBlock(title: "失败", value: "\(model.failedDownloadCount)", symbol: "xmark.circle")
                    summaryBlock(title: "活动", value: "\(model.activeDownloadCount)", symbol: "bolt.circle")
                }

                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)
            }
        }
    }

    private var table: some View {
        Table(model.downloads) {
            TableColumn("文件") { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.filename)
                        .lineLimit(1)
                    Text([item.year, item.ftype, item.label].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .width(min: 320)

            TableColumn("状态") { item in
                Text(item.status.title)
            }
            .width(90)

            TableColumn("进度") { item in
                ProgressView(value: item.progress)
            }
            .width(140)

            TableColumn("信息") { item in
                Text(item.message)
                    .lineLimit(2)
            }
        }
        .overlay {
            if model.downloads.isEmpty {
                ContentUnavailableView(
                    "没有下载任务",
                    systemImage: "arrow.down.circle",
                    description: Text("批量预览后可以在这里查看下载进度。")
                )
            }
        }
    }

    private var progressValue: Double {
        guard model.downloadSnapshot.total > 0 else { return 0 }
        return Double(model.downloadSnapshot.done) / Double(model.downloadSnapshot.total)
    }

    private func summaryBlock(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: CPDesign.Spacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CPDesign.Spacing.sm)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
    }
}
