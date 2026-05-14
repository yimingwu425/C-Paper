import SwiftUI

struct ProfileView: View {
    @Environment(AuthService.self) private var authService

    var body: some View {
        Group {
            if authService.isAuthenticated {
                List {
                    Section {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(authService.currentUser?.nickname ?? "用户")
                                    .font(.headline)
                                Text(authService.currentUser?.email ?? "")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("设置") {
                        NavigationLink { Text("代理设置") } label: {
                            Label("代理设置", systemImage: "network")
                        }
                        NavigationLink { Text("关于") } label: {
                            Label("关于 C-Paper", systemImage: "info.circle")
                        }
                    }

                    Section {
                        Button("登出", role: .destructive) {
                            authService.logout()
                        }
                    }
                }
            } else {
                LoginView()
            }
        }
        .navigationTitle("我的")
    }
}
