import SwiftUI

struct AboutSettingsSection: View {
    var body: some View {
        SettingsSection(
            title: "关于我们",
            subtitle: "项目信息、资料来源、隐私和版权说明。",
            systemImage: "info.circle"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                AboutRow(label: "作者") {
                    Text("Yiming Wu")
                }
                AboutRow(label: "网站") {
                    Link("yiming.us/c-paper", destination: URL(string: "https://yiming.us/c-paper")!)
                }
                AboutRow(label: "GitHub") {
                    Link("github.com/yimingwu425/C-Paper", destination: URL(string: "https://github.com/yimingwu425/C-Paper")!)
                }
                AboutRow(label: "试卷来源") {
                    Text("FrankCIE、EasyPaper、PastPapers.co、PapaCambridge")
                        .fixedSize(horizontal: false, vertical: true)
                }
                AboutRow(label: "隐私") {
                    Text("设置、下载历史和支持诊断保存在本机。诊断信息会脱敏代理凭据、EasyPaper token 和本机用户路径；C-Paper 不上传这些数据。")
                        .fixedSize(horizontal: false, vertical: true)
                }
                AboutRow(label: "版权") {
                    Text("C-Paper 使用 MIT License。试卷、评分标准及相关资料版权归 Cambridge Assessment International Education 或相应权利方所有，本项目不拥有、不托管、不重新分发试卷文件。")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct UpdateSettingsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        let updateWorkflowPresentation = UpdateWorkflowPresentation(status: model.updateStatus)
        SettingsSection(
            title: "检查更新",
            subtitle: "通过 GitHub Release 对比当前版本并下载最新 DMG。",
            systemImage: "arrow.down.app"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if updateSettingsWorkflowPresentation.showsUpdateNotice,
                   let notice = model.updateNotice {
                    UpdateNoticeCard(
                        message: notice.message,
                        primaryActionTitle: notice.action.title,
                        hasDiagnostic: true,
                        primaryAction: {
                            Task { await model.performUpdateNoticeAction() }
                        },
                        copyAction: { model.copyDiagnostic(notice.diagnostic) },
                        revealActionTitle: updateWorkflowPresentation.revealActionTitle,
                        revealAction: model.performUpdateNoticeRevealAction,
                        dismissAction: model.dismissUpdateNotice
                    )
                }

                SettingsRow(label: "当前版本") {
                    Text(BackendConstants.version)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.primary)
                }

                SettingsRow(label: "状态") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.updateStatus.message)
                            .font(.callout)
                            .foregroundStyle(statusColor)
                            .fixedSize(horizontal: false, vertical: true)

                        if case let .downloading(state) = model.updateStatus {
                            let progress = state.progress
                            ProgressView(value: progress ?? 0)
                                .progressViewStyle(.linear)
                                .frame(maxWidth: 260)
                                .accessibilityLabel("更新下载进度")
                                .accessibilityValue(progress.map { "\(Int($0 * 100))%" } ?? "正在准备")
                        }
                    }
                }

                if updateSettingsWorkflowPresentation.showsDownloadedSummary,
                   let downloadedState = model.downloadedUpdateState,
                   let summary = model.updateDownloadedSummary {
                    SettingsRow(label: "更新包") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                StatusBadge(
                                    text: downloadedState.origin.badgeTitle,
                                    systemImage: downloadedState.origin == .restoredArtifact ? "arrow.uturn.backward.circle" : "arrow.down.circle",
                                    tint: .accentColor,
                                    prominence: .tinted
                                )
                                if downloadedState.installState == .requiresManualOpen {
                                    StatusBadge(
                                        text: "待手动打开",
                                        systemImage: "shippingbox",
                                        tint: .orange,
                                        prominence: .tinted
                                    )
                                }
                            }

                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if updateSettingsWorkflowPresentation.showsDestinationPath,
                   let destinationURL = model.updateStatus.destinationURL {
                    SettingsRow(label: "保存到") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(updateDestinationDirectoryText(for: destinationURL))
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Text(destinationURL.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Spacer()
                        .frame(width: 86)

                    Button {
                        Task { await model.checkForUpdates(source: .manual) }
                    } label: {
                        Label(updateSettingsWorkflowPresentation.checkButtonTitle, systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GlassButtonStyle(.subtle))
                    .disabled(updateSettingsWorkflowPresentation.disablesCheckButton)

                    if updateSettingsWorkflowPresentation.showsDownloadButton {
                        Button {
                            Task { await model.downloadAvailableUpdate() }
                        } label: {
                            Label("下载更新", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(GlassButtonStyle(.primary))
                        .disabled(updateSettingsWorkflowPresentation.disablesDownloadButton)
                    }

                    if updateSettingsWorkflowPresentation.showsOpenDownloadedButton {
                        Button {
                            model.openDownloadedUpdate()
                        } label: {
                            Label("打开 DMG", systemImage: "shippingbox")
                        }
                        .buttonStyle(GlassButtonStyle(.primary))

                    }

                    if updateSettingsWorkflowPresentation.showsRevealDownloadedButton {
                        Button {
                            model.revealDownloadedUpdate()
                        } label: {
                            Label("显示文件", systemImage: "finder")
                        }
                        .buttonStyle(GlassButtonStyle(.subtle))
                    }
                }

                SettingsHint("DMG 下载完成后拖入 Applications。若 macOS 阻止打开，请进入“系统设置 > 隐私与安全性”，在安全性提示处允许打开 C-Paper。")
            }
        }
    }

    private var updateSettingsWorkflowPresentation: UpdateSettingsWorkflowPresentation {
        UpdateSettingsWorkflowPresentation(
            status: model.updateStatus,
            updateNotice: model.updateNotice,
            downloadedSummary: model.updateDownloadedSummary
        )
    }

    private var statusColor: Color {
        switch model.updateStatus {
        case let .downloaded(state):
            switch state.installState {
            case .missingFile, .invalidFile:
                return .orange
            case .downloaded, .requiresManualOpen:
                return .accentColor
            }
        case .available:
            return .accentColor
        case .failed:
            return .orange
        default:
            return .secondary
        }
    }

    private func updateDestinationDirectoryText(for url: URL) -> String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }
}

struct SupportSettingsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsSection(
            title: "支持诊断",
            subtitle: "最近一次失败的脱敏诊断与本机支持目录。",
            systemImage: "stethoscope"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsRow(label: "目录") {
                    Text(SupportDiagnostic.redact(model.supportDirectoryPath))
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                SettingsRow(label: "最近") {
                    Text(model.lastDiagnostic?.message ?? "暂无诊断")
                        .font(.callout)
                        .foregroundStyle(model.lastDiagnostic == nil ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Spacer()
                        .frame(width: 86)

                    Button {
                        model.copyLatestDiagnostic()
                    } label: {
                        Label("复制诊断", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(GlassButtonStyle(.subtle))
                    .disabled(!settingsWorkflowPresentation.canCopyLatestDiagnostic)

                    Button {
                        model.revealSupportDirectory()
                    } label: {
                        Label("显示文件夹", systemImage: "folder")
                    }
                    .buttonStyle(GlassButtonStyle(.subtle))
                }
            }
        }
    }

    private var settingsWorkflowPresentation: SettingsWorkflowPresentation {
        SettingsWorkflowPresentation(
            supportDirectoryNotice: model.supportDirectoryNotice,
            settingsNotice: model.settingsNotice,
            lastDiagnostic: model.lastDiagnostic
        )
    }
}

private struct AboutRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        SettingsRow(label: label) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsSection<Content: View>: View {
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

struct SettingsRow<Content: View>: View {
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

struct SettingsHint: View {
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
