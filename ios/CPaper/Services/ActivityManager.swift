import Foundation
import ActivityKit

struct DownloadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var completedCount: Int
        var totalCount: Int
        var currentFile: String
        var isDownloading: Bool
    }

    var subjectName: String
    var startedAt: Date
}

@Observable
final class ActivityManager {
    var currentActivity: Activity<DownloadActivityAttributes>?

    func startActivity(subject: String, total: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attrs = DownloadActivityAttributes(subjectName: subject, startedAt: Date())
        let state = DownloadActivityAttributes.ContentState(
            completedCount: 0,
            totalCount: total,
            currentFile: "",
            isDownloading: true
        )

        do {
            currentActivity = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            print("Failed to start activity: \(error)")
        }
    }

    func updateProgress(completed: Int, total: Int, currentFile: String) {
        guard let activity = currentActivity else { return }

        let state = DownloadActivityAttributes.ContentState(
            completedCount: completed,
            totalCount: total,
            currentFile: currentFile,
            isDownloading: true
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func endActivity() {
        guard let activity = currentActivity else { return }

        let state = DownloadActivityAttributes.ContentState(
            completedCount: activity.content.state.totalCount,
            totalCount: activity.content.state.totalCount,
            currentFile: "",
            isDownloading: false
        )

        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 5))
            currentActivity = nil
        }
    }
}
