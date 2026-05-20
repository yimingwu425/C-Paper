import Foundation

struct BridgeRequest<Params: Encodable>: Encodable {
    let id: String
    let method: String
    let params: Params
}

struct EmptyParams: Encodable {}

struct BridgeResponse<Payload: Decodable>: Decodable {
    let id: String
    let ok: Bool
    let payload: Payload?
    let error: String?
}

enum PythonBridgeError: LocalizedError {
    case launchFailed
    case processUnavailable
    case encodingFailed
    case invalidResponse(String)
    case backend(String)
    case missingScript(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed:
            "Unable to launch Python bridge."
        case .processUnavailable:
            "Python bridge is not running."
        case .encodingFailed:
            "Unable to encode bridge request."
        case .invalidResponse(let message):
            "Invalid bridge response: \(message)"
        case .backend(let message):
            message
        case .missingScript(let path):
            "找不到 Python bridge 脚本：\(path)"
        }
    }
}

actor PythonBridge {
    private let pythonPath: String
    private let bridgeScript: URL
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errorOutput: FileHandle?
    private var buffer = Data()

    init(pythonPath: String = PythonBridge.defaultPythonPath(), bridgeScript: URL = PythonBridge.defaultBridgeScriptURL()) {
        self.pythonPath = pythonPath
        self.bridgeScript = bridgeScript
    }

    nonisolated static func defaultPythonPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let fileManager = FileManager.default
        var candidates: [String] = []

        if let explicit = environment["CPAPER_PYTHON"], !explicit.isEmpty {
            candidates.append(explicit)
        }

        let pathEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        candidates.append(contentsOf: pathEntries.map { URL(fileURLWithPath: $0).appendingPathComponent("python3").path })
        candidates.append(contentsOf: [
            "/opt/anaconda3/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ])

        for candidate in Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates {
            if fileManager.isExecutableFile(atPath: candidate), pythonSupportsBridge(candidate) {
                return candidate
            }
        }

        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) ?? "/usr/bin/python3"
    }

    nonisolated private static func pythonSupportsBridge(_ path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-c", "import requests"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    nonisolated static func defaultBridgeScriptURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        bundleURL: URL = Bundle.main.bundleURL,
        executableURL: URL? = Bundle.main.executableURL
    ) -> URL {
        let fileManager = FileManager.default

        if let explicitScript = environment["CPAPER_BRIDGE_SCRIPT"], !explicitScript.isEmpty {
            let url = URL(fileURLWithPath: explicitScript)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        var roots: [URL] = []
        if let explicitRoot = environment["CPAPER_ROOT"], !explicitRoot.isEmpty {
            roots.append(URL(fileURLWithPath: explicitRoot))
        }

        roots.append(contentsOf: [
            currentDirectory,
            currentDirectory.deletingLastPathComponent(),
            currentDirectory.deletingLastPathComponent().deletingLastPathComponent(),
            bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        ])

        if let executableURL {
            var candidate = executableURL
            for _ in 0..<5 {
                candidate.deleteLastPathComponent()
                roots.append(candidate)
            }
        }

        for root in roots {
            let candidates = [
                root.appendingPathComponent("native/bridge/cpaper_bridge.py"),
                root.appendingPathComponent("bridge/cpaper_bridge.py")
            ]
            if let existing = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
                return existing
            }
        }

        return currentDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("bridge/cpaper_bridge.py")
    }

    nonisolated var bridgeScriptPath: String {
        bridgeScript.path
    }

    nonisolated var pythonExecutablePath: String {
        pythonPath
    }

    func start() throws {
        if process?.isRunning == true {
            return
        }

        guard FileManager.default.fileExists(atPath: bridgeScript.path) else {
            throw PythonBridgeError.missingScript(bridgeScript.path)
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [bridgeScript.path]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw PythonBridgeError.launchFailed
        }

        self.process = process
        self.input = stdinPipe.fileHandleForWriting
        self.output = stdoutPipe.fileHandleForReading
        self.errorOutput = stderrPipe.fileHandleForReading
        self.buffer = Data()
    }

    func stop() {
        process?.terminate()
        process = nil
        input = nil
        output = nil
        errorOutput = nil
        buffer = Data()
    }

    nonisolated func makeRequestLine<Params: Encodable>(id: String, method: String, params: Params) throws -> Data {
        let request = BridgeRequest(id: id, method: method, params: params)
        let encoder = JSONEncoder()

        do {
            var data = try encoder.encode(request)
            data.append(0x0A)
            return data
        } catch {
            throw PythonBridgeError.encodingFailed
        }
    }

    func send<Params: Encodable, Payload: Decodable>(
        method: String,
        params: Params,
        payloadType: Payload.Type
    ) async throws -> Payload {
        try start()
        guard let input, let output else {
            throw PythonBridgeError.processUnavailable
        }

        let requestID = UUID().uuidString
        let line = try makeRequestLine(id: requestID, method: method, params: params)
        try input.write(contentsOf: line)

        let responseLine = try readResponseLine(from: output)
        let decoder = JSONDecoder()
        let response = try decoder.decode(BridgeResponse<Payload>.self, from: responseLine)
        if response.ok, let payload = response.payload {
            return payload
        }
        throw PythonBridgeError.backend(response.error ?? "Unknown backend error")
    }

    private func readResponseLine(from handle: FileHandle) throws -> Data {
        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newlineIndex)
                buffer.removeSubrange(...newlineIndex)
                return Data(line)
            }

            let chunk = handle.availableData
            if chunk.isEmpty {
                let stderrData = errorOutput?.availableData ?? Data()
                let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
                if !stderrText.isEmpty {
                    throw PythonBridgeError.invalidResponse(
                        stderrText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    )
                }
                throw PythonBridgeError.invalidResponse("bridge closed unexpectedly")
            }
            buffer.append(chunk)
        }
    }
}
