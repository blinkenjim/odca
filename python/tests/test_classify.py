import numpy as np

from odca.automaton import Rule
from odca.classify import evaluate, find_candidate


def test_all_zero_rule_is_rejected_as_cyclic():
    # Everything maps to state 0: collapses to a fixed point immediately.
    metrics = evaluate(Rule([0] * 20), rng=np.random.default_rng(0))
    assert metrics["cycle_period"] == 1
    assert not metrics["maybe_iv"]


def test_evaluate_returns_expected_metrics():
    metrics = evaluate(Rule.random(np.random.default_rng(5)),
                       rng=np.random.default_rng(6))
    assert set(metrics) == {
        "maybe_iv", "reason", "score",
        "mean_entropy", "std_entropy", "cycle_period",
    }
    assert 0.0 <= metrics["mean_entropy"] <= 1.0
    assert metrics["score"] >= 0.0


def test_find_candidate_returns_a_rule():
    rule, tries = find_candidate(np.random.default_rng(8))
    assert isinstance(rule, Rule)
    assert tries >= 1


def test_find_candidate_fallback_returns_best_seen():
    # With max_tries=1 the single rule is returned whether or not it passed.
    rule, tries = find_candidate(np.random.default_rng(9), max_tries=1)
    assert isinstance(rule, Rule)
    assert tries == 1
