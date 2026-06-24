import Foundation

final class StagedFileSystem: @unchecked Sendable {
    typealias BeforeFinalizeHook = @Sendable () async -> Void
    typealias StagedWrite = @Sendable (_ partialURL: URL) async throws -> Void

    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: createIntermediates)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func replaceItemAt(_ originalItemURL: URL, withItemAt newItemURL: URL) throws -> URL? {
        try fileManager.replaceItemAt(originalItemURL, withItemAt: newItemURL)
    }

    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try fileManager.moveItem(at: srcURL, to: dstURL)
    }

    func stagedWrite(
        to destinationURL: URL,
        beforeFinalize: BeforeFinalizeHook? = nil,
        write: StagedWrite
    ) async throws {
        try createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let partialURL = stagingURL(for: destinationURL)
        try? removeItem(at: partialURL)
        defer {
            try? removeItem(at: partialURL)
        }

        try await write(partialURL)
        try Task.checkCancellation()
        await beforeFinalize?()
        try Task.checkCancellation()

        if fileExists(atPath: destinationURL.path) {
            _ = try replaceItemAt(destinationURL, withItemAt: partialURL)
        } else {
            do {
                try moveItem(at: partialURL, to: destinationURL)
            } catch {
                guard fileExists(atPath: destinationURL.path) else {
                    throw error
                }
                _ = try replaceItemAt(destinationURL, withItemAt: partialURL)
            }
        }
    }

    func stagingURL(for destinationURL: URL) -> URL {
        destinationURL.deletingLastPathComponent()
            .appendingPathComponent("\(destinationURL.lastPathComponent).part.\(UUID().uuidString)")
    }
}
