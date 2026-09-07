"""Shared command-line handling for odca and odca-select (R-U9, R-W1, R-X1)."""

import sys
from pathlib import Path

CELL_FLAGS = ("--4", "--2", "--1")  # pixels per cell for the run, both programs (R-U2)


def parse(argv, program, help_text, flags=()):
    """Return (file, set of flags given). --help prints and exits 0 first.

    The odca file is the one positional argument; a missing one is a usage
    error (exit 2), an unknown flag likewise.
    """
    args = list(sys.argv[1:] if argv is None else argv)
    if "--help" in args:  # R-U9: before any state, search, or window
        print(help_text, end="")
        sys.exit(0)
    given = set()
    files = []
    for a in args:
        if a in flags:
            given.add(a)
        elif a.startswith("-"):
            print(f"{program}: unknown option {a}")
            sys.exit(2)
        else:
            files.append(a)
    if len(files) != 1:
        print(f"usage: {program} <file.odca>" + (" [" + "] [".join(flags) + "]" if flags else ""))
        sys.exit(2)
    return Path(files[0]), given


def cell_size(program, flags):
    """Pixels per cell: 4 unless one cell flag says otherwise; two is a usage error."""
    chosen = [f for f in CELL_FLAGS if f in flags]
    if len(chosen) > 1:
        print(f"{program}: choose one of {', '.join(CELL_FLAGS)}")
        sys.exit(2)
    return int(chosen[0][2:]) if chosen else 4


def initial_delay(cell):
    """R-U5: 1/60 s at the default cell size, halved for each halving of the cell."""
    from .session import INITIAL_DELAY
    return INITIAL_DELAY * cell / 4


def run(session_kwargs, fullscreen=False, cell=4):
    """Open the pygame viewer on a Session built with the given keyword arguments."""
    from .session import Session  # deferred: pygame prints a banner on import
    from .viewer import Viewer
    width, height = 1200, 800
    session = Session(width // cell, height // cell, initial_delay=initial_delay(cell), **session_kwargs)
    Viewer(width, height, cell, session=session, fullscreen=fullscreen).run()
