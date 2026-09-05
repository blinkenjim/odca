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


def test_append_interesting_writes_pairs(tmp_path):
    from odca.store import load_interesting_pairs
    path = tmp_path / "interesting-rules.json"
    rule = Rule.random(np.random.default_rng(6))
    append_interesting(rule, path)  # default color set
    append_interesting(rule, path, "Mine", ["#000000", "#111111", "#222222", "#333333"])
    pairs = load_interesting_pairs(path)
    assert [p["rule"] for p in pairs] == [rule.id, rule.id]
    assert pairs[0]["colorset"] == "ODCA default" and pairs[1]["colors"][3] == "#333333"
    assert path.read_text().startswith('{\n "pairs": [\n  {\n   "rule": "')


def test_load_interesting_round_trip(tmp_path):
    path = tmp_path / "interesting-rules.json"
    rng = np.random.default_rng(7)
    rules = [Rule.random(rng) for _ in range(3)]
    for rule in rules:
        append_interesting(rule, path)
    assert load_interesting(path) == rules


def test_load_interesting_skips_invalid_pairs(tmp_path):
    path = tmp_path / "interesting-rules.json"
    rule = Rule.random(np.random.default_rng(8))
    path.write_text('{"pairs": [{"rule": "notarule", "colorset": "x", "colors": ["#000000"]*4}, '
                    f'{{"rule": "{rule.id}", "colorset": "ok", "colors": ["#000000", "#000000", "#000000", "#000000"]}}]}}'
                    .replace('["#000000"]*4', '["#000000", "#000000", "#000000", "#000000"]'))
    assert load_interesting(path) == [rule]
    path.write_text(f"rule {rule.id}\n")  # the old text format is no longer read
    assert load_interesting(path) == []


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


def test_save_color_sets_preserves_pool_and_dropped(tmp_path):  # R-P4
    from odca.store import load_color_set_file, load_color_sets, save_color_set_file, save_color_sets
    path = tmp_path / "colorsets.json"
    save_color_set_file({"sets": [
        {"slot": 1, "name": "One", "colors": ["#000000", "#111111", "#222222", "#333333"]},
        {"slot": None, "name": "Pool A", "colors": ["#AAAAAA", "#BBBBBB", "#CCCCCC", "#DDDDDD"]},
    ], "dropped": ["Gone"]}, path)
    assert set(load_color_sets(path)) == {1}  # pool-only sets are not digit-bound
    save_color_sets({1: {"name": "One", "colors": ["#333333", "#222222", "#111111", "#000000"]},
                     2: {"name": "Two", "colors": ["#010101"] * 4}}, path)
    f = load_color_set_file(path)
    assert [e["name"] for e in f["sets"]] == ["One", "Two", "Pool A"]
    assert f["sets"][0]["colors"][0] == "#333333" and f["sets"][2]["slot"] is None
    assert f["dropped"] == ["Gone"]
    text = path.read_text()
    assert text.endswith(' "dropped": [\n  "Gone"\n ]\n}\n')


def test_candidate_palettes_load_and_skip_malformed(tmp_path):  # PT-27
    from odca.store import load_candidate_palettes
    path = tmp_path / "candidates.json"
    path.write_text('{"palettes": [{"index": 0, "name": "Good", "colors": ["#0a0a0a", "#111111", "#222222", "#333333"]},'
                    ' {"index": 1, "name": "Short", "colors": ["#000000"]},'
                    ' {"index": 2, "colors": ["#000000", "#000000", "#000000", "#000000"]},'
                    ' {"index": 3, "name": "Bad", "colors": ["#000000", "#000000", "#000000", "nope"]}]}')
    assert load_candidate_palettes(path) == [
        {"slot": None, "name": "Good", "colors": ["#0A0A0A", "#111111", "#222222", "#333333"]}]
    assert load_candidate_palettes(tmp_path / "missing.json") == []


def test_screensaver_file_round_trip(tmp_path):  # PT-29
    from odca.store import load_screensaver, save_screensaver
    path = tmp_path / "saver.json"
    assert load_screensaver(path) is None  # missing
    save_screensaver([], path)
    assert path.read_text() == '{\n "pairs": []\n}\n'
    assert load_screensaver(path) == []
    rule = Rule.random(np.random.default_rng(9))
    pairs = [{"rule": rule.id, "colorset": 'Say "hi"', "colors": ["#000000", "#111111", "#222222", "#333333"]}]
    save_screensaver(pairs, path)
    assert load_screensaver(path) == pairs
    assert '\\"hi\\"' in path.read_text()
    path.write_text('{"pairs": [{"rule": "notarule", "colorset": "x", "colors": ["#000000", "#000000", "#000000", "#000000"]}]}')
    assert load_screensaver(path) == []
    path.write_text("{not json")
    assert load_screensaver(path) == []
