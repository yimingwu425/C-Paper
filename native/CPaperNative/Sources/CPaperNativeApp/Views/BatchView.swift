import SwiftUI

struct BatchView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.lg) {
            header
            actionBar
            previewHeader
            previewList
        }
        .padding(28)
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("批量下载")
                    .font(.largeTitle.weight(.semibold))
                Text("先预览文件清单，再启动下载队列。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(model.batchPreview.count) 个文件")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var actionBar: some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: CPDesign.Spacing.md) {
                Text("批量条件")
                    .font(.headline)

                HStack(spacing: CPDesign.Spacing.md) {
                    Picker("科目", selection: $model.selectedSubject) {
                        ForEach(model.subjects) { subject in
                            Text(subject.displayName).tag(Optional(subject))
                        }
                    }
                    .frame(minWidth: 300)

                    Stepper("从 \(model.batchYearFrom)", value: $model.batchYearFrom, in: 2000...model.batchYearTo)
                        .frame(width: 150)

                    Stepper("到 \(model.batchYearTo)", value: $model.batchYearTo, in: model.batchYearFrom...2035)
                        .frame(width: 150)
                }

                HStack(alignment: .top, spacing: CPDesign.Spacing.lg) {
                    optionGroup(title: "考季") {
                        HStack(spacing: CPDesign.Spacing.sm) {
                            ForEach(Season.allCases) { season in
                                Toggle(season.label, isOn: binding(for: season))
                                    .toggleStyle(.button)
                            }
                        }
                    }

                    optionGroup(title: "Paper") {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 8), count: 3), alignment: .leading, spacing: 8) {
                            ForEach(1...6, id: \.self) { group in
                                Toggle("P\(group)", isOn: binding(forGroup: group))
                                    .toggleStyle(.button)
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: CPDesign.Spacing.sm) {
                        Button {
                            Task { await model.previewBatch() }
                        } label: {
                            Label("预览", systemImage: "eye")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(model.selectedSubject == nil || model.batchSeasons.isEmpty || model.batchPaperGroups.isEmpty || model.isLoading || !model.backendState.isAvailable)

                        Button {
                            Task { await model.startBatchDownload() }
                        } label: {
                            Label("开始下载", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.batchGroups.isEmpty)
                    }
                }
            }
        }
    }

    private var previewHeader: some View {
        HStack {
            Text("预览清单")
                .font(.headline)
            Spacer()
            if !model.batchGroups.isEmpty {
                Text("\(model.batchGroups.count) 组")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var previewList: some View {
        List(selection: $model.selectedPreview) {
            ForEach(model.batchPreview) { file in
                PaperRow(file: file)
                    .tag(Optional(file))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
        .overlay {
            if model.batchPreview.isEmpty {
                ContentUnavailableView(
                    "暂无预览",
                    systemImage: "tray.and.arrow.down",
                    description: Text(model.backendState.isAvailable ? "选择条件后点击预览。" : "先连接 Python bridge。")
                )
            }
        }
    }

    private func optionGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.sm) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(CPDesign.Spacing.sm)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
    }

    private func binding(for season: Season) -> Binding<Bool> {
        Binding(
            get: { model.batchSeasons.contains(season) },
            set: { isOn in
                if isOn {
                    model.batchSeasons.insert(season)
                } else {
                    model.batchSeasons.remove(season)
                }
            }
        )
    }

    private func binding(forGroup group: Int) -> Binding<Bool> {
        Binding(
            get: { model.batchPaperGroups.contains(group) },
            set: { isOn in
                if isOn {
                    model.batchPaperGroups.insert(group)
                } else {
                    model.batchPaperGroups.remove(group)
                }
            }
        )
    }
}
