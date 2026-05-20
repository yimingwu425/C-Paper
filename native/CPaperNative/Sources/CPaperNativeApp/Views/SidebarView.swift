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

            Section("常用科目") {
                if model.favorites.isEmpty {
                    Text("暂无常用科目")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.favorites) { subject in
                        Button {
                            model.selectFavorite(subject)
                        } label: {
                            Label(subject.displayName, systemImage: "star")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("C-Paper")
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
    }
}
