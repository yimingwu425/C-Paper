import Foundation

struct Subject: Codable, Identifiable {
    var id: String { code }
    let code: String
    let name: String
}

struct PaperSearchResult: Codable {
    let filename: String
    let url: String
}

@Observable
final class PaperService {
    private let apiClient: APIClient
    private let dataSourceBase = Constants.dataSourceURL

    var subjects: [Subject] = []
    var isLoading = false

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func loadSubjects() async throws {
        guard subjects.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        let url = URL(string: "\(dataSourceBase)\(Constants.API.subjects)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode([Subject].self, from: data)
        subjects = decoded
    }

    func search(subject: String, year: Int, season: String) async throws -> [PaperSearchResult] {
        let url = URL(string: "\(dataSourceBase)\(Constants.API.search)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode([
            "subject": subject,
            "year": "\(year)",
            "season": season
        ] as [String: String])

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([PaperSearchResult].self, from: data)
    }

    func downloadURL(filename: String) -> URL {
        URL(string: "\(dataSourceBase)\(Constants.API.download)/\(filename)")!
    }
}
