"""odca-select: compose pairs in an odca file (REQTS section 4c)."""

import sys

from .cli import CELL_FLAGS, cell_size, choose_experiment, parse, run
from .help import HELP_ODCA_SELECT
from .store import rejection


def main(argv=None):
    file, flags, values = parse(argv, "odca-select", HELP_ODCA_SELECT,
                                flags=("--longest",) + CELL_FLAGS,
                                options=("-x", "--experiment"))
    # R-P6: a missing file is made on the first save (R-W1), but one that
    # exists and will not parse must not open a window: this program saves
    # back over the file it was given, so starting on an empty reading of it
    # would destroy it.
    why = rejection(file)
    if why is not None:
        print(f"error: {why}")
        sys.exit(1)
    cell = cell_size("odca-select", flags)  # R-U2
    experiment = choose_experiment("odca-select", values)  # R-M12
    # R-W1: a missing file is created on the first save; R-W9: --longest shows only the pairs with seeds
    run({"select_file": file, "select_longest": "--longest" in flags,
         "experiment": experiment}, cell=cell)


if __name__ == "__main__":
    main()
