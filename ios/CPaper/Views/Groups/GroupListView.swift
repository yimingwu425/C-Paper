import SwiftUI

struct GroupListView: View {
    @Environment(AuthService.self) private var authService
    @Environment(APIClient.self) private var apiClient
    @State private var groups: [GroupResponse] = []
    @State private var isLoading = false
    @State private var showJoinSheet = false
    @State private var joinCode = ""

    var body: some View {
        Group {
            if !authService.isAuthenticated {
                EmptyStateView(icon: "person.3", title: "需要登录", subtitle: "登录后可以使用学习小组功能")
            } else if isLoading {
                ProgressView()
            } else if groups.isEmpty {
                EmptyStateView(icon: "person.3", title: "暂无小组", subtitle: "创建或加入一个学习小组")
            } else {
                List(groups, id: \.id) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name ?? "")
                            .font(.headline)
                        Text("邀请码: \(group.inviteCode ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("学习小组")
        .toolbar {
            if authService.isAuthenticated {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("创建小组") { }
                        Button("加入小组") { showJoinSheet = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showJoinSheet) {
            NavigationStack {
                VStack(spacing: 16) {
                    TextField("输入邀请码", text: $joinCode)
                        .textFieldStyle(.roundedBorder)
                    Button("加入") { }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .navigationTitle("加入小组")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            guard authService.isAuthenticated else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let service = GroupService(apiClient: apiClient)
                groups = try await service.listGroups()
            } catch {}
        }
    }
}
