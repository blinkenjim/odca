"""Run the language-neutral conformance vectors against this implementation.

Any ODCA implementation, in any language, must pass conformance/vectors.json;
see TESTS.md. This is the Python runner.
"""

import json
from pathlib import Path

import pytest

from odca.automaton import COUNT_VECTORS, Automaton, Rule

# Repo root (two levels above python/tests/) holds the shared vectors file.
VECTORS = json.loads(
    (Path(__file__).resolve().parent.parent.parent / "conformance" / "vectors.json")
    .read_text()
)


def test_count_vector_canonical_order():
    assert [list(v) for v in COUNT_VECTORS] == VECTORS["count_vectors"]


@pytest.mark.parametrize("rule_id", VECTORS["valid_rule_ids"])
def test_valid_rule_ids_round_trip(rule_id):
    assert Rule.from_id(rule_id).id == rule_id


@pytest.mark.parametrize("rule_id", VECTORS["invalid_rule_ids"])
def test_invalid_rule_ids_rejected(rule_id):
    with pytest.raises(ValueError):
        Rule.from_id(rule_id)


@pytest.mark.parametrize(
    "case", VECTORS["evolution"], ids=[c["name"] for c in VECTORS["evolution"]]
)
def test_evolution(case):
    a = Automaton(
        len(case["initial"]),
        rule=Rule.from_id(case["rule"]),
        seed=[int(c) for c in case["initial"]],
        wrap=case["wrap"],
    )
    for generation, expected in enumerate(case["expected"], start=1):
        actual = "".join(str(c) for c in a.step())
        assert actual == expected, (
            f"{case['name']}: generation {generation} diverged"
        )
