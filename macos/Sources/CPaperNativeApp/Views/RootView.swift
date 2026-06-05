import SwiftUI

struct RootView: View {
    @State private var model = AppModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .frame(minWidth: 1100, minHeight: 720)
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.route)
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.isLoading)
        .animation(CPDesign.Motion.gentle(reduceMotion: reduceMotion), value: model.downloadSnapshot.phase)
        .task {
            await model.bootstrap()
            await model.checkForUpdates(source: .startup)
        }
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
