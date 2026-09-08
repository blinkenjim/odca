"""Persistence (R-P): per-user state in ~/.odca/, the library and odca files."""

import json
from pathlib import Path

from .automaton import Rule

DEFAULT_PATH = Path.home() / ".odca" / "rule"
CANDIDATES_PATH = Path.home() / ".odca" / "candidates"
# Repository root: python/odca/store.py -> python/odca -> python -> root.
# The library is shared by all implementations (R-P4).
_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
LIBRARY_PATH = _REPO_ROOT / "library.json"  # the color set pool (R-P4)
CANDIDATE_PALETTES_PATH = _REPO_ROOT / "colorsets" / "candidates.json"  # raw pool source (R-V2)

# Built-in fallback so the default slot always exists (R-U4).
DEFAULT_COLOR_SETS = {1: {"name": "ODCA default", "colors": ["#121218", "#EBEBE1", "#FFA136", "#409CFF"]}}


def load_rule(path=DEFAULT_PATH):
    """Return the saved Rule, or None if the file is missing or invalid."""
    try:
        return Rule.from_id(Path(path).read_text().strip())
    except (OSError, ValueError):
        return None


def save_rule(rule, path=DEFAULT_PATH):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(rule.id + "\n")


def _valid_color(c):
    return (isinstance(c, str) and len(c) == 7 and c[0] == "#"
            and all(ch in "0123456789abcdefABCDEF" for ch in c[1:]))


def load_odca_file(path):
    """Return an odca file's pairs [{'name'?, 'rule', 'colorset', 'colors'}] (R-P3),
    None if the file is missing, [] if unparseable; malformed pairs are skipped.
    A pair's 'name' is present only when the file gives one. The 3.0.0
    key `looks` is still read.
    """
    try:
        text = Path(path).read_text()
    except OSError:
        return None
    try:
        root = json.loads(text)
        entries = root.get("pairs", root.get("looks", []))
    except (ValueError, AttributeError):
        return []
    pairs = []
    for e in entries if isinstance(entries, list) else []:
        try:
            rule = Rule.from_id(str(e["rule"]))
            set_name, colors = str(e["colorset"]), list(e["colors"])
        except (KeyError, TypeError, ValueError):
            continue
        if len(colors) == 4 and all(_valid_color(c) for c in colors):
            pair = {"rule": rule.id, "colorset": set_name, "colors": [c.upper() for c in colors]}
            if isinstance(e.get("name"), str):
                pair = {"name": e["name"], **pair}
            pairs.append(pair)
    return pairs


def save_odca_file(pairs, path):
    """Write an odca file (R-P3) in the shared layout: name (when the pair has one), rule, colorset, colors."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    entries = []
    for p in pairs:
        e = {"name": p["name"]} if p.get("name") is not None else {}
        e.update({"rule": p["rule"], "colorset": p["colorset"], "colors": list(p["colors"])})
        entries.append(e)
    path.write_text(json.dumps({"pairs": entries}, indent=1) + "\n")


def next_pair_name(pairs):
    """The next generated name, `pair-NNNN` (R-P3): one past the highest number
    in use in the file, four digits, more once they are needed."""
    used = [int(p["name"][5:]) for p in pairs
            if isinstance(p.get("name"), str) and p["name"].startswith("pair-") and p["name"][5:].isdigit()]
    return f"pair-{max(used, default=-1) + 1:04d}"


def load_color_set_file(path=LIBRARY_PATH):
    """Return {'sets': [...], 'dropped': [...]} from the library (R-P4).

    Each set is {'slot': int or None, 'name', 'colors'}; slotted sets are
    bound to digit keys, the rest form the pool. Malformed entries are
    skipped; a missing or unreadable file yields no sets.
    """
    result = {"sets": [], "dropped": []}
    try:
        root = json.loads(Path(path).read_text())
        entries = root.get("sets", [])
        dropped = root.get("dropped", [])
    except (OSError, ValueError, AttributeError):
        return result
    for e in entries if isinstance(entries, list) else []:
        try:
            name, colors = str(e["name"]), list(e["colors"])
        except (KeyError, TypeError):
            continue
        slot = e.get("slot")
        if slot is not None and not (isinstance(slot, int) and 0 <= slot <= 9):
            continue
        if len(colors) == 4 and all(_valid_color(c) for c in colors):
            result["sets"].append({"slot": slot, "name": name,
                                   "colors": [c.upper() for c in colors]})
    if isinstance(dropped, list):
        result["dropped"] = [str(n) for n in dropped]
    return result


def save_color_set_file(file, path=LIBRARY_PATH):
    """Write the whole pool: sets in the given order (slot omitted when None)."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    entries = []
    for e in file["sets"]:
        entry = {} if e.get("slot") is None else {"slot": e["slot"]}
        entry.update({"name": e["name"], "colors": list(e["colors"])})
        entries.append(entry)
    path.write_text(json.dumps({"sets": entries, "dropped": list(file["dropped"])}, indent=1) + "\n")


def load_color_sets(path=LIBRARY_PATH):
    """Return {slot: {'name', 'colors'}} for the digit-bound sets (R-U4).

    The built-in default fills slot 1 unless the file defines it.
    """
    sets = {k: {"name": v["name"], "colors": list(v["colors"])}
            for k, v in DEFAULT_COLOR_SETS.items()}
    for e in load_color_set_file(path)["sets"]:
        if e["slot"] is not None:
            sets[e["slot"]] = {"name": e["name"], "colors": list(e["colors"])}
    return sets


def save_color_sets(sets, path=LIBRARY_PATH):
    """Replace the digit-bound sets, preserving the pool and the dropped list."""
    file = load_color_set_file(path)
    slotted = [{"slot": slot, "name": v["name"], "colors": list(v["colors"])}
               for slot, v in sorted(sets.items())]
    pool = [e for e in file["sets"] if e["slot"] is None]
    save_color_set_file({"sets": slotted + pool, "dropped": file["dropped"]}, path)


def load_candidate_palettes(path=CANDIDATE_PALETTES_PATH):
    """Palettes from colorsets/candidates.json, the raw pool source (R-V2), slot None."""
    try:
        entries = json.loads(Path(path).read_text()).get("palettes", [])
    except (OSError, ValueError, AttributeError):
        return []
    out = []
    for e in entries if isinstance(entries, list) else []:
        try:
            name, colors = str(e["name"]), list(e["colors"])
        except (KeyError, TypeError):
            continue
        if len(colors) == 4 and all(_valid_color(c) for c in colors):
            out.append({"slot": None, "name": name, "colors": [c.upper() for c in colors]})
    return out


def load_candidates(path=CANDIDATES_PATH):
    """Return the saved candidate Rules, skipping any invalid lines."""
    try:
        lines = Path(path).read_text().splitlines()
    except OSError:
        return []
    rules = []
    for line in lines:
        try:
            rules.append(Rule.from_id(line.strip()))
        except ValueError:
            pass
    return rules


def save_candidates(rules, path=CANDIDATES_PATH):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(rule.id + "\n" for rule in rules))


class Store:
    """Persistence with configurable locations.

    The defaults are the real per-user state directory and the shared
    library; tests point everything at a temporary directory (R-P).
    """

    def __init__(self, state_dir=None, library_file=None, candidates_file=None):
        self.state_dir = Path(state_dir) if state_dir else Path.home() / ".odca"
        self.library_file = Path(library_file) if library_file else LIBRARY_PATH
        self.candidate_palettes_file = Path(candidates_file) if candidates_file else CANDIDATE_PALETTES_PATH

    @property
    def rule_file(self):
        return self.state_dir / "rule"

    @property
    def candidates_file(self):
        return self.state_dir / "candidates"

    def load_rule(self):
        return load_rule(self.rule_file)

    def save_rule(self, rule):
        save_rule(rule, self.rule_file)

    def load_candidates(self):
        return load_candidates(self.candidates_file)

    def save_candidates(self, rules):
        save_candidates(rules, self.candidates_file)

    def load_color_sets(self):
        return load_color_sets(self.library_file)

    def load_color_set_file(self):
        return load_color_set_file(self.library_file)

    def save_color_set_file(self, file):
        save_color_set_file(file, self.library_file)

    def load_candidate_palettes(self):
        return load_candidate_palettes(self.candidate_palettes_file)

    def save_color_sets(self, sets):
        save_color_sets(sets, self.library_file)
