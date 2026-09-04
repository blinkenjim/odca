import numpy as np

from odca.automaton import Rule
from odca.store import append_interesting, load_interesting, load_rule, save_rule


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


def test_append_interesting_appends_in_keeper_format(tmp_path):
    path = tmp_path / "interesting-rules.txt"
    path.write_text("rule 00000000000000000000\n")
    rule = Rule.random(np.random.default_rng(6))
    append_interesting(rule, path)
    assert path.read_text() == f"rule 00000000000000000000\nrule {rule.id}\n"


def test_load_interesting_round_trip(tmp_path):
    path = tmp_path / "interesting-rules.txt"
    rng = np.random.default_rng(7)
    rules = [Rule.random(rng) for _ in range(3)]
    for rule in rules:
        append_interesting(rule, path)
    assert load_interesting(path) == rules


def test_load_interesting_skips_invalid_lines(tmp_path):
    path = tmp_path / "interesting-rules.txt"
    rule = Rule.random(np.random.default_rng(8))
    path.write_text(f"# comment\nrule notarule\nrule {rule.id}\nstray line\n")
    assert load_interesting(path) == [rule]


def test_load_interesting_missing_file(tmp_path):
    assert load_interesting(tmp_path / "nope") == []


def test_save_overwrites_previous(tmp_path):
    path = tmp_path / "rule"
    rng = np.random.default_rng(4)
    first, second = Rule.random(rng), Rule.random(rng)
    save_rule(first, path)
    save_rule(second, path)
    assert load_rule(path) == second


def test_color_sets_round_trip_and_tolerance(tmp_path):  # PT-24
    from odca.store import load_color_sets, save_color_sets
    path = tmp_path / "colorsets.json"
    assert set(load_color_sets(path)) == {1}  # missing file: default only
    sets = {0: {"name": "A", "colors": ["#010203", "#040506", "#070809", "#0A0B0C"]},
            1: {"name": "Mine", "colors": ["#000000", "#FFFFFF", "#FF0000", "#0000FF"]}}
    save_color_sets(sets, path)
    assert load_color_sets(path) == sets  # file's slot 1 overrides the built-in
    path.write_text('{"sets": [{"slot": 4, "name": "bad", "colors": ["#12"]}, '
                    '{"slot": 12, "name": "x", "colors": ["#000000", "#000000", "#000000", "#000000"]}, '
                    '{"slot": 7, "name": "ok", "colors": ["#abcdef", "#000000", "#111111", "#222222"]}]}')
    loaded = load_color_sets(path)
    assert set(loaded) == {1, 7} and loaded[7]["colors"][0] == "#ABCDEF"
    path.write_text("not json")
    assert set(load_color_sets(path)) == {1}
