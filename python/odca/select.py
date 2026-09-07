"""odca-select: compose looks in an odca file (REQTS section 4c)."""

from .cli import CELL_FLAGS, cell_size, parse, run
from .help import HELP_ODCA_SELECT


def main(argv=None):
    file, flags, _ = parse(argv, "odca-select", HELP_ODCA_SELECT, flags=CELL_FLAGS)
    cell = cell_size("odca-select", flags)  # R-U2
    run({"select_file": file}, cell=cell)  # R-W1: a missing file is created on the first save


if __name__ == "__main__":
    main()
