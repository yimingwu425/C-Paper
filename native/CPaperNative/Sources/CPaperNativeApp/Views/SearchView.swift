import SwiftUI

struct SearchView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: CPDesign.Spacing.lg) {
            header
            controls
            results
        }
        .padding(28)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Search papers")
                .font(.largeTitle.weight(.semibold))
            Text("Find question papers and mark schemes by subject, year, and season.")
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        GlassSurface {
            HStack(alignment: .center, spacing: CPDesign.Spacing.md) {
                Picker("Subject", selection: $model.selectedSubject) {
                    ForEach(model.subjects) { subject in
                        Text(subject.displayName).tag(Optional(subject))
                    }
                }
                .frame(minWidth: 260)

                Picker("Season", selection: $model.selectedSeason) {
                    ForEach(Season.allCases) { season in
                        Text(season.label).tag(season)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                Stepper("Year \(model.selectedYear)", value: $model.selectedYear, in: 2000...2035)
                    .frame(width: 160)

                Button {
                    Task { await model.search() }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.selectedSubject == nil || model.isLoading)
            }
        }
    }

    private var results: some View {
        List(selection: $model.selectedPreview) {
            ForEach(model.searchResults) { file in
                PaperRow(file: file)
                    .tag(Optional(file))
            }
        }
        .overlay {
            if model.searchResults.isEmpty {
                ContentUnavailableView(
                    "No results",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Choose filters and search.")
                )
            }
        }
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
        .padding(.vertical, 4)
    }
}
