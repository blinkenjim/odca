import numpy as np

from odca.automaton import Rule
from odca.store import load_odca_file, load_rule, save_odca_file, save_rule


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


def test_odca_file_round_trip_and_layout(tmp_path):  # PT-8
    path = tmp_path / "looks.odca"
    rng = np.random.default_rng(6)
    looks = [{"rule": Rule.random(rng).id, "colorset": "Mine", "colors": ["#000000", "#111111", "#222222", "#333333"]}
             for _ in range(3)]
    save_odca_file(looks, path)
    assert load_odca_file(path) == looks
    assert path.read_text().startswith('{\n "looks": [\n  {\n   "rule": "')


def test_odca_file_skips_invalid_looks(tmp_path):  # PT-8
    path = tmp_path / "looks.odca"
    rule = Rule.random(np.random.default_rng(8))
    path.write_text('{"looks": [{"rule": "notarule", "colorset": "x", "colors": ["#000000", "#000000", "#000000", "#000000"]}, '
                    f'{{"rule": "{rule.id}", "colorset": "ok", "colors": ["#000000", "#000000", "#000000", "#000000"]}}]}}')
    assert [p["rule"] for p in load_odca_file(path)] == [rule.id]
    path.write_text(f'{{"pairs": [{{"rule": "{rule.id}", "colorset": "old", "colors": ["#000000", "#000000", "#000000", "#000000"]}}]}}')
    assert load_odca_file(path) == []  # the 2.x "pairs" key is no longer read


def test_odca_file_missing_reads_as_none(tmp_path):
    assert load_odca_file(tmp_path / "nope.odca") is None


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


def test_odca_file_edge_cases(tmp_path):  # PT-29
    path = tmp_path / "saver.odca"
    save_odca_file([], path)
    assert path.read_text() == '{\n "looks": []\n}\n'
    assert load_odca_file(path) == []
    rule = Rule.random(np.random.default_rng(9))
    looks = [{"rule": rule.id, "colorset": 'Say "hi"', "colors": ["#000000", "#111111", "#222222", "#333333"]}]
    save_odca_file(looks, path)
    assert load_odca_file(path) == looks
    assert '\\"hi\\"' in path.read_text()
    path.write_text("{not json")
    assert load_odca_file(path) == []
