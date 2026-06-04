import Foundation

enum BackendConstants {
    static let version = "6.0.2"
    static let userAgent = "C-Paper/6.0.2 (Swift Native; macOS)"
    static let frankcieBaseURL = URL(string: "https://cie.fraft.cn")!
    static let papaCambridgePastPapersBaseURL = URL(string: "https://pastpapers.papacambridge.com")!
    static let pastPapersBaseURL = URL(string: "https://pastpapers.co")!
    static let easyPaperAPIBaseURL = URL(string: "https://server.easy-paper.com")!
    static let easyPaperPDFBaseURL = URL(string: "https://server.easy-paper.com")!
    static let cacheTTL: TimeInterval = 24 * 60 * 60
    static let cacheMaxFiles = 200
    static let historyMaxItems = 2_000
}
