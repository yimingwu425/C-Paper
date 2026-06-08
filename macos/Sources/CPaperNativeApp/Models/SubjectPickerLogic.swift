import Foundation

enum SubjectPickerLogic {
    static func filteredSubjects(_ subjects: [Subject], query: String) -> [Subject] {
        let sortedSubjects = subjects.sorted { $0.code < $1.code }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return sortedSubjects
        }

        let normalizedQuery = trimmedQuery.localizedLowercase
        return sortedSubjects.filter { subject in
            subject.code.localizedLowercase.contains(normalizedQuery)
                || subject.displayName.localizedLowercase.contains(normalizedQuery)
        }
    }

    static func subjectSelectionState(
        for selection: Subject?,
        manualCode: String
    ) -> (selection: Subject?, manualCode: String) {
        guard selection != nil else {
            return (selection, manualCode)
        }
        return (selection, "")
    }

    static func manualCodeState(
        for manualCode: String,
        selection: Subject?
    ) -> (selection: Subject?, manualCode: String) {
        guard SubjectNormalizer.subjectCode(in: manualCode) != nil else {
            return (selection, manualCode)
        }
        return (nil, manualCode)
    }
}
