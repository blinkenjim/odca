"""Play scripts (TESTS.md layer 1 script cases and PT-38; REQTS R-X7, R-X1)."""

from pathlib import Path

import pytest

from odca.automaton import Rule
from odca.show import ShowError, load_script, load_show, parse, parse_json
from odca.store import save_odca_file

ROOT = Path(__file__).resolve().parent.parent.parent
CASES = ROOT / "conformance" / "scripts"

PAIR = {"rule": Rule.from_id("00000000000000000000").id, "colorset": "ODCA default",
        "colors": ["#121218", "#EBEBE1", "#FFA136", "#409CFF"]}


@pytest.mark.parametrize("case", sorted(p.stem for p in CASES.glob("*.play")))
def test_script_cases_match_the_golden_output(case):  # layer 1: the parser's JSON, byte for byte
    text = (CASES / f"{case}.play").read_text(encoding="utf-8")
    assert parse_json(text) + "\n" == (CASES / f"{case}.json").read_text(encoding="utf-8")


def test_the_generated_parser_is_the_same_on_both_sides():  # the two checked-in copies of script/regen's output
    ours = ROOT / "python" / "odca" / "cshow"
    theirs = ROOT / "swift" / "Sources" / "CShow"
    for name in ("show.lex.c", "show.lex.h", "show.tab.c", "show.tab.h", "show_internal.h", "include/show.h"):
        assert (ours / name).read_bytes() == (theirs / name).read_bytes(), name


def test_parse_gives_statements_or_a_positioned_error():  # PT-38, R-X7
    assert parse("import a.odca\nplay\n") == [{"line": 1, "import": "a.odca"}, {"line": 2, "play": True}]
    assert parse("shuffle\n") == [{"line": 1, "shuffle": True}]
    assert parse("# only a comment") == []
    with pytest.raises(ShowError) as e:
        parse("import a.odca\nplay\nplay\n")
    assert str(e.value) == "3:1: play given twice"
    with pytest.raises(ShowError) as e:
        parse("import a.odca\nplay\nshuffle\n")
    assert str(e.value) == "3:1: shuffle after play"


def test_a_script_plays_what_it_imports(tmp_path):  # PT-38, R-X7
    save_odca_file([PAIR], tmp_path / "one.odca")
    (tmp_path / "sub").mkdir()
    save_odca_file([PAIR, PAIR], tmp_path / "sub" / "two pairs.odca")
    script = tmp_path / "sub" / "show.play"
    script.write_text('import ../one.odca   # relative to the script\nimport "two pairs.odca"\nplay\n')
    assert load_script(script) == ([PAIR, PAIR, PAIR], False)
    script.write_text('import ../one.odca\nshuffle\n')  # R-X7: the pairs shuffled per pass
    assert load_script(script) == ([PAIR], True)
    script.write_text("import ../one.odca\n")  # imports without play: nothing plays
    assert load_script(script) == ([], False)
    script.write_text("shuffle\n")  # a play word without imports: nothing to play
    assert load_script(script) == ([], True)
    script.write_text("import gone.odca\nplay\n")
    with pytest.raises(ShowError) as e:
        load_script(script)
    assert str(e.value) == f"{script}:1: cannot read gone.odca"
    (tmp_path / "sub" / "notes.txt").write_text("hello\n")
    script.write_text("\n\nimport notes.txt\nplay\n")
    with pytest.raises(ShowError) as e:
        load_script(script)
    assert str(e.value) == f"{script}:3: notes.txt is not an odca file"
    script.write_text("import ../one.odca\nshuffle\nimport ../one.odca\n")
    with pytest.raises(ShowError) as e:
        load_script(script)
    assert str(e.value) == f"{script}:3:1: import after shuffle"
    with pytest.raises(ShowError) as e:
        load_script(tmp_path / "missing.play")
    assert str(e.value) == f"{tmp_path / 'missing.play'}: cannot read"


def test_the_show_is_one_segment_per_file(tmp_path):  # PT-38, R-X1
    save_odca_file([PAIR], tmp_path / "one.odca")
    script = tmp_path / "show.play"
    script.write_text("import one.odca\nimport one.odca\nplay\n")
    (tmp_path / "empty.odca").write_text('{"pairs": []}')
    shuffled = tmp_path / "shuffled.play"
    shuffled.write_text("import one.odca\nshuffle\n")
    show = load_show([script, tmp_path / "one.odca", tmp_path / "empty.odca", shuffled])
    assert show == [{"file": "show.play", "pairs": [PAIR, PAIR], "shuffle": False},  # a script: what it plays
                    {"file": "one.odca", "pairs": [PAIR], "shuffle": False},  # an odca file: import it, play it
                    {"file": "empty.odca", "pairs": [], "shuffle": False},
                    {"file": "shuffled.play", "pairs": [PAIR], "shuffle": True}]  # R-X7
    (tmp_path / "show.txt").write_text("import one.odca\nplay\n")
    assert load_show([tmp_path / "show.txt"])[0]["pairs"] == [PAIR]  # any other extension is a script
    with pytest.raises(ShowError):
        load_show([tmp_path / "missing.odca"])
