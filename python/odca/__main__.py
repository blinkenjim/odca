"""Command-line entry point: python -m odca [mode flags]

No flags are needed for ordinary use. Developer / workbench flags (REQTS 4b-4d):
    --colorset-review              review the color set pool (N/P step, X drops)
    --screensaver-review <file>    compose a screensaver file of rule/color-set pairs
    --consistency-check <file>     the same on an existing file, viewed grouped by rule
    --screensaver <file>           play an existing screensaver file (--sequential is the default order)
"""

import sys
from pathlib import Path

from .session import Session
from .viewer import Viewer


def _value(args, flag):
    """The argument after `flag`, '' if the flag is last, None if absent."""
    if flag not in args:
        return None
    i = args.index(flag)
    return args[i + 1] if i + 1 < len(args) else ""


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    review = "--colorset-review" in args
    screensaver = _value(args, "--screensaver-review")
    consistency = _value(args, "--consistency-check")
    play = _value(args, "--screensaver")
    group_by_rule = False
    for flag, value in (("--screensaver-review", screensaver), ("--consistency-check", consistency),
                        ("--screensaver", play)):
        if value == "":
            print(f"usage: odca {flag} <file.json>")
            sys.exit(2)
    for flag, value in (("--consistency-check", consistency), ("--screensaver", play)):
        if value is not None and not Path(value).exists():
            print(f"error: {value} does not exist")
            sys.exit(1)
    if consistency is not None:
        screensaver, group_by_rule = consistency, True
    if play is not None and (review or screensaver is not None):
        print("note: --screensaver takes precedence over review flags")
    width, height, cell = 1200, 800, 4
    session = Session(width // cell, height // cell, review_mode=review,
                      screensaver_file=screensaver, group_by_rule=group_by_rule, play_file=play)
    Viewer(width, height, cell, session=session).run()


if __name__ == "__main__":
    main()
