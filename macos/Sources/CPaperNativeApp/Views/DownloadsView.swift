import SwiftUI

struct DownloadsView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ProductBackdrop()

            ScrollableWorkflowPage { size in
                VStack(alignment: .leading, spacing: 22) {
                    header
                    summary
                    table
                        .frame(minHeight: max(300, size.height - 430), alignment: .top)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.downloads)
        .animation(CPDesign.Motion.gentle(reduceMotion: reduceMotion), value: model.downloadSnapshot)
    }

    private var header: some View {
        PageHero(
            eyebrow: "Download Center",
            title: "下载队列",
            subtitle: model.downloadSnapshot.message,
            symbolName: "arrow.down.doc"
        ) {
            HeaderCount(value: model.downloadSnapshot.total, unit: "个任务")
            if model.downloadSnapshot.isRunning {
                Button {
                    Task { await model.cancelDownloads() }
                } label: {
                    Label("取消", systemImage: "stop.circle")
                }
                .buttonStyle(GlassButtonStyle(.destructive))
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 18) {
            GlassSurface(role: .floating, padding: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    ResultPanelToolbar(
                        title: "队列概览",
                        subtitle: model.downloads.isEmpty ? "等待从批量页加入文件" : "\(model.completedDownloadCount) 个已完成，\(model.failedDownloadCount) 个需要处理",
                        symbolName: "chart.line.uptrend.xyaxis"
                    ) {
                        Text("\(Int(progressValue * 100))%")
                            .font(.headline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                    }

                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                        .animation(CPDesign.Motion.gentle(reduceMotion: reduceMotion), value: progressValue)

                    HStack(spacing: 12) {
                        queueStage(title: "准备", value: model.downloadSnapshot.total - model.completedDownloadCount - model.failedDownloadCount, tint: .orange)
                        queueStage(title: "完成", value: model.completedDownloadCount, tint: .green)
                        queueStage(title: "失败", value: model.failedDownloadCount, tint: .red)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            summaryBlock(title: "总数", value: "\(model.downloadSnapshot.total)", symbol: "tray.full", tint: .accentColor)
            summaryBlock(title: "活动", value: "\(model.activeDownloadCount)", symbol: "bolt.circle", tint: .orange)
        }
    }

    private var table: some View {
        GlassSurface(role: .base, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                ResultPanelToolbar(
                    title: "文件队列",
                    subtitle: model.downloads.isEmpty ? "队列为空" : "按状态检查每个文件的下载进度",
                    symbolName: "list.bullet.rectangle.portrait"
                ) {
                    if model.downloadSnapshot.isRunning {
                        StatusBadge(text: "运行中", systemImage: "arrow.down.circle", tint: .accentColor, prominence: .tinted)
                    } else if model.failedDownloadCount > 0 {
                        StatusBadge(text: "需处理", systemImage: "exclamationmark.triangle", tint: .orange, prominence: .tinted)
                    }
                }
                .padding(.horizontal, 2)

                Group {
                    if model.downloads.isEmpty {
                        DownloadEmptyPanel()
                            .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
                    } else {
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
                                StatusBadge(text: item.status.title, systemImage: item.status.symbolName, tint: item.status.tint, prominence: .tinted)
                            }
                            .width(110)

                            TableColumn("进度") { item in
                                ProgressView(value: item.progress)
                                    .tint(item.status.tint)
                                    .animation(CPDesign.Motion.gentle(reduceMotion: reduceMotion), value: item.progress)
                            }
                            .width(140)

                            TableColumn("信息") { item in
                                Text(item.message)
                                    .lineLimit(2)
                                    .foregroundStyle(item.status == .failed ? .red : .secondary)
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
                .frame(minHeight: 300)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.58))
                        .overlay {
                            LinearGradient(
                                colors: [Color.white.opacity(0.20), Color.accentColor.opacity(0.055)],
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
            }
        }
    }

    private var progressValue: Double {
        guard model.downloadSnapshot.total > 0 else { return 0 }
        return Double(model.downloadSnapshot.done) / Double(model.downloadSnapshot.total)
    }

    private func summaryBlock(title: String, value: String, symbol: String, tint: Color) -> some View {
        GlassSurface(role: .content, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 164)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: 58, height: 58)
                .blur(radius: 20)
                .offset(x: 16, y: -18)
        }
    }

    private func queueStage(title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint.opacity(0.20))
                .frame(width: 8, height: 8)
            Text(title)
                .foregroundStyle(.secondary)
            Text("\(max(value, 0))")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.46), in: Capsule(style: .continuous))
    }
}

private struct DownloadEmptyPanel: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.13))
                    .frame(width: 84, height: 84)
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text("没有下载任务")
                    .font(.title3.weight(.semibold))
                Text("从批量下载页生成清单后，文件队列和进度会集中显示在这里。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(28)
    }
}

private extension DownloadStatus {
    var symbolName: String {
        switch self {
        case .pending: "clock"
        case .downloading: "arrow.down.circle"
        case .done: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "stop.circle"
        case .skipped: "forward.circle"
        }
    }

    var tint: Color {
        switch self {
        case .pending: .secondary
        case .downloading: .accentColor
        case .done: .green
        case .failed: .red
        case .cancelled: .orange
        case .skipped: .secondary
        }
    }
}
