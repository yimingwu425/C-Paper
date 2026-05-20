import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var proxyStatus = ""

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader()
            Divider()

            VStack(alignment: .leading, spacing: 22) {
                SaveSettingsSection(model: model)
                ProxySettingsSection(model: model, proxyStatus: $proxyStatus)
                DownloadSettingsSection(model: model)
            }
            .padding(24)

            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: 620, height: 500)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("取消") {
                dismiss()
            }
            Button("保存") {
                Task {
                    await model.saveSettings()
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(CPDesign.Spacing.md)
    }
}

private struct SettingsHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.title3.weight(.semibold))
                Text("保存位置、代理和下载行为")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

private struct SaveSettingsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsSection(title: "保存", systemImage: "folder") {
            SettingsRow(label: "保存目录") {
                HStack(spacing: 8) {
                    TextField("保存目录", text: $model.settings.saveDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("浏览") {
                        Task { await model.chooseSaveDirectory() }
                    }
                }
            }
        }
    }
}

private struct ProxySettingsSection: View {
    @Bindable var model: AppModel
    @Binding var proxyStatus: String

    var body: some View {
        SettingsSection(title: "网络", systemImage: "network") {
            VStack(alignment: .leading, spacing: 10) {
                SettingsRow(label: "代理 URL") {
                    TextField("http://127.0.0.1:7890", text: $model.settings.proxyURL)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 10) {
                    Spacer()
                        .frame(width: 84)
                    Button("测试代理") {
                        Task { proxyStatus = await model.testProxy() }
                    }
                    if !proxyStatus.isEmpty {
                        Text(proxyStatus)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct DownloadSettingsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsSection(title: "下载", systemImage: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsRow(label: "速率") {
                    HStack(spacing: 10) {
                        Slider(value: $model.settings.rate, in: 1...10, step: 1)
                        Text("\(Int(model.settings.rate))/s")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                SettingsRow(label: "并发") {
                    Stepper("\(model.settings.threads)", value: $model.settings.threads, in: 1...8)
                        .frame(width: 100, alignment: .leading)
                }

                SettingsRow(label: "重复文件") {
                    Picker("重复文件", selection: $model.settings.duplicateMode) {
                        ForEach(DuplicateMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }

                HStack(spacing: 18) {
                    Spacer()
                        .frame(width: 84)
                    Toggle("包含 Mark Scheme", isOn: $model.settings.includeMarkSchemes)
                    Toggle("合并年份文件夹", isOn: $model.settings.mergeFolders)
                }
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(width: 92, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .trailing)
            content
        }
    }
}
