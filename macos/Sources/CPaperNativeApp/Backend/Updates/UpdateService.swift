import Foundation

enum UpdateServiceError: Error, LocalizedError, Equatable {
    case invalidLatestRelease
    case noCompatibleDMGAsset
    case invalidVersion(String)

    var errorDescription: String? {
        switch self {
        case .invalidLatestRelease:
            "GitHub Release 信息格式无效"
        case .noCompatibleDMGAsset:
            "最新版本没有可下载的 macOS DMG"
        case .invalidVersion(let version):
            "版本号格式无效：\(version)"
        }
    }
}

struct AppVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ rawValue: String) throws {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^v"#, with: "", options: [.regularExpression, .caseInsensitive])
        let core = trimmed.split(separator: "-", maxSplits: 1).first.map(String.init) ?? trimmed
        let pieces = core.split(separator: ".").compactMap { Int($0) }
        guard pieces.count == 2 || pieces.count == 3 else {
            throw UpdateServiceError.invalidVersion(rawValue)
        }
        major = pieces[0]
        minor = pieces[1]
        patch = pieces.count == 3 ? pieces[2] : 0
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

final class UpdateService: @unchecked Sendable {
    typealias NetworkClientFactory = @Sendable (_ proxyURL: String) -> any NetworkClientProtocol
    typealias DownloadWriter = @Sendable (_ sourceURL: URL, _ destinationURL: URL, _ proxyURL: String, _ progress: @escaping @Sendable (Double?) async -> Void) async throws -> Void
    typealias TransferClientFactory = @Sendable (_ proxyURL: String) -> HTTPFileTransferClient

    private let currentVersion: String
    private let latestReleaseURL: URL
    private let updatesDirectory: URL
    private let networkClientFactory: NetworkClientFactory
    private let downloadWriter: DownloadWriter?
    private let transferClientFactory: TransferClientFactory
    private let fileManager: FileManager

    init(
        currentVersion: String = BackendConstants.version,
        latestReleaseURL: URL = BackendConstants.githubLatestReleaseAPIURL,
        updatesDirectory: URL? = nil,
        networkClientFactory: @escaping NetworkClientFactory = { proxyURL in
            NetworkClient(proxy: ProxyConfiguration(rawValue: proxyURL))
        },
        downloadWriter: DownloadWriter? = nil,
        transferClientFactory: @escaping TransferClientFactory = { proxyURL in
            HTTPFileTransferClient(proxy: ProxyConfiguration(rawValue: proxyURL))
        },
        fileManager: FileManager = .default
    ) {
        self.currentVersion = currentVersion
        self.latestReleaseURL = latestReleaseURL
        self.updatesDirectory = updatesDirectory ?? Self.defaultUpdatesDirectory()
        self.networkClientFactory = networkClientFactory
        self.downloadWriter = downloadWriter
        self.transferClientFactory = transferClientFactory
        self.fileManager = fileManager
    }

    func checkForUpdate(proxyURL: String) async throws -> AppUpdateCheckResult {
        let request = HTTPRequestBuilder().get(latestReleaseURL)
        let data = try await networkClientFactory(proxyURL).data(for: request)
        let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        guard payload.hasRequiredReleaseFields else {
            throw UpdateServiceError.invalidLatestRelease
        }
        guard let release = payload.appUpdateRelease else {
            throw UpdateServiceError.noCompatibleDMGAsset
        }

        let current = try AppVersion(currentVersion)
        let latest = try AppVersion(release.version)
        if latest > current {
            return .available(release)
        }
        return .upToDate(current: currentVersion, latest: release.version)
    }

    func downloadUpdate(
        _ release: AppUpdateRelease,
        proxyURL: String,
        progress: @escaping @Sendable (Double?) async -> Void
    ) async throws -> URL {
        try fileManager.createDirectory(at: updatesDirectory, withIntermediateDirectories: true)

        let destinationURL = destinationURL(for: release)
        let filename = destinationURL.lastPathComponent
        let partialURL = updatesDirectory.appendingPathComponent("\(filename).part")
        try? fileManager.removeItem(at: partialURL)

        do {
            try await writeDownload(from: release.downloadURL, to: partialURL, proxyURL: proxyURL, progress: progress)
        } catch {
            try? fileManager.removeItem(at: partialURL)
            throw error
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: partialURL)
        } else {
            try fileManager.moveItem(at: partialURL, to: destinationURL)
        }
        await progress(1)
        return destinationURL
    }

    func destinationURL(for release: AppUpdateRelease) -> URL {
        updatesDirectory.appendingPathComponent(release.assetName.safeUpdateFilename)
    }

    private static func defaultUpdatesDirectory() -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: (("~/Downloads") as NSString).expandingTildeInPath, isDirectory: true)
        return downloads
            .appendingPathComponent("C-Paper", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
    }

    private func writeDownload(
        from sourceURL: URL,
        to destinationURL: URL,
        proxyURL: String,
        progress: @escaping @Sendable (Double?) async -> Void
    ) async throws {
        if let downloadWriter {
            try await downloadWriter(sourceURL, destinationURL, proxyURL, progress)
        } else {
            try await transferClientFactory(proxyURL).transfer(from: sourceURL, to: destinationURL, progress: progress)
        }
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case assets
    }

    var hasRequiredReleaseFields: Bool {
        !tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var appUpdateRelease: AppUpdateRelease? {
        guard let asset = assets.first(where: \.isCompatibleDMG) else {
            return nil
        }
        let version = tagName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^v"#, with: "", options: [.regularExpression, .caseInsensitive])
        return AppUpdateRelease(
            version: version,
            tagName: tagName,
            name: name ?? "C-Paper \(version)",
            htmlURL: htmlURL,
            assetName: asset.name,
            downloadURL: asset.browserDownloadURL
        )
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let contentType: String?
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case contentType = "content_type"
        case browserDownloadURL = "browser_download_url"
    }

    var isCompatibleDMG: Bool {
        name.localizedCaseInsensitiveContains("C-Paper-Native")
            && name.localizedCaseInsensitiveContains("standalone")
            && name.lowercased().hasSuffix(".dmg")
            && (contentType == nil || contentType == "application/x-apple-diskimage" || contentType == "application/octet-stream")
    }
}

private extension String {
    var safeUpdateFilename: String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        let scalars = unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let filename = String(scalars)
        return filename.lowercased().hasSuffix(".dmg") ? filename : "\(filename).dmg"
    }
}
