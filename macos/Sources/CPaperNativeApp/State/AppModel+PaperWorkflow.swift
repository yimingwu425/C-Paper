import Foundation

extension AppModel {
    func search() async {
        guard let selectedSubject = activeSubject else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await backend.search(subject: selectedSubject, year: selectedYear, season: selectedSeason, settings: settings)
            searchResults = payload.files
            searchGroups = payload.groups
            expandedPaperComponents = Set(payload.files.compactMap { $0.componentKey }.prefix(3))
            selectedPreview = nil
            recordSourceWarnings(payload.warnings)
        } catch {
            handleBackendError(
                error,
                context: .sourceProvider,
                details: [
                    SupportDiagnosticDetail(label: "Subject", value: selectedSubject.code),
                    SupportDiagnosticDetail(label: "Year", value: "\(selectedYear)"),
                    SupportDiagnosticDetail(label: "Season", value: selectedSeason.rawValue),
                    SupportDiagnosticDetail(label: "Source Mode", value: settings.sourceMode.title)
                ]
            )
        }
    }

    func previewBatch() async {
        guard let selectedSubject = activeSubject else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await backend.batchPreview(
                subject: selectedSubject,
                yearFrom: batchYearFrom,
                yearTo: batchYearTo,
                seasons: batchSeasonList,
                paperGroups: batchPaperGroups,
                settings: settings
            )
            batchGroups = payload.groups
            batchPreview = payload.files
            selectedPreview = nil
            if let warning = payload.warnings.first {
                let diagnostic = recordSourceWarnings(payload.warnings)
                errorMessage = diagnostic?.message ?? SupportDiagnostic.redact(warning)
            }
        } catch {
            handleBackendError(
                error,
                context: .sourceProvider,
                details: [
                    SupportDiagnosticDetail(label: "Subject", value: selectedSubject.code),
                    SupportDiagnosticDetail(label: "Year Range", value: "\(batchYearFrom)-\(batchYearTo)"),
                    SupportDiagnosticDetail(label: "Source Mode", value: settings.sourceMode.title)
                ]
            )
        }
    }

    func startSearchDownload() async {
        guard !searchGroups.isEmpty else { return }

        do {
            let chosenDirectory = await backend.chooseDirectory()
            guard !chosenDirectory.isEmpty else {
                return
            }
            settings.saveDirectory = chosenDirectory

            let params = DownloadStartParams(
                groups: searchGroups,
                saveDir: settings.saveDirectory,
                options: settings.downloadOptions
            )
            let result = try await backend.startDownload(
                groups: params.groups,
                saveDirectory: params.saveDir,
                options: params.options,
                proxyURL: settings.proxyURL
            )
            guard result.ok else {
                throw BackendError.invalidResponse("下载任务启动失败")
            }
            route = .downloads
            await refreshDownloads()
            startPollingDownloads()
        } catch {
            handleBackendError(error, context: .download)
        }
    }

    func startSingleFileDownload(_ file: PaperFile) async {
        do {
            guard let saveDirectory = try await resolvedSaveDirectory() else {
                return
            }

            let params = DownloadStartParams(
                groups: [backendGroup(for: file)],
                saveDir: saveDirectory,
                options: settings.downloadOptions
            )
            let result = try await backend.startDownload(
                groups: params.groups,
                saveDirectory: params.saveDir,
                options: params.options,
                proxyURL: settings.proxyURL
            )
            guard result.ok else {
                throw BackendError.invalidResponse("下载任务启动失败")
            }
            await refreshDownloads()
            startPollingDownloads()
        } catch {
            handleBackendError(
                error,
                context: .download,
                details: [
                    SupportDiagnosticDetail(label: "Filename", value: file.filename)
                ]
            )
        }
    }

    func startBatchDownload() async {
        guard !batchGroups.isEmpty else { return }

        do {
            let chosenDirectory = await backend.chooseDirectory()
            guard !chosenDirectory.isEmpty else {
                return
            }
            settings.saveDirectory = chosenDirectory

            let params = DownloadStartParams(
                groups: batchGroups,
                saveDir: settings.saveDirectory,
                options: settings.downloadOptions
            )
            let result = try await backend.startDownload(
                groups: params.groups,
                saveDirectory: params.saveDir,
                options: params.options,
                proxyURL: settings.proxyURL
            )
            guard result.ok else {
                throw BackendError.invalidResponse("下载任务启动失败")
            }
            route = .downloads
            await refreshDownloads()
            startPollingDownloads()
        } catch {
            handleBackendError(error, context: .download)
        }
    }

    func refreshDownloads() async {
        let snapshot = await backend.downloadStatus()
        let items = await backend.downloadItems()
        downloadSnapshot = snapshot
        downloads = items.sorted { $0.id < $1.id }
        recordDownloadFailuresIfNeeded(snapshot: snapshot, items: items)
        if snapshot.isRunning {
            ensureDownloadPolling()
        } else {
            stopPollingDownloads()
        }
    }

    func cancelDownloads() async {
        await backend.cancelDownloads()
        await refreshDownloads()
    }

    func startPollingDownloads() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refreshDownloads()
                if !downloadSnapshot.isRunning {
                    break
                }
                try? await Task.sleep(nanoseconds: 750_000_000)
            }
        }
    }

    func ensureDownloadPolling() {
        guard pollTask == nil else { return }
        startPollingDownloads()
    }

    func stopPollingDownloads() {
        pollTask?.cancel()
        pollTask = nil
    }

    func resolvedSaveDirectory() async throws -> String? {
        let expandedPath = (settings.saveDirectory as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if !expandedPath.isEmpty,
           FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return settings.saveDirectory
        }

        let chosenDirectory = await backend.chooseDirectory()
        guard !chosenDirectory.isEmpty else {
            return nil
        }
        settings.saveDirectory = chosenDirectory
        await saveSettings()
        return chosenDirectory
    }

    func backendGroup(for file: PaperFile) -> NativePaperGroup {
        let type = file.paperType?.uppercased()
        let sy = syCode(season: file.season, year: file.year)
        let component = PaperComponent(
            sourceID: file.sourceID,
            filename: file.filename,
            url: file.url,
            paperType: file.paperType?.lowercased() ?? "",
            subjectCode: file.subjectCode,
            sy: sy,
            number: file.number,
            label: file.label
        )

        if type == "QP" {
            return NativePaperGroup(
                sourceID: file.sourceID,
                subjectCode: file.subjectCode,
                sy: sy,
                number: file.number,
                paperGroup: nil,
                qp: component,
                ms: nil,
                extras: []
            )
        }

        if type == "MS" {
            return NativePaperGroup(
                sourceID: file.sourceID,
                subjectCode: file.subjectCode,
                sy: sy,
                number: file.number,
                paperGroup: nil,
                qp: nil,
                ms: component,
                extras: []
            )
        }

        return NativePaperGroup(
            sourceID: file.sourceID,
            subjectCode: file.subjectCode,
            sy: sy,
            number: file.number,
            paperGroup: nil,
            qp: nil,
            ms: nil,
            extras: [component]
        )
    }

    func syCode(season: String?, year: Int?) -> String? {
        guard let season, let year else { return nil }
        let prefix: String
        switch season {
        case "Mar":
            prefix = "m"
        case "Jun":
            prefix = "s"
        case "Nov":
            prefix = "w"
        default:
            prefix = "w"
        }
        let shortYear = String(year % 100)
        return "\(prefix)\(shortYear.count == 1 ? "0\(shortYear)" : shortYear)"
    }

    @discardableResult
    private func recordSourceWarnings(_ warnings: [String]) -> SupportDiagnostic? {
        guard let firstWarning = warnings.first else { return nil }
        return recordDiagnostic(
            context: .sourceProvider,
            message: firstWarning,
            details: warnings.prefix(6).enumerated().map { index, warning in
                SupportDiagnosticDetail(label: "Warning \(index + 1)", value: warning)
            }
        )
    }

    private func recordDownloadFailuresIfNeeded(
        snapshot: DownloadStatusSnapshot,
        items: [DownloadTaskItem]
    ) {
        guard !snapshot.isRunning else { return }
        let failedItems = items.filter { $0.status == .failed }
        guard !failedItems.isEmpty else { return }

        let details = failedItems.prefix(6).flatMap { item in
            [
                SupportDiagnosticDetail(label: "\(item.filename) Error", value: item.error),
                SupportDiagnosticDetail(label: "\(item.filename) Save Path", value: item.savePath)
            ]
        }
        recordDiagnostic(
            context: .download,
            message: "\(failedItems.count) 个下载任务失败",
            details: details
        )
    }
}
