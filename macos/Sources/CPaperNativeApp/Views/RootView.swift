import AppKit
import SwiftUI

struct RootView: View {
    @State private var bootCoordinator: AppBootCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(bootCoordinator: AppBootCoordinator = AppBootCoordinator()) {
        _bootCoordinator = State(initialValue: bootCoordinator)
    }

    var body: some View {
        Group {
            switch bootCoordinator.phase {
            case .loading:
                StartupLoadingView()
            case let .ready(model):
                ReadyRootView(model: model, reduceMotion: reduceMotion)
            case let .failed(failure):
                StartupFailureView(failure: failure) {
                    Task {
                        await bootCoordinator.retry()
                    }
                }
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .task {
            await bootCoordinator.startIfNeeded()
        }
    }
}

private struct ReadyRootView: View {
    @Bindable var model: AppModel
    let reduceMotion: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } detail: {
            ZStack(alignment: .bottom) {
                ProductBackdrop()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Group {
                        switch model.route {
                        case .search:
                            SearchView(model: model)
                        case .batch:
                            BatchView(model: model)
                        case .downloads:
                            DownloadsView(model: model)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.992, anchor: .center)))
                    .id(model.route)
                }

                StatusToast(model: model)
                    .padding(.bottom, CPDesign.Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .nativeContentBackground()
        }
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.route)
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.isLoading)
        .animation(CPDesign.Motion.gentle(reduceMotion: reduceMotion), value: model.downloadSnapshot.phase)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task {
                        switch model.route {
                        case .search:
                            await model.search()
                        case .batch:
                            await model.previewBatch()
                        case .downloads:
                            await model.refreshDownloads()
                        }
                    }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)

                Button {
                    withAnimation(CPDesign.Motion.standard(reduceMotion: reduceMotion)) {
                        model.route = .downloads
                    }
                    Task { await model.refreshDownloads() }
                } label: {
                    Label("下载", systemImage: "arrow.down.circle")
                }

                Button {
                    model.isSettingsPresented = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $model.isSettingsPresented) {
            SettingsView(model: model)
                .presentationBackground(.regularMaterial)
        }
        .alert(
            "C-Paper",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.clearError()
                    }
                }
            ),
            actions: {
                if model.lastDiagnostic != nil {
                    Button("复制诊断") {
                        model.copyLatestDiagnostic()
                    }
                    Button("显示支持文件夹") {
                        model.revealSupportDirectory()
                    }
                }
                Button("好", role: .cancel) {
                    model.clearError()
                }
            },
            message: {
                Text(model.errorMessage ?? "")
            }
        )
        .alert(
            "发现新版本",
            isPresented: Binding(
                get: { model.pendingUpdatePrompt != nil },
                set: { isPresented in
                    if !isPresented {
                        model.pendingUpdatePrompt = nil
                    }
                }
            ),
            actions: {
                Button("稍后", role: .cancel) {
                    model.pendingUpdatePrompt = nil
                }
                Button("下载更新") {
                    Task { await model.downloadAvailableUpdate() }
                }
            },
            message: {
                if let release = model.pendingUpdatePrompt {
                    Text("当前版本 \(BackendConstants.version)，最新版本 \(release.version)。下载完成后打开 DMG 安装；如果 macOS 阻止启动，请到“系统设置 > 隐私与安全性”允许打开 C-Paper。")
                }
            }
        )
    }
}

private struct StartupLoadingView: View {
    var body: some View {
        ZStack {
            ProductBackdrop()
                .ignoresSafeArea()

            GlassSurface(role: .floating, padding: CPDesign.Spacing.xl, strokeOpacity: 0.72) {
                VStack(spacing: CPDesign.Spacing.md) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("正在启动 C-Paper")
                        .font(.headline.weight(.semibold))
                    Text("正在准备设置、收藏与下载状态。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 320)
            }
        }
        .nativeContentBackground()
    }
}

private struct StartupFailureView: View {
    let failure: AppBootFailure
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            ProductBackdrop()
                .ignoresSafeArea()

            GlassSurface(role: .floating, padding: CPDesign.Spacing.xl, strokeOpacity: 0.76) {
                VStack(alignment: .leading, spacing: CPDesign.Spacing.lg) {
                    VStack(alignment: .leading, spacing: CPDesign.Spacing.sm) {
                        Label("启动失败", systemImage: "exclamationmark.triangle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("C-Paper 未能完成初始化。请重试；如果问题持续，请复制下方诊断信息。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: CPDesign.Spacing.sm) {
                        Text(failure.message)
                            .font(.headline.weight(.semibold))
                        ScrollView {
                            Text(failure.diagnosticText)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 120, maxHeight: 220)
                        .padding(CPDesign.Spacing.md)
                        .liquidGlassSurface(.content, strokeOpacity: 0.5)
                    }

                    HStack(spacing: CPDesign.Spacing.sm) {
                        Button("重试", action: onRetry)
                            .keyboardShortcut(.defaultAction)

                        Button("复制诊断信息") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(failure.diagnosticText, forType: .string)
                        }

                        if let supportDirectoryURL = failure.supportDirectoryURL {
                            Button("显示支持文件夹") {
                                try? FileManager.default.createDirectory(at: supportDirectoryURL, withIntermediateDirectories: true)
                                NSWorkspace.shared.activateFileViewerSelecting([supportDirectoryURL])
                            }
                        }
                    }
                }
                .frame(width: 520, alignment: .leading)
            }
        }
        .nativeContentBackground()
    }
}

private struct StatusToast: View {
    @Bindable var model: AppModel

    var body: some View {
        if isVisible {
            HStack(spacing: CPDesign.Spacing.sm) {
                icon
                    .frame(width: 18, height: 18)
                Text(message)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, CPDesign.Spacing.md)
            .padding(.vertical, CPDesign.Spacing.sm)
            .liquidGlassSurface(.floating, strokeOpacity: 0.72)
            .frame(maxWidth: 460)
        }
    }

    private var isVisible: Bool {
        model.isLoading || model.downloadSnapshot.isRunning
    }

    private var message: String {
        if model.downloadSnapshot.isRunning {
            return model.downloadSnapshot.message
        }
        if model.isLoading {
            return "正在更新试卷数据"
        }
        return ""
    }

    @ViewBuilder
    private var icon: some View {
        if model.downloadSnapshot.isRunning || model.isLoading {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

#Preview {
    RootView()
}
