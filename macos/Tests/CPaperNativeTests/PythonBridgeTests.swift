import XCTest
@testable import CPaperNativeApp

final class PythonBridgeTests: XCTestCase {
    func testRequestLineEndsWithNewline() throws {
        let bridge = PythonBridge()
        let data = try bridge.makeRequestLine(id: "abc", method: "get_subjects", params: EmptyParams())
        XCTAssertEqual(data.last, 10)
    }

    func testRequestLineContainsMethodAndID() throws {
        let bridge = PythonBridge()
        let data = try bridge.makeRequestLine(id: "abc", method: "get_subjects", params: EmptyParams())
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"method\":\"get_subjects\""))
        XCTAssertTrue(text.contains("\"id\":\"abc\""))
    }

    func testDefaultBridgeScriptResolvesFromPackageDirectory() {
        let packageDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let script = PythonBridge.defaultBridgeScriptURL(
            environment: [:],
            currentDirectory: packageDirectory,
            bundleURL: packageDirectory.appendingPathComponent(".build/test-host.app"),
            executableURL: nil
        )

        XCTAssertTrue(script.path.hasSuffix("bridge/cpaper_bridge.py"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path))
    }

    func testDefaultBridgeExecutableUsesExplicitEnvironmentPath() {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let executable = temporaryDirectory.appendingPathComponent("CPaperBridge")
        try? FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: executable.path, contents: Data("#!/bin/sh\n".utf8))
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let resolved = PythonBridge.defaultBridgeExecutableURL(
            environment: ["CPAPER_BRIDGE_EXECUTABLE": executable.path]
        )

        XCTAssertEqual(resolved?.path, executable.path)
    }
}
