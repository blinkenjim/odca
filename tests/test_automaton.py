import numpy as np
import pytest

from odca.automaton import (
    COUNT_VECTORS,
    N_STATES,
    RULE_SIZE,
    Automaton,
    Rule,
    count_vectors,
)


def make_rule(mapping):
    """Build a Rule sending each count-vector in `mapping` to its state, rest to 0."""
    states = [mapping.get(v, 0) for v in COUNT_VECTORS]
    return Rule(states)


def test_twenty_count_vectors():
    vs = count_vectors()
    assert len(vs) == 20
    assert len(set(vs)) == 20
    assert all(sum(v) == 3 for v in vs)


def test_weighted_sums_are_unique():
    sums = {n1 + 4 * n2 + 16 * n3 for (n0, n1, n2, n3) in COUNT_VECTORS}
    assert len(sums) == 20


def test_rule_id_round_trip():
    rule = Rule.random(np.random.default_rng(42))
    assert Rule.from_id(rule.id) == rule
    assert len(rule.id) == RULE_SIZE
    assert set(rule.id) <= set("0123")


def test_mutated_changes_exactly_one_entry():
    rng = np.random.default_rng(11)
    rule = Rule.random(rng)
    for _ in range(50):
        mutant = rule.mutated(rng)
        diffs = np.nonzero(rule.states != mutant.states)[0]
        assert len(diffs) == 1
        i = diffs[0]
        assert 0 <= mutant.states[i] < N_STATES
        assert mutant.states[i] != rule.states[i]
        rule = mutant


def test_bad_rule_ids_rejected():
    with pytest.raises(ValueError):
        Rule.from_id("0" * 19)
    with pytest.raises(ValueError):
        Rule.from_id("4" + "0" * 19)
    with pytest.raises(ValueError):
        Rule([0] * 19)
    with pytest.raises(ValueError):
        Rule([4] + [0] * 19)


def test_step_uses_counts():
    # Width 3 with wrap: every cell sees the same multiset {1, 2, 3},
    # i.e. count vector (0, 1, 1, 1).
    rule = make_rule({(0, 1, 1, 1): 2})
    a = Automaton(3, rule=rule, seed=[1, 2, 3])
    a.step()
    assert list(a.cells) == [2, 2, 2]


def test_permutation_invariance():
    # Reordering the same states must give the same next generation.
    rng = np.random.default_rng(7)
    rule = Rule.random(rng)
    # Width-3 wrap means all cells share one neighborhood multiset,
    # so both rows must be uniform and equal.
    a = Automaton(3, rule=rule, seed=[1, 2, 3])
    b = Automaton(3, rule=rule, seed=[3, 2, 1])
    ra, rb = a.step(), b.step()
    assert len(set(ra)) == 1
    assert list(ra) == list(rb)


def test_quiescent_background():
    # If (3,0,0,0) -> 0, an all-zero row stays all-zero.
    rule = make_rule({(3, 0, 0, 0): 0, (2, 1, 0, 0): 3})
    a = Automaton(9, rule=rule, seed=[0] * 9)
    a.step()
    assert not a.cells.any()


def test_wrap_vs_fixed_edges():
    # (2,1,0,0) -> 3: a lone state-1 cell lights its whole neighborhood.
    rule = make_rule({(2, 1, 0, 0): 3})
    a = Automaton(5, rule=rule, seed=[1, 0, 0, 0, 0], wrap=True)
    a.step()
    assert list(a.cells) == [3, 3, 0, 0, 3]  # wraps to the far edge
    b = Automaton(5, rule=rule, seed=[1, 0, 0, 0, 0], wrap=False)
    b.step()
    assert list(b.cells) == [3, 3, 0, 0, 0]  # edge cell sees implicit 0 outside


def test_seed_validation():
    with pytest.raises(ValueError):
        Automaton(5, seed=[4, 0, 0, 0, 0])
    with pytest.raises(ValueError):
        Automaton(5, seed=[0, 0, 0])
    with pytest.raises(ValueError):
        Automaton(5, seed="nonsense")


def test_generation_counter_and_run_shape():
    a = Automaton(16, rule=Rule.random(np.random.default_rng(1)))
    h = a.run(20)
    assert a.generation == 20
    assert h.shape == (21, 16)
    assert h.dtype == np.uint8
    assert (h < N_STATES).all()
    a.reset("random")
    assert a.generation == 0
