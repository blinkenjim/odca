"""Background multicore search for maybe-Class-IV rules.

Worker processes (not threads: the GIL would serialize threads on this
CPU-bound work) each generate and screen their own random rules, pushing the
IDs of rules that pass the maybe-Class-IV screen into a bounded queue. When
the queue is full — meaning the viewer's stash is topped up — workers block
on the put and stop consuming CPU until a candidate is taken.
"""

import multiprocessing as mp
import os
import queue as queue_mod

import numpy as np

from .automaton import Rule
from .classify import evaluate


def _worker(q, stop):
    rng = np.random.default_rng()  # per-process OS entropy; workers differ
    while not stop.is_set():
        rule = Rule.random(rng)
        if evaluate(rule, rng=rng)["maybe_iv"]:
            while not stop.is_set():
                try:
                    q.put(rule.id, timeout=0.25)
                    break
                except queue_mod.Full:
                    pass


class CandidateSearch:
    """A pool of worker processes continuously screening random rules."""

    def __init__(self, workers=None, queue_size=32):
        if workers is None:
            workers = max(1, (os.cpu_count() or 2) - 1)  # leave a core for the UI
        self._stop = mp.Event()
        self._queue = mp.Queue(maxsize=queue_size)
        self._processes = [
            mp.Process(target=_worker, args=(self._queue, self._stop), daemon=True)
            for _ in range(workers)
        ]

    def start(self):
        for p in self._processes:
            p.start()

    def drain(self):
        """Return all candidates found since the last drain (may be empty)."""
        found = []
        while True:
            try:
                found.append(Rule.from_id(self._queue.get_nowait()))
            except queue_mod.Empty:
                return found

    def stop(self):
        self._stop.set()
        for p in self._processes:
            p.join(timeout=1.0)
        for p in self._processes:
            if p.is_alive():
                p.terminate()
