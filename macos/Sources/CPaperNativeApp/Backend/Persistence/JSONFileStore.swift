import Foundation

struct JSONFileStore<Value: Codable> {
    let url: URL
    let defaultValue: Value
    var fileManager: FileManager = .default
    var now: () -> Date = Date.init

    init(
        url: URL,
        defaultValue: Value,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.url = url
        self.defaultValue = defaultValue
        self.fileManager = fileManager
        self.now = now
    }

    func read() -> Value {
        guard fileManager.fileExists(atPath: url.path) else {
            return defaultValue
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(Value.self, from: data)
        } catch {
            backupCorruptFile()
            return defaultValue
        }
    }

    func write(_ value: Value) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        JSONDecoder()
    }

    private func backupCorruptFile() {
        let backupURL = corruptBackupURL()
        do {
            try fileManager.moveItem(at: url, to: backupURL)
        } catch {
            try? fileManager.removeItem(at: url)
        }
    }

    private func corruptBackupURL() -> URL {
        let timestamp = Int(now().timeIntervalSince1970)
        var candidate = URL(fileURLWithPath: "\(url.path).corrupt.\(timestamp)")
        var suffix = 1

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = URL(fileURLWithPath: "\(url.path).corrupt.\(timestamp).\(suffix)")
            suffix += 1
        }

        return candidate
    }
}
