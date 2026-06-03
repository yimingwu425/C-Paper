import Foundation

struct SourceHealthChecker {
    func check(_ source: any PaperSource) async -> SourceHealth {
        await source.healthCheck()
    }

    func checkAll(_ sources: [any PaperSource]) async -> [SourceHealth] {
        var health: [SourceHealth] = []
        for source in sources {
            health.append(await source.healthCheck())
        }
        return health
    }
}
