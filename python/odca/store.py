"""Persistence (R-P): per-user state in ~/.odca/, the keeper file at the repo root."""

from pathlib import Path

from .automaton import Rule

DEFAULT_PATH = Path.home() / ".odca" / "rule"
CANDIDATES_PATH = Path.home() / ".odca" / "candidates"
# Repository root: python/odca/store.py -> python/odca -> python -> root.
# The keeper file is shared by all implementations (R-P3).
INTERESTING_PATH = (
    Path(__file__).resolve().parent.parent.parent / "interesting-rules.txt"
)


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


def append_interesting(rule, path=INTERESTING_PATH):
    """Append the rule to the keeper file, matching its 'rule <id>' format."""
    with open(path, "a") as f:
        f.write(f"rule {rule.id}\n")


def load_interesting(path=INTERESTING_PATH):
    """Return the Rules in the keeper file, in order, skipping invalid lines."""
    try:
        lines = Path(path).read_text().splitlines()
    except OSError:
        return []
    rules = []
    for line in lines:
        parts = line.split()
        if len(parts) == 2 and parts[0] == "rule":
            try:
                rules.append(Rule.from_id(parts[1]))
            except ValueError:
                pass
    return rules


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

    def __init__(self, state_dir=None, keeper_file=None):
        self.state_dir = Path(state_dir) if state_dir else Path.home() / ".odca"
        self.keeper_file = Path(keeper_file) if keeper_file else INTERESTING_PATH

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

    def append_interesting(self, rule):
        append_interesting(rule, self.keeper_file)

    def load_interesting(self):
        return load_interesting(self.keeper_file)
