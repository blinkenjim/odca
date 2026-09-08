"""Shared command-line handling for odca and odca-select (R-U9, R-W1, R-X1)."""

import sys
from pathlib import Path

CELL_FLAGS = ("--4", "--3", "--2", "--1")  # pixels per cell for the run, both programs (R-U2)


def parse(argv, program, help_text, flags=(), options=()):
    """Return (file, set of flags given, {option: value}). --help prints and exits 0 first.

    The odca file is the one positional argument; a missing one is a usage
    error (exit 2), an unknown flag likewise. `options` take the next
    argument as their value; one without a value is a usage error.
    """
    args = list(sys.argv[1:] if argv is None else argv)
    if "--help" in args:  # R-U9: before any state, search, or window
        print(help_text, end="")
        sys.exit(0)
    given, values, files = set(), {}, []
    i = 0
    while i < len(args):
        a = args[i]
        if a in flags:
            given.add(a)
        elif a in options:
            if i + 1 >= len(args) or args[i + 1].startswith("-"):
                print(f"{program}: {a} needs a value")
                sys.exit(2)
            values[a] = args[i + 1]
            i += 1
        elif a.startswith("-"):
            print(f"{program}: unknown option {a}")
            sys.exit(2)
        else:
            files.append(a)
        i += 1
    if len(files) != 1:
        usage = "".join(f" [{f}]" for f in flags) + "".join(f" [{o} N]" for o in options)
        print(f"usage: {program} <file.odca>{usage}")
        sys.exit(2)
    return Path(files[0]), given, values


def whole_seconds(program, values, option, default):
    """A positive whole number of seconds given to `option`, or `default` (R-X2, R-X3)."""
    if option not in values:
        return default
    v = values[option]
    if not v.isdigit() or int(v) < 1:
        print(f"{program}: {option} needs a whole number of seconds")
        sys.exit(2)
    return int(v)


def cell_size(program, flags):
    """Pixels per cell: 4 unless one cell flag says otherwise; two is a usage error."""
    chosen = [f for f in CELL_FLAGS if f in flags]
    if len(chosen) > 1:
        print(f"{program}: choose one of {', '.join(CELL_FLAGS)}")
        sys.exit(2)
    return int(chosen[0][2:]) if chosen else 2  # R-U2: 2-point cells by default


def initial_delay(cell):
    """R-U5: 1/60 s at the default cell size, halved for each halving of the cell."""
    from .session import INITIAL_DELAY
    return INITIAL_DELAY * cell / 4


def run(session_kwargs, fullscreen=False, cell=2):
    """Open the pygame viewer on a Session built with the given keyword arguments."""
    from .session import Session  # deferred: pygame prints a banner on import
    from .viewer import Viewer
    width, height = 1200, 800
    session = Session(width // cell, height // cell, initial_delay=initial_delay(cell), **session_kwargs)
    Viewer(width, height, cell, session=session, fullscreen=fullscreen).run()
