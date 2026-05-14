import Foundation
import Accelerate

@Observable
final class EmbeddingService {
    var isReady = false
    var error: String?

    private var model: NSObject? // Would be MLModel in production

    func initialize() async {
        // In production, load Core ML model:
        // let url = Bundle.main.url(forResource: "EmbeddingModel", withExtension: "mlmodelc")!
        // model = try! MLModel(contentsOf: url)
        isReady = true
    }

    func computeEmbedding(text: String) async throws -> [Float] {
        // Placeholder: in production, run Core ML inference
        // For now, return a random normalized vector for testing
        let dim = 384
        var vector = (0..<dim).map { _ in Float.random(in: -1...1) }
        normalize(&vector)
        return vector
    }

    func computeBatch(texts: [String]) async throws -> [[Float]] {
        try await withThrowingTaskGroup(of: [Float].self) { group in
            for text in texts {
                group.addTask { try await self.computeEmbedding(text: text) }
            }
            var results: [[Float]] = []
            for try await emb in group {
                results.append(emb)
            }
            return results
        }
    }

    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dotProduct / denom : 0
    }

    private func normalize(_ v: inout [Float]) {
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        let factor = 1.0 / max(sqrt(norm), 1e-8)
        vDSP_vsmul(v, 1, [factor], &v, 1, vDSP_Length(v.count))
    }
}
