"""Persistence for the current rule between runs."""

from pathlib import Path

from .automaton import Rule

DEFAULT_PATH = Path.home() / ".odca" / "rule"
CANDIDATES_PATH = Path.home() / ".odca" / "candidates"
INTERESTING_PATH = Path(__file__).resolve().parent.parent / "interesting-rules.txt"


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
