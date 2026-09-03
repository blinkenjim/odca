"""Count-based four-state, radius-1 cellular automaton.

Each cell has one of 4 states. A cell's next state depends only on how many
cells of its 3-cell neighborhood (left, self, right) are in each state — not
on which cell holds which state. There are 20 possible count vectors
(n0, n1, n2, n3) with n0+n1+n2+n3 = 3, so a rule is a table of 20 next
states: a rule space of 4^20 ≈ 1.1e12.

Lookup uses the summing trick from the original 6809 version: weight the
states 0, 1, 4, 16 and sum the neighborhood. Because no count can exceed 3,
the sum n1 + 4*n2 + 16*n3 uniquely encodes the count vector.
"""

import numpy as np

N_STATES = 4
NEIGHBORHOOD = 3  # left, self, right

_WEIGHTS = np.array([0, 1, 4, 16], dtype=np.uint8)
_DENSE_SIZE = 3 * 16 + 1  # max weighted sum is 3 cells of state 3


def count_vectors():
    """All (n0, n1, n2, n3) with sum 3, in lexicographic order. 20 of them."""
    return [
        (n0, n1, n2, NEIGHBORHOOD - n0 - n1 - n2)
        for n0 in range(NEIGHBORHOOD + 1)
        for n1 in range(NEIGHBORHOOD - n0 + 1)
        for n2 in range(NEIGHBORHOOD - n0 - n1 + 1)
    ]


COUNT_VECTORS = count_vectors()
RULE_SIZE = len(COUNT_VECTORS)  # 20


class Rule:
    """Maps each of the 20 neighborhood count-vectors to a next state.

    A rule's shareable ID is its 20 next-states written as base-4 digits,
    in COUNT_VECTORS order.
    """

    def __init__(self, states):
        states = np.asarray(states, dtype=np.uint8)
        if states.shape != (RULE_SIZE,):
            raise ValueError(f"rule needs {RULE_SIZE} entries, got {states.shape}")
        if (states >= N_STATES).any():
            raise ValueError(f"rule entries must be in 0..{N_STATES - 1}")
        self.states = states
        self.dense = np.zeros(_DENSE_SIZE, dtype=np.uint8)
        for (n0, n1, n2, n3), s in zip(COUNT_VECTORS, states):
            self.dense[n1 + 4 * n2 + 16 * n3] = s

    @property
    def id(self):
        return "".join(str(s) for s in self.states)

    @classmethod
    def from_id(cls, rule_id):
        if len(rule_id) != RULE_SIZE or not set(rule_id) <= set("0123"):
            raise ValueError(
                f"rule ID must be {RULE_SIZE} digits 0-3, got {rule_id!r}"
            )
        return cls([int(ch) for ch in rule_id])

    @classmethod
    def random(cls, rng=None):
        rng = rng if rng is not None else np.random.default_rng()
        return cls(rng.integers(0, N_STATES, RULE_SIZE, dtype=np.uint8))

    def mutated(self, rng=None):
        """Return a copy with one randomly chosen entry changed to a different state."""
        rng = rng if rng is not None else np.random.default_rng()
        states = self.states.copy()
        i = rng.integers(RULE_SIZE)
        states[i] = (states[i] + rng.integers(1, N_STATES)) % N_STATES
        return Rule(states)

    def __eq__(self, other):
        return isinstance(other, Rule) and np.array_equal(self.states, other.states)

    def __repr__(self):
        return f"Rule({self.id})"


class Automaton:
    """A fixed-width row of 4-state cells evolving under a count-based Rule."""

    def __init__(self, width, rule=None, seed="single", wrap=True, rng=None):
        if width < 3:
            raise ValueError(f"width must be at least 3, got {width}")
        self.width = width
        self.wrap = wrap
        self.rng = rng if rng is not None else np.random.default_rng()
        self.rule = rule if rule is not None else Rule.random(self.rng)
        self.reset(seed)

    def reset(self, seed="single"):
        """Reset the row. seed is 'single', 'random', or an array of states."""
        if isinstance(seed, str):
            if seed == "single":
                self.cells = np.zeros(self.width, dtype=np.uint8)
                self.cells[self.width // 2] = 1
            elif seed == "random":
                self.cells = self.rng.integers(
                    0, N_STATES, self.width, dtype=np.uint8
                )
            else:
                raise ValueError(f"unknown seed {seed!r}")
        else:
            cells = np.asarray(seed, dtype=np.uint8)
            if cells.shape != (self.width,):
                raise ValueError(f"seed must have shape ({self.width},)")
            if (cells >= N_STATES).any():
                raise ValueError(f"seed states must be in 0..{N_STATES - 1}")
            self.cells = cells
        self.generation = 0

    def neighborhood_sums(self):
        """Weighted neighborhood sums (rule-table indices) for the current row."""
        w = _WEIGHTS[self.cells]
        if self.wrap:
            left, right = np.roll(w, 1), np.roll(w, -1)
        else:
            # Cells beyond the edges are permanently state 0 (weight 0).
            left = np.concatenate(([0], w[:-1])).astype(np.uint8)
            right = np.concatenate((w[1:], [0])).astype(np.uint8)
        return left + w + right

    def step(self):
        """Advance one generation and return the new row."""
        self.cells = self.rule.dense[self.neighborhood_sums()]
        self.generation += 1
        return self.cells

    def run(self, generations):
        """Return a (generations+1, width) array: the current row plus each step."""
        history = np.empty((generations + 1, self.width), dtype=np.uint8)
        history[0] = self.cells
        for i in range(1, generations + 1):
            history[i] = self.step()
        return history
