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
                    if !model.backendState.isAvailable {
                        BackendStatusBanner(model: model)
                            .padding(.horizontal, CPDesign.Spacing.lg)
                            .padding(.top, CPDesign.Spacing.md)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

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
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.backendState.isAvailable)
        .animation(CPDesign.Motion.standard(reduceMotion: reduceMotion), value: model.isLoading)
        .animation(CPDesign.Motion.gentle(reduceMotion: reduceMotion), value: model.downloadSnapshot.phase)
        .task {
            await model.bootstrap()
        }
        .toolbar {
            ToolbarItem {
                BackendStatusPill(state: model.backendState)
            }

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
                .disabled(model.isLoading || !model.backendState.isAvailable)

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
    }
}

private struct BackendStatusPill: View {
    let state: BackendConnectionState

    var body: some View {
        StatusBadge(text: state.title, systemImage: symbolName, tint: foregroundStyle)
    }

    private var symbolName: String {
        switch state {
        case .checking: "clock"
        case .connected: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var foregroundStyle: Color {
        switch state {
        case .checking: .secondary
        case .connected: .green
        case .failed: .orange
        }
    }
}

private struct BackendStatusBanner: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: CPDesign.Spacing.md) {
            statusIcon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.backendState.title)
                    .font(.headline)
                Text(model.backendState.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(model.bridgeScriptPath)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(model.pythonExecutablePath)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: CPDesign.Spacing.md)

            Button {
                Task { await model.bootstrap() }
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
            }
            .buttonStyle(GlassButtonStyle(.primary))
        }
        .padding(CPDesign.Spacing.md)
        .liquidGlassSurface(.floating)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch model.backendState {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
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
        model.isLoading || model.downloadSnapshot.isRunning || model.backendState == .checking
    }

    private var message: String {
        if model.downloadSnapshot.isRunning {
            return model.downloadSnapshot.message
        }
        if model.isLoading {
            return "正在更新试卷数据"
        }
        return model.backendState.detail
    }

    @ViewBuilder
    private var icon: some View {
        if model.downloadSnapshot.isRunning || model.isLoading || model.backendState == .checking {
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
