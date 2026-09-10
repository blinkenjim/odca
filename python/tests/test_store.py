import numpy as np

from odca.automaton import Rule
from odca.store import load_odca_file, load_rule, load_seeds, merge_seeds, save_odca_file, save_rule


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
    path = tmp_path / "pairs.odca"
    rng = np.random.default_rng(6)
    pairs = [{"rule": Rule.random(rng).id, "colorset": "Mine", "colors": ["#000000", "#111111", "#222222", "#333333"]}
             for _ in range(3)]
    save_odca_file(pairs, path)
    assert load_odca_file(path) == pairs
    assert path.read_text().startswith('{\n "pairs": [\n  {\n   "rule": "')
    named = [{"name": "pair-0007", **pairs[0]}, pairs[1]]  # a name is kept, and written first
    save_odca_file(named, path)
    assert load_odca_file(path) == named
    assert path.read_text().startswith('{\n "pairs": [\n  {\n   "name": "pair-0007",\n   "rule": "')
    path.write_text(path.read_text().replace('"pairs"', '"looks"'))  # the 3.0.0 key is still read
    assert load_odca_file(path) == named


def test_next_pair_name_is_one_past_the_highest_in_use():  # PT-8, R-P3
    from odca.store import next_pair_name
    assert next_pair_name([]) == "pair-0000"
    assert next_pair_name([{"name": "pair-0000"}, {"name": "pair-0002"}, {"rule": "x"}]) == "pair-0003"
    assert next_pair_name([{"name": "pair-9999"}]) == "pair-10000"  # five digits once they are needed
    assert next_pair_name([{"name": "sunset"}]) == "pair-0000"  # other names do not count


def test_odca_file_skips_invalid_pairs(tmp_path):  # PT-8
    path = tmp_path / "pairs.odca"
    rule = Rule.random(np.random.default_rng(8))
    path.write_text('{"pairs": [{"rule": "notarule", "colorset": "x", "colors": ["#000000", "#000000", "#000000", "#000000"]}, '
                    f'{{"rule": "{rule.id}", "colorset": "ok", "colors": ["#000000", "#000000", "#000000", "#000000"]}}]}}')
    assert [p["rule"] for p in load_odca_file(path)] == [rule.id]
    path.write_text(f'{{"entries": [{{"rule": "{rule.id}", "colorset": "old", "colors": ["#000000", "#000000", "#000000", "#000000"]}}]}}')
    assert load_odca_file(path) == []  # an unknown key holds nothing


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
    assert path.read_text() == '{\n "pairs": []\n}\n'
    assert load_odca_file(path) == []
    rule = Rule.random(np.random.default_rng(9))
    pairs = [{"rule": rule.id, "colorset": 'Say "hi"', "colors": ["#000000", "#111111", "#222222", "#333333"]}]
    save_odca_file(pairs, path)
    assert load_odca_file(path) == pairs
    assert '\\"hi\\"' in path.read_text()
    path.write_text("{not json")
    assert load_odca_file(path) == []


def test_seeds_round_trip_layout_and_carry_through(tmp_path):  # PT-43, R-P3
    kills3, all_zero = "3" + "1" * 19, "0" * 20
    file = tmp_path / "pairs.odca"
    pair = {"name": "pair-0000", "rule": kills3, "colorset": "ODCA default",
            "colors": ["#121218", "#EBEBE1", "#FFA136", "#409CFF"]}
    def seed(text, generations, end="state 3 extinct"):
        return {"row": [int(c) for c in text], "generations": generations, "end": end}
    save_odca_file([pair], file, seeds={kills3: {8: [seed("31111111", 1), seed("33331111", 3)]},
                                        all_zero: {8: [seed("01230123", 50, "survived")]}})
    reference = (  # what the Swift writer produces for the same content (its test holds the same text)
        '{\n "pairs": [\n  {\n   "name": "pair-0000",\n   "rule": "31111111111111111111",\n'
        '   "colorset": "ODCA default",\n   "colors": [\n    "#121218",\n    "#EBEBE1",\n    "#FFA136",\n'
        '    "#409CFF"\n   ]\n  }\n ],\n "seeds": {\n  "00000000000000000000": {\n   "8": [\n    {\n'
        '     "row": "01230123",\n     "generations": 50,\n     "end": "survived"\n    }\n   ]\n  },\n'
        '  "31111111111111111111": {\n   "8": [\n    {\n     "row": "33331111",\n     "generations": 3,\n'
        '     "end": "state 3 extinct"\n    },\n    {\n     "row": "31111111",\n     "generations": 1,\n'
        '     "end": "state 3 extinct"\n    }\n   ]\n  }\n }\n}\n')
    assert file.read_text() == reference
    assert load_odca_file(file) == [pair]
    loaded = load_seeds(file)
    assert loaded[kills3][8] == [seed("33331111", 3), seed("31111111", 1)]  # longest first
    assert loaded[all_zero][8] == [seed("01230123", 50, "survived")]
    save_odca_file([pair, pair], file)  # odca-select's path carries the section through
    assert load_seeds(file) == loaded and len(load_odca_file(file)) == 2
    save_odca_file([pair], file, seeds={})  # no seeds: no section
    assert "seeds" not in file.read_text() and load_seeds(file) == {}
    file.write_text('{"pairs": [], "seeds": {"%s": {"8": [{"row": "3111111", "generations": 1, "end": "x"},'
                    ' {"row": "3111111a", "generations": 1, "end": "x"}, {"row": "31111111", "generations": 2,'
                    ' "end": "state 3 extinct"}], "2": [{"row": "31", "generations": 1, "end": "x"}]},'
                    ' "nonsense": {"8": []}}}' % kills3)
    assert load_seeds(file) == {kills3: {8: [seed("31111111", 2)]}}  # malformed entries skipped
    twelve = [seed("".join("3" if b == "1" else "1" for b in format(n, "08b")), n * 10) for n in range(12)]
    merged = merge_seeds(twelve)
    assert [s["generations"] for s in merged] == [110, 100, 90, 80, 70, 60, 50, 40, 30, 20]
    assert merge_seeds(merged, merged) == merged
    assert [ "".join(map(str, s["row"])) for s in merge_seeds([seed("11111131", 5), seed("11111113", 5)])] == ["11111113", "11111131"]
