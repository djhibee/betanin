# standard library
import time
from collections import defaultdict
from collections import deque


class FailureLimiter:
    "in-memory limiter: too many failures within `window` seconds blocks a key"

    def __init__(self, max_failures=5, window=300):
        self.max_failures = max_failures
        self.window = window
        self._failures = defaultdict(deque)

    def _prune(self, key, now):
        failures = self._failures[key]
        while failures and now - failures[0] > self.window:
            failures.popleft()
        if not failures:
            del self._failures[key]
        return failures

    def retry_after(self, key):
        "seconds until `key` may try again, or 0 if it is not blocked"
        now = time.monotonic()
        failures = self._prune(key, now)
        if len(failures) < self.max_failures:
            return 0
        return max(1, int(failures[0] + self.window - now) + 1)

    def add_failure(self, key):
        self._failures[key].append(time.monotonic())

    def reset(self, key):
        self._failures.pop(key, None)


LOGIN = FailureLimiter()
