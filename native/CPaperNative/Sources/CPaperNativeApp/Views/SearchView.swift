import SwiftUI

struct SearchView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.lg) {
            SearchHeader(model: model)
            HStack(alignment: .top, spacing: 20) {
                GlassSurface(role: .content, padding: 14) {
                    SearchFilterPanel(model: model)
                }
                .frame(width: 240)
                SearchResultsPanel(model: model)
            }
            .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.searchResults)
            .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.selectedPreview)
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
                    .font(.title2.weight(.semibold))
                Text(model.selectedSubject?.displayName ?? "选择一个科目后开始检索")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HeaderCount(value: model.searchResults.count, unit: "个文件")
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }
        }
    }
}

private struct SearchFilterPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldBlock("科目") {
                SubjectPicker(subjects: model.subjects, selection: $model.selectedSubject)
            }

            FieldBlock("考季") {
                SeasonPillPicker(selection: $model.selectedSeason)
            }

            FieldBlock("年份") {
                CompactYearField(value: $model.selectedYear, range: 2000...2035)
            }

            Divider()

            VStack(spacing: CPDesign.Spacing.sm) {
                Button {
                    Task { await model.search() }
                } label: {
                    Label(model.isLoading ? "搜索中" : "搜索", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(.primary))
                .disabled(model.selectedSubject == nil || model.isLoading || !model.backendState.isAvailable)

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
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(.subtle))
                .disabled(model.selectedSubject == nil || !model.backendState.isAvailable)
            }
        }
    }
}

private struct SearchResultsPanel: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassSurface(role: .base, padding: CPDesign.Spacing.sm) {
            VStack(alignment: .leading, spacing: CPDesign.Spacing.sm) {
                HStack {
                    Text("检索结果")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, CPDesign.Spacing.sm)

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
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(.background.opacity(0.58), in: RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
                .overlay {
                    if model.searchResults.isEmpty {
                        ContentUnavailableView(
                            "暂无结果",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(model.backendState.isAvailable ? "选择筛选条件后点击搜索。" : "先连接 Python bridge。")
                        )
                        .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
                    }
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
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}

struct SubjectPicker: View {
    let subjects: [Subject]
    @Binding var selection: Subject?

    var body: some View {
        Picker("科目", selection: $selection) {
            Text(subjects.isEmpty ? "正在载入科目" : "选择科目")
                .tag(Optional<Subject>.none)
            ForEach(subjects) { subject in
                Text(subject.displayName).tag(Optional(subject))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CompactYearField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Year", text: textBinding)
            .textFieldStyle(.plain)
            .font(.callout.monospacedDigit())
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: 58)
            .background {
                RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                    .stroke(isFocused ? Color.accentColor.opacity(0.42) : Color.secondary.opacity(0.16), lineWidth: 1)
            }
            .focused($isFocused)
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { String(value) },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                guard let parsed = Int(digits) else { return }
                value = min(max(parsed, range.lowerBound), range.upperBound)
            }
        )
    }
}

struct SeasonPillPicker: View {
    @Binding var selection: Season

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Season.allCases) { season in
                Button {
                    selection = season
                } label: {
                    Text(season.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(selection == season ? .primary : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background {
                            RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                                .fill(Color.primary.opacity(selection == season ? 0.070 : 0.025))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                                .stroke(selection == season ? Color.accentColor.opacity(0.26) : Color.secondary.opacity(0.14), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
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
                .symbolRenderingMode(.hierarchical)
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
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: CPDesign.Spacing.sm) {
            Image(systemName: file.paperType == "MS" ? "checklist" : "doc.text")
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
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
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                .fill(hoverFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                .stroke(.quaternary.opacity(isHovering ? 0.65 : 0), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
        .scaleEffect(isHovering && !reduceMotion ? 1.004 : 1)
        .animation(CPDesign.Motion.tactile(reduceMotion: reduceMotion), value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var hoverFill: Color {
        guard isHovering else { return .clear }
        return colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.035)
    }
}
