"""Command-line entries (TESTS.md PT-35)."""

from pathlib import Path

import pytest

from odca.help import HELP_ODCA, HELP_ODCA_SELECT
from odca.play import main as play_main
from odca.select import main as select_main

CONFORMANCE = Path(__file__).resolve().parent.parent.parent / "conformance"


def test_help_texts_match_the_shared_copies():  # R-U9
    assert HELP_ODCA == (CONFORMANCE / "help-odca.txt").read_text()
    assert HELP_ODCA_SELECT == (CONFORMANCE / "help-odca-select.txt").read_text()


@pytest.mark.parametrize("main, text", [(play_main, HELP_ODCA), (select_main, HELP_ODCA_SELECT)])
def test_help_prints_and_exits_zero(main, text, capsys, tmp_path, monkeypatch):  # PT-35
    monkeypatch.setenv("HOME", str(tmp_path))  # no state may be touched
    with pytest.raises(SystemExit) as e:
        main(["missing.odca", "--help"])
    assert e.value.code == 0
    assert capsys.readouterr().out == text
    assert not (tmp_path / ".odca").exists()


def test_usage_errors(capsys, tmp_path):  # R-W1, R-X1
    with pytest.raises(SystemExit) as e:
        play_main([])
    assert e.value.code == 2 and "usage: odca <file.odca> [--shuffle] [--fullscreen]" in capsys.readouterr().out
    with pytest.raises(SystemExit) as e:
        play_main([str(tmp_path / "nope.odca")])
    assert e.value.code == 1 and "does not exist" in capsys.readouterr().out
    with pytest.raises(SystemExit) as e:
        select_main(["--shuffle", "x.odca"])
    assert e.value.code == 2 and "unknown option --shuffle" in capsys.readouterr().out
    with pytest.raises(SystemExit) as e:
        select_main(["x.odca", "--fullscreen"])  # odca's flag only (R-U2)
    assert e.value.code == 2 and "unknown option --fullscreen" in capsys.readouterr().out


def test_odca_flags_are_parsed(monkeypatch, tmp_path):  # R-U2, R-X1
    from odca import play
    file = tmp_path / "show.odca"
    file.write_text('{"looks": []}')
    calls = []
    monkeypatch.setattr(play, "run", lambda kwargs, fullscreen=False: calls.append((kwargs, fullscreen)))
    play.main([str(file), "--fullscreen"])
    play.main(["--shuffle", str(file)])
    assert calls == [({"play_file": file, "shuffle": False}, True),
                     ({"play_file": file, "shuffle": True}, False)]
