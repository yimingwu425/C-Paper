import Foundation

enum BackendConstants {
    static let version = "6.0.0"
    static let userAgent = "C-Paper/6.0.0 (Swift Native; macOS)"
    static let frankcieBaseURL = URL(string: "https://cie.fraft.cn")!
    static let papaCambridgeBaseURL = URL(string: "https://papacambridge.com")!
    static let pastPapersBaseURL = URL(string: "https://pastpapers.co")!
    static let easyPaperBaseURL = URL(string: "https://easy-paper.com/paperview")!
    static let cacheTTL: TimeInterval = 24 * 60 * 60
    static let cacheMaxFiles = 200
    static let historyMaxItems = 2_000
}
