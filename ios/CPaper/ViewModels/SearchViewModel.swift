import Foundation

@Observable
final class SearchViewModel {
    var searchText: String = ""
    var selectedSubject: Subject?
    var selectedYear: Int = 2024
    var selectedSeason: String = "Jun"
    var subjects: [Subject] = []
    var results: [PaperSearchResult] = []
    var isLoading: Bool = false
    var error: String?

    private let paperService: PaperService

    init(paperService: PaperService) {
        self.paperService = paperService
    }

    func loadSubjects() async {
        do {
            try await paperService.loadSubjects()
            subjects = paperService.subjects
        } catch {
            self.error = error.localizedDescription
        }
    }

    func search() async {
        guard let subject = selectedSubject else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            results = try await paperService.search(
                subject: subject.code, year: selectedYear, season: selectedSeason
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}
