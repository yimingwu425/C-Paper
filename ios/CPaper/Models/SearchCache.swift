import Foundation
import SwiftData

@Model
final class SearchCache {
    @Attribute(.unique) var cacheKey: String
    var data: Data
    var cachedAt: Date

    init(cacheKey: String, data: Data) {
        self.cacheKey = cacheKey
        self.data = data
        self.cachedAt = Date()
    }
}
