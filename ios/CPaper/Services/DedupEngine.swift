import Foundation

@Observable
final class DedupEngine {
    var isReady = false
    var totalQuestions = 0

    private let embeddingService: EmbeddingService
    private var embeddings: [[Float]] = []
    private var metadata: [DedupMeta] = []

    let thresholdHigh: Float = 0.80
    let thresholdMedium: Float = 0.65

    init(embeddingService: EmbeddingService) {
        self.embeddingService = embeddingService
    }

    func addQuestions(_ questions: [OCRQuestion], paperId: String, subject: String, year: Int) async throws {
        let texts = questions.map { $0.text }
        let newEmbeddings = try await embeddingService.computeBatch(texts: texts)

        for (i, q) in questions.enumerated() {
            embeddings.append(newEmbeddings[i])
            metadata.append(DedupMeta(
                paperId: paperId,
                questionNumber: q.number,
                text: String(q.text.prefix(500)),
                subject: subject,
                year: year
            ))
        }
        totalQuestions = metadata.count
        isReady = true
    }

    func findSimilar(to text: String, topK: Int = 10) async throws -> [DedupMatch] {
        guard !embeddings.isEmpty else { return [] }

        let queryEmb = try await embeddingService.computeEmbedding(text: text)

        var scores: [(Int, Float)] = []
        for (i, emb) in embeddings.enumerated() {
            let sim = embeddingService.cosineSimilarity(queryEmb, emb)
            if sim >= thresholdMedium {
                scores.append((i, sim))
            }
        }

        scores.sort { $0.1 > $1.1 }

        return scores.prefix(topK).map { (idx, score) in
            DedupMatch(
                questionNumber: metadata[idx].questionNumber,
                paperId: metadata[idx].paperId,
                similarity: score,
                matchedText: String(metadata[idx].text.prefix(200)),
                subject: metadata[idx].subject,
                year: metadata[idx].year
            )
        }
    }
}

struct DedupMeta {
    let paperId: String
    let questionNumber: String
    let text: String
    let subject: String
    let year: Int
}

struct DedupMatch: Identifiable {
    let id = UUID()
    let questionNumber: String
    let paperId: String
    let similarity: Float
    let matchedText: String
    let subject: String
    let year: Int
}
