import SwiftUI

struct SearchView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.lg) {
            header
            controls
            results
        }
        .padding(28)
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("搜索试卷")
                    .font(.largeTitle.weight(.semibold))
                Text(model.selectedSubject?.displayName ?? "选择一个科目后开始检索")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(model.searchResults.count) 个文件")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 12) {
            LabeledContent("科目") {
                Picker("科目", selection: $model.selectedSubject) {
                    ForEach(model.subjects) { subject in
                        Text(subject.displayName).tag(Optional(subject))
                    }
                }
                .labelsHidden()
                .frame(width: 260)
            }

            Divider()
                .frame(height: 22)

            LabeledContent("考季") {
                Picker("考季", selection: $model.selectedSeason) {
                    ForEach(Season.allCases) { season in
                        Text(season.label).tag(season)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            Divider()
                .frame(height: 22)

            Stepper("年份 \(model.selectedYear)", value: $model.selectedYear, in: 2000...2035)
                .frame(width: 160)

            Spacer(minLength: CPDesign.Spacing.sm)

            Button {
                Task { await model.search() }
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(model.selectedSubject == nil || model.isLoading || !model.backendState.isAvailable)
        }
        .padding(.horizontal, CPDesign.Spacing.md)
        .padding(.vertical, 10)
        .background(.bar, in: RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.sm) {
            HStack {
                Text("检索结果")
                    .font(.headline)
                Spacer()
                Text("\(model.searchResults.count) 个文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            List(selection: $model.selectedPreview) {
                ForEach(model.searchResults) { file in
                    PaperRow(file: file)
                        .tag(Optional(file))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
            .overlay {
                if model.searchResults.isEmpty {
                    ContentUnavailableView(
                        "暂无结果",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(model.backendState.isAvailable ? "选择筛选条件后点击搜索。" : "先连接 Python bridge。")
                    )
                }
            }
        }
    }
}

struct PaperRow: View {
    let file: PaperFile

    var body: some View {
        HStack(spacing: CPDesign.Spacing.sm) {
            Image(systemName: file.paperType == "MS" ? "checklist" : "doc.text")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(file.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}
