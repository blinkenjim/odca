"""odca: play a show, one or more play scripts or odca files (REQTS section 4d)."""

import sys

from .cli import CELL_FLAGS, cell_size, parse, run, whole_number, whole_seconds
from .help import HELP_ODCA
from .session import MIN_COLS, PLAY_GRACE, PLAY_TIMEOUT
from .show import ShowError, load_show, seed_width


def main(argv=None):
    files, flags, values = parse(argv, "odca", HELP_ODCA, flags=("--shuffle", "--longest", "--fullscreen") + CELL_FLAGS,
                                 options=("--watchdog", "--grace", "--cells"), positional="<file> [<file> ...]", many=True)
    cell = cell_size("odca", flags)  # R-U2
    longest = "--longest" in flags  # R-X8
    if longest:
        for option in ("--watchdog", "--grace"):  # no clocks: a seed plays to its end
            if option in values:
                print(f"odca: {option} does not apply with --longest")
                sys.exit(2)
    elif "--cells" in values:
        print("odca: --cells applies only with --longest")
        sys.exit(2)
    timing = {"play_timeout": whole_seconds("odca", values, "--watchdog", PLAY_TIMEOUT),  # R-X2
              "play_grace": whole_seconds("odca", values, "--grace", PLAY_GRACE)}  # R-X3
    cells = whole_number("odca", values, "--cells", "cells", minimum=MIN_COLS)
    for file in files:
        if not file.exists():  # R-X1: every file must exist
            print(f"error: {file} does not exist")
            sys.exit(1)
        if longest and file.suffix != ".odca":  # R-X8: odca files only
            print(f"error: {file}: --longest plays odca files only")
            sys.exit(1)
    try:
        show = load_show(files)  # R-X1, R-X7: scripts are read and checked before the window opens
        width = seed_width(show, cells) if longest else None  # R-X8: the one width, or the chosen one
    except ShowError as e:
        print(f"error: {e}")
        sys.exit(1)
    run({"show": show, "shuffle": "--shuffle" in flags, "longest": longest, **timing},
        fullscreen="--fullscreen" in flags, cell=cell, cols=width)


if __name__ == "__main__":
    main()
