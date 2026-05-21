import SwiftUI

struct BatchView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.lg) {
            BatchHeader(model: model)
            HStack(alignment: .top, spacing: 20) {
                GlassSurface(role: .content, padding: 14) {
                    BatchFilterPanel(model: model)
                }
                .frame(width: 240)
                BatchPreviewPanel(model: model)
            }
            .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.batchPreview)
        }
        .padding(28)
    }
}

private struct BatchHeader: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("批量下载")
                    .font(.title2.weight(.semibold))
                Text("先预览文件清单，再选择保存目录并启动下载。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HeaderCount(value: model.batchPreview.count, unit: "个文件")
        }
    }
}

private struct BatchFilterPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldBlock("科目") {
                SubjectPicker(subjects: model.subjects, selection: $model.selectedSubject)
            }

            FieldBlock("年份") {
                HStack(spacing: 8) {
                    Text("从")
                        .foregroundStyle(.secondary)
                    CompactYearField(value: $model.batchYearFrom, range: 2000...model.batchYearTo)
                    Text("到")
                        .foregroundStyle(.secondary)
                    CompactYearField(value: $model.batchYearTo, range: model.batchYearFrom...2035)
                }
                .font(.callout)
            }

            FieldBlock("考季") {
                HStack(spacing: 6) {
                    ForEach(Season.allCases) { season in
                        Toggle(season.label, isOn: seasonBinding(season))
                            .toggleStyle(CompactPillToggleStyle())
                    }
                }
            }

            FieldBlock("Paper") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 6), count: 3), alignment: .leading, spacing: 6) {
                    ForEach(1...6, id: \.self) { group in
                        Toggle("P\(group)", isOn: groupBinding(group))
                            .toggleStyle(CompactPillToggleStyle())
                    }
                }
            }

            Divider()

            VStack(spacing: CPDesign.Spacing.sm) {
                Button {
                    Task { await model.previewBatch() }
                } label: {
                    Label(model.isLoading ? "预览中" : "预览清单", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(model.batchGroups.isEmpty ? .primary : .normal))
                .disabled(model.selectedSubject == nil || model.batchSeasons.isEmpty || model.batchPaperGroups.isEmpty || model.isLoading || !model.backendState.isAvailable)

                Button {
                    Task { await model.startBatchDownload() }
                } label: {
                    Label("选择目录并下载", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(.primary))
                .disabled(model.batchGroups.isEmpty)
            }
        }
    }

    private func seasonBinding(_ season: Season) -> Binding<Bool> {
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

    private func groupBinding(_ group: Int) -> Binding<Bool> {
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

private struct BatchPreviewPanel: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassSurface(role: .base, padding: CPDesign.Spacing.sm) {
            VStack(alignment: .leading, spacing: CPDesign.Spacing.sm) {
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
                .padding(.horizontal, CPDesign.Spacing.sm)

                List(selection: $model.selectedPreview) {
                    ForEach(model.batchPreview) { file in
                        PaperRow(file: file)
                            .tag(Optional(file))
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(.background.opacity(0.58), in: RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
                .overlay {
                    if model.batchPreview.isEmpty {
                        ContentUnavailableView(
                            "暂无预览",
                            systemImage: "tray.and.arrow.down",
                            description: Text(model.backendState.isAvailable ? "选择条件后点击预览。" : "先连接 Python bridge。")
                        )
                        .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
                    }
                }
            }
        }
    }
}
