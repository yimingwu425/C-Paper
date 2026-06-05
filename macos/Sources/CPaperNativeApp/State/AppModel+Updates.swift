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
            updateStatus = .failed(error.localizedDescription)
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
        updateStatus = .downloading(progress: nil)
        do {
            let downloadedURL = try await backend.downloadUpdate(release, proxyURL: settings.proxyURL) { [weak self] progress in
                await MainActor.run {
                    self?.updateStatus = .downloading(progress: progress)
                }
            }
            updateStatus = .downloaded(downloadedURL)
        } catch {
            updateStatus = .failed(error.localizedDescription)
        }
    }

    func openDownloadedUpdate() {
        guard let url = updateStatus.downloadedURL else { return }
        NSWorkspace.shared.open(url)
    }

    func revealDownloadedUpdate() {
        guard let url = updateStatus.downloadedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
