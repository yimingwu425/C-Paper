import Foundation

enum CircuitBreakerState: String {
    case closed
    case open
    case halfOpen = "half-open"
}

enum CircuitBreakerError: LocalizedError, Equatable {
    case open

    var errorDescription: String? {
        switch self {
        case .open:
            "Circuit breaker is open."
        }
    }
}

actor CircuitBreaker {
    private let failureThreshold: Int
    private let recoveryTimeout: Duration
    private let clock = ContinuousClock()
    private var failures = 0
    private var openedAt: ContinuousClock.Instant?
    private(set) var state: CircuitBreakerState = .closed

    init(failureThreshold: Int = 5, recoveryTimeout: Duration = .seconds(30)) {
        self.failureThreshold = failureThreshold
        self.recoveryTimeout = recoveryTimeout
    }

    func retryDelayBeforeNextRequest() -> Duration? {
        guard state == .open else { return nil }
        guard let openedAt else { return recoveryTimeout }

        let elapsed = openedAt.duration(to: clock.now)
        guard elapsed < recoveryTimeout else { return nil }
        return recoveryTimeout - elapsed
    }

    func allowRequest() throws {
        guard state == .open else { return }
        guard let openedAt else {
            throw CircuitBreakerError.open
        }

        if openedAt.duration(to: clock.now) >= recoveryTimeout {
            state = .halfOpen
            return
        }

        throw CircuitBreakerError.open
    }

    func recordSuccess() {
        failures = 0
        openedAt = nil
        state = .closed
    }

    func recordFailure() {
        switch state {
        case .halfOpen:
            open()
        case .closed:
            failures += 1
            if failures >= failureThreshold {
                open()
            }
        case .open:
            break
        }
    }

    private func open() {
        state = .open
        openedAt = clock.now
    }
}
