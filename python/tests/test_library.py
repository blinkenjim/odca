"""PT-37: the shipped library matches the spec's R-U4 table (the spec is authoritative)."""

import re
from pathlib import Path

from odca.store import LIBRARY_PATH, load_color_sets

ROOT = Path(__file__).resolve().parent.parent.parent


def spec_slots():
    text = (ROOT / "REQTS.md").read_text()
    table = re.search(r"\| slot \| name \| state 0 .*?\n\|[-| ]+\|\n((?:\|.*\|\n)+)", text)
    assert table, "R-U4 slot table not found in REQTS.md"
    slots = {}
    for line in table.group(1).strip().splitlines():
        cells = [c.strip() for c in line.strip("|").split("|")]
        slots[int(cells[0])] = {"name": cells[1], "colors": [c.strip("`") for c in cells[2:6]]}
    return slots


def test_shipped_library_matches_the_spec_table():  # PT-37
    assert LIBRARY_PATH == ROOT / "library.json"
    assert load_color_sets(LIBRARY_PATH) == spec_slots()
