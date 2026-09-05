"""Persistence (R-P): per-user state in ~/.odca/, the keeper file at the repo root."""

import json
from pathlib import Path

from .automaton import Rule

DEFAULT_PATH = Path.home() / ".odca" / "rule"
CANDIDATES_PATH = Path.home() / ".odca" / "candidates"
# Repository root: python/odca/store.py -> python/odca -> python -> root.
# The keeper file is shared by all implementations (R-P3).
_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
INTERESTING_PATH = _REPO_ROOT / "interesting-rules.json"  # screensaver-format pairs (R-P3)
COLORSETS_PATH = _REPO_ROOT / "colorsets" / "colorsets.json"  # shared (R-P4)

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


def load_interesting_pairs(path=INTERESTING_PATH):
    """Return the keeper file's pairs [{'rule', 'colorset', 'colors'}] (R-P3, R-P5).

    Malformed pairs are skipped; a missing or unparseable file yields none.
    """
    try:
        entries = json.loads(Path(path).read_text()).get("pairs", [])
    except (OSError, ValueError, AttributeError):
        return []
    pairs = []
    for e in entries if isinstance(entries, list) else []:
        try:
            rule = Rule.from_id(str(e["rule"]))
            name, colors = str(e["colorset"]), list(e["colors"])
        except (KeyError, TypeError, ValueError):
            continue
        if len(colors) == 4 and all(_valid_color(c) for c in colors):
            pairs.append({"rule": rule.id, "colorset": name, "colors": [c.upper() for c in colors]})
    return pairs


def save_interesting_pairs(pairs, path=INTERESTING_PATH):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    entries = [{"rule": p["rule"], "colorset": p["colorset"], "colors": list(p["colors"])} for p in pairs]
    path.write_text(json.dumps({"pairs": entries}, indent=1) + "\n")


def append_interesting(rule, path=INTERESTING_PATH, colorset=None, colors=None):
    """Append the rule, with its presentation, as a pair (default color set if none given)."""
    if colorset is None or colors is None:
        d = DEFAULT_COLOR_SETS[1]
        colorset, colors = d["name"], d["colors"]
    pairs = load_interesting_pairs(path)
    pairs.append({"rule": rule.id, "colorset": colorset, "colors": list(colors)})
    save_interesting_pairs(pairs, path)


def load_interesting(path=INTERESTING_PATH):
    """Return the saved Rules in order (one per pair)."""
    return [Rule.from_id(p["rule"]) for p in load_interesting_pairs(path)]


def _valid_color(c):
    return (isinstance(c, str) and len(c) == 7 and c[0] == "#"
            and all(ch in "0123456789abcdefABCDEF" for ch in c[1:]))


def load_color_set_file(path=COLORSETS_PATH):
    """Return {'sets': [...], 'dropped': [...]} from the color sets file (R-P4).

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


def save_color_set_file(file, path=COLORSETS_PATH):
    """Write the whole pool: sets in the given order (slot omitted when None)."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    entries = []
    for e in file["sets"]:
        entry = {} if e.get("slot") is None else {"slot": e["slot"]}
        entry.update({"name": e["name"], "colors": list(e["colors"])})
        entries.append(entry)
    path.write_text(json.dumps({"sets": entries, "dropped": list(file["dropped"])}, indent=1) + "\n")


def load_color_sets(path=COLORSETS_PATH):
    """Return {slot: {'name', 'colors'}} for the digit-bound sets (R-U4).

    The built-in default fills slot 1 unless the file defines it.
    """
    sets = {k: {"name": v["name"], "colors": list(v["colors"])}
            for k, v in DEFAULT_COLOR_SETS.items()}
    for e in load_color_set_file(path)["sets"]:
        if e["slot"] is not None:
            sets[e["slot"]] = {"name": e["name"], "colors": list(e["colors"])}
    return sets


def save_color_sets(sets, path=COLORSETS_PATH):
    """Replace the digit-bound sets, preserving the pool and the dropped list."""
    file = load_color_set_file(path)
    slotted = [{"slot": slot, "name": v["name"], "colors": list(v["colors"])}
               for slot, v in sorted(sets.items())]
    pool = [e for e in file["sets"] if e["slot"] is None]
    save_color_set_file({"sets": slotted + pool, "dropped": file["dropped"]}, path)


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
    keeper file; tests point both at a temporary directory (R-P).
    """

    def __init__(self, state_dir=None, keeper_file=None, colorsets_file=None):
        self.state_dir = Path(state_dir) if state_dir else Path.home() / ".odca"
        self.keeper_file = Path(keeper_file) if keeper_file else INTERESTING_PATH
        self.colorsets_file = Path(colorsets_file) if colorsets_file else COLORSETS_PATH

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

    def append_interesting(self, rule, colorset=None, colors=None):
        append_interesting(rule, self.keeper_file, colorset, colors)

    def load_interesting_pairs(self):
        return load_interesting_pairs(self.keeper_file)

    def load_interesting(self):
        return load_interesting(self.keeper_file)

    def load_color_sets(self):
        return load_color_sets(self.colorsets_file)

    def save_color_sets(self, sets):
        save_color_sets(sets, self.colorsets_file)
