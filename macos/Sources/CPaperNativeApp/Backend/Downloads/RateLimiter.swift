import Foundation

actor RateLimiter {
    private let clock = ContinuousClock()
    private var interval: Duration
    private var nextAvailable: ContinuousClock.Instant

    init(rate: Double) {
        let clamped = max(rate, 0.01)
        self.interval = .nanoseconds(Int64(1_000_000_000 / clamped))
        self.nextAvailable = clock.now
    }

    func acquire() async throws {
        let now = clock.now
        let scheduled = max(now, nextAvailable)
        nextAvailable = scheduled.advanced(by: interval)

        if scheduled > now {
            try await clock.sleep(until: scheduled)
        }
    }

    func updateRate(_ rate: Double) {
        let clamped = max(rate, 0.01)
        interval = .nanoseconds(Int64(1_000_000_000 / clamped))
        nextAvailable = clock.now
    }
}
