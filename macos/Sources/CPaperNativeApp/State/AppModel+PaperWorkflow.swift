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
        } catch {
            handleBackendError(error)
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
                errorMessage = warning
            }
        } catch {
            handleBackendError(error)
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
            handleBackendError(error)
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
            handleBackendError(error)
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
            handleBackendError(error)
        }
    }

    func refreshDownloads() async {
        let snapshot = await backend.downloadStatus()
        let items = await backend.downloadItems()
        downloadSnapshot = snapshot
        downloads = items.sorted { $0.id < $1.id }
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
}
