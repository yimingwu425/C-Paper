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
        favoriteNotice = nil

        do {
            try backend.addFavorite(subject)
            await loadFavorites()
            favoriteNotice = nil
        } catch {
            handleFavoriteMutationFailure(
                error,
                action: .retryAdd(subject: subject),
                subject: subject,
                operation: "收藏"
            )
        }
    }

    func removeFavorite(_ subject: Subject) async {
        favoriteNotice = nil
        do {
            try backend.removeFavorite(code: subject.code)
            await loadFavorites()
            favoriteNotice = nil
        } catch {
            handleFavoriteMutationFailure(
                error,
                action: .retryRemove(subject: subject),
                subject: subject,
                operation: "移除收藏"
            )
        }
    }

    func loadSubjects() async {
        sourceNotice = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await backend.loadSubjects(proxyURL: settings.proxyURL, sourceMode: settings.sourceMode)
            subjects = payload.sorted { $0.code < $1.code }
            if let preferred = subjects.first(where: { $0.code == settings.lastSubject }) {
                selectedSubject = preferred
                manualSubjectCode = ""
            } else if selectedSubject == nil {
                if !settings.lastSubject.isEmpty {
                    manualSubjectCode = settings.lastSubject
                }
            }
        } catch {
            handleLoadSubjectsFailure(error)
            if selectedSubject == nil, manualSubjectCode.isEmpty, !settings.lastSubject.isEmpty {
                manualSubjectCode = settings.lastSubject
            }
        }
    }

    func handleLoadSubjectsFailure(_ error: Error) {
        if let sourceNoticeForUnsupportedList = unsupportedSubjectListSourceNotice(for: error) {
            sourceNotice = sourceNoticeForUnsupportedList
            return
        }
        let diagnostic = recordDiagnostic(
            context: .sourceProvider,
            message: error.localizedDescription,
            details: [
                SupportDiagnosticDetail(label: "Source Mode", value: settings.sourceMode.title)
            ]
        )
        sourceNotice = SourceNotice(
            diagnostic: diagnostic,
            level: .failure,
            action: .retryLoadSubjects
        )
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

    @discardableResult
    func saveSettings() async -> Bool {
        await saveSettings(settings)
    }

    @discardableResult
    func saveSettings(_ draftSettings: DownloadSettings) async -> Bool {
        var committedSettings = draftSettings
        committedSettings.lastSubject = activeSubject?.code ?? ""
        committedSettings.lastMode = route.rawValue

        do {
            try backend.saveSettings(committedSettings)
            settings = committedSettings
            settingsNotice = nil
            saveDirectoryNotice = nil
            return true
        } catch {
            let diagnostic = recordDiagnostic(
                context: .settings,
                message: error.localizedDescription,
                details: [
                    SupportDiagnosticDetail(label: "Save Directory", value: committedSettings.saveDirectory),
                    SupportDiagnosticDetail(label: "Source Mode", value: committedSettings.sourceMode.title)
                ]
            )
            settingsNotice = SettingsNotice(diagnostic: diagnostic)
            return false
        }
    }

    func dismissSettingsNotice() {
        settingsNotice = nil
    }

    func dismissFavoriteNotice() {
        favoriteNotice = nil
    }

    func performFavoriteNoticeAction() async {
        guard let notice = favoriteNotice else { return }
        switch notice.action {
        case let .retryAdd(subject):
            selectedSubject = subjects.first { $0.code == subject.code } ?? subject
            manualSubjectCode = ""
            await addSelectedSubjectToFavorites()
        case let .retryRemove(subject):
            await removeFavorite(subject)
        }
    }

    func handleFavoriteMutationFailure(
        _ error: Error,
        action: FavoriteNoticeAction,
        subject: Subject,
        operation: String
    ) {
        let diagnostic = recordDiagnostic(
            context: .favorites,
            message: error.localizedDescription,
            details: [
                SupportDiagnosticDetail(label: "Operation", value: operation),
                SupportDiagnosticDetail(label: "Subject Code", value: subject.code),
                SupportDiagnosticDetail(label: "Subject Name", value: subject.name)
            ]
        )
        favoriteNotice = FavoriteNotice(diagnostic: diagnostic, action: action)
    }

    private func unsupportedSubjectListSourceNotice(for error: Error) -> SourceNotice? {
        guard settings.sourceMode != .automatic else {
            return nil
        }
        guard let sourceError = error as? PaperSourceError,
              case let .sourceUnavailable(message) = sourceError,
              message.contains("暂不支持科目列表")
        else {
            return nil
        }

        let diagnostic = recordDiagnostic(
            context: .sourceProvider,
            message: "当前来源不支持科目列表，请直接手动输入科目代码或切换来源。",
            details: [
                SupportDiagnosticDetail(label: "Source Mode", value: settings.sourceMode.title),
                SupportDiagnosticDetail(label: "Reason", value: message)
            ]
        )
        return SourceNotice(
            diagnostic: diagnostic,
            level: .failure,
            action: nil
        )
    }

    func chooseSaveDirectory() async -> String? {
        let path = await backend.chooseDirectory()
        if path.isEmpty {
            return nil
        }
        return path
    }

    func testProxy() async -> String {
        await testProxy(settings.proxyURL)
    }

    func testProxy(_ proxyURL: String) async -> String {
        let result = await backend.testProxy(proxyURL)
        if result.ok, let latency = result.latencyMs {
            return "连接成功 (\(latency) ms)"
        }
        return result.error ?? "代理测试失败"
    }
}
