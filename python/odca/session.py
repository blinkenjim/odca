"""Toolkit-free orchestration layer (spec R-U, R-K, R-B, R-O).

Everything the interactive program does except rendering pixels and reading
raw key events lives here, so it runs headlessly in tests and the pygame
layer (viewer.py) stays thin. The UI translates toolkit key events into the
single-character keys below, calls tick(dt) at its refresh rate, and draws
`history` with the palette for `color_set`.

Keys (single characters):
    q   quit
    r   new random rule, screened: candidates that look like Class I-III
        are discarded and regenerated until a maybe-Class-IV rule passes
        (served from the background-search stash when available)
    m   mutate the rule: change one randomly chosen entry to a new state
    u   undo the last rule change (r, m, n, p, u); repeatable
    s   save the current rule to interesting-rules.txt
    n   next saved interesting rule; stepping past the last saved rule
        returns to the unsaved rule, when one exists
    p   previous saved interesting rule; stepping back from rule 0 returns
        to the unsaved rule, when one exists
    i   initialize all cells to random contents
    +   speed up (halve the delay between generations)
    -   slow down (double the delay between generations)
    0-9 select a color set (0: CoCo set 0, 1: CoCo set 1, 2: default)
    ' ' pause / resume; while paused every key but space, Return, and q
        is ignored
    '\\n' (Return) while paused: compute and display one generation
        (single step), remaining paused; ignored when not paused
    s   while paused: run one screenful of generations at one eighth the
        current delay, then remain paused; each press queues another
        screenful (when not paused, 's' saves the rule as above)

Resuming from pause with space (re)starts a screen counter: from then on,
every completed screenful of generations prints 'screen N', however the
generations were computed (running, zipping, or single-stepping).
    a   toggle auto-init (off at startup): once every row on screen is
        boring — a state the rule can produce has gone extinct (and no
        other minority state is still alive), the rows are repeating, or
        the minority population has been stagnant for several screens —
        re-initialize the cells as 'i' does

At startup, if the loaded rule matches a saved rule the cycle position
points at it (so n/p step to its neighbors); otherwise the position is the
unsaved slot, so the first n selects rule 0 and the first p the last rule.
"""

from collections import Counter, deque

import numpy as np

from .automaton import N_STATES, Automaton, Rule
from .classify import find_candidate
from .search import CandidateSearch
from .store import Store

DEFINED_COLOR_SETS = 3  # slots 0-2; 3-9 reserved (R-U4)
DEFAULT_COLOR_SET = 2
INITIAL_DELAY = 1 / 60  # seconds between generations (R-U5)
MIN_DELAY = 1 / 16384  # R-K8
MAX_DELAY = 8.0
MAX_CANDIDATES = 64  # stash cap; background workers throttle once full (R-S3)
MINORITY_FRACTION = 0.10  # a producible state below this share is a minority (R-A1)
STAGNATION_SCREENS = 4  # minority population steady this many screens -> stagnant
STAGNATION_SWING = 0.25  # (max - min) / mean below this counts as steady
STEP_CAP = 2000  # per-tick catch-up cap so a stall can't freeze the UI (R-U5)
SCREEN_SPEEDUP = 8  # paused 's' zips a screenful at delay / SCREEN_SPEEDUP (R-K13)

KEY_SPACE = " "
KEY_RETURN = "\n"


class Session:
    def __init__(self, cols, rows, store=None, search=None, rng=None):
        self.cols = cols
        self.rows = rows
        self.store = store if store is not None else Store()
        self.search = search if search is not None else CandidateSearch()
        self.rng = rng if rng is not None else np.random.default_rng()

        # Startup per R-U1: previous rule (random fallback), random cells.
        rule = self.store.load_rule() or Rule.random(self.rng)
        self.automaton = Automaton(cols, rule=rule, seed="random", rng=self.rng)
        self.store.save_rule(rule)

        # history[i] is a row of cells; row 0 is the oldest visible generation.
        self.history = np.zeros((rows, cols), dtype=np.uint8)
        self.filled = 0
        self.delay = INITIAL_DELAY
        self.paused = False
        self.screen_remaining = 0  # generations still to zip after a paused 's'
        self.screen_counter = None  # screenfuls since the last resume; None = inactive
        self._counted = 0  # generations since the counter started
        self.color_set = DEFAULT_COLOR_SET
        self.undo_stack = []
        self._accumulated = 0.0
        self.auto_init = False  # R-K12: off at startup, not persisted
        self._boring_streak = 0
        self._boring_reason = None
        self._recent_rows = deque()  # row bytes of the last `rows` generations
        self._recent_counts = Counter()
        # minority-state cell counts over the last STAGNATION_SCREENS screens
        self._minority_counts = deque(maxlen=STAGNATION_SCREENS * rows)

        # The saved rules form a cycle with one extra slot for the "unsaved"
        # rule — the one running before browsing began. index None = on it.
        # If the startup rule is itself a saved rule, point the cycle at it
        # and leave the unsaved slot empty until 'r' or 'm' fills it (R-B3).
        saved = self.store.load_interesting()
        if rule in saved:
            self.interesting_index = saved.index(rule)
            self.unsaved_rule = None
        else:
            self.interesting_index = None
            self.unsaved_rule = rule

        self.candidates = self.store.load_candidates()
        self._push(self.automaton.cells)
        print(f"rule {rule.id}")

    @property
    def rule(self):
        return self.automaton.rule

    @property
    def rule_id(self):
        return self.automaton.rule.id

    def start_search(self):
        self.search.start()

    def stop_search(self):
        self.search.stop()

    def _push(self, row):
        if self.filled < self.rows:
            self.history[self.filled] = row
            self.filled += 1
        else:
            self.history[:-1] = self.history[1:]
            self.history[-1] = row

    def _advance(self):
        """Compute one generation, display it, and apply auto-init (R-A)."""
        row = self.automaton.step()
        self._push(row)
        self._observe(row)
        if self.screen_counter is not None:  # R-K14
            self._counted += 1
            if self._counted % self.rows == 0:
                self.screen_counter += 1
                print(f"screen {self.screen_counter}")  # R-O7
        if self.auto_init and self._boring_streak >= self.rows:
            reason = self._boring_reason
            self.init_cells()
            print(f"auto-init ({reason})")  # R-O6

    def _observe(self, row):
        """Classify a computed generation as boring or not (R-A1)."""
        key = row.tobytes()
        repeating = self._recent_counts[key] > 0
        self._recent_rows.append(key)
        self._recent_counts[key] += 1
        if len(self._recent_rows) > self.rows:
            old = self._recent_rows.popleft()
            self._recent_counts[old] -= 1
            if self._recent_counts[old] == 0:
                del self._recent_counts[old]
        census = np.bincount(row, minlength=N_STATES)
        producible = sorted(set(int(s) for s in self.automaton.rule.states))
        extinct = [s for s in producible if census[s] == 0]
        # A living minority is a shrinking (or drifting) group whose fate is
        # still unresolved; an extinction only counts once none remain.
        minority = [s for s in producible if 0 < census[s] < MINORITY_FRACTION * len(row)]
        living_minority = bool(minority)
        self._minority_counts.append(int(sum(census[s] for s in minority)))
        stagnant = False
        if len(self._minority_counts) == self._minority_counts.maxlen:
            lo, hi = min(self._minority_counts), max(self._minority_counts)
            mean = sum(self._minority_counts) / len(self._minority_counts)
            # A steady minority population is a structure drifting in parallel
            # with nothing growing or shrinking: long-period repetition.
            stagnant = mean > 0 and (hi - lo) / mean < STAGNATION_SWING
        if extinct and not living_minority:
            plural = "s" if len(extinct) > 1 else ""
            reason = f"state{plural} {', '.join(map(str, extinct))} extinct"
        elif repeating:
            reason = "repeating"
        elif stagnant:
            reason = "stagnant"
        else:
            reason = None
        if reason is None:
            self._boring_streak = 0
        else:
            self._boring_streak += 1
        self._boring_reason = reason

    def _reset_boredom(self):  # R-A3
        self._boring_streak = 0
        self._boring_reason = None
        self._recent_rows.clear()
        self._recent_counts.clear()
        self._minority_counts.clear()

    def tick(self, dt):
        """Advance by elapsed wall-clock seconds (R-U5); call at ~60 Hz."""
        self._drain_search()
        self._accumulated += dt
        if self.paused:
            if self.screen_remaining > 0:  # R-K13: zip a queued screenful
                delay = self.delay / SCREEN_SPEEDUP
                steps = min(int(self._accumulated / delay), self.screen_remaining, STEP_CAP)
                self._accumulated -= steps * delay
                for _ in range(steps):
                    self._advance()
                self.screen_remaining -= steps
            if self.screen_remaining == 0:
                self._accumulated = 0.0  # no catch-up burst on resume (R-K10)
            return
        steps = int(self._accumulated / self.delay)
        self._accumulated -= steps * self.delay
        for _ in range(min(steps, STEP_CAP)):
            self._advance()

    def _drain_search(self):
        if len(self.candidates) < MAX_CANDIDATES:
            found = self.search.drain()
            if found:
                self.candidates.extend(found)
                del self.candidates[MAX_CANDIDATES:]
                self.store.save_candidates(self.candidates)

    def _set_rule(self, rule):
        self.automaton.rule = rule
        self._reset_boredom()
        self.store.save_rule(rule)
        print(f"rule {rule.id}")  # R-O1

    def _set_unsaved_rule(self, rule):
        """Make `rule` current and the occupant of the cycle's unsaved slot."""
        self.unsaved_rule = rule
        self.interesting_index = None
        self._set_rule(rule)

    def new_rule(self):  # R-K2
        self.undo_stack.append(self.automaton.rule)
        self._drain_search()
        if self.candidates:
            rule = self.candidates.pop(0)
            self.store.save_candidates(self.candidates)
        else:
            # Stash is empty (e.g. first run): search synchronously.
            rule, tries = find_candidate(self.rng)
            if tries > 1:
                print(f"discarded {tries - 1} rule{'s' if tries > 2 else ''}")  # R-O2
        self._set_unsaved_rule(rule)

    def mutate_rule(self):  # R-K3
        self.undo_stack.append(self.automaton.rule)
        self._set_unsaved_rule(self.automaton.rule.mutated(self.rng))

    def undo(self):  # R-K4
        if self.undo_stack:
            self._set_rule(self.undo_stack.pop())

    def save_interesting(self):  # R-K5
        self.store.append_interesting(self.automaton.rule)
        print(f"saved rule {self.automaton.rule.id}")  # R-O3

    def init_cells(self):  # R-K6
        self.automaton.reset("random")
        self._push(self.automaton.cells)
        self._reset_boredom()

    def select_interesting(self, step):  # R-B2, R-B3
        """Cycle through the saved rules plus the unsaved slot, if occupied.

        The cycle is [saved rule 0 .. n-1, unsaved rule]; index None means
        the unsaved slot, so from it 'n' selects rule 0 and 'p' rule n-1.
        When no unsaved rule exists (startup matched a saved rule and no
        'r'/'m' has fired), the cycle is just the n saved rules.
        """
        rules = self.store.load_interesting()
        if not rules:
            print("no saved interesting rules")  # R-O5
            return
        n = len(rules)
        total = n + 1 if self.unsaved_rule is not None else n
        at = n if self.interesting_index is None else self.interesting_index
        to = (at + step) % total
        self.undo_stack.append(self.automaton.rule)
        if to == n:  # only reachable when the unsaved slot is occupied
            self.interesting_index = None
            print("unsaved rule")  # R-O4
            self._set_rule(self.unsaved_rule)
        else:
            self.interesting_index = to
            print(f"interesting {to + 1}/{n}")  # R-O4
            self._set_rule(rules[to])

    def handle_key(self, key):
        """Apply a single-character key; return False when the program should quit."""
        if key == "q":
            return False
        if self.paused:  # R-K10: only space, Return, s, q are live
            if key == KEY_SPACE:
                self.paused = False
                self.screen_remaining = 0
                self.screen_counter = 0  # R-K14: resume (re)starts the screen counter
                self._counted = 0
            elif key == KEY_RETURN:
                self._advance()  # R-K11: single step, stay paused
            elif key == "s":
                self.screen_remaining += self.rows  # R-K13: queue a screenful
            return True
        if key == KEY_SPACE:
            self.paused = True
        elif key == "r":
            self.new_rule()
        elif key == "m":
            self.mutate_rule()
        elif key == "u":
            self.undo()
        elif key == "s":
            self.save_interesting()
        elif key == "n":
            self.select_interesting(1)
        elif key == "p":
            self.select_interesting(-1)
        elif key == "i":
            self.init_cells()
        elif key == "a":  # R-K12
            self.auto_init = not self.auto_init
            print(f"auto-init {'on' if self.auto_init else 'off'}")  # R-O6
        elif key == "+":
            self.delay = max(self.delay / 2, MIN_DELAY)
        elif key == "-":
            self.delay = min(self.delay * 2, MAX_DELAY)
        elif len(key) == 1 and key.isdigit():
            if int(key) < DEFINED_COLOR_SETS:
                self.color_set = int(key)
        return True
