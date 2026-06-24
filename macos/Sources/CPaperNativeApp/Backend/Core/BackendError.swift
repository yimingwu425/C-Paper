import Foundation

enum BackendError: LocalizedError, Equatable {
    case invalidURL(String)
    case invalidResponse(String)
    case sourceUnavailable(PaperSourceID, String)
    case noResults([SourceAttempt])
    case downloadInProgress
    case invalidFilename(String)
    case fileSystem(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "无效 URL：\(value)"
        case .invalidResponse(let message):
            return "响应无效：\(message)"
        case .sourceUnavailable(let sourceID, let message):
            return "\(sourceID.title) 不可用：\(message)"
        case .noResults(let attempts):
            let summary = attempts.map { "\($0.sourceID.title): \($0.diagnosticMessage)" }.joined(separator: "；")
            return summary.isEmpty ? "未找到试卷" : "未找到试卷（\(summary)）"
        case .downloadInProgress:
            return "下载进行中，暂时无法执行该操作"
        case .invalidFilename(let filename):
            return "无效文件名：\(filename)"
        case .fileSystem(let message):
            return message
        }
    }
}
