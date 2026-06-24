import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var proxyStatus = ""
    @State private var draftSettings: DownloadSettings

    init(model: AppModel) {
        self.model = model
        _draftSettings = State(initialValue: model.settings)
    }

    var body: some View {
        ZStack {
            ProductBackdrop()

            VStack(spacing: 16) {
                SettingsHeader()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        if settingsWorkflowPresentation.showsSupportDirectoryNotice,
                           let notice = model.supportDirectoryNotice {
                            SupportDirectoryNoticeCard(
                                message: notice.message,
                                retryAction: model.revealSupportDirectory,
                                copyAction: { model.copyDiagnostic(notice.diagnostic) },
                                dismissAction: model.dismissSupportDirectoryNotice
                            )
                        }
                        if settingsWorkflowPresentation.showsSettingsNotice,
                           let notice = model.settingsNotice {
                            SettingsNoticeCard(
                                message: notice.message,
                                copyAction: { model.copyDiagnostic(notice.diagnostic) },
                                revealAction: model.revealSupportDirectory,
                                dismissAction: model.dismissSettingsNotice
                            )
                        }
                        SaveSettingsSection(settings: $draftSettings) {
                            if let selectedPath = await model.chooseSaveDirectory() {
                                draftSettings.saveDirectory = selectedPath
                            }
                        }
                        SourceSettingsSection(settings: $draftSettings)
                        ProxySettingsSection(settings: $draftSettings, proxyStatus: $proxyStatus) { proxyURL in
                            await model.testProxy(proxyURL)
                        }
                        DownloadSettingsSection(settings: $draftSettings)
                        AboutSettingsSection()
                        UpdateSettingsSection(model: model)
                        SupportSettingsSection(model: model)
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)

                footer
            }
            .padding(20)
        }
        .controlSize(.small)
        .frame(width: 720, height: 660)
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: proxyStatus)
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.updateStatus)
    }

    private var settingsWorkflowPresentation: SettingsWorkflowPresentation {
        SettingsWorkflowPresentation(
            supportDirectoryNotice: model.supportDirectoryNotice,
            settingsNotice: model.settingsNotice,
            lastDiagnostic: model.lastDiagnostic
        )
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
                    if await model.saveSettings(draftSettings) {
                        dismiss()
                    }
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
