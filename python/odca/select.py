"""odca-select: compose looks in an odca file (REQTS section 4c)."""

from .cli import parse, run
from .help import HELP_ODCA_SELECT


def main(argv=None):
    file, _ = parse(argv, "odca-select", HELP_ODCA_SELECT)
    run({"select_file": file})  # R-W1: a missing file is created on the first save


if __name__ == "__main__":
    main()
