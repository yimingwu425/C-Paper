import Foundation
import XCTest
@testable import CPaperNativeApp

extension XCTestCase {
    func makeDownloadPaperGroup(sy: String) -> NativePaperGroup {
        NativePaperGroup(
            sourceID: .frankcie,
            subjectCode: "9709",
            sy: sy,
            number: "12",
            paperGroup: 1,
            qp: makeDownloadComponent(filename: "9709_s23_qp_12.pdf", type: "QP", label: "Paper 1", sy: sy),
            ms: makeDownloadComponent(filename: "9709_s23_ms_12.pdf", type: "MS", label: "Mark Scheme 1", sy: sy),
            extras: []
        )
    }

    func makeDownloadComponent(
        filename: String,
        type: String,
        label: String? = "Paper",
        sy: String = "s23",
        url: URL? = nil
    ) -> PaperComponent {
        PaperComponent(
            sourceID: .frankcie,
            filename: filename,
            url: url ?? URL(string: "https://example.test/\(filename)")!,
            paperType: type,
            subjectCode: "9709",
            sy: sy,
            number: "12",
            label: label
        )
    }

    func makeDownloadOptions(
        rate: Double = 20,
        threads: Int = 2,
        merge: Bool = false,
        duplicateMode: DuplicateMode = .overwrite,
        includeMarkSchemes: Bool = true
    ) -> DownloadOptions {
        DownloadOptions(
            rate: rate,
            threads: threads,
            merge: merge,
            duplicateMode: duplicateMode,
            includeMarkSchemes: includeMarkSchemes
        )
    }

    func makeTemporaryDownloadDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperDownloadManagerTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    func waitForDownloadCompletion(_ manager: DownloadManager) async throws -> DownloadStatusSnapshot {
        for _ in 0..<200 {
            let snapshot = await manager.status()
            if !snapshot.isRunning {
                return snapshot
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Timed out waiting for download manager completion.")
        return await manager.status()
    }
}

actor AttemptCounter {
    private var count = 0

    var value: Int {
        count
    }

    func next() -> Int {
        count += 1
        return count
    }
}

actor CircuitBreakerAttemptRecorder {
    private var count = 0
    private var openedAt: Date?
    private var recoveredAt: Date?

    var value: Int {
        count
    }

    var recoveryDelay: TimeInterval? {
        guard let openedAt, let recoveredAt else { return nil }
        return recoveredAt.timeIntervalSince(openedAt)
    }

    func next() -> Int {
        count += 1
        if count == 5 {
            openedAt = Date()
        } else if count == 6 {
            recoveredAt = Date()
        }
        return count
    }
}

actor DownloadURLRecorder {
    private var recordedURL: URL?

    var value: URL? {
        recordedURL
    }

    func set(_ url: URL) {
        recordedURL = url
    }
}

actor ControlledDownloadCoordinator {
    private var startedFilenames: Set<String> = []
    private var startWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var allowWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var transferEvents: [(url: URL, proxyURL: String)] = []

    func markStarted(_ filename: String) {
        startedFilenames.insert(filename)
        let waiters = startWaiters.removeValue(forKey: filename) ?? []
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilStarted(_ filename: String) async {
        if startedFilenames.contains(filename) {
            return
        }

        await withCheckedContinuation { continuation in
            startWaiters[filename, default: []].append(continuation)
        }
    }

    func waitUntilAllowed(_ filename: String) async {
        await withCheckedContinuation { continuation in
            allowWaiters[filename] = continuation
        }
    }

    func allow(_ filename: String) {
        let waiter = allowWaiters.removeValue(forKey: filename)
        waiter?.resume()
    }

    func recordTransfer(url: URL, proxyURL: String) {
        transferEvents.append((url, proxyURL))
    }

    func transfers() -> [(url: URL, proxyURL: String)] {
        transferEvents
    }
}

actor NativeHistoryRecorder {
    private let store: DownloadHistoryStore

    init(paths: AppStoragePaths) {
        self.store = DownloadHistoryStore(paths: paths)
    }

    func record(_ task: DownloadDestinationTask) {
        try? store.record(
            filename: task.filename,
            label: task.label,
            year: task.year,
            savePath: task.saveURL.path
        )
    }
}
