import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.route) {
            Section {
                ForEach(AppRoute.allCases) { route in
                    Label(route.title, systemImage: route.symbolName)
                        .tag(route)
                }
            }

            Section {
                if model.favorites.isEmpty {
                    Text("暂无常用科目")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.favorites) { subject in
                        HStack(spacing: 6) {
                            Button {
                                model.selectFavorite(subject)
                            } label: {
                                Label(subject.displayName, systemImage: "star")
                            }
                            .buttonStyle(.plain)

                            Spacer(minLength: 4)

                            Button {
                                Task { await model.removeFavorite(subject) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.tertiary)
                            .help("移除收藏")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("常用科目")
                    Spacer()
                    Button {
                        Task { await model.addSelectedSubjectToFavorites() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedSubject == nil || model.isSelectedSubjectFavorite || !model.backendState.isAvailable)
                    .help("添加当前科目")
                }
            }
        }
        .navigationTitle("C-Paper")
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
    }
}
