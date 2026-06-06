import XCTest
@testable import CPaperNativeApp

@MainActor
final class StartupBootCoordinatorTests: XCTestCase {
    func testRetryRecoversAfterInitializationFailure() async throws {
        let expectedModel = try makeModel()
        var attempts = 0
        let coordinator = AppBootCoordinator(
            autoStart: false,
            makeModel: {
                attempts += 1
                if attempts == 1 {
                    throw BootFactoryError.sample
                }
                return expectedModel
            },
            bootstrapModel: { _ in },
            checkForStartupUpdates: { _ in }
        )

        await coordinator.retry()

        guard case let .failed(failure) = coordinator.phase else {
            return XCTFail("Expected failed phase after initialization error")
        }
        XCTAssertEqual(failure.message, "无法启动 C-Paper")
        XCTAssertTrue(failure.diagnosticText.contains(BootFactoryError.sample.localizedDescription))

        await coordinator.retry()

        guard case let .ready(model) = coordinator.phase else {
            return XCTFail("Expected ready phase after retry succeeds")
        }
        XCTAssertTrue(model === expectedModel)
        XCTAssertEqual(attempts, 2)
    }

    func testRetryPublishesOnlyLatestSuccessfulModelAndSkipsStaleStartupUpdateCheck() async throws {
        let firstModel = try makeModel()
        let secondModel = try makeModel()
        let gate = BootAttemptGate()
        let counter = BootUpdateCounter()
        var attempts = 0
        let coordinator = AppBootCoordinator(
            autoStart: false,
            makeModel: {
                attempts += 1
                return attempts == 1 ? firstModel : secondModel
            },
            bootstrapModel: { model in
                if model === firstModel {
                    await gate.markFirstBootStarted()
                    await gate.waitForFirstBootRelease()
                } else {
                    await gate.markSecondBootStarted()
                }
            },
            checkForStartupUpdates: { _ in
                await counter.increment()
            }
        )

        async let firstAttempt: Void = coordinator.retry()
        await gate.waitForFirstBootStart()

        async let secondAttempt: Void = coordinator.retry()
        await gate.waitForSecondBootStart()
        await gate.releaseFirstBoot()

        _ = await (firstAttempt, secondAttempt)

        let updateCalls = await counter.value()
        XCTAssertEqual(updateCalls, 1)
        XCTAssertEqual(attempts, 2)

        guard case let .ready(model) = coordinator.phase else {
            return XCTFail("Expected ready phase after latest attempt succeeds")
        }
        XCTAssertTrue(model === secondModel)
    }

    private func makeModel() throws -> AppModel {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPaperStartupBootTests-\(UUID().uuidString)", isDirectory: true)
        let backend = try NativeBackendService(paths: AppStoragePaths(rootURL: rootURL))
        return AppModel(backend: backend)
    }
}

private enum BootFactoryError: LocalizedError {
    case sample

    var errorDescription: String? {
        switch self {
        case .sample:
            return "无法创建启动后端"
        }
    }
}

private actor BootAttemptGate {
    private var firstBootStarted = false
    private var secondBootStarted = false
    private var firstBootContinuation: CheckedContinuation<Void, Never>?
    private var firstStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var secondStartWaiters: [CheckedContinuation<Void, Never>] = []

    func markFirstBootStarted() {
        firstBootStarted = true
        firstStartWaiters.forEach { $0.resume() }
        firstStartWaiters.removeAll()
    }

    func waitForFirstBootStart() async {
        guard !firstBootStarted else { return }
        await withCheckedContinuation { continuation in
            firstStartWaiters.append(continuation)
        }
    }

    func waitForFirstBootRelease() async {
        await withCheckedContinuation { continuation in
            firstBootContinuation = continuation
        }
    }

    func releaseFirstBoot() {
        firstBootContinuation?.resume()
        firstBootContinuation = nil
    }

    func markSecondBootStarted() {
        secondBootStarted = true
        secondStartWaiters.forEach { $0.resume() }
        secondStartWaiters.removeAll()
    }

    func waitForSecondBootStart() async {
        guard !secondBootStarted else { return }
        await withCheckedContinuation { continuation in
            secondStartWaiters.append(continuation)
        }
    }
}

private actor BootUpdateCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}
