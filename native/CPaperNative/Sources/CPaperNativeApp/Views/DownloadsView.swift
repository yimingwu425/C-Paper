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
                Text("Downloads")
                    .font(.largeTitle.weight(.semibold))
                Text(model.downloadSnapshot.message)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.downloadSnapshot.isRunning {
                Button {
                    Task { await model.cancelDownloads() }
                } label: {
                    Label("Cancel", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var summary: some View {
        GlassSurface {
            HStack(spacing: CPDesign.Spacing.xl) {
                summaryBlock(title: "Total", value: "\(model.downloadSnapshot.total)")
                summaryBlock(title: "Completed", value: "\(model.completedDownloadCount)")
                summaryBlock(title: "Failed", value: "\(model.failedDownloadCount)")
                summaryBlock(title: "Active", value: "\(model.activeDownloadCount)")
                Spacer()
                ProgressView(value: progressValue)
                    .frame(width: 180)
            }
        }
    }

    private var table: some View {
        Table(model.downloads) {
            TableColumn("File") { item in
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

            TableColumn("Status") { item in
                Text(item.status.title)
            }
            .width(90)

            TableColumn("Progress") { item in
                ProgressView(value: item.progress)
            }
            .width(140)

            TableColumn("Message") { item in
                Text(item.message)
                    .lineLimit(2)
            }
        }
    }

    private var progressValue: Double {
        guard model.downloadSnapshot.total > 0 else { return 0 }
        return Double(model.downloadSnapshot.done) / Double(model.downloadSnapshot.total)
    }

    private func summaryBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
    }
}
