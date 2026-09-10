"""odca-select: compose pairs in an odca file (REQTS section 4c)."""

from .cli import CELL_FLAGS, cell_size, parse, run
from .help import HELP_ODCA_SELECT


def main(argv=None):
    file, flags, _ = parse(argv, "odca-select", HELP_ODCA_SELECT, flags=("--longest",) + CELL_FLAGS)
    cell = cell_size("odca-select", flags)  # R-U2
    # R-W1: a missing file is created on the first save; R-W9: --longest shows only the pairs with seeds
    run({"select_file": file, "select_longest": "--longest" in flags}, cell=cell)


if __name__ == "__main__":
    main()
