import Foundation

enum APIError: LocalizedError {
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case unauthorized
    case rateLimited
    case serverError(Int)
    case notFound
    case validationError(String)

    var errorDescription: String? {
        switch self {
        case .networkError: return "网络连接失败，请检查网络设置"
        case .unauthorized: return "登录已过期，请重新登录"
        case .rateLimited: return "请求过于频繁，请稍后再试"
        case .serverError(let code): return "服务器错误 (\(code))"
        case .notFound: return "内容不存在"
        case .validationError(let msg): return msg
        default: return "未知错误"
        }
    }
}
