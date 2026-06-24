import Foundation

private enum CompletedDownloadIntegrityIssue {
    case missing
    case retryableInvalid(String)
    case inspectOnlyInvalid(String)

    var diagnosticValue: String {
        switch self {
        case .missing:
            return "文件不存在。"
        case let .retryableInvalid(reason), let .inspectOnlyInvalid(reason):
            return reason
        }
    }

    var signatureKey: String {
        switch self {
        case .missing:
            return "missing"
        case let .retryableInvalid(reason):
            return "retryable-invalid:\(reason)"
        case let .inspectOnlyInvalid(reason):
            return "inspect-only-invalid:\(reason)"
        }
    }

    var isRetryableRepair: Bool {
        switch self {
        case .missing, .retryableInvalid:
            return true
        case .inspectOnlyInvalid:
            return false
        }
    }

    var taskIntegrityState: DownloadTaskIntegrityState {
        switch self {
        case .missing:
            return .missingFile
        case let .retryableInvalid(reason):
            if reason == "下载文件为空。" {
                return .emptyFile
            }
            return .unreadableFile
        case let .inspectOnlyInvalid(reason):
            if reason == "下载路径指向目录而不是文件。" {
                return .directoryPath
            }
            return .nonRegularFile
        }
    }
}

enum ResolvedSaveDirectoryResult {
    case ready(String)
    case cancelled
    case persistenceFailed(SupportDiagnostic)
}

extension AppModel {
    func search() async {
        guard let selectedSubject = activeSubject else { return }
        sourceNotice = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await backend.search(subject: selectedSubject, year: selectedYear, season: selectedSeason, settings: settings)
            searchResults = payload.files
            searchGroups = payload.groups
            searchResultSourceID = payload.sourceID
            searchUsedAutomaticFallback = payload.usedAutomaticFallback
            expandedPaperComponents = Set(payload.files.compactMap { $0.componentKey }.prefix(3))
            selectedPreview = nil
            applySourceWarnings(payload.warnings)
        } catch {
            handleSearchFailure(error, selectedSubject: selectedSubject)
        }
    }

    func previewBatch() async {
        guard let selectedSubject = activeSubject else { return }
        sourceNotice = nil
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
            batchPreviewSourceIDs = payload.sourceIDs
            batchPreviewSuccessfulQueryCount = payload.successfulQueryCount
            batchPreviewAutomaticFallbackQueryCount = payload.automaticFallbackQueryCount
            selectedPreview = nil
            applySourceWarnings(payload.warnings)
        } catch {
            handleBatchPreviewFailure(error, selectedSubject: selectedSubject)
        }
    }

    func handleSearchFailure(_ error: Error, selectedSubject: Subject) {
        sourceNotice = nil
        searchResults = []
        searchGroups = []
        searchResultSourceID = nil
        searchUsedAutomaticFallback = false
        expandedPaperComponents = []
        selectedPreview = nil
        let diagnostic = recordDiagnostic(
            context: .sourceProvider,
            message: error.localizedDescription,
            details: [
                SupportDiagnosticDetail(label: "Subject", value: selectedSubject.code),
                SupportDiagnosticDetail(label: "Year", value: "\(selectedYear)"),
                SupportDiagnosticDetail(label: "Season", value: selectedSeason.rawValue),
                SupportDiagnosticDetail(label: "Source Mode", value: settings.sourceMode.title)
            ]
        )
        sourceNotice = SourceNotice(diagnostic: diagnostic, level: .failure, action: .retrySearch)
    }

    func handleBatchPreviewFailure(_ error: Error, selectedSubject: Subject) {
        sourceNotice = nil
        batchPreview = []
        batchGroups = []
        batchPreviewSourceIDs = []
        batchPreviewSuccessfulQueryCount = 0
        batchPreviewAutomaticFallbackQueryCount = 0
        selectedPreview = nil
        let diagnostic = recordDiagnostic(
            context: .sourceProvider,
            message: error.localizedDescription,
            details: [
                SupportDiagnosticDetail(label: "Subject", value: selectedSubject.code),
                SupportDiagnosticDetail(label: "Year Range", value: "\(batchYearFrom)-\(batchYearTo)"),
                SupportDiagnosticDetail(label: "Source Mode", value: settings.sourceMode.title)
            ]
        )
        sourceNotice = SourceNotice(diagnostic: diagnostic, level: .failure, action: .retryBatchPreview)
    }

    func dismissSourceNotice() {
        sourceNotice = nil
    }

    func performSourceNoticeAction() async {
        guard let notice = sourceNotice else { return }
        switch notice.action {
        case .retryLoadSubjects:
            await loadSubjects()
        case .retrySearch:
            await search()
        case .retryBatchPreview:
            await previewBatch()
        case nil:
            break
        }
    }

    func startSearchDownload() async {
        guard !searchGroups.isEmpty else { return }
        await startDownload(
            groups: searchGroups,
            failureAction: .retrySearchDownload,
            successRoute: .downloads
        )
    }

    func startSingleFileDownload(_ file: PaperFile, forcedDuplicateMode: DuplicateMode? = nil) async {
        let retryOrigin: AppRoute = route == .batch ? .batch : .search
        await startDownload(
            groups: [backendGroup(for: file)],
            failureAction: .retrySingleFileDownload(file: file, origin: retryOrigin),
            successRoute: nil,
            forcedDuplicateMode: forcedDuplicateMode,
            details: [
                SupportDiagnosticDetail(label: "Filename", value: file.filename)
            ]
        )
    }

    func startBatchDownload() async {
        guard !batchGroups.isEmpty else { return }
        await startDownload(
            groups: batchGroups,
            failureAction: .retryBatchDownload,
            successRoute: .downloads
        )
    }

    private func startDownload(
        groups: [NativePaperGroup],
        failureAction: DownloadNoticeAction,
        successRoute: AppRoute?,
        forcedDuplicateMode: DuplicateMode? = nil,
        details: [SupportDiagnosticDetail] = []
    ) async {
        downloadNotice = nil

        do {
            let saveDirectoryResolution = try await resolvedSaveDirectory()
            switch saveDirectoryResolution {
            case let .ready(saveDirectory):
                var downloadOptions = settings.downloadOptions
                if let forcedDuplicateMode {
                    downloadOptions.duplicateMode = forcedDuplicateMode
                }
                let params = DownloadStartParams(
                    groups: groups,
                    saveDir: saveDirectory,
                    options: downloadOptions
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
                if let successRoute {
                    route = successRoute
                }
                await refreshDownloads()
                startPollingDownloads()
            case .cancelled:
                return
            case let .persistenceFailed(diagnostic):
                downloadNotice = DownloadNotice(diagnostic: diagnostic, action: failureAction)
            }
        } catch {
            handleDownloadStartFailure(error, action: failureAction, details: details)
        }
    }

    func dismissDownloadNotice() {
        downloadNotice = nil
    }

    func performDownloadNoticeAction() async {
        guard let notice = downloadNotice else { return }
        switch notice.action {
        case .retrySearchDownload:
            await startSearchDownload()
        case .retryBatchDownload:
            await startBatchDownload()
        case let .retrySingleFileDownload(file, _):
            await startSingleFileDownload(file)
        }
    }

    func handleDownloadStartFailure(
        _ error: Error,
        action: DownloadNoticeAction,
        details: [SupportDiagnosticDetail] = []
    ) {
        let diagnostic = recordDiagnostic(
            context: .download,
            message: error.localizedDescription,
            details: details
        )
        downloadNotice = DownloadNotice(diagnostic: diagnostic, action: action)
    }

    func refreshDownloads() async {
        let snapshot = await backend.downloadStatus()
        let items = await backend.downloadItems()
        let recoverySummary = await backend.consumeDownloadRecoverySummary()
        downloadSnapshot = snapshot
        downloads = items.sorted { $0.id < $1.id }
        if !downloads.contains(where: { $0.status == .failed && $0.errorType == .interrupted }) {
            downloadRecoveredCleanedPartialCount = 0
        }
        if let recoverySummary {
            recordRecoveredDownloadSessionIfNeeded(
                summary: recoverySummary,
                snapshot: snapshot,
                items: items
            )
        } else {
            if snapshot.isRunning || !items.contains(where: { $0.status == .failed }) {
                downloadRecoveryNotice = nil
            }
            recordDownloadFailuresIfNeeded(snapshot: snapshot, items: items)
        }
        recordCompletedDownloadIntegrityIfNeeded(snapshot: snapshot, items: items)
        retryPreviewAfterSuccessfulRepairIfNeeded(snapshot: snapshot, items: items)
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

    func retryRecoverableDownloads() async {
        let didStart = await backend.retryRecoverableDownloads()
        guard didStart else { return }
        await refreshDownloads()
        startPollingDownloads()
    }

    func retryDownloadsNeedingRepair() async {
        guard let notice = downloadIntegrityNotice, !notice.retryableTaskIDs.isEmpty else { return }
        let didStart = await backend.retryCompletedDownloadsNeedingRepair(ids: notice.retryableTaskIDs)
        guard didStart else { return }
        await refreshDownloads()
        startPollingDownloads()
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

    func resolvedSaveDirectory() async throws -> ResolvedSaveDirectoryResult {
        if usableSaveDirectoryURL() != nil {
            return .ready(settings.saveDirectory)
        }

        let chosenDirectory = await backend.chooseDirectory()
        guard !chosenDirectory.isEmpty else {
            return .cancelled
        }
        var draftSettings = settings
        draftSettings.saveDirectory = chosenDirectory
        let didSave = await saveSettings(draftSettings)
        guard didSave else {
            if let diagnostic = settingsNotice?.diagnostic ?? latestDiagnostic(for: .settings) {
                return .persistenceFailed(diagnostic)
            }
            let diagnostic = recordDiagnostic(
                context: .settings,
                message: "保存新的下载目录失败，请重试。",
                details: [
                    SupportDiagnosticDetail(label: "Save Directory", value: chosenDirectory)
                ]
            )
            settingsNotice = SettingsNotice(diagnostic: diagnostic)
            return .persistenceFailed(diagnostic)
        }
        return .ready(chosenDirectory)
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

    func applySourceWarnings(_ warnings: [String]) {
        if let diagnostic = recordSourceWarnings(warnings) {
            sourceNotice = SourceNotice(
                diagnostic: diagnostic,
                level: sourceNoticeLevel(for: warnings),
                action: nil
            )
        } else {
            sourceNotice = nil
        }
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

    private func sourceNoticeLevel(for warnings: [String]) -> SourceNoticeLevel {
        guard let firstWarning = warnings.first else {
            return .warning
        }
        if firstWarning.hasPrefix("首选来源响应过慢或不可用，已自动切换到 ")
            || firstWarning.hasPrefix("前 ")
        {
            return .automaticFallback
        }
        return .warning
    }

    func recordDownloadFailuresIfNeeded(
        snapshot: DownloadStatusSnapshot,
        items: [DownloadTaskItem]
    ) {
        guard !snapshot.isRunning else {
            lastDownloadFailureDiagnosticSignature = nil
            return
        }
        let failedItems = items.filter { $0.status == .failed }
        guard !failedItems.isEmpty else {
            lastDownloadFailureDiagnosticSignature = nil
            return
        }

        let signature = downloadFailureDiagnosticSignature(for: failedItems)
        guard signature != lastDownloadFailureDiagnosticSignature else {
            return
        }
        lastDownloadFailureDiagnosticSignature = signature

        let details = downloadFailureDiagnosticDetails(for: failedItems)
        recordDiagnostic(
            context: .download,
            message: "\(failedItems.count) 个下载任务失败",
            details: details
        )
    }

    func recordRecoveredDownloadSessionIfNeeded(
        summary: DownloadSessionRecoverySummary,
        snapshot: DownloadStatusSnapshot,
        items: [DownloadTaskItem]
    ) {
        guard !snapshot.isRunning else { return }
        let failedItems = items.filter { $0.status == .failed }
        guard !failedItems.isEmpty else { return }
        downloadRecoveredCleanedPartialCount = summary.cleanedPartialCount

        let signature = downloadFailureDiagnosticSignature(for: failedItems)
        lastDownloadFailureDiagnosticSignature = signature

        var details = [
            SupportDiagnosticDetail(label: "Recovered Failed Tasks", value: "\(summary.resumedFailureCount)"),
            SupportDiagnosticDetail(label: "Cleaned Partial Files", value: "\(summary.cleanedPartialCount)")
        ]
        details.append(contentsOf: downloadFailureDiagnosticDetails(for: failedItems))

        let taskCount = summary.resumedFailureCount
        let message: String
        if taskCount == 1 {
            message = "检测到 1 个上次中断的下载任务"
        } else {
            message = "检测到 \(taskCount) 个上次中断的下载任务"
        }

        recordDiagnostic(
            context: .download,
            message: message,
            details: details
        )
        if let diagnostic = latestDiagnostic(for: .download) {
            downloadRecoveryNotice = DownloadRecoveryNotice(
                diagnostic: diagnostic,
                recoveredTaskCount: summary.resumedFailureCount,
                cleanedPartialCount: summary.cleanedPartialCount
            )
        }
    }

    private func downloadFailureDiagnosticSignature(for failedItems: [DownloadTaskItem]) -> String {
        failedItems
            .sorted { lhs, rhs in
                if lhs.id != rhs.id {
                    return lhs.id < rhs.id
                }
                return lhs.filename < rhs.filename
            }
            .map { item in
                [
                    String(item.id),
                    item.filename,
                    item.errorType?.rawValue ?? "",
                    item.error,
                    item.savePath
                ].joined(separator: "\u{1F}")
            }
            .joined(separator: "\u{1E}")
    }

    private func downloadFailureDiagnosticDetails(for failedItems: [DownloadTaskItem]) -> [SupportDiagnosticDetail] {
        failedItems.prefix(6).flatMap { item in
            var details = [
                SupportDiagnosticDetail(label: "\(item.filename) Reason", value: item.message)
            ]
            if let guidance = item.recoveryAction.guidance {
                details.append(
                    SupportDiagnosticDetail(label: "\(item.filename) Suggested Action", value: guidance)
                )
            }
            if let rawErrorMessage = item.rawErrorMessage, rawErrorMessage != item.message {
                details.append(
                    SupportDiagnosticDetail(label: "\(item.filename) Raw Error", value: rawErrorMessage)
                )
            }
            details.append(
                SupportDiagnosticDetail(label: "\(item.filename) Save Path", value: item.savePath)
            )
            return details
        }
    }

    func dismissDownloadIntegrityNotice() {
        downloadIntegrityNotice = nil
    }

    private func recordCompletedDownloadIntegrityIfNeeded(
        snapshot: DownloadStatusSnapshot,
        items: [DownloadTaskItem]
    ) {
        guard !snapshot.isRunning else {
            downloadIntegrityNotice = nil
            downloadIntegrityStatesByTaskID = [:]
            return
        }

        let affectedCompletedItems = items.compactMap { item -> (DownloadTaskItem, CompletedDownloadIntegrityIssue)? in
            guard item.status == .done else { return nil }
            guard let issue = completedDownloadIntegrityIssue(for: item.savePath) else {
                return nil
            }
            return (item, issue)
        }

        guard !affectedCompletedItems.isEmpty else {
            downloadIntegrityNotice = nil
            downloadIntegrityStatesByTaskID = [:]
            lastDownloadIntegrityDiagnosticSignature = nil
            return
        }

        downloadIntegrityStatesByTaskID = Dictionary(
            uniqueKeysWithValues: affectedCompletedItems.map { item, issue in
                (item.id, issue.taskIntegrityState)
            }
        )

        let missingFileCount = affectedCompletedItems.filter { _, issue in
            if case .missing = issue {
                return true
            }
            return false
        }.count
        let invalidFileCount = affectedCompletedItems.count - missingFileCount
        let retryableTaskIDs = affectedCompletedItems.compactMap { item, issue in
            issue.isRetryableRepair ? item.id : nil
        }

        let signature = affectedCompletedItems
            .sorted { lhs, rhs in
                if lhs.0.id != rhs.0.id {
                    return lhs.0.id < rhs.0.id
                }
                return lhs.0.filename < rhs.0.filename
            }
            .map { item, issue in
                [String(item.id), item.filename, item.savePath, issue.signatureKey].joined(separator: "\u{1F}")
            }
            .joined(separator: "\u{1E}")

        if signature != lastDownloadIntegrityDiagnosticSignature {
            lastDownloadIntegrityDiagnosticSignature = signature
            let diagnostic = recordDiagnostic(
                context: .downloadIntegrity,
                message: downloadIntegrityDiagnosticMessage(
                    missingFileCount: missingFileCount,
                    invalidFileCount: invalidFileCount
                ),
                details: affectedCompletedItems.prefix(6).flatMap { item, issue in
                    [
                        SupportDiagnosticDetail(label: "\(item.filename) Status", value: item.status.title),
                        SupportDiagnosticDetail(label: "\(item.filename) Save Path", value: item.savePath),
                        SupportDiagnosticDetail(label: "\(item.filename) Integrity", value: issue.diagnosticValue)
                    ]
                }
            )
            downloadIntegrityNotice = DownloadIntegrityNotice(
                diagnostic: diagnostic,
                missingFileCount: missingFileCount,
                invalidFileCount: invalidFileCount,
                retryableTaskIDs: retryableTaskIDs
            )
            return
        }

        if let diagnostic = latestDiagnostic(for: .downloadIntegrity) {
            downloadIntegrityNotice = DownloadIntegrityNotice(
                diagnostic: diagnostic,
                missingFileCount: missingFileCount,
                invalidFileCount: invalidFileCount,
                retryableTaskIDs: retryableTaskIDs
            )
        }
    }

    private func completedDownloadIntegrityIssue(for savePath: String) -> CompletedDownloadIntegrityIssue? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: savePath, isDirectory: &isDirectory) else {
            return .missing
        }
        if isDirectory.boolValue {
            return .inspectOnlyInvalid("下载路径指向目录而不是文件。")
        }
        guard FileManager.default.isReadableFile(atPath: savePath) else {
            return .retryableInvalid("下载文件当前不可读。")
        }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: savePath),
           let fileType = attributes[.type] as? FileAttributeType,
           fileType != .typeRegular {
            return .inspectOnlyInvalid("下载路径不是常规文件。")
        }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: savePath),
           let size = attributes[.size] as? NSNumber,
           size.int64Value == 0 {
            return .retryableInvalid("下载文件为空。")
        }
        return nil
    }

    private func retryPreviewAfterSuccessfulRepairIfNeeded(
        snapshot: DownloadStatusSnapshot,
        items: [DownloadTaskItem]
    ) {
        guard !snapshot.isRunning, let pendingFileID = pendingPreviewRepairFileID else { return }
        defer { pendingPreviewRepairFileID = nil }
        guard selectedPreview?.id == pendingFileID, let selectedPreview else { return }
        if items.contains(where: { $0.filename == selectedPreview.filename && $0.status == .done }) {
            retryPreview()
        }
    }

    private func downloadIntegrityDiagnosticMessage(
        missingFileCount: Int,
        invalidFileCount: Int
    ) -> String {
        if invalidFileCount == 0 {
            return "部分已完成的下载文件已丢失，请重新下载缺失文件。"
        }
        if missingFileCount == 0 {
            return "部分已完成的下载文件已不可用，请重新下载或检查对应文件。"
        }
        return "部分已完成的下载文件已丢失或不可用，请重新下载或检查对应文件。"
    }
}
