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
                .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.searchResults)
                .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.selectedPreview)
            }
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
            subtitle: model.selectedSubject?.displayName ?? "选择科目、年份和考季，快速定位可下载试卷。",
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

                if !model.searchResults.isEmpty {
                    Button {
                        Task { await model.startSearchDownload() }
                    } label: {
                        Label("下载当前结果", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle(.primary))
                    .disabled(model.searchGroups.isEmpty || model.isLoading || !model.backendState.isAvailable)
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
                        }
                    }
                }
                .padding(.horizontal, 2)

                HStack(spacing: 14) {
                    resultsList

                    if let selectedPreview = model.selectedPreview {
                        PDFPreviewView(model: model, file: selectedPreview)
                            .frame(minWidth: 360, idealWidth: 430, maxWidth: 520)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
                            }
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
            }
        }
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
                    steps: model.backendState.isAvailable ? [
                        "选择科目",
                        "确认年份和考季",
                        "点击搜索并等待分组"
                    ] : [
                        "等待 Python bridge 连接",
                        "检查脚本路径",
                        "连接后重新搜索"
                    ]
                )
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
            }
        }
        .frame(minWidth: 360)
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

struct ProductBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(red: 0.90, green: 0.95, blue: 1.0).opacity(0.62),
                Color(red: 0.77, green: 0.84, blue: 1.0).opacity(0.28)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color(red: 0.47, green: 0.58, blue: 1.0).opacity(0.16))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: 120, y: -150)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Color(red: 0.45, green: 0.83, blue: 0.94).opacity(0.10))
                .frame(width: 420, height: 420)
                .blur(radius: 110)
                .offset(x: -160, y: 140)
        }
    }
}

struct PageHero<Accessory: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbolName: String
    let accessory: Accessory

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        symbolName: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.20), Color(red: 0.56, green: 0.45, blue: 1.0).opacity(0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: symbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 20)
            HStack(spacing: 10) {
                accessory
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [Color.white.opacity(0.38), Color.accentColor.opacity(0.055)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.46), lineWidth: 1)
        }
        .shadow(color: Color.accentColor.opacity(0.08), radius: 22, x: 0, y: 14)
    }
}

struct ControlPanelHeader: View {
    let title: String
    let subtitle: String
    let symbolName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct GuidanceCard: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
        }
    }
}

struct ResultPanelToolbar<Accessory: View>: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let accessory: Accessory

    init(title: String, subtitle: String, symbolName: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            accessory
        }
        .padding(.vertical, 8)
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
    let onPreview: () -> Void
    let onDownload: () -> Void
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
            HStack(spacing: 6) {
                PaperRowActionButton(
                    title: "预览",
                    systemImage: "eye",
                    isVisible: isHovering,
                    action: onPreview
                )
                PaperRowActionButton(
                    title: "下载",
                    systemImage: "arrow.down.circle",
                    isVisible: isHovering,
                    action: onDownload
                )
            }
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
        .onTapGesture(perform: onPreview)
    }

    private var hoverFill: Color {
        guard isHovering else { return .clear }
        return colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.035)
    }
}

private struct PaperRowActionButton: View {
    let title: String
    let systemImage: String
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(Color.accentColor.opacity(isVisible ? 0.12 : 0))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        .disabled(!isVisible)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct WorkflowEmptyState: View {
    let title: String
    let systemImage: String
    let steps: [String]

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 78, height: 78)
                Circle()
                    .stroke(Color.white.opacity(0.44), lineWidth: 1)
                    .frame(width: 78, height: 78)
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text("按下面顺序操作，列表会在这里更新。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 7) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20, height: 20)
                            .background {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.14))
                            }
                        Text(step)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.50))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.accentColor.opacity(0.10), lineWidth: 1)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 640)
    }
}
