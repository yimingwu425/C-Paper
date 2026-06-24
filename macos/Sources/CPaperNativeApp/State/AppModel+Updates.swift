import AppKit
import Foundation

private enum DownloadedUpdateFileAvailability {
    case ready
    case missing
    case invalid(String)
}

extension AppModel {
    var updateNoticeRevealActionTitle: String {
        UpdateWorkflowPresentation(status: updateStatus).revealActionTitle
    }

    func checkForUpdates(source: UpdateCheckSource) async {
        if source == .startup {
            guard !didRunStartupUpdateCheck else { return }
            didRunStartupUpdateCheck = true
        }

        updateNotice = nil
        updateStatus = .checking
        do {
            let result = try await backend.checkForUpdate(proxyURL: settings.proxyURL)
            switch result {
            case let .upToDate(current, latest):
                updateStatus = .upToDate(current: current, latest: latest)
            case let .available(release):
                if let restoredState = restoredDownloadedUpdateState(for: release) {
                    updateStatus = .downloaded(restoredState)
                } else {
                    updateStatus = .available(release)
                }
                if source == .startup {
                    pendingUpdatePrompt = release
                }
            }
        } catch {
            let diagnostic = recordDiagnostic(context: .update, message: error.localizedDescription)
            let failure = UpdateFailureState(phase: .check, message: diagnostic.message)
            updateStatus = .failed(failure)
            updateNotice = UpdateNotice(diagnostic: diagnostic, action: failure.recoveryAction)
        }
    }

    func downloadAvailableUpdate() async {
        let release: AppUpdateRelease?
        if let pendingUpdatePrompt {
            release = pendingUpdatePrompt
        } else {
            release = updateStatus.availableRelease
        }
        guard let release else { return }

        pendingUpdatePrompt = nil
        let destinationURL = backend.updateDestinationURL(for: release)
        updateNotice = nil
        updateStatus = .downloading(
            UpdateDownloadState(
                release: release,
                progress: nil,
                destinationURL: destinationURL
            )
        )
        do {
            let downloadedURL = try await backend.downloadUpdate(release, proxyURL: settings.proxyURL) { [weak self] progress in
                await MainActor.run {
                    self?.updateStatus = .downloading(
                        UpdateDownloadState(
                            release: release,
                            progress: progress,
                            destinationURL: destinationURL
                        )
                    )
                }
            }
            let downloadedState = DownloadedUpdateState(
                release: release,
                fileURL: downloadedURL,
                installState: .downloaded,
                origin: .currentSession
            )
            updateStatus = .downloaded(downloadedState)
            _ = openDownloadedUpdate()
        } catch {
            let diagnostic = recordDiagnostic(
                context: .update,
                message: error.localizedDescription
            )
            let failure = UpdateFailureState(
                phase: .download,
                message: diagnostic.message,
                release: release,
                destinationURL: destinationURL
            )
            updateStatus = .failed(failure)
            updateNotice = UpdateNotice(diagnostic: diagnostic, action: failure.recoveryAction)
            errorMessage = nil
        }
    }

    func dismissUpdateNotice() {
        updateNotice = nil
    }

    func performUpdateNoticeRevealAction() {
        if updateStatus.canAccessDownloadedFile {
            revealDownloadedUpdate()
        } else {
            revealSupportDirectory()
        }
    }

    func performUpdateNoticeAction() async {
        guard let notice = updateNotice else { return }
        switch notice.action {
        case .retryCheck:
            await checkForUpdates(source: .manual)
        case .retryDownload:
            await downloadAvailableUpdate()
        case .openDownloadedDMG:
            _ = openDownloadedUpdate()
        }
    }

    @discardableResult
    func openDownloadedUpdate() -> Bool {
        guard case let .downloaded(state) = updateStatus else {
            return false
        }
        switch downloadedUpdateFileAvailability(for: state.fileURL) {
        case .missing:
            handleMissingDownloadedUpdateFile(state)
            return false
        case let .invalid(reason):
            handleInvalidDownloadedUpdateFile(state, reason: reason)
            return false
        case .ready:
            break
        }
        let didOpen = openDownloadedUpdateFile()
        if didOpen {
            if state.installState == .requiresManualOpen {
                updateStatus = .downloaded(
                    DownloadedUpdateState(
                        release: state.release,
                        fileURL: state.fileURL,
                        installState: .downloaded,
                        origin: state.origin
                    )
                )
            }
            updateNotice = nil
            errorMessage = nil
        } else {
            handleDownloadedUpdateOpenFailure(state)
        }
        return didOpen
    }

    func revealDownloadedUpdate() {
        guard case let .downloaded(state) = updateStatus else { return }
        switch downloadedUpdateFileAvailability(for: state.fileURL) {
        case .missing:
            handleMissingDownloadedUpdateFile(state)
            return
        case let .invalid(reason):
            handleInvalidDownloadedUpdateFile(state, reason: reason)
            return
        case .ready:
            break
        }
        NSWorkspace.shared.activateFileViewerSelecting([state.fileURL])
    }

    func handleDownloadedUpdateOpenFailure(_ state: DownloadedUpdateState) {
        updateStatus = .downloaded(
            DownloadedUpdateState(
                release: state.release,
                fileURL: state.fileURL,
                installState: .requiresManualOpen,
                origin: state.origin
            )
        )
        let diagnostic = recordDiagnostic(
            context: .update,
            message: "更新 DMG 已下载，但打开失败，请在设置中重试或手动检查文件。",
            details: [
                SupportDiagnosticDetail(label: "Downloaded File", value: state.fileURL.path)
            ]
        )
        updateNotice = UpdateNotice(
            diagnostic: diagnostic,
            action: .openDownloadedDMG
        )
        errorMessage = nil
    }

    func handleInvalidDownloadedUpdateFile(_ state: DownloadedUpdateState, reason: String) {
        updateStatus = .downloaded(
            DownloadedUpdateState(
                release: state.release,
                fileURL: state.fileURL,
                installState: .invalidFile,
                origin: state.origin
            )
        )
        let diagnostic = recordDiagnostic(
            context: .update,
            message: "已下载的更新 DMG 无法使用，请重新下载。",
            details: [
                SupportDiagnosticDetail(label: "Downloaded File", value: state.fileURL.path),
                SupportDiagnosticDetail(label: "Reason", value: reason)
            ]
        )
        updateNotice = UpdateNotice(
            diagnostic: diagnostic,
            action: .retryDownload
        )
        errorMessage = nil
    }

    func handleMissingDownloadedUpdateFile(_ state: DownloadedUpdateState) {
        updateStatus = .downloaded(
            DownloadedUpdateState(
                release: state.release,
                fileURL: state.fileURL,
                installState: .missingFile,
                origin: state.origin
            )
        )
        let diagnostic = recordDiagnostic(
            context: .update,
            message: "已下载的更新 DMG 不存在，请重新下载。",
            details: [
                SupportDiagnosticDetail(label: "Downloaded File", value: state.fileURL.path)
            ]
        )
        updateNotice = UpdateNotice(
            diagnostic: diagnostic,
            action: .retryDownload
        )
        errorMessage = nil
    }

    private func downloadedUpdateFileAvailability(for url: URL) -> DownloadedUpdateFileAvailability {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .missing
        }
        if isDirectory.boolValue {
            return .invalid("更新路径指向目录而不是 DMG 文件。")
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return .invalid("更新文件当前不可读。")
        }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileType = attributes[.type] as? FileAttributeType,
           fileType != .typeRegular {
            return .invalid("更新路径不是常规文件。")
        }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber,
           size.int64Value == 0 {
            return .invalid("更新文件为空。")
        }
        return .ready
    }

    private func restoredDownloadedUpdateState(for release: AppUpdateRelease) -> DownloadedUpdateState? {
        let destinationURL = backend.updateDestinationURL(for: release)
        guard case .ready = downloadedUpdateFileAvailability(for: destinationURL) else {
            return nil
        }
        return DownloadedUpdateState(
            release: release,
            fileURL: destinationURL,
            installState: .requiresManualOpen,
            origin: .restoredArtifact
        )
    }
}
