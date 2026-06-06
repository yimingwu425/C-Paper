import Foundation
import Observation

struct AppBootFailure {
    let message: String
    let diagnosticText: String

    init(error: Error) {
        message = "无法启动 C-Paper"
        diagnosticText = """
        \(error.localizedDescription)

        \(String(reflecting: error))
        """
    }
}

enum AppBootPhase {
    case loading
    case ready(AppModel)
    case failed(AppBootFailure)
}

@MainActor
@Observable
final class AppBootCoordinator {
    typealias ModelFactory = @MainActor () throws -> AppModel
    typealias BootAction = @MainActor (AppModel) async -> Void

    var phase: AppBootPhase = .loading

    @ObservationIgnored private let autoStart: Bool
    @ObservationIgnored private let makeModel: ModelFactory
    @ObservationIgnored private let bootstrapModel: BootAction
    @ObservationIgnored private let checkForStartupUpdates: BootAction
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var attemptID = 0

    init(
        autoStart: Bool = true,
        makeModel: @escaping ModelFactory = { try AppModel.live() },
        bootstrapModel: @escaping BootAction = { model in
            await model.bootstrap()
        },
        checkForStartupUpdates: @escaping BootAction = { model in
            await model.checkForUpdates(source: .startup)
        }
    ) {
        self.autoStart = autoStart
        self.makeModel = makeModel
        self.bootstrapModel = bootstrapModel
        self.checkForStartupUpdates = checkForStartupUpdates
    }

    func startIfNeeded() async {
        guard autoStart, !didStart else { return }
        await retry()
    }

    func retry() async {
        didStart = true
        attemptID += 1
        let currentAttemptID = attemptID
        phase = .loading

        do {
            let model = try makeModel()

            await bootstrapModel(model)
            guard attemptID == currentAttemptID else { return }

            await checkForStartupUpdates(model)
            guard attemptID == currentAttemptID else { return }

            phase = .ready(model)
        } catch {
            guard attemptID == currentAttemptID else { return }
            phase = .failed(AppBootFailure(error: error))
        }
    }
}
