import SwiftUI

struct BatchView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.lg) {
            BatchHeader(model: model)
            HStack(alignment: .top, spacing: CPDesign.Spacing.lg) {
                BatchFilterPanel(model: model)
                    .frame(width: 280)
                BatchPreviewPanel(model: model)
            }
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
                    .font(.title.weight(.semibold))
                Text("先预览文件清单，再选择保存目录并启动下载。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(model.batchPreview.count) 个文件")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct BatchFilterPanel: View {
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
            }

            FieldBlock("年份") {
                VStack(alignment: .leading, spacing: 8) {
                    Stepper("从 \(model.batchYearFrom)", value: $model.batchYearFrom, in: 2000...model.batchYearTo)
                    Stepper("到 \(model.batchYearTo)", value: $model.batchYearTo, in: model.batchYearFrom...2035)
                }
            }

            FieldBlock("考季") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Season.allCases) { season in
                        Toggle(season.label, isOn: seasonBinding(season))
                    }
                }
            }

            FieldBlock("Paper") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 6), count: 3), alignment: .leading, spacing: 6) {
                    ForEach(1...6, id: \.self) { group in
                        Toggle("P\(group)", isOn: groupBinding(group))
                            .toggleStyle(.button)
                    }
                }
            }

            Divider()

            Button {
                Task { await model.previewBatch() }
            } label: {
                Label("预览清单", systemImage: "eye")
            }
            .buttonStyle(.bordered)
            .disabled(model.selectedSubject == nil || model.batchSeasons.isEmpty || model.batchPaperGroups.isEmpty || model.isLoading || !model.backendState.isAvailable)

            Button {
                Task { await model.startBatchDownload() }
            } label: {
                Label("选择目录并下载", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.batchGroups.isEmpty)
        }
        .padding(CPDesign.Spacing.md)
        .background(.bar, in: RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
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

    var body: some View {
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
    }
}
