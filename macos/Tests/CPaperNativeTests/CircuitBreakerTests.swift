import XCTest
@testable import CPaperNativeApp

final class CircuitBreakerTests: XCTestCase {
    func testOpenCircuitBreakerUsesLocalizedDescription() {
        XCTAssertEqual(CircuitBreakerError.open.localizedDescription, "熔断器已打开。")
    }
}
