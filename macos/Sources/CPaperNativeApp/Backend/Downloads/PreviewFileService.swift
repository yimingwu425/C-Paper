import Foundation

final class PreviewFileService: @unchecked Sendable {
    typealias TransferWriter = @Sendable (_ sourceURL: URL, _ destinationURL: URL, _ proxyURL: String) async throws -> Void

    private let paths: AppStoragePaths
    private let transfer: TransferWriter
    private let fileManager: FileManager

    init(
        paths: AppStoragePaths,
        transfer: @escaping TransferWriter = PreviewFileService.defaultTransfer,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.transfer = transfer
        self.fileManager = fileManager
    }

    func previewURL(for file: PaperFile, settings: DownloadSettings) async throws -> URL {
        let saveDirectory = URL(fileURLWithPath: (settings.saveDirectory as NSString).expandingTildeInPath)
        if let downloadedURL = DownloadDestinationBuilder.existingDownloadURL(
            for: file,
            saveDirectory: saveDirectory,
            fileManager: fileManager
        ) {
            return downloadedURL
        }

        let cacheURL = previewCacheURL(for: file)
        if fileManager.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }

        let sourceURL = try DownloadSourceURLResolver.resolvedSourceURL(for: file)
        try fileManager.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try await transfer(sourceURL, cacheURL, settings.proxyURL)
        return cacheURL
    }

    private func previewCacheURL(for file: PaperFile) -> URL {
        paths.cacheDirectory
            .appendingPathComponent("preview", isDirectory: true)
            .appendingPathComponent(file.filename)
    }

    static func defaultTransfer(sourceURL: URL, destinationURL: URL, proxyURL: String) async throws {
        let client = HTTPFileTransferClient(proxy: ProxyConfiguration(rawValue: proxyURL))
        try await client.transfer(from: sourceURL, to: destinationURL) { _ in }
    }
}
