import Foundation

@Observable
final class DownloadService: NSObject, URLSessionDownloadDelegate {
    private var session: URLSession!
    private var activeTasks: [URLSessionDownloadTask: DownloadTask] = [:]
    private let tokenManager: TokenManager

    var onProgress: ((UUID, Double) -> Void)?
    var onComplete: ((UUID, URL?) -> Void)?
    var onError: ((UUID, Error) -> Void)?

    init(tokenManager: TokenManager) {
        self.tokenManager = tokenManager
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    func download(filename: String, url: URL, saveDir: URL, task: DownloadTask) {
        var request = URLRequest(url: url)
        if let token = tokenManager.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let downloadTask = session.downloadTask(with: request)
        activeTasks[downloadTask] = task
        downloadTask.resume()
    }

    func cancel(taskId: UUID) {
        for (dlTask, task) in activeTasks where task.id == taskId {
            dlTask.cancel()
            activeTasks.removeValue(forKey: dlTask)
            break
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let task = activeTasks[downloadTask] else { return }
        let dest = URL(fileURLWithPath: task.savePath)

        do {
            let dir = dest.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            onComplete?(task.id, dest)
        } catch {
            onError?(task.id, error)
        }

        activeTasks.removeValue(forKey: downloadTask)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let task = activeTasks[downloadTask], totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress?(task.id, progress)
    }
}
