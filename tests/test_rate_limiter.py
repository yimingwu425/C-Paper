import time
import pytest
from backend import TokenBucket


class TestTokenBucket:
    def test_initial_full(self):
        tb = TokenBucket(rate=10, capacity=5)
        t0 = time.monotonic()
        # Acquire 5 tokens immediately (bucket starts full)
        for _ in range(5):
            tb.acquire()
        elapsed = time.monotonic() - t0
        assert elapsed < 0.1, f"Expected near-immediate acquire, got {elapsed:.2f}s"

    def test_rate_limited(self):
        tb = TokenBucket(rate=10, capacity=5)
        t0 = time.monotonic()
        for _ in range(10):
            tb.acquire()
        elapsed = time.monotonic() - t0
        # 5 from capacity, 5 need waiting at rate=10/s → ~0.5s
        assert 0.3 < elapsed < 1.0, f"Expected ~0.5s, got {elapsed:.2f}s"

    def test_drain(self):
        tb = TokenBucket(rate=1, capacity=5)
        tb.drain()
        t0 = time.monotonic()
        tb.acquire()
        elapsed = time.monotonic() - t0
        assert 0.8 < elapsed < 1.5, f"Expected ~1.0s, got {elapsed:.2f}s"

    def test_drain_resets(self):
        tb = TokenBucket(rate=100, capacity=10)
        tb.drain()
        t0 = time.monotonic()
        tb.acquire()
        elapsed = time.monotonic() - t0
        # Rate=100/s means ~0.01s wait
        assert elapsed < 0.1, f"Expected near-immediate, got {elapsed:.2f}s"
