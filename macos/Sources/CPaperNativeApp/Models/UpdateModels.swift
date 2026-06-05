import Foundation

enum UpdateCheckSource {
    case startup
    case manual
}

struct AppUpdateRelease: Identifiable, Hashable, Codable, Sendable {
    let version: String
    let tagName: String
    let name: String
    let htmlURL: URL
    let assetName: String
    let downloadURL: URL

    var id: String { tagName }
}

enum AppUpdateCheckResult: Equatable, Sendable {
    case upToDate(current: String, latest: String)
    case available(AppUpdateRelease)
}

enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(current: String, latest: String)
    case available(AppUpdateRelease)
    case downloading(progress: Double?)
    case downloaded(URL)
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            return "尚未检查更新"
        case .checking:
            return "正在检查 GitHub 最新版本"
        case let .upToDate(current, _):
            return "当前已是最新版 \(current)"
        case let .available(release):
            return "发现新版本 \(release.version)"
        case let .downloading(progress):
            if let progress {
                return "正在下载更新 \(Int(progress * 100))%"
            }
            return "正在下载更新"
        case .downloaded:
            return "更新 DMG 已下载"
        case let .failed(message):
            return message
        }
    }

    var downloadedURL: URL? {
        if case let .downloaded(url) = self {
            return url
        }
        return nil
    }

    var availableRelease: AppUpdateRelease? {
        switch self {
        case let .available(release):
            return release
        default:
            return nil
        }
    }
}
