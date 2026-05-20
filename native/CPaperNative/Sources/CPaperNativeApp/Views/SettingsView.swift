import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var proxyStatus = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Save") {
                    HStack {
                        TextField("Save directory", text: $model.settings.saveDirectory)
                        Button("Browse") {
                            Task { await model.chooseSaveDirectory() }
                        }
                    }
                }

                Section("Network") {
                    TextField("Proxy URL", text: $model.settings.proxyURL)
                    HStack {
                        Button("Test Proxy") {
                            Task { proxyStatus = await model.testProxy() }
                        }
                        if !proxyStatus.isEmpty {
                            Text(proxyStatus)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Section("Downloads") {
                    HStack {
                        Text("Rate")
                        Slider(value: $model.settings.rate, in: 1...10, step: 1)
                        Text("\(Int(model.settings.rate))/s")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }

                    Stepper("Concurrency \(model.settings.threads)", value: $model.settings.threads, in: 1...8)

                    Picker("Duplicate Mode", selection: $model.settings.duplicateMode) {
                        ForEach(DuplicateMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Toggle("Include Mark Schemes", isOn: $model.settings.includeMarkSchemes)
                    Toggle("Merge Year Folders", isOn: $model.settings.mergeFolders)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    Task {
                        await model.saveSettings()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(CPDesign.Spacing.md)
        }
        .frame(width: 540, height: 520)
    }
}
