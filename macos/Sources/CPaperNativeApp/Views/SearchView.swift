import SwiftUI

struct SearchView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ProductBackdrop()

            VStack(alignment: .leading, spacing: 26) {
                SearchHeader(model: model)
                HStack(alignment: .top, spacing: 28) {
                    GlassSurface(role: .content, padding: 20) {
                        SearchFilterPanel(model: model)
                    }
                    .frame(width: 322)
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.18))
                            .frame(width: 84, height: 84)
                            .blur(radius: 28)
                            .offset(x: 26, y: -30)
                    }
                    SearchResultsPanel(model: model)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.searchResults)
                .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.selectedPreview)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(34)
        }
    }
}

private struct SearchHeader: View {
    @Bindable var model: AppModel

    var body: some View {
        PageHero(
            eyebrow: "Smart Search",
            title: "搜索试卷",
            subtitle: model.activeSubject?.displayName ?? "选择科目、年份和考季，快速定位可下载试卷。",
            symbolName: "doc.text.magnifyingglass"
        ) {
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
        VStack(alignment: .leading, spacing: 14) {
            ControlPanelHeader(
                title: "检索条件",
                subtitle: "先选科目，再用考季和年份收窄范围。",
                symbolName: "slider.horizontal.3"
            )

            FieldBlock("科目") {
                SubjectPicker(
                    subjects: model.subjects,
                    selection: $model.selectedSubject,
                    manualCode: $model.manualSubjectCode
                )
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
                .disabled(!model.hasSearchSubject || model.isLoading)

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
                .disabled(!model.hasSearchSubject)

                if !model.searchResults.isEmpty {
                    Button {
                        Task { await model.startSearchDownload() }
                    } label: {
                        Label("下载当前结果", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle(.primary))
                    .disabled(model.searchGroups.isEmpty || model.isLoading)
                }
            }

            GuidanceCard(
                title: "结果会自动分组",
                text: "同一套 Paper 的 Question Paper 和 Mark Scheme 会靠在一起，方便成套下载。"
            )
        }
    }
}

private struct SearchResultsPanel: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassSurface(role: .base, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                ResultPanelToolbar(
                    title: "检索结果",
                    subtitle: model.searchResults.isEmpty ? "等待搜索条件" : "\(paperGroups.count) 组试卷组件",
                    symbolName: "tray.full"
                ) {
                    if !model.searchResults.isEmpty {
                        HStack(spacing: 10) {
                            Text("\(model.searchResults.count)")
                                .font(.headline.weight(.semibold).monospacedDigit())
                            Text("files")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                Task { await model.startSearchDownload() }
                            } label: {
                                Label("下载全部", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(GlassButtonStyle(.primary))
                            .controlSize(.small)
                            .disabled(model.searchGroups.isEmpty || model.isLoading)
                        }
                    }
                }
                .padding(.horizontal, 2)

                AdaptivePDFPreviewPane(hasPreview: model.selectedPreview != nil) {
                    resultsList
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

    private var resultsList: some View {
        List(selection: $model.selectedPreview) {
            ForEach(paperGroups) { group in
                DisclosureGroup(isExpanded: expandedBinding(for: group.id)) {
                    ForEach(group.files) { file in
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
                } label: {
                    PaperGroupHeader(group: group)
                }
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
            if model.searchResults.isEmpty {
                WorkflowEmptyState(
                    title: "暂无结果",
                    systemImage: "doc.text.magnifyingglass",
                    steps: [
                        "选择科目",
                        "确认年份和考季",
                        "点击搜索并等待分组"
                    ]
                )
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
            }
        }
        .frame(minWidth: PDFPreviewPaneLayout.listMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
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
