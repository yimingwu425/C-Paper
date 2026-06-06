import Foundation

enum DownloadSourceURLResolver {
    static func resolvedSourceURL(for component: PaperComponent) throws -> URL {
        try resolvedSourceURL(sourceID: component.sourceID, url: component.url)
    }

    static func resolvedSourceURL(for file: PaperFile) throws -> URL {
        try resolvedSourceURL(sourceID: file.sourceID, url: file.url)
    }

    private static func resolvedSourceURL(sourceID: PaperSourceID, url: URL) throws -> URL {
        guard sourceID == .easyPaper, let filePath = url.easyPaperFilePath else {
            return url
        }
        let token = try EasyPaperCrypto().encryptedRequestToken(payload: [
            "dir": filePath,
            "source": "website"
        ])
        return try easyPaperBaseURL(from: url)
            .appendingPathComponent("paperdownload")
            .appendingPathComponent("dir_v3")
            .appendingPathComponent(token)
    }

    private static func easyPaperBaseURL(from url: URL) throws -> URL {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme,
              let host = components.host
        else {
            throw DownloadDestinationError.invalidSaveDirectory
        }

        var baseComponents = URLComponents()
        baseComponents.scheme = scheme
        baseComponents.host = host
        baseComponents.port = components.port
        guard let baseURL = baseComponents.url else {
            throw DownloadDestinationError.invalidSaveDirectory
        }
        return baseURL
    }
}
