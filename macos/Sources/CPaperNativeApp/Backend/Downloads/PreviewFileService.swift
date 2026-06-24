import Foundation

actor PreviewFileService {
    typealias TransferWriter = @Sendable (_ sourceURL: URL, _ destinationURL: URL, _ proxyURL: String) async throws -> Void

    private let paths: AppStoragePaths
    private let transfer: TransferWriter
    private let fileSystem: StagedFileSystem
    private var inFlightDownloads: [URL: Task<URL, Error>] = [:]

    init(
        paths: AppStoragePaths,
        transfer: @escaping TransferWriter = PreviewFileService.defaultTransfer,
        fileSystem: StagedFileSystem = StagedFileSystem(fileManager: .default)
    ) {
        self.paths = paths
        self.transfer = transfer
        self.fileSystem = fileSystem
    }

    func previewURL(for file: PaperFile, settings: DownloadSettings) async throws -> URL {
        let saveDirectory = URL(fileURLWithPath: (settings.saveDirectory as NSString).expandingTildeInPath)
        if let downloadedURL = DownloadDestinationBuilder.existingDownloadURL(
            for: file,
            saveDirectory: saveDirectory,
            fileManager: fileSystem.fileManager
        ) {
            return downloadedURL
        }

        let cacheURL = try previewCacheURL(for: file)
        if fileSystem.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }

        if let existingTask = inFlightDownloads[cacheURL] {
            return try await existingTask.value
        }

        let sourceURL = try DownloadSourceURLResolver.resolvedSourceURL(for: file)
        let fileSystem = self.fileSystem
        let task = Task { [transfer, fileSystem] in
            try await fileSystem.stagedWrite(to: cacheURL) { partialURL in
                try await transfer(sourceURL, partialURL, settings.proxyURL)
            }
            return cacheURL
        }
        inFlightDownloads[cacheURL] = task

        do {
            let resolvedURL = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            inFlightDownloads[cacheURL] = nil
            return resolvedURL
        } catch {
            inFlightDownloads[cacheURL] = nil
            throw error
        }
    }

    private func previewCacheURL(for file: PaperFile) throws -> URL {
        guard let filename = DownloadDestinationBuilder.safePDFFileName(file.filename, url: file.url) else {
            throw BackendError.invalidFilename(file.filename)
        }

        return paths.cacheDirectory
            .appendingPathComponent("preview", isDirectory: true)
            .appendingPathComponent(filename)
    }

    static func defaultTransfer(sourceURL: URL, destinationURL: URL, proxyURL: String) async throws {
        let client = HTTPFileTransferClient(proxy: ProxyConfiguration(rawValue: proxyURL))
        try await client.transfer(from: sourceURL, to: destinationURL) { _ in }
    }
}
