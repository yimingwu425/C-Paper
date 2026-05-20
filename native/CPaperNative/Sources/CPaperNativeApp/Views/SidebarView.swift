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

            Section("Favorites") {
                if model.favorites.isEmpty {
                    Text("No favorites yet")
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
