import SwiftUI

struct ContentView: View {
    @Environment(AuthService.self) private var authService
    @State private var selectedTab: Tab = .search
    @State private var searchPath = NavigationPath()
    @State private var groupPath = NavigationPath()

    enum Tab: String, CaseIterable {
        case search, groups, favorites, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $searchPath) {
                SearchView()
            }
            .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            .tag(Tab.search)

            NavigationStack(path: $groupPath) {
                GroupListView()
            }
            .tabItem { Label("小组", systemImage: "person.3") }
            .tag(Tab.groups)

            NavigationStack {
                FavoritesView()
            }
            .tabItem { Label("收藏", systemImage: "star") }
            .tag(Tab.favorites)

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("我的", systemImage: "person.circle") }
            .tag(Tab.profile)
        }
        .task {
            await authService.restoreSession()
        }
    }
}
