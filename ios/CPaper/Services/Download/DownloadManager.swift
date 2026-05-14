import Foundation

@Observable
final class DownloadManager {
    var activeDownloads: [UUID: DownloadTask] = [:]
    var completedDownloads: [UUID: DownloadTask] = [:]

    private var downloadService: DownloadService?

    func configure(tokenManager: TokenManager) {
        downloadService = DownloadService(tokenManager: tokenManager)

        downloadService?.onProgress = { [weak self] taskId, progress in
            self?.activeDownloads[taskId]?.progress = progress
        }

        downloadService?.onComplete = { [weak self] taskId, url in
            guard let self, var task = self.activeDownloads[taskId] else { return }
            task.status = "done"
            task.progress = 1.0
            task.completedAt = Date()
            self.activeDownloads.removeValue(forKey: taskId)
            self.completedDownloads[taskId] = task
        }

        downloadService?.onError = { [weak self] taskId, error in
            self?.activeDownloads[taskId]?.status = "failed"
            self?.activeDownloads[taskId]?.error = error.localizedDescription
        }
    }

    func startDownload(filename: String, url: URL, saveDir: URL) -> UUID {
        let task = DownloadTask(filename: filename, savePath: saveDir.appendingPathComponent(filename).path)
        activeDownloads[task.id] = task
        downloadService?.download(filename: filename, url: url, saveDir: saveDir, task: task)
        return task.id
    }

    func cancelDownload(taskId: UUID) {
        downloadService?.cancel(taskId: taskId)
        activeDownloads.removeValue(forKey: taskId)
    }
}
