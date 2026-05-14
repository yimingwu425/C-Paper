import Foundation

protocol LLMProvider {
    var name: String { get }
    func analyze(text: String, model: String, apiKey: String) async throws -> AnalysisResult
}

struct AnalysisResult: Codable {
    let paperInfo: PaperAnalysisInfo?
    let topics: [TopicDistribution]?
    let difficultyDistribution: DifficultyDist?
    let repeatedFromPrevious: [RepeatedQuestion]?
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case paperInfo = "paper_info"
        case topics
        case difficultyDistribution = "difficulty_distribution"
        case repeatedFromPrevious = "repeated_from_previous"
        case summary
    }
}

struct PaperAnalysisInfo: Codable {
    let subject: String?
    let year: Int?
    let season: String?
    let paperNumber: Int?
    let totalMarks: Int?
    let questionCount: Int?

    enum CodingKeys: String, CodingKey {
        case subject, year, season
        case paperNumber = "paper_number"
        case totalMarks = "total_marks"
        case questionCount = "question_count"
    }
}

struct TopicDistribution: Codable {
    let name: String?
    let questions: [Int]?
    let totalMarks: Int?

    enum CodingKeys: String, CodingKey {
        case name, questions
        case totalMarks = "total_marks"
    }
}

struct DifficultyDist: Codable {
    let easy: Int?
    let medium: Int?
    let hard: Int?
}

struct RepeatedQuestion: Codable {
    let question: Int?
    let similarTo: String?
    let similarity: Double?

    enum CodingKeys: String, CodingKey {
        case question
        case similarTo = "similar_to"
        case similarity
    }
}

@Observable
final class LLMService {
    var isAnalyzing = false
    var error: String?

    private let systemPrompt = """
    你是一个 CIE 试卷分析专家。请分析试卷文本，返回严格 JSON 格式。
    输出: {"paper_info":{...},"topics":[...],"difficulty_distribution":{...},"repeated_from_previous":[...],"summary":"..."}
    summary 用中文撰写。仅返回 JSON。
    """

    func analyze(text: String, provider: String, apiKey: String, model: String, baseURL: String = "") async throws -> AnalysisResult {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let truncated = text.count > 48000 ? String(text.prefix(48000)) + "\n[截断...]" : text

        if provider == "anthropic" {
            return try await callAnthropic(text: truncated, apiKey: apiKey, model: model, baseURL: baseURL.isEmpty ? "https://api.anthropic.com" : baseURL)
        } else {
            let url = baseURL.isEmpty ? "https://api.openai.com/v1" : baseURL
            if provider == "qwen" {
                return try await callOpenAICompatible(text: truncated, apiKey: apiKey, model: model, baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1")
            }
            return try await callOpenAICompatible(text: truncated, apiKey: apiKey, model: model, baseURL: url)
        }
    }

    private func callOpenAICompatible(text: String, apiKey: String, model: String, baseURL: String) async throws -> AnalysisResult {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "试卷文本:\n\n\(text)"]
            ],
            "temperature": 0.3,
            "max_tokens": 4096
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return try parseLLMResponse(decoded.choices.first?.message.content ?? "")
    }

    private func callAnthropic(text: String, apiKey: String, model: String, baseURL: String) async throws -> AnalysisResult {
        let url = URL(string: "\(baseURL)/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [["role": "user", "content": "试卷文本:\n\n\(text)"]],
            "temperature": 0.3
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return try parseLLMResponse(decoded.content.first?.text ?? "")
    }

    private func parseLLMResponse(_ raw: String) throws -> AnalysisResult {
        // Try direct JSON
        if let data = raw.data(using: .utf8),
           let result = try? JSONDecoder().decode(AnalysisResult.self, from: data) {
            return result
        }
        // Try extracting JSON from markdown code block
        let jsonPattern = /```(?:json)?\s*(\{[\s\S]*?\})\s*```/
        if let match = raw.firstMatch(of: jsonPattern) {
            let json = String(match.1)
            if let data = json.data(using: .utf8),
               let result = try? JSONDecoder().decode(AnalysisResult.self, from: data) {
                return result
            }
        }
        throw APIError.validationError("AI 返回格式无法解析")
    }
}

private struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
}

private struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

private struct OpenAIMessage: Codable {
    let content: String
}

private struct AnthropicResponse: Codable {
    let content: [AnthropicContent]
}

private struct AnthropicContent: Codable {
    let text: String
}
