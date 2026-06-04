import Foundation

enum CloudflareChallengeDetector {
    static func isChallenge(html: String) -> Bool {
        let lowercased = html.lowercased()
        return lowercased.contains("just a moment")
            || lowercased.contains("cf-mitigated")
            || lowercased.contains("challenge-platform")
            || lowercased.contains("/cdn-cgi/challenge-platform")
    }
}

extension NetworkClientError {
    var isLikelyChallenge: Bool {
        switch self {
        case .httpStatus(403):
            true
        default:
            false
        }
    }
}
