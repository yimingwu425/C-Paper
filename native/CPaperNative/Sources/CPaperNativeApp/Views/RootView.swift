import SwiftUI

struct RootView: View {
    @State private var model = AppModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } content: {
            VStack(spacing: 0) {
                if !model.backendState.isAvailable {
                    BackendStatusBanner(model: model)
                        .padding(.horizontal, CPDesign.Spacing.lg)
                        .padding(.top, CPDesign.Spacing.md)
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
            }
        } detail: {
            PDFPreviewView(file: model.selectedPreview)
        }
        .frame(minWidth: 1100, minHeight: 720)
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

                Button {
                    model.route = .downloads
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
        Label(state.title, systemImage: symbolName)
            .font(.caption.weight(.medium))
            .foregroundStyle(foregroundStyle)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.quaternary, lineWidth: 1)
            }
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
            .buttonStyle(.borderedProminent)
        }
        .padding(CPDesign.Spacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CPDesign.Radius.control, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
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

#Preview {
    RootView()
}
