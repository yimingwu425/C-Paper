import AppKit
import Foundation

extension AppModel {
    func checkForUpdates(source: UpdateCheckSource) async {
        if source == .startup {
            guard !didRunStartupUpdateCheck else { return }
            didRunStartupUpdateCheck = true
        }

        updateStatus = .checking
        do {
            let result = try await backend.checkForUpdate(proxyURL: settings.proxyURL)
            switch result {
            case let .upToDate(current, latest):
                updateStatus = .upToDate(current: current, latest: latest)
            case let .available(release):
                updateStatus = .available(release)
                if source == .startup {
                    pendingUpdatePrompt = release
                }
            }
        } catch {
            let diagnostic = recordDiagnostic(context: .update, message: error.localizedDescription)
            updateStatus = .failed(diagnostic.message)
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
        errorMessage = nil
        updateStatus = .downloading(progress: nil, destinationURL: destinationURL)
        do {
            let downloadedURL = try await backend.downloadUpdate(release, proxyURL: settings.proxyURL) { [weak self] progress in
                await MainActor.run {
                    self?.updateStatus = .downloading(progress: progress, destinationURL: destinationURL)
                }
            }
            updateStatus = .downloaded(downloadedURL)
            if openDownloadedUpdateFile() {
                errorMessage = nil
            } else {
                errorMessage = "更新 DMG 已下载，但自动打开失败，请在设置中手动打开。"
            }
        } catch {
            let diagnostic = recordDiagnostic(context: .update, message: error.localizedDescription)
            updateStatus = .failed(diagnostic.message)
        }
    }

    @discardableResult
    func openDownloadedUpdate() -> Bool {
        openDownloadedUpdateFile()
    }

    func revealDownloadedUpdate() {
        guard let url = updateStatus.downloadedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
