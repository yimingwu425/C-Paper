import SwiftUI

struct RootView: View {
    @State private var model = AppModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } content: {
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
        } detail: {
            PDFPreviewView(file: model.selectedPreview)
        }
        .frame(minWidth: 1100, minHeight: 720)
        .task {
            await model.bootstrap()
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
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    model.route = .downloads
                    Task { await model.refreshDownloads() }
                } label: {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }

                Button {
                    model.isSettingsPresented = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
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
                Button("OK", role: .cancel) {
                    model.clearError()
                }
            },
            message: {
                Text(model.errorMessage ?? "")
            }
        )
    }
}

#Preview {
    RootView()
}
