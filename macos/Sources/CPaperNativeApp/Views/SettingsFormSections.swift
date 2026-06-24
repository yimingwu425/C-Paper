import SwiftUI

struct SaveSettingsSection: View {
    @Binding var settings: DownloadSettings
    let chooseSaveDirectory: () async -> Void

    var body: some View {
        SettingsSection(
            title: "保存",
            subtitle: "决定下载文件最终落在哪里。",
            systemImage: "folder"
        ) {
            SettingsRow(label: "保存目录") {
                HStack(spacing: 8) {
                    GlassTextField("保存目录", text: $settings.saveDirectory, systemImage: "folder")
                    Button("浏览") {
                        Task { await chooseSaveDirectory() }
                    }
                    .buttonStyle(GlassButtonStyle(.subtle))
                }
            }
            SettingsHint("批量下载和单份下载都会写入这个目录。建议使用独立文件夹，避免和手动整理的资料混在一起。")
        }
    }
}

struct ProxySettingsSection: View {
    @Binding var settings: DownloadSettings
    @Binding var proxyStatus: String
    let testProxy: (String) async -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsSection(
            title: "网络",
            subtitle: "用于学校网络、地区访问不稳定时的连接修正。",
            systemImage: "network"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsRow(label: "代理 URL") {
                    GlassTextField("http://127.0.0.1:7890", text: $settings.proxyURL, systemImage: "network")
                }
                SettingsHint("如果学校网络或地区访问不稳定，可在这里填本机代理地址。留空则直连。")

                HStack(spacing: 10) {
                    Spacer()
                        .frame(width: 86)
                    Button("测试代理") {
                        Task { proxyStatus = await testProxy(settings.proxyURL) }
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

struct SourceSettingsSection: View {
    @Binding var settings: DownloadSettings

    var body: some View {
        SettingsSection(
            title: "数据源",
            subtitle: "自动模式会在主来源不可用时按顺序尝试备用来源。",
            systemImage: "tray.full"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsRow(label: "来源") {
                    GlassMenuField(selection: $settings.sourceMode, systemImage: "tray.full") {
                        ForEach(PaperSourceID.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    } label: {
                        Text(settings.sourceMode.title)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(width: 220)
                }

                SettingsHint(settings.sourceMode == .automatic
                    ? "自动顺序：FrankCIE、EasyPaper、PastPapers、PapaCambridge。"
                    : "手动模式只使用选定来源，失败时不会自动切换。部分来源不提供科目列表，需要手动输入科目代码。")
            }
        }
    }
}

struct DownloadSettingsSection: View {
    @Binding var settings: DownloadSettings

    var body: some View {
        SettingsSection(
            title: "下载",
            subtitle: "控制下载速度和并发数量。",
            systemImage: "arrow.down.circle"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsRow(label: "速率") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.rate, in: 1...10, step: 1)
                        Text("\(Int(settings.rate))/s")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                SettingsRow(label: "并发") {
                    Stepper("\(settings.threads)", value: $settings.threads, in: 1...8)
                        .frame(width: 100, alignment: .leading)
                }

                SettingsRow(label: "重复文件") {
                    GlassMenuField(selection: $settings.duplicateMode, systemImage: "doc.on.doc") {
                        ForEach(DuplicateMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    } label: {
                        Text(settings.duplicateMode.title)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(width: 180)
                }

                SettingsHint("并发越高下载越快，但网络波动时建议降低到 3-4。")
            }
        }
    }
}
