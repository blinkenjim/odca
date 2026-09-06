"""odca: play the looks of an odca file (REQTS section 4d)."""

import sys

from .cli import parse, run
from .help import HELP_ODCA


def main(argv=None):
    file, flags = parse(argv, "odca", HELP_ODCA, flags=("--shuffle", "--fullscreen"))
    if not file.exists():  # R-X1: the file must exist
        print(f"error: {file} does not exist")
        sys.exit(1)
    run({"play_file": file, "shuffle": "--shuffle" in flags}, fullscreen="--fullscreen" in flags)


if __name__ == "__main__":
    main()
