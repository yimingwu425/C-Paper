import Foundation

actor PreviewFileService {
    typealias TransferWriter = @Sendable (_ sourceURL: URL, _ destinationURL: URL, _ proxyURL: String) async throws -> Void

    private let paths: AppStoragePaths
    private let transfer: TransferWriter
    private let fileSystem: PreviewFileSystem
    private var inFlightDownloads: [URL: Task<URL, Error>] = [:]

    init(
        paths: AppStoragePaths,
        transfer: @escaping TransferWriter = PreviewFileService.defaultTransfer,
        fileSystem: PreviewFileSystem = PreviewFileSystem(fileManager: .default)
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
            try fileSystem.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let partialURL = cacheURL.deletingLastPathComponent()
                .appendingPathComponent("\(cacheURL.lastPathComponent).part.\(UUID().uuidString)")
            defer {
                try? fileSystem.removeItem(at: partialURL)
            }

            try await transfer(sourceURL, partialURL, settings.proxyURL)
            if fileSystem.fileExists(atPath: cacheURL.path) {
                _ = try fileSystem.replaceItemAt(cacheURL, withItemAt: partialURL)
            } else {
                try fileSystem.moveItem(at: partialURL, to: cacheURL)
            }
            return cacheURL
        }
        inFlightDownloads[cacheURL] = task

        do {
            let resolvedURL = try await task.value
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

final class PreviewFileSystem: @unchecked Sendable {
    let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: createIntermediates)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func replaceItemAt(_ originalItemURL: URL, withItemAt newItemURL: URL) throws -> URL? {
        try fileManager.replaceItemAt(originalItemURL, withItemAt: newItemURL)
    }

    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try fileManager.moveItem(at: srcURL, to: dstURL)
    }
}
