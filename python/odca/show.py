"""Play scripts (R-X7) and the show odca plays (R-X1).

The script parser is one C program shared by every implementation
(script/show.l, script/show.y; the generated C in odca/cshow/ is built
into odca._show by pip install and loaded here through ctypes). It turns a
script into JSON; this module resolves the imports and hands odca its
show: one segment per command-line file, each a list of pairs.
"""

import ctypes
import importlib.util
import json
from pathlib import Path

from .store import load_odca_file, load_seeds, merge_seed_maps


class ShowError(Exception):
    """A script or file that cannot be played; the message is for the user."""


_lib = None


def _library():
    global _lib
    if _lib is None:
        spec = importlib.util.find_spec("odca._show")
        if spec is None or not spec.origin:
            raise ImportError("odca._show is not built: in python/, run .venv/bin/pip install -e '.[test]'")
        lib = ctypes.CDLL(spec.origin)
        lib.show_parse.restype = ctypes.c_void_p
        lib.show_parse.argtypes = [ctypes.c_char_p]
        lib.show_free.argtypes = [ctypes.c_void_p]
        _lib = lib
    return _lib


def parse_json(text):
    """The parser's own JSON for a script (R-X7), byte for byte."""
    lib = _library()
    p = lib.show_parse(text.encode("utf-8"))
    try:
        return ctypes.string_at(p).decode("utf-8")
    finally:
        lib.show_free(p)


def parse(text):
    """A script's statements, [{'line', 'import': name} | {'line', 'play': True}],
    [{'line', 'import': name} | {'line', 'play': True} | {'line', 'shuffle':
    True}], or ShowError('line:column: message') at the first error."""
    result = json.loads(parse_json(text))
    if not result["ok"]:
        raise ShowError(f"{result['line']}:{result['column']}: {result['message']}")
    return result["statements"]


def _is_odca_file(path):
    try:
        root = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return False
    return isinstance(root, dict) and ("pairs" in root or "looks" in root)


def load_script(path):
    """What a script plays (R-X7): (pairs, shuffle, seeds) — every pair of
    every imported odca file in import order, or none when the script says
    neither `play` nor `shuffle`; which of the two it said; and the seeds
    of every imported file, merged (R-X4). Imports are relative to the
    script's directory."""
    path = Path(path)
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        raise ShowError(f"{path}: cannot read") from None
    try:
        statements = parse(text)
    except ShowError as e:
        raise ShowError(f"{path}:{e}") from None
    pairs, seeds, plays, shuffle = [], {}, False, False
    for statement in statements:
        if "import" in statement:
            name = statement["import"]
            target = path.parent / name
            if not target.exists():
                raise ShowError(f"{path}:{statement['line']}: cannot read {name}")
            if not _is_odca_file(target):
                raise ShowError(f"{path}:{statement['line']}: {name} is not an odca file")
            pairs.extend(load_odca_file(target))
            seeds = merge_seed_maps(seeds, load_seeds(target))
        else:
            plays, shuffle = True, "shuffle" in statement
    return (pairs, shuffle, seeds) if plays else ([], False, {})


def load_show(files):
    """The show for odca's command line (R-X1): one segment per file, in
    the order given, {'file': name, 'pairs': [...], 'shuffle': bool,
    'seeds': {rule: {width: [...]}}} (the recorded seeds of every odca
    file behind the segment, R-X4). A `.odca` file is its own script:
    import it, play it, unshuffled. Anything else is a play script."""
    segments = []
    for file in files:
        file = Path(file)
        if file.suffix == ".odca":
            pairs, shuffle, seeds = load_odca_file(file), False, load_seeds(file)
            if pairs is None:
                raise ShowError(f"{file}: cannot read")
        else:
            pairs, shuffle, seeds = load_script(file)
        segments.append({"file": file.name, "pairs": pairs, "shuffle": shuffle, "seeds": seeds})
    return segments
