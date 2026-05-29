import SwiftUI

struct BatchView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ProductBackdrop()

            VStack(alignment: .leading, spacing: 26) {
                BatchHeader(model: model)
                HStack(alignment: .top, spacing: 28) {
                    GlassSurface(role: .content, padding: 20) {
                        BatchFilterPanel(model: model)
                    }
                    .frame(width: 322)
                    .overlay(alignment: .bottomLeading) {
                        Circle()
                            .fill(Color(red: 0.42, green: 0.80, blue: 0.95).opacity(0.14))
                            .frame(width: 120, height: 120)
                            .blur(radius: 34)
                            .offset(x: -32, y: 42)
                    }
                    BatchPreviewPanel(model: model)
                }
                .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.batchPreview)
                .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.selectedPreview)
            }
            .padding(34)
        }
    }
}

private struct BatchHeader: View {
    @Bindable var model: AppModel

    var body: some View {
        PageHero(
            eyebrow: "Batch Queue",
            title: "批量下载",
            subtitle: "组合年份、考季和 Paper，先生成清单，再一次性写入目录。",
            symbolName: "tray.and.arrow.down"
        ) {
            HeaderCount(value: model.batchPreview.count, unit: "个文件")
        }
    }
}

private struct BatchFilterPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ControlPanelHeader(
                title: "批量规则",
                subtitle: "适合教师按年份和 Paper 成套整理。",
                symbolName: "square.stack.3d.up"
            )

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

            FieldBlock("文件整理") {
                VStack(spacing: 8) {
                    BatchRuleToggle(
                        title: "包含 Mark Scheme",
                        subtitle: "同时下载答案与评分细则",
                        systemImage: "checkmark.seal",
                        isOn: $model.settings.includeMarkSchemes
                    )
                    BatchRuleToggle(
                        title: "合并年份文件夹",
                        subtitle: "按科目整理，减少目录层级",
                        systemImage: "folder.badge.gearshape",
                        isOn: $model.settings.mergeFolders
                    )
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
                .disabled(model.batchGroups.isEmpty || model.isLoading || !model.backendState.isAvailable)
            }

            GuidanceCard(
                title: "预览优先",
                text: "下载前先核对清单，可以避免选错年份或 Paper 后产生大量错误文件。"
            )
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

private struct BatchRuleToggle: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isOn ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.58))
                    Image(systemName: isOn ? "checkmark" : systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOn ? Color.accentColor : .secondary)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.08) : Color.white.opacity(0.42))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isOn ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.58), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct BatchPreviewPanel: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassSurface(role: .base, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                ResultPanelToolbar(
                    title: "预览清单",
                    subtitle: model.batchPreview.isEmpty ? "等待生成批量清单" : "即将写入下载队列",
                    symbolName: "list.bullet.rectangle"
                ) {
                    if !model.batchGroups.isEmpty {
                        Text("\(model.batchGroups.count) 组")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 2)

                HStack(spacing: 14) {
                    previewList

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

    private var previewList: some View {
        List(selection: $model.selectedPreview) {
            ForEach(model.batchPreview) { file in
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
            if model.batchPreview.isEmpty {
                WorkflowEmptyState(
                    title: "暂无预览",
                    systemImage: "tray.and.arrow.down",
                    steps: model.backendState.isAvailable ? [
                        "选择科目和年份",
                        "勾选考季与 Paper",
                        "预览清单后下载"
                    ] : [
                        "等待 Python bridge 连接",
                        "检查网络代理",
                        "连接后重新预览"
                    ]
                )
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
            }
        }
        .frame(minWidth: 360)
    }
}
