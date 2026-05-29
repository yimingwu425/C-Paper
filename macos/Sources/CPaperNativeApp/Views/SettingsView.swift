import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var proxyStatus = ""

    var body: some View {
        ZStack {
            ProductBackdrop()

            VStack(spacing: 16) {
                SettingsHeader()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        SaveSettingsSection(model: model)
                        ProxySettingsSection(model: model, proxyStatus: $proxyStatus)
                        DownloadSettingsSection(model: model)
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)

                footer
            }
            .padding(20)
        }
        .controlSize(.small)
        .frame(width: 720, height: 560)
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: proxyStatus)
    }

    private var footer: some View {
        HStack(spacing: CPDesign.Spacing.sm) {
            Label("设置保存后会立即用于下一次搜索和下载。", systemImage: "checkmark.seal")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("取消") {
                dismiss()
            }
            .buttonStyle(GlassButtonStyle(.normal))

            Button("保存") {
                Task {
                    await model.saveSettings()
                    dismiss()
                }
            }
            .buttonStyle(GlassButtonStyle(.primary))
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.44), lineWidth: 1)
        }
    }
}

private struct SettingsHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.22), Color(red: 0.56, green: 0.45, blue: 1.0).opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "gearshape.2")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 5) {
                Text("Preferences")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text("设置")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("管理保存位置、网络代理和下载并发。批量文件整理规则已移到批量下载页。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(18)
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

private struct SaveSettingsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsSection(
            title: "保存",
            subtitle: "决定下载文件最终落在哪里。",
            systemImage: "folder"
        ) {
            SettingsRow(label: "保存目录") {
                HStack(spacing: 8) {
                    TextField("保存目录", text: $model.settings.saveDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("浏览") {
                        Task { await model.chooseSaveDirectory() }
                    }
                    .buttonStyle(GlassButtonStyle(.subtle))
                }
            }
            SettingsHint("批量下载和单份下载都会写入这个目录。建议使用独立文件夹，避免和手动整理的资料混在一起。")
        }
    }
}

private struct ProxySettingsSection: View {
    @Bindable var model: AppModel
    @Binding var proxyStatus: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsSection(
            title: "网络",
            subtitle: "用于学校网络、地区访问不稳定时的连接修正。",
            systemImage: "network"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsRow(label: "代理 URL") {
                    TextField("http://127.0.0.1:7890", text: $model.settings.proxyURL)
                        .textFieldStyle(.roundedBorder)
                }
                SettingsHint("如果学校网络或地区访问不稳定，可在这里填本机代理地址。留空则直连。")

                HStack(spacing: 10) {
                    Spacer()
                        .frame(width: 86)
                    Button("测试代理") {
                        Task { proxyStatus = await model.testProxy() }
                    }
                    .buttonStyle(GlassButtonStyle(.subtle))
                    if !proxyStatus.isEmpty {
                        Text(proxyStatus)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .transition(.opacity.combined(with: .move(edge: reduceMotion ? .bottom : .trailing)))
                    }
                }
            }
        }
    }
}

private struct DownloadSettingsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsSection(
            title: "下载",
            subtitle: "控制下载速度和并发数量。",
            systemImage: "arrow.down.circle"
        ) {
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

                SettingsHint("并发越高下载越快，但网络波动时建议降低到 3-4。")
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let content: Content

    init(title: String, subtitle: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [Color.white.opacity(0.30), Color.accentColor.opacity(0.045)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 1)
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .trailing)
            content
        }
    }
}

private struct SettingsHint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack {
            Spacer()
                .frame(width: 86)
            Text(text)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
