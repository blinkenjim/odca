"""odca: play a show, one or more play scripts or odca files (REQTS section 4d)."""

import sys

from .cli import CELL_FLAGS, cell_size, parse, run, whole_seconds
from .help import HELP_ODCA
from .session import PLAY_GRACE, PLAY_TIMEOUT
from .show import ShowError, load_show


def main(argv=None):
    files, flags, values = parse(argv, "odca", HELP_ODCA, flags=("--shuffle", "--fullscreen") + CELL_FLAGS,
                                 options=("--watchdog", "--grace"), positional="<file> [<file> ...]", many=True)
    cell = cell_size("odca", flags)  # R-U2
    timing = {"play_timeout": whole_seconds("odca", values, "--watchdog", PLAY_TIMEOUT),  # R-X2
              "play_grace": whole_seconds("odca", values, "--grace", PLAY_GRACE)}  # R-X3
    for file in files:
        if not file.exists():  # R-X1: every file must exist
            print(f"error: {file} does not exist")
            sys.exit(1)
    try:
        show = load_show(files)  # R-X1, R-X7: scripts are read and checked before the window opens
    except ShowError as e:
        print(f"error: {e}")
        sys.exit(1)
    run({"show": show, "shuffle": "--shuffle" in flags, **timing},
        fullscreen="--fullscreen" in flags, cell=cell)


if __name__ == "__main__":
    main()
