import SwiftUI

struct BatchFilterPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ControlPanelHeader(
                title: "批量规则",
                subtitle: "适合教师按年份和 Paper 成套整理。",
                symbolName: "square.stack.3d.up"
            )

            FieldBlock("科目") {
                SubjectPicker(
                    subjects: model.subjects,
                    selection: $model.selectedSubject,
                    manualCode: $model.manualSubjectCode
                )
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
                .disabled(!model.hasSearchSubject || model.batchSeasons.isEmpty || model.batchPaperGroups.isEmpty || model.isLoading)

                Button {
                    Task { await model.startBatchDownload() }
                } label: {
                    Label("选择目录并下载", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(.primary))
                .disabled(model.batchGroups.isEmpty || model.isLoading)
            }

            GuidanceCard(
                title: "预览优先",
                text: "下载前先核对清单，可以避免选错年份或 Paper 后产生大量错误文件。"
            )
        }
        .onSubmit {
            guard
                model.hasSearchSubject,
                !model.batchSeasons.isEmpty,
                !model.batchPaperGroups.isEmpty,
                !model.isLoading
            else {
                return
            }
            Task { await model.previewBatch() }
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
