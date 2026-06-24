import XCTest
@testable import CPaperNativeApp

final class WorkflowPresentationTests: XCTestCase {
    func testDownloadsWorkflowPresentationShowsCancelActionWhileQueueIsRunning() {
        let presentation = DownloadsWorkflowPresentation(
            snapshot: DownloadStatusSnapshot(
                phase: .running,
                done: 1,
                total: 3,
                success: 1,
                message: "下载中...",
                failed: 0,
                cancelled: 0,
                skipped: 0
            ),
            failedDownloadCount: 0,
            hasRetryableFailedDownloads: false,
            hasSaveDirectoryNotice: false,
            hasRecoveryNotice: false,
            hasRecoverySummary: false,
            hasIntegrityNotice: false,
            downloadCount: 2
        )

        XCTAssertEqual(presentation.headerAction, .cancelRunning)
        XCTAssertEqual(presentation.queueBadge, .running)
        XCTAssertFalse(presentation.showsCopyDiagnosticButton)
        XCTAssertFalse(presentation.showsEmptyState)
    }

    func testDownloadsWorkflowPresentationShowsRetryActionAndAttentionForRetryableFailures() {
        let presentation = DownloadsWorkflowPresentation(
            snapshot: DownloadStatusSnapshot(
                phase: .done,
                done: 2,
                total: 2,
                success: 1,
                message: "完成",
                failed: 1,
                cancelled: 0,
                skipped: 0
            ),
            failedDownloadCount: 1,
            hasRetryableFailedDownloads: true,
            hasSaveDirectoryNotice: true,
            hasRecoveryNotice: false,
            hasRecoverySummary: true,
            hasIntegrityNotice: true,
            downloadCount: 2
        )

        XCTAssertEqual(presentation.headerAction, .retryFailed)
        XCTAssertEqual(presentation.queueBadge, .attention)
        XCTAssertTrue(presentation.showsCopyDiagnosticButton)
        XCTAssertTrue(presentation.showsSaveDirectoryNotice)
        XCTAssertTrue(presentation.showsRecoverySummary)
        XCTAssertTrue(presentation.showsIntegrityNotice)
    }

    func testDownloadsWorkflowPresentationShowsEmptyStateWithoutActionsForIdleEmptyQueue() {
        let presentation = DownloadsWorkflowPresentation(
            snapshot: DownloadStatusSnapshot(
                phase: .idle,
                done: 0,
                total: 0,
                success: 0,
                message: "Ready",
                failed: nil,
                cancelled: nil,
                skipped: nil
            ),
            failedDownloadCount: 0,
            hasRetryableFailedDownloads: false,
            hasSaveDirectoryNotice: false,
            hasRecoveryNotice: false,
            hasRecoverySummary: false,
            hasIntegrityNotice: false,
            downloadCount: 0
        )

        XCTAssertEqual(presentation.headerAction, .none)
        XCTAssertEqual(presentation.queueBadge, .none)
        XCTAssertFalse(presentation.showsCopyDiagnosticButton)
        XCTAssertTrue(presentation.showsEmptyState)
    }

    func testSearchWorkflowPresentationShowsSourceSummaryOnlyWhenResultsAndSourceArePresent() {
        let hidden = SearchWorkflowPresentation(
            resultCount: 0,
            sourceSummary: "来自 FrankCIE",
            sourceID: .frankcie,
            sourceNotice: nil,
            downloadNotice: nil
        )
        let visible = SearchWorkflowPresentation(
            resultCount: 2,
            sourceSummary: "来自 FrankCIE",
            sourceID: .frankcie,
            sourceNotice: nil,
            downloadNotice: nil
        )

        XCTAssertFalse(hidden.showsSourceSummary)
        XCTAssertTrue(visible.showsSourceSummary)
    }

    func testSearchWorkflowPresentationKeepsDownloadNoticeScopedToSearchRoute() {
        let searchNotice = DownloadNotice(
            diagnostic: SupportDiagnostic(context: .download, message: "搜索下载失败"),
            action: .retrySearchDownload
        )
        let batchNotice = DownloadNotice(
            diagnostic: SupportDiagnostic(context: .download, message: "批量下载失败"),
            action: .retryBatchDownload
        )

        XCTAssertTrue(
            SearchWorkflowPresentation(
                resultCount: 1,
                sourceSummary: nil,
                sourceID: nil,
                sourceNotice: nil,
                downloadNotice: searchNotice
            ).showsDownloadNotice
        )
        XCTAssertFalse(
            SearchWorkflowPresentation(
                resultCount: 1,
                sourceSummary: nil,
                sourceID: nil,
                sourceNotice: nil,
                downloadNotice: batchNotice
            ).showsDownloadNotice
        )
    }

    func testBatchWorkflowPresentationKeepsDownloadNoticeScopedToBatchRoute() {
        let batchNotice = DownloadNotice(
            diagnostic: SupportDiagnostic(context: .download, message: "批量下载失败"),
            action: .retryBatchDownload
        )
        let searchNotice = DownloadNotice(
            diagnostic: SupportDiagnostic(context: .download, message: "搜索下载失败"),
            action: .retrySearchDownload
        )

        XCTAssertTrue(
            BatchPreviewWorkflowPresentation(
                previewCount: 1,
                sourceSummary: "来自多个来源",
                sourceNotice: nil,
                downloadNotice: batchNotice
            ).showsDownloadNotice
        )
        XCTAssertFalse(
            BatchPreviewWorkflowPresentation(
                previewCount: 1,
                sourceSummary: "来自多个来源",
                sourceNotice: nil,
                downloadNotice: searchNotice
            ).showsDownloadNotice
        )
    }

    func testUpdateWorkflowPresentationPrefersOpeningDownloadedFileWhenArtifactIsAccessible() {
        let release = AppUpdateRelease(
            version: "6.0.6",
            tagName: "v6.0.6",
            name: "C-Paper 6.0.6",
            htmlURL: URL(string: "https://example.com/release")!,
            assetName: "C-Paper-Native-6.0.6.dmg",
            downloadURL: URL(string: "https://example.com/dmg")!
        )
        let status = UpdateStatus.downloaded(
            DownloadedUpdateState(
                release: release,
                fileURL: URL(fileURLWithPath: "/tmp/C-Paper.dmg"),
                installState: .downloaded,
                origin: .currentSession
            )
        )

        let presentation = UpdateWorkflowPresentation(status: status)

        XCTAssertTrue(presentation.canAccessDownloadedFile)
        XCTAssertTrue(presentation.prefersOpeningDownloadedFile)
        XCTAssertEqual(presentation.revealActionTitle, "显示文件")
        XCTAssertEqual(presentation.primaryInstallActionTitle, "打开已下载更新")
    }

    func testUpdateWorkflowPresentationFallsBackToDownloadAndSupportFolderWhenArtifactIsUnavailable() {
        let release = AppUpdateRelease(
            version: "6.0.6",
            tagName: "v6.0.6",
            name: "C-Paper 6.0.6",
            htmlURL: URL(string: "https://example.com/release")!,
            assetName: "C-Paper-Native-6.0.6.dmg",
            downloadURL: URL(string: "https://example.com/dmg")!
        )
        let status = UpdateStatus.downloaded(
            DownloadedUpdateState(
                release: release,
                fileURL: URL(fileURLWithPath: "/tmp/C-Paper.dmg"),
                installState: .missingFile,
                origin: .restoredArtifact
            )
        )

        let presentation = UpdateWorkflowPresentation(status: status)

        XCTAssertFalse(presentation.canAccessDownloadedFile)
        XCTAssertFalse(presentation.prefersOpeningDownloadedFile)
        XCTAssertEqual(presentation.revealActionTitle, "显示支持文件夹")
        XCTAssertEqual(presentation.primaryInstallActionTitle, "下载更新")
    }

    func testRootWorkflowPresentationPrefersOpeningDownloadedArtifactInPendingUpdatePrompt() {
        let release = sampleRelease()
        let presentation = RootWorkflowPresentation(
            route: .search,
            isLoading: false,
            updateNotice: nil,
            supportDirectoryNotice: nil,
            pendingUpdatePrompt: release,
            errorMessage: nil,
            lastDiagnostic: nil,
            updateStatus: .downloaded(
                DownloadedUpdateState(
                    release: release,
                    fileURL: URL(fileURLWithPath: "/tmp/C-Paper.dmg"),
                    installState: .downloaded,
                    origin: .restoredArtifact
                )
            ),
            currentVersion: "6.0.5"
        )

        XCTAssertTrue(presentation.showsPendingUpdatePrompt)
        XCTAssertEqual(presentation.pendingUpdatePromptPrimaryActionTitle, "打开已下载更新")
        XCTAssertEqual(presentation.refreshAction, .search)
        XCTAssertEqual(presentation.updateNoticeTopPadding, 24)
        XCTAssertTrue(presentation.pendingUpdatePromptMessage?.contains("可直接打开安装") == true)
    }

    func testRootWorkflowPresentationTracksNoticeStackingAndDiagnosticAlertActions() {
        let supportDiagnostic = SupportDiagnostic(context: .update, message: "支持目录失败")
        let presentation = RootWorkflowPresentation(
            route: .downloads,
            isLoading: true,
            updateNotice: UpdateNotice(diagnostic: SupportDiagnostic(context: .update, message: "更新失败"), action: .retryDownload),
            supportDirectoryNotice: SupportDirectoryNotice(diagnostic: supportDiagnostic),
            pendingUpdatePrompt: nil,
            errorMessage: "更新失败",
            lastDiagnostic: supportDiagnostic,
            updateStatus: .failed(UpdateFailureState(phase: .download, message: "更新失败")),
            currentVersion: "6.0.5"
        )

        XCTAssertTrue(presentation.showsUpdateNotice)
        XCTAssertTrue(presentation.showsSupportDirectoryNotice)
        XCTAssertEqual(presentation.updateNoticeTopPadding, 12)
        XCTAssertEqual(presentation.refreshAction, .refreshDownloads)
        XCTAssertTrue(presentation.disablesRefreshButton)
        XCTAssertTrue(presentation.showsErrorAlert)
        XCTAssertTrue(presentation.showsErrorAlertDiagnosticActions)
    }

    func testRootWorkflowPresentationMapsBatchRouteToBatchRefreshAction() {
        let presentation = RootWorkflowPresentation(
            route: .batch,
            isLoading: false,
            updateNotice: nil,
            supportDirectoryNotice: nil,
            pendingUpdatePrompt: nil,
            errorMessage: nil,
            lastDiagnostic: nil,
            updateStatus: .idle,
            currentVersion: "6.0.5"
        )

        XCTAssertEqual(presentation.refreshAction, .batchPreview)
        XCTAssertFalse(presentation.disablesRefreshButton)
        XCTAssertFalse(presentation.showsErrorAlert)
        XCTAssertFalse(presentation.showsErrorAlertDiagnosticActions)
    }

    func testUpdateSettingsWorkflowPresentationShowsDownloadAndLocalArtifactActionsForAccessibleDMG() {
        let release = sampleRelease()
        let presentation = UpdateSettingsWorkflowPresentation(
            status: .downloaded(
                DownloadedUpdateState(
                    release: release,
                    fileURL: URL(fileURLWithPath: "/tmp/C-Paper.dmg"),
                    installState: .downloaded,
                    origin: .currentSession
                )
            ),
            updateNotice: UpdateNotice(
                diagnostic: SupportDiagnostic(context: .update, message: "已下载"),
                action: .openDownloadedDMG
            ),
            downloadedSummary: "当前更新包已在本次会话下载完成。"
        )

        XCTAssertTrue(presentation.showsUpdateNotice)
        XCTAssertTrue(presentation.showsDownloadedSummary)
        XCTAssertTrue(presentation.showsDestinationPath)
        XCTAssertEqual(presentation.checkButtonTitle, "检查更新")
        XCTAssertFalse(presentation.disablesCheckButton)
        XCTAssertTrue(presentation.showsDownloadButton)
        XCTAssertFalse(presentation.disablesDownloadButton)
        XCTAssertTrue(presentation.showsOpenDownloadedButton)
        XCTAssertTrue(presentation.showsRevealDownloadedButton)
    }

    func testUpdateSettingsWorkflowPresentationDisablesActionsWhileDownloadIsInFlight() {
        let release = sampleRelease()
        let presentation = UpdateSettingsWorkflowPresentation(
            status: .downloading(
                UpdateDownloadState(
                    release: release,
                    progress: 0.4,
                    destinationURL: URL(fileURLWithPath: "/tmp/C-Paper.dmg")
                )
            ),
            updateNotice: nil,
            downloadedSummary: nil
        )

        XCTAssertFalse(presentation.showsUpdateNotice)
        XCTAssertFalse(presentation.showsDownloadedSummary)
        XCTAssertTrue(presentation.showsDestinationPath)
        XCTAssertEqual(presentation.checkButtonTitle, "检查更新")
        XCTAssertTrue(presentation.disablesCheckButton)
        XCTAssertTrue(presentation.showsDownloadButton)
        XCTAssertTrue(presentation.disablesDownloadButton)
        XCTAssertFalse(presentation.showsOpenDownloadedButton)
        XCTAssertFalse(presentation.showsRevealDownloadedButton)
    }

    func testSettingsWorkflowPresentationTracksNoticesAndLatestDiagnosticAvailability() {
        let diagnostic = SupportDiagnostic(context: .settings, message: "保存设置失败")
        let presentation = SettingsWorkflowPresentation(
            supportDirectoryNotice: SupportDirectoryNotice(diagnostic: diagnostic),
            settingsNotice: SettingsNotice(diagnostic: diagnostic),
            lastDiagnostic: diagnostic
        )

        XCTAssertTrue(presentation.showsSupportDirectoryNotice)
        XCTAssertTrue(presentation.showsSettingsNotice)
        XCTAssertTrue(presentation.canCopyLatestDiagnostic)
    }
}

private func sampleRelease() -> AppUpdateRelease {
    AppUpdateRelease(
        version: "6.0.6",
        tagName: "v6.0.6",
        name: "C-Paper 6.0.6",
        htmlURL: URL(string: "https://example.com/release")!,
        assetName: "C-Paper-Native-6.0.6.dmg",
        downloadURL: URL(string: "https://example.com/dmg")!
    )
}
