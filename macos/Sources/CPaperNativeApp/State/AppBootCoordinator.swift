import Foundation
import Observation

struct AppBootFailure {
    let message: String
    let diagnosticText: String
    let supportDirectoryURL: URL?

    init(
        message: String,
        diagnosticText: String,
        supportDirectoryURL: URL?
    ) {
        self.message = message
        self.diagnosticText = diagnosticText
        self.supportDirectoryURL = supportDirectoryURL
    }

    init(error: Error) {
        message = "无法启动 C-Paper"
        let supportStore: SupportDiagnosticsStore?
        if let paths = try? AppStoragePaths() {
            supportStore = SupportDiagnosticsStore(paths: paths)
        } else {
            supportStore = nil
        }
        let diagnostic = SupportDiagnostic(
            context: .startup,
            message: error.localizedDescription,
            details: [
                SupportDiagnosticDetail(label: "Error", value: String(reflecting: error))
            ],
            supportDirectoryPath: supportStore?.directoryURL.path
        )
        supportDirectoryURL = supportStore?.directoryURL
        if let reportURL = try? supportStore?.write(diagnostic) {
            diagnosticText = diagnostic.withReportURL(reportURL).reportText
        } else {
            diagnosticText = diagnostic.reportText
        }
    }

    func revealSupportDirectory(
        fileManager: FileManager = .default,
        revealInFinder: (URL) -> Void
    ) throws {
        guard let supportDirectoryURL else { return }
        try fileManager.createDirectory(at: supportDirectoryURL, withIntermediateDirectories: true)
        revealInFinder(supportDirectoryURL)
    }

    func supportDirectoryRevealErrorMessage(for error: Error) -> String {
        guard let supportDirectoryURL else {
            return "无法显示支持文件夹。请复制诊断信息继续排查。"
        }
        let redactedPath = SupportDiagnostic.redact(supportDirectoryURL.path)
        return """
        无法显示支持文件夹。请复制诊断信息，并手动检查以下路径是否可用：
        \(redactedPath)

        原因：\(error.localizedDescription)
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
