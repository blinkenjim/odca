import numpy as np

from odca.automaton import Rule
from odca.store import load_rule, save_rule


def test_save_and_load_round_trip(tmp_path):
    path = tmp_path / "state" / "rule"
    rule = Rule.random(np.random.default_rng(3))
    save_rule(rule, path)
    assert load_rule(path) == rule


def test_load_missing_file_returns_none(tmp_path):
    assert load_rule(tmp_path / "nope") is None


def test_load_corrupt_file_returns_none(tmp_path):
    path = tmp_path / "rule"
    path.write_text("not a rule\n")
    assert load_rule(path) is None


def test_save_overwrites_previous(tmp_path):
    path = tmp_path / "rule"
    rng = np.random.default_rng(4)
    first, second = Rule.random(rng), Rule.random(rng)
    save_rule(first, path)
    save_rule(second, path)
    assert load_rule(path) == second
