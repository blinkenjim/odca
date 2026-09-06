"""Command-line entry (TESTS.md PT-35)."""

from pathlib import Path

import pytest

from odca.__main__ import main
from odca.help import HELP_TEXT

HELP_FILE = Path(__file__).resolve().parent.parent.parent / "conformance" / "help.txt"


def test_help_text_matches_the_shared_copy():  # R-U9
    assert HELP_TEXT == HELP_FILE.read_text()


def test_help_prints_and_exits_zero(capsys, tmp_path, monkeypatch):  # PT-35
    monkeypatch.setenv("HOME", str(tmp_path))  # no state may be touched
    with pytest.raises(SystemExit) as e:
        main(["--help", "--screensaver", "missing.json"])
    assert e.value.code == 0
    assert capsys.readouterr().out == HELP_TEXT
    assert not (tmp_path / ".odca").exists()
