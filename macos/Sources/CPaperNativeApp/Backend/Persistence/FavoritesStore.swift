import Foundation

struct FavoritesStore {
    private let store: JSONFileStore<[Subject]>

    init(paths: AppStoragePaths, fileManager: FileManager = .default) {
        store = JSONFileStore(url: paths.favoritesURL, defaultValue: [], fileManager: fileManager)
    }

    init(store: JSONFileStore<[Subject]>) {
        self.store = store
    }

    func load() -> [Subject] {
        uniqueByCode(store.read())
    }

    func add(_ subject: Subject) throws {
        var favorites = load()
        guard !favorites.contains(where: { $0.code == subject.code }) else {
            try store.write(favorites)
            return
        }

        favorites.append(subject)
        try store.write(favorites)
    }

    func remove(code: String) throws {
        let favorites = load().filter { $0.code != code }
        try store.write(favorites)
    }

    private func uniqueByCode(_ subjects: [Subject]) -> [Subject] {
        var seen = Set<String>()
        return subjects.filter { subject in
            seen.insert(subject.code).inserted
        }
    }
}
