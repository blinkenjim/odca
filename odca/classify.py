"""Heuristic behavior-class screening for rules.

Exact Wolfram-class membership is undecidable (Culik & Yu), so this module
screens behaviorally: run the rule from a random seed and measure what it
does. Two signals, applied in order:

1. Cycle detection. On a finite wrapped row every rule eventually cycles;
   hitting a repeat within the sample window means the transient and period
   are both short — Class I or II. Discard.

2. Input entropy (after Wuensche). Each step, the Shannon entropy of the
   distribution of rule-table entries that actually fired across the row.
   Class III runs hot and flat: high mean entropy, low variance. Class IV
   rules host localized structures against a regular background, so their
   entropy wanders: mid-range mean, high variance over time. We keep rules
   whose entropy variance is high — the maybe-Class-IV candidates.

Thresholds are calibrated so that roughly the most variance-rich few percent
of random rules pass. This is a sieve, not a proof: expect false positives,
and judge the survivors by eye.
"""

import numpy as np

from .automaton import Automaton, Rule

WIDTH = 256
TRANSIENT = 200  # generations to run before measuring
SAMPLE = 400  # generations measured

_MAX_ENTROPY = np.log2(20)  # normalization: all 20 table entries equally used

# Calibrated on 400 random rules (2026-09): ~31% cycle out as Class I/II;
# among the rest, mean normalized entropy is typically 0.5-0.96 and entropy
# std has 95th percentile ~0.055. Reject as Class III when mean entropy
# exceeds CHAOS_MEAN with std below FLAT_STD; accept as a candidate when std
# reaches CANDIDATE_STD (~4% of random rules pass).
CHAOS_MEAN = 0.80
FLAT_STD = 0.02
CANDIDATE_STD = 0.055


def evaluate(rule, rng=None):
    """Run one behavioral screening of `rule`; return a metrics dict.

    Keys: 'maybe_iv' (bool), 'reason' (str), 'score' (float, higher = more
    Class-IV-like), 'mean_entropy', 'std_entropy', 'cycle_period'
    (None if no cycle was seen).
    """
    rng = rng if rng is not None else np.random.default_rng()
    a = Automaton(WIDTH, rule=rule, seed="random", rng=rng)
    for _ in range(TRANSIENT):
        a.step()

    seen = {}
    entropies = []
    cycle_period = None
    for t in range(SAMPLE):
        key = a.cells.tobytes()
        if key in seen:
            cycle_period = t - seen[key]
            break
        seen[key] = t
        counts = np.bincount(a.neighborhood_sums(), minlength=49)
        p = counts[counts > 0] / a.width
        entropies.append(float(-(p * np.log2(p)).sum()) / _MAX_ENTROPY)
        a.step()

    if cycle_period is not None:
        return {
            "maybe_iv": False,
            "reason": f"cyclic (period {cycle_period})",
            "score": 0.0,
            "mean_entropy": float(np.mean(entropies)) if entropies else 0.0,
            "std_entropy": 0.0,
            "cycle_period": cycle_period,
        }

    mean = float(np.mean(entropies))
    std = float(np.std(entropies))
    if std >= CANDIDATE_STD:
        maybe_iv, reason = True, "candidate"
    elif mean > CHAOS_MEAN and std < FLAT_STD:
        maybe_iv, reason = False, "chaotic"
    else:
        maybe_iv, reason = False, "flat"
    return {
        "maybe_iv": maybe_iv,
        "reason": reason,
        "score": std,
        "mean_entropy": mean,
        "std_entropy": std,
        "cycle_period": None,
    }


def find_candidate(rng=None, max_tries=200):
    """Generate random rules until one passes the maybe-Class-IV screen.

    Returns (rule, tries). If max_tries rules all fail, returns the
    best-scoring one seen — the caller always gets a rule.
    """
    rng = rng if rng is not None else np.random.default_rng()
    best, best_score = None, -1.0
    for i in range(1, max_tries + 1):
        rule = Rule.random(rng)
        metrics = evaluate(rule, rng=rng)
        if metrics["maybe_iv"]:
            return rule, i
        if metrics["score"] > best_score:
            best, best_score = rule, metrics["score"]
    return best, max_tries
