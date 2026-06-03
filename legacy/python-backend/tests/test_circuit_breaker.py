import time
import pytest
from backend import CircuitBreaker


class TestCircuitBreaker:
    def test_starts_closed(self):
        cb = CircuitBreaker(failure_threshold=3, recovery_timeout=1.0)
        assert cb.state == CircuitBreaker.CLOSED

    def test_opens_after_threshold(self):
        cb = CircuitBreaker(failure_threshold=3, recovery_timeout=10.0)
        for _ in range(3):
            cb.record_failure()
        assert cb.state == CircuitBreaker.OPEN

    def test_does_not_open_before_threshold(self):
        cb = CircuitBreaker(failure_threshold=5, recovery_timeout=10.0)
        for _ in range(4):
            cb.record_failure()
        assert cb.state != CircuitBreaker.OPEN

    def test_half_open_after_timeout(self):
        cb = CircuitBreaker(failure_threshold=2, recovery_timeout=0.3)
        cb.record_failure()
        cb.record_failure()
        assert cb.state == CircuitBreaker.OPEN
        time.sleep(0.4)
        assert cb.state == CircuitBreaker.HALF_OPEN

    def test_success_resets_to_closed(self):
        cb = CircuitBreaker(failure_threshold=2, recovery_timeout=10.0)
        cb.record_failure()
        cb.record_failure()
        assert cb.state == CircuitBreaker.OPEN
        cb.record_success()  # manual success in HALF_OPEN
        assert cb.state == CircuitBreaker.CLOSED
