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

# R-M12: experimental rule classes (-x / --experiment). Every one but 0 brings
# the grandparent -- the cell's own state two generations back -- into the
# rule, making it a second-order automaton. That is a studied family: case 2 is
# Fredkin's construction, the standard way to make a reversible CA out of an
# irreversible one (Toffoli and Margolus, Cellular Automata Machines, 1987). A
# second-order rule is always a first-order rule on the doubled state
# (current, previous), so none of it is more powerful -- it is a differently
# shaped slice of that space. Since 3.93.0 an odca file records which class a
# pair's rule belongs to (R-P3), so all four can be kept in one file.
EXPERIMENTS = (0, 1, 2, 3)
NONE, MODAL, FREDKIN, TOTALISTIC4 = EXPERIMENTS


def counted_cells(experiment):
    """Cells whose states the rule counts: four under TOTALISTIC4, where the
    grandparent is counted like a neighbor."""
    return 4 if experiment == TOTALISTIC4 else NEIGHBORHOOD


def experiment_weights(experiment):
    """The summing trick of R-M7 generalized: one more than the counted cells
    as the radix makes a plain sum a unique index. Three cells give the
    familiar 0, 1, 4, 16; four give 0, 1, 5, 25."""
    radix = counted_cells(experiment) + 1
    return np.array([0, 1, radix, radix * radix], dtype=np.uint8)


def experiment_count_vectors(experiment):
    """The count vectors summing to the counted cells: 20 for three, 35 for four."""
    total = counted_cells(experiment)
    return [
        (n0, n1, n2, total - n0 - n1 - n2)
        for n0 in range(total + 1)
        for n1 in range(total - n0 + 1)
        for n2 in range(total - n0 - n1 + 1)
    ]


def experiment_dense_size(experiment):
    """Entries a weighted sum indexes: 49 for three counted cells, 101 for four."""
    return counted_cells(experiment) * int(experiment_weights(experiment)[3]) + 1


def experiment_rule_size(experiment):
    """Entries in a rule table, times four under MODAL where the grandparent
    chooses a column."""
    n = len(experiment_count_vectors(experiment))
    return n * N_STATES if experiment == MODAL else n


# R-P3: what an odca file's `experiment` key says, and reads back. The ODCA
# writes no key at all, so every file written before R-M12 stays exactly what
# it was and reads as what it always meant.
EXPERIMENT_NAMES = {MODAL: "modal", FREDKIN: "fredkin", TOTALISTIC4: "totalistic4"}


def experiment_named(text):
    """The class an `experiment` key names, or None for one this version does
    not know. A missing key is the ODCA."""
    if text is None:
        return NONE
    for experiment, name in EXPERIMENT_NAMES.items():
        if name == text:
            return experiment
    return None


def seed_key(experiment, rule_id):
    """The key a rule's seeds are recorded under (R-P3). An ODCA rule keeps
    the bare ID it always had; another class qualifies it, since 20 digits
    mean two different automata once FREDKIN exists."""
    name = EXPERIMENT_NAMES.get(experiment)
    return f"{name}:{rule_id}" if name else rule_id


def split_seed_key(key):
    """(class, rule ID) from such a key, or None if it names a class this
    version does not know."""
    if ":" not in key:
        return NONE, key
    name, _, rule_id = key.partition(":")
    experiment = experiment_named(name)
    return None if experiment is None else (experiment, rule_id)


class Rule:
    """Maps each of the 20 neighborhood count-vectors to a next state.

    A rule's shareable ID is its 20 next-states written as base-4 digits,
    in COUNT_VECTORS order.
    """

    def __init__(self, states, experiment=NONE):
        states = np.asarray(states, dtype=np.uint8)
        size = experiment_rule_size(experiment)
        if states.shape != (size,):
            raise ValueError(f"rule needs {size} entries, got {states.shape}")
        if (states >= N_STATES).any():
            raise ValueError(f"rule entries must be in 0..{N_STATES - 1}")
        self.experiment = experiment
        self.states = states
        # One dense lookup per grandparent state under MODAL, one otherwise;
        # a weighted neighborhood sum indexes within it (R-M7).
        w = experiment_weights(experiment)
        self.span = experiment_dense_size(experiment)
        blocks = N_STATES if experiment == MODAL else 1
        self.dense = np.zeros(self.span * blocks, dtype=np.uint8)
        for i, (n0, n1, n2, n3) in enumerate(experiment_count_vectors(experiment)):
            at = n1 * int(w[1]) + n2 * int(w[2]) + n3 * int(w[3])
            if experiment == MODAL:
                for g in range(N_STATES):
                    self.dense[g * self.span + at] = states[i * N_STATES + g]
            else:
                self.dense[at] = states[i]

    @property
    def id(self):
        return "".join(str(s) for s in self.states)

    @classmethod
    def from_id(cls, rule_id, experiment=NONE):
        size = experiment_rule_size(experiment)
        if len(rule_id) != size or not set(rule_id) <= set("0123"):
            raise ValueError(
                f"rule ID must be {size} digits 0-3, got {rule_id!r}"
            )
        return cls([int(ch) for ch in rule_id], experiment)

    @classmethod
    def random(cls, rng=None, experiment=NONE):
        rng = rng if rng is not None else np.random.default_rng()
        size = experiment_rule_size(experiment)
        return cls(rng.integers(0, N_STATES, size, dtype=np.uint8), experiment)

    def mutated(self, rng=None):
        """Return a copy with one randomly chosen entry changed to a different state."""
        rng = rng if rng is not None else np.random.default_rng()
        states = self.states.copy()
        i = rng.integers(len(states))
        states[i] = (states[i] + rng.integers(1, N_STATES)) % N_STATES
        return Rule(states, self.experiment)

    def __eq__(self, other):
        return (isinstance(other, Rule) and self.experiment == other.experiment
                and np.array_equal(self.states, other.states))

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
        # R-M12: a second-order rule reads the row before this one as each
        # cell's grandparent. Two independent random rows give it somewhere
        # to go; seeding the grandparent equal to the seed would start every
        # run from a standstill. Kept whatever the rule class, so the
        # boringness detector can judge the pair (R-A1).
        if self.rule.experiment != NONE and isinstance(seed, str) and seed == "random":
            self.previous = self.rng.integers(0, N_STATES, self.width, dtype=np.uint8)
        else:
            self.previous = self.cells.copy()
        self.generation = 0

    @property
    def state(self):
        """What is really the state of a second-order automaton (R-M12): the
        visible row and the one behind it. The boringness detector compares
        these rather than the row alone, since the same row reached from two
        different pasts has two different futures."""
        if self.rule.experiment == NONE:
            return self.cells
        return np.concatenate((self.cells, self.previous))

    def neighborhood_sums(self):
        """Weighted neighborhood sums (rule-table indices) for the current row.
        Under R-M12's TOTALISTIC4 the grandparent is counted as a fourth cell,
        so the weights are that experiment's, not case 0's."""
        weights = experiment_weights(self.rule.experiment)
        w = weights[self.cells]
        if self.wrap:
            left, right = np.roll(w, 1), np.roll(w, -1)
        else:
            # Cells beyond the edges are permanently state 0 (weight 0).
            left = np.concatenate(([0], w[:-1])).astype(np.uint8)
            right = np.concatenate((w[1:], [0])).astype(np.uint8)
        sums = left + w + right
        if self.rule.experiment == TOTALISTIC4:
            sums = sums + weights[self.previous]
        return sums

    def step(self):
        """Advance one generation and return the new row."""
        sums = self.neighborhood_sums()
        experiment = self.rule.experiment
        if experiment == MODAL:  # the grandparent picks the column
            nxt = self.rule.dense[self.previous.astype(np.intp) * self.rule.span + sums]
        elif experiment == FREDKIN:  # reversible: subtract the grandparent, mod 4
            nxt = (self.rule.dense[sums].astype(np.int16) - self.previous) % N_STATES
            nxt = nxt.astype(np.uint8)
        else:
            nxt = self.rule.dense[sums]
        self.previous = self.cells
        self.cells = nxt
        self.generation += 1
        return self.cells

    def run(self, generations):
        """Return a (generations+1, width) array: the current row plus each step."""
        history = np.empty((generations + 1, self.width), dtype=np.uint8)
        history[0] = self.cells
        for i in range(1, generations + 1):
            history[i] = self.step()
        return history
