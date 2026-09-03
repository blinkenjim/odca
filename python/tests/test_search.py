import time

import numpy as np

from odca.automaton import Rule
from odca.search import CandidateSearch
from odca.store import load_candidates, save_candidates


def test_candidates_round_trip(tmp_path):
    path = tmp_path / "candidates"
    rng = np.random.default_rng(2)
    rules = [Rule.random(rng) for _ in range(5)]
    save_candidates(rules, path)
    assert load_candidates(path) == rules


def test_load_candidates_missing_file(tmp_path):
    assert load_candidates(tmp_path / "nope") == []


def test_load_candidates_skips_invalid_lines(tmp_path):
    path = tmp_path / "candidates"
    rule = Rule.random(np.random.default_rng(3))
    path.write_text(f"garbage\n{rule.id}\n123\n")
    assert load_candidates(path) == [rule]


def test_search_finds_candidates_and_stops():
    search = CandidateSearch(workers=2)
    search.start()
    found = []
    deadline = time.time() + 30
    while not found and time.time() < deadline:
        found = search.drain()
        time.sleep(0.05)
    search.stop()
    assert found, "no candidate found within 30s"
    assert all(isinstance(r, Rule) for r in found)
