import SwiftUI

struct BatchView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.lg) {
            header
            actionBar
            previewList
        }
        .padding(28)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Batch download")
                .font(.largeTitle.weight(.semibold))
            Text("Preview files across years and paper groups before starting a managed download queue.")
                .foregroundStyle(.secondary)
        }
    }

    private var actionBar: some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: CPDesign.Spacing.md) {
                HStack(spacing: CPDesign.Spacing.md) {
                    Picker("Subject", selection: $model.selectedSubject) {
                        ForEach(model.subjects) { subject in
                            Text(subject.displayName).tag(Optional(subject))
                        }
                    }
                    .frame(minWidth: 260)

                    Stepper("From \(model.batchYearFrom)", value: $model.batchYearFrom, in: 2000...model.batchYearTo)
                        .frame(width: 160)

                    Stepper("To \(model.batchYearTo)", value: $model.batchYearTo, in: model.batchYearFrom...2035)
                        .frame(width: 160)
                }

                HStack(alignment: .top, spacing: CPDesign.Spacing.xl) {
                    VStack(alignment: .leading, spacing: CPDesign.Spacing.xs) {
                        Text("Seasons")
                            .font(.headline)
                        ForEach(Season.allCases) { season in
                            Toggle(season.label, isOn: binding(for: season))
                        }
                    }

                    VStack(alignment: .leading, spacing: CPDesign.Spacing.xs) {
                        Text("Paper groups")
                            .font(.headline)
                        LazyVGrid(columns: [.init(.fixed(56)), .init(.fixed(56)), .init(.fixed(56))], alignment: .leading, spacing: 8) {
                            ForEach(1...6, id: \.self) { group in
                                Toggle("P\(group)", isOn: binding(forGroup: group))
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: CPDesign.Spacing.sm) {
                        Button {
                            Task { await model.previewBatch() }
                        } label: {
                            Label("Preview", systemImage: "eye")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(model.selectedSubject == nil || model.batchSeasons.isEmpty || model.batchPaperGroups.isEmpty || model.isLoading)

                        Button {
                            Task { await model.startBatchDownload() }
                        } label: {
                            Label("Start Download", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.batchGroups.isEmpty)
                    }
                }
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
        .overlay {
            if model.batchPreview.isEmpty {
                ContentUnavailableView(
                    "No preview yet",
                    systemImage: "tray.and.arrow.down",
                    description: Text("Choose filters, then preview the generated file list.")
                )
            }
        }
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
