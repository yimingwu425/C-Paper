import SwiftUI

struct SearchView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.lg) {
            SearchHeader(model: model)
            HStack(alignment: .top, spacing: CPDesign.Spacing.lg) {
                SearchFilterPanel(model: model)
                    .frame(width: 260)
                SearchResultsPanel(model: model)
            }
        }
        .padding(28)
    }
}

private struct SearchHeader: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("搜索试卷")
                    .font(.title.weight(.semibold))
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
}

private struct SearchFilterPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.md) {
            FieldBlock("科目") {
                Picker("科目", selection: $model.selectedSubject) {
                    ForEach(model.subjects) { subject in
                        Text(subject.displayName).tag(Optional(subject))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            FieldBlock("考季") {
                Picker("考季", selection: $model.selectedSeason) {
                    ForEach(Season.allCases) { season in
                        Text(season.label).tag(season)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            FieldBlock("年份") {
                Stepper("\(model.selectedYear)", value: $model.selectedYear, in: 2000...2035)
            }

            Divider()

            Button {
                Task {
                    if model.isSelectedSubjectFavorite, let subject = model.selectedSubject {
                        await model.removeFavorite(subject)
                    } else {
                        await model.addSelectedSubjectToFavorites()
                    }
                }
            } label: {
                Label(model.isSelectedSubjectFavorite ? "取消收藏" : "收藏科目", systemImage: model.isSelectedSubjectFavorite ? "star.fill" : "star")
            }
            .disabled(model.selectedSubject == nil || !model.backendState.isAvailable)

            Button {
                Task { await model.search() }
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.selectedSubject == nil || model.isLoading || !model.backendState.isAvailable)
        }
        .padding(CPDesign.Spacing.md)
        .background(.bar, in: RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct SearchResultsPanel: View {
    @Bindable var model: AppModel

    var body: some View {
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
                ForEach(paperGroups) { group in
                    DisclosureGroup(isExpanded: expandedBinding(for: group.id)) {
                        ForEach(group.files) { file in
                            PaperRow(file: file)
                                .tag(Optional(file))
                        }
                    } label: {
                        PaperGroupHeader(group: group)
                    }
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

    private var paperGroups: [PaperComponentGroup] {
        let grouped = Dictionary(grouping: model.searchResults) { $0.componentKey ?? "other" }
        return grouped.map { PaperComponentGroup(id: $0.key, files: sortedFiles($0.value)) }
            .sorted(by: sortGroups)
    }

    private func sortedFiles(_ files: [PaperFile]) -> [PaperFile] {
        files.sorted { ($0.paperType ?? "") > ($1.paperType ?? "") }
    }

    private func sortGroups(_ lhs: PaperComponentGroup, _ rhs: PaperComponentGroup) -> Bool {
        switch (Int(lhs.id), Int(rhs.id)) {
        case let (left?, right?):
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.id < rhs.id
        }
    }

    private func expandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { model.expandedPaperComponents.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    model.expandedPaperComponents.insert(id)
                } else {
                    model.expandedPaperComponents.remove(id)
                }
            }
        )
    }
}

struct FieldBlock<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

struct PaperComponentGroup: Identifiable {
    let id: String
    let files: [PaperFile]

    var title: String {
        files.first?.componentTitle ?? "Other"
    }

    var detail: String {
        let types = files.compactMap(\.paperType)
        if types.isEmpty {
            return "\(files.count) 个文件"
        }
        return "\(types.joined(separator: " + ")) · \(files.count) 个文件"
    }
}

struct PaperGroupHeader: View {
    let group: PaperComponentGroup

    var body: some View {
        HStack(spacing: CPDesign.Spacing.sm) {
            Image(systemName: "doc.on.doc")
                .foregroundStyle(.secondary)
            Text(group.title)
                .font(.headline)
            Text(group.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
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
