import SwiftUI
import SwiftData

@main
struct CPaperApp: App {
    let apiClient: APIClient
    let authService: AuthService
    let downloadManager: DownloadManager

    init() {
        let tokenManager = TokenManager()
        self.apiClient = APIClient(tokenManager: tokenManager)
        self.authService = AuthService(apiClient: apiClient, tokenManager: tokenManager)
        self.downloadManager = DownloadManager()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(apiClient)
                .environment(authService)
                .environment(downloadManager)
        }
        .modelContainer(for: [
            Paper.self, DownloadTask.self, Favorite.self,
            Share.self, StudyGroup.self, Review.self, SearchCache.self
        ])
    }
}
