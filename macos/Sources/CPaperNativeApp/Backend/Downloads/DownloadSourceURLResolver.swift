import Foundation

enum DownloadSourceURLResolver {
    static func resolvedSourceURL(for component: PaperComponent) throws -> URL {
        guard component.sourceID == .easyPaper, let filePath = component.url.easyPaperFilePath else {
            return component.url
        }
        let token = try EasyPaperCrypto().encryptedRequestToken(payload: [
            "dir": filePath,
            "source": "website"
        ])
        return try easyPaperBaseURL(from: component.url)
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
