"""odca: play the pairs of an odca file (REQTS section 4d)."""

import sys

from .cli import CELL_FLAGS, cell_size, parse, run, whole_seconds
from .help import HELP_ODCA
from .session import PLAY_GRACE, PLAY_TIMEOUT


def main(argv=None):
    file, flags, values = parse(argv, "odca", HELP_ODCA, flags=("--shuffle", "--fullscreen") + CELL_FLAGS,
                                options=("--watchdog", "--grace"))
    cell = cell_size("odca", flags)  # R-U2
    timing = {"play_timeout": whole_seconds("odca", values, "--watchdog", PLAY_TIMEOUT),  # R-X2
              "play_grace": whole_seconds("odca", values, "--grace", PLAY_GRACE)}  # R-X3
    if not file.exists():  # R-X1: the file must exist
        print(f"error: {file} does not exist")
        sys.exit(1)
    run({"play_file": file, "shuffle": "--shuffle" in flags, **timing},
        fullscreen="--fullscreen" in flags, cell=cell)


if __name__ == "__main__":
    main()
