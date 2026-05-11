"""TokenBucket rate limiter and CircuitBreaker fault isolation"""
import time, threading


class TokenBucket:
    def __init__(self, rate: float, capacity: int):
        self._rate = rate
        self._capacity = float(capacity)
        self._tokens = float(capacity)
        self._last_refill = time.monotonic()
        self._lock = threading.Lock()

    def acquire(self, tokens: float = 1.0) -> float:
        waited = 0.0
        while True:
            with self._lock:
                now = time.monotonic()
                elapsed = now - self._last_refill
                self._tokens = min(self._capacity, self._tokens + elapsed * self._rate)
                self._last_refill = now
                if self._tokens >= tokens:
                    self._tokens -= tokens
                    return waited
                wait = (tokens - self._tokens) / self._rate
            time.sleep(wait)
            waited += wait

    def drain(self):
        with self._lock:
            self._tokens = 0.0
            self._last_refill = time.monotonic()

    def update_rate(self, rate: float):
        with self._lock:
            self._rate = rate


class CircuitBreaker:
    CLOSED, OPEN, HALF_OPEN = "CLOSED", "OPEN", "HALF_OPEN"

    def __init__(self, failure_threshold: int = 5, recovery_timeout: float = 30.0):
        self._threshold = failure_threshold
        self._recovery = recovery_timeout
        self._failures = 0
        self._state = self.CLOSED
        self._last_failure = 0.0
        self._lock = threading.Lock()

    @property
    def state(self):
        with self._lock:
            if self._state == self.OPEN:
                if time.monotonic() - self._last_failure >= self._recovery:
                    self._state = self.HALF_OPEN
            return self._state

    def record_success(self):
        with self._lock:
            self._state = self.CLOSED
            self._failures = 0

    def record_failure(self):
        with self._lock:
            self._failures += 1
            self._last_failure = time.monotonic()
            if self._state == self.HALF_OPEN or self._failures >= self._threshold:
                self._state = self.OPEN
