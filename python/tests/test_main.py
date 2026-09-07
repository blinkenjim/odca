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
    assert e.value.code == 2 and "usage: odca <file.odca> [--shuffle] [--fullscreen] [--4] [--2] [--1] [--watchdog N] [--grace N]" in capsys.readouterr().out
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
    monkeypatch.setattr(play, "run", lambda kwargs, fullscreen=False, cell=4: calls.append((kwargs, fullscreen, cell)))
    play.main([str(file), "--fullscreen"])
    play.main(["--shuffle", str(file)])
    play.main([str(file), "--1"])
    play.main(["--watchdog", "20", str(file), "--grace", "10"])
    clocks = {"play_timeout": 120.0, "play_grace": 60.0}  # the defaults (R-X2, R-X3)
    assert calls == [({"play_file": file, "shuffle": False, **clocks}, True, 4),
                     ({"play_file": file, "shuffle": True, **clocks}, False, 4),
                     ({"play_file": file, "shuffle": False, **clocks}, False, 1),
                     ({"play_file": file, "shuffle": False, "play_timeout": 20, "play_grace": 10}, False, 4)]


def test_watchdog_and_grace_need_whole_seconds(tmp_path, capsys):  # R-X2, R-X3, R-U9
    from odca import play, select
    file = tmp_path / "show.odca"
    file.write_text('{"looks": []}')
    for args in (["--watchdog"], ["--watchdog", "--grace", "5"], ["--grace", "x"], ["--watchdog", "0"], ["--grace", "1.5"]):
        with pytest.raises(SystemExit) as e:
            play.main([str(file)] + args)
        assert e.value.code == 2, args
        assert "needs a" in capsys.readouterr().out
    with pytest.raises(SystemExit) as e:
        select.main([str(file), "--watchdog", "20"])  # odca only
    assert e.value.code == 2 and "unknown option --watchdog" in capsys.readouterr().out


def test_initial_delay_follows_the_cell_size():  # R-U5
    from odca.cli import initial_delay
    from odca.session import INITIAL_DELAY
    assert initial_delay(4) == INITIAL_DELAY
    assert initial_delay(2) == INITIAL_DELAY / 2 and initial_delay(1) == INITIAL_DELAY / 4


def test_cell_size_flags(monkeypatch, tmp_path, capsys):  # R-U2
    from odca import select
    calls = []
    monkeypatch.setattr(select, "run", lambda kwargs, fullscreen=False, cell=4: calls.append(cell))
    select.main(["--2", "x.odca"])
    select.main(["x.odca", "--4"])
    select.main(["x.odca"])
    assert calls == [2, 4, 4]
    with pytest.raises(SystemExit) as e:
        select.main(["x.odca", "--2", "--1"])  # at most one
    assert e.value.code == 2 and "choose one of --4, --2, --1" in capsys.readouterr().out
