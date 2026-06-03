import Foundation

struct SettingsStore {
    private let store: JSONFileStore<DownloadSettings>

    init(paths: AppStoragePaths, fileManager: FileManager = .default) {
        store = JSONFileStore(
            url: paths.settingsURL,
            defaultValue: DownloadSettings(),
            fileManager: fileManager
        )
    }

    init(store: JSONFileStore<DownloadSettings>) {
        self.store = store
    }

    func load() -> DownloadSettings {
        store.read()
    }

    func save(_ settings: DownloadSettings) throws {
        try store.write(settings)
    }
}
