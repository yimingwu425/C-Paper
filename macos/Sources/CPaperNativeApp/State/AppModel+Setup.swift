import Foundation

extension AppModel {
    func bootstrap() async {
        await loadSettings()
        await loadSubjects()
        await loadFavorites()
        await refreshDownloads()
    }


    func selectFavorite(_ subject: Subject) {
        selectedSubject = subjects.first { $0.code == subject.code } ?? subject
        route = .search
    }

    func addSelectedSubjectToFavorites() async {
        guard let subject = activeSubject, !isSelectedSubjectFavorite else { return }

        do {
            try backend.addFavorite(subject)
            await loadFavorites()
        } catch {
            handleBackendError(error)
        }
    }

    func removeFavorite(_ subject: Subject) async {
        do {
            try backend.removeFavorite(code: subject.code)
            await loadFavorites()
        } catch {
            handleBackendError(error)
        }
    }

    func loadSubjects() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await backend.loadSubjects(proxyURL: settings.proxyURL, sourceMode: settings.sourceMode)
            subjects = payload.sorted { $0.code < $1.code }
            if let preferred = subjects.first(where: { $0.code == settings.lastSubject }) {
                selectedSubject = preferred
                manualSubjectCode = ""
            } else if selectedSubject == nil {
                selectedSubject = subjects.first
                if selectedSubject != nil {
                    manualSubjectCode = ""
                } else if !settings.lastSubject.isEmpty {
                    manualSubjectCode = settings.lastSubject
                }
            }
        } catch {
            handleBackendError(error)
            if selectedSubject == nil, manualSubjectCode.isEmpty, !settings.lastSubject.isEmpty {
                manualSubjectCode = settings.lastSubject
            }
        }
    }

    func loadFavorites() async {
        favorites = backend.loadFavorites()
    }

    func loadSettings() async {
        let loaded = backend.loadSettings()
        settings = loaded
        if let savedRoute = AppRoute(rawValue: loaded.lastMode) {
            route = savedRoute
        }
    }

    func saveSettings() async {
        settings.lastSubject = activeSubject?.code ?? ""
        settings.lastMode = route.rawValue

        do {
            try backend.saveSettings(settings)
        } catch {
            handleBackendError(error)
        }
    }

    func chooseSaveDirectory() async {
        let path = await backend.chooseDirectory()
        if !path.isEmpty {
            settings.saveDirectory = path
        }
    }

    func testProxy() async -> String {
        let result = await backend.testProxy(settings.proxyURL)
        if result.ok, let latency = result.latencyMs {
            return "连接成功 (\(latency) ms)"
        }
        return result.error ?? "代理测试失败"
    }
}
