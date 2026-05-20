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

        XCTAssertTrue(script.path.hasSuffix("native/bridge/cpaper_bridge.py"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path))
    }
}
