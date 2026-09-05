"""Toolkit-free orchestration layer (spec R-U, R-K, R-B, R-A, R-V, R-W, R-X, R-O).

Everything the interactive program does except rendering pixels and reading
raw key events lives here, so it runs headlessly in tests and the pygame
layer (viewer.py) stays thin. The UI translates toolkit key events into the
single-character keys below, calls tick(dt) at its refresh rate, and draws
`history` through `palette8` and `row_banks`.

Keys (single characters):
    q   quit
    r   new random rule, screened: candidates that look like Class I-III
        are discarded and regenerated until a maybe-Class-IV rule passes
        (served from the background-search stash when available)
    m   mutate the rule: change one randomly chosen entry to a new state
    u   undo the last rule change (r, m, n, p, u); repeatable
    s   save the current rule with its presentation (the active color set,
        arranged) to interesting-rules.json
    n   next saved interesting rule, with its saved colors; stepping past the
        last returns to the unsaved rule, when one exists
    p   previous saved interesting rule; stepping back from rule 0 returns
        to the unsaved rule, when one exists
    i   initialize all cells to random contents
    +   speed up (halve the delay between generations)
    -   slow down (double the delay between generations)
    0-9 select a digit-bound color set — the "hot ten" (colorsets/colorsets.json)
    [ ] step backward / forward through the whole color set pool
    c   cycle the active color set through the 24 ways of assigning its
        four colors to the four states (remembered per set)
    C   the same cycle in reverse
    S   save the active color set, with its arrangement, into its pool entry
    ' ' pause / resume; while paused every key but space, Return, s, the
        color keys (c, C, S, [, ], digits), and q is ignored
    '\\n' (Return) while paused: compute and display one generation
        (single step), remaining paused; ignored when not paused
    s   while paused: run one screenful of generations at one eighth the
        current delay, then remain paused; each press queues another
        screenful (when not paused, 's' saves the rule as above)
    a   toggle auto-init (on at startup): once every row on screen is
        boring, re-initialize the cells as 'i' does

Resuming from pause with space (re)starts a screen counter: from then on,
every completed screenful of generations prints 'screen N'.

Modes (spec sections 4b-4d), selected at construction:
    review_mode        color set review: N/P ([ ]) step the pool, X drops,
                       every drop saves; digits disabled
    screensaver_file   screensaver review: N/P step the file's pairs, s saves
                       the pair under review, S appends, X deletes, [ ] walk
                       the pool; group_by_rule views the pairs grouped by rule
                       (consistency check) without touching file order
    play_file          screensaver mode: play the pairs in order, each for a
                       watchdog of PLAY_TIMEOUT seconds, then hand over after
                       PLAY_GRACE quiet seconds or at the next re-init; rows
                       keep the colors they were painted with
"""

from collections import Counter, deque
from itertools import permutations
from pathlib import Path

import numpy as np

from .automaton import N_STATES, Automaton, Rule
from .classify import find_candidate
from .search import CandidateSearch
from .store import DEFAULT_COLOR_SETS, Store, load_screensaver, save_screensaver

DEFAULT_COLOR_SET = 1  # slot active at startup (R-U4)
KEY_ORDER = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]  # digit keys in review order (R-V2, R-K17)
ARRANGEMENTS = list(permutations(range(4)))  # the 24 ways to assign 4 colors to 4 states
INITIAL_DELAY = 1 / 60  # seconds between generations (R-U5)
MIN_DELAY = 1 / 16384  # R-K8
MAX_DELAY = 8.0
MAX_CANDIDATES = 64  # stash cap; background workers throttle once full (R-S3)
REPEAT_SCREENS = 10  # a row recurring within this many screens is repeating (R-A1)
MINORITY_FRACTION = 0.10  # a producible state below this share is a minority (R-A1)
STAGNATION_SCREENS = 4  # minority population steady this many screens -> stagnant
STAGNATION_SWING = 0.25  # (max - min) / mean below this counts as steady
STEP_CAP = 2000  # per-tick catch-up cap so a stall can't freeze the UI (R-U5)
SMOOTH_SCROLL_DELAY = 2 * INITIAL_DELAY  # slower than this: continuous scrolling (R-U3)
SCREEN_SPEEDUP = 8  # paused 's' zips a screenful at delay / SCREEN_SPEEDUP (R-K13)
PLAY_TIMEOUT = 120.0  # screensaver: a pair's screen time before it may advance (R-X2)
PLAY_GRACE = 60.0  # screensaver: no transition within this long of an initialization (R-X3)

KEY_SPACE = " "
KEY_RETURN = "\n"


def _rgb(c):
    return tuple(int(c[j:j + 2], 16) for j in (1, 3, 5))


class Session:
    def __init__(self, cols, rows, store=None, search=None, rng=None,
                 review_mode=False, screensaver_file=None, group_by_rule=False, play_file=None):
        self.cols = cols
        self.rows = rows
        self.store = store if store is not None else Store()
        self.search = search if search is not None else CandidateSearch()
        self.rng = rng if rng is not None else np.random.default_rng()
        # Mode precedence: screensaver play, then screensaver review, then color set review.
        self.play_file = Path(play_file) if play_file else None
        if self.play_file is not None:
            screensaver_file = None
        self.screensaver_file = Path(screensaver_file) if screensaver_file else None
        self.review_mode = bool(review_mode) and self.screensaver_file is None and self.play_file is None
        self.group_by_rule = bool(group_by_rule) and self.screensaver_file is not None

        # Startup per R-U1: previous rule (random fallback), random cells.
        rule = self.store.load_rule() or Rule.random(self.rng)
        self.automaton = Automaton(cols, rule=rule, seed="random", rng=self.rng)
        self.store.save_rule(rule)

        # history[i] is a row of cells; row 0 is the oldest. One row more than
        # the display holds, so continuous scrolling has a row to slide in.
        # row_banks[i] is the palette bank each row was painted from (R-X5).
        self.history = np.zeros((rows + 1, cols), dtype=np.uint8)
        self.row_banks = np.zeros(rows + 1, dtype=np.uint8)
        self._bank = 0
        self._banks = None  # two banks of four hex colors, once play mode paints a row
        self.filled = 0
        self.delay = INITIAL_DELAY
        self.paused = False
        self.screen_remaining = 0  # generations still to zip after a paused 's'
        self.screen_counter = None  # screenfuls since the last resume; None = inactive
        self._counted = 0  # generations since the counter started
        self.undo_stack = []
        self._accumulated = 0.0
        self._zip_accumulated = 0.0
        self.auto_init = True  # R-K12: on at startup, not persisted
        self._boring_streak = 0
        self._boring_reason = None
        self._recent_rows = deque()  # row bytes of the last REPEAT_SCREENS screens
        self._recent_counts = Counter()
        # Brent's cycle detection: one saved row, refreshed at powers of two.
        self._brent_snapshot = None
        self._brent_power = 1
        self._brent_steps = 0
        self.cycle_period = None  # exact period once a cycle is detected
        # minority-state cell counts over the last STAGNATION_SCREENS screens
        self._minority_counts = deque(maxlen=STAGNATION_SCREENS * rows)

        # Colors (R-U4, R-K17): every mode but color set review draws through
        # the active set, which may be any pool member; it starts as the
        # default slot. Arrangements are remembered per set name.
        self.color_sets = self.store.load_color_sets()  # slot -> {name, colors} (R-P4)
        self.color_set = DEFAULT_COLOR_SET
        self._arrangement_by_name = {}
        self.pool = self._pool_order()
        d = self.color_sets[self.color_set]
        self.active_set = {"slot": self.color_set, "name": d["name"], "colors": list(d["colors"])}
        self.unsaved_set = dict(self.active_set)  # the set shown with the unsaved rule (R-B3)

        # Color set review (R-V)
        self.review_entries = []
        self.review_index = 0
        self.dropped_names = []
        self._review_arrangement = {}
        # Screensaver review (R-W): pairs in file order, presentation order, cursor
        self.pairs = []
        self.pair_index = None
        self.view_order = []
        self.view_position = None
        # Screensaver play (R-X)
        self.play_elapsed = 0.0  # unpaused seconds on the current pair
        self.since_init = 0.0  # unpaused seconds since the last (re)initialization

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
        if self.review_mode:
            self._load_review()
        if self.screensaver_file is not None:
            self._load_screensaver()
        if self.play_file is not None:
            self._load_play()

    # ------------------------------------------------------------------ basics

    @property
    def rule(self):
        return self.automaton.rule

    @property
    def rule_id(self):
        return self.automaton.rule.id

    @property
    def screensaver_mode(self):
        return self.screensaver_file is not None

    @property
    def play_mode(self):
        return self.play_file is not None

    def start_search(self):
        self.search.start()

    def stop_search(self):
        self.search.stop()

    def finish(self):
        """Call at program exit; color set review saves the kept sets (R-V5)."""
        if self.review_mode:
            self.save_review()

    # ------------------------------------------------------------------ colors

    @property
    def active_name(self):
        return self.active_set["name"]

    def _active_arrangement(self):
        return self._arrangement_by_name.get(self.active_name, 0)

    def _arranged_active_colors(self):
        base = self.active_set["colors"]
        return [base[i] for i in ARRANGEMENTS[self._active_arrangement()]]

    def _review_entry(self):
        return self.review_entries[self.review_index] if self.review_entries else None

    def _arranged_review_colors(self):
        e = self._review_entry()
        if e is None:
            return list(DEFAULT_COLOR_SETS[1]["colors"])
        return [e["colors"][i] for i in ARRANGEMENTS[self._review_arrangement.get(e["name"], 0)]]

    def _current_hex(self):
        return self._arranged_review_colors() if self.review_mode else self._arranged_active_colors()

    @property
    def palette(self):
        """The active color set as four (r, g, b) tuples, states 0-3, arranged."""
        return [_rgb(c) for c in self._current_hex()]

    @property
    def palette8(self):
        """Two banks of four (R-X5); outside screensaver mode both are the active set."""
        if self.play_mode and self._banks is not None:
            return [_rgb(c) for c in self._banks[0] + self._banks[1]]
        p = self.palette
        return p + p

    def color(self, row, col):
        """Display color of a history cell: its state through its row's bank."""
        return self.palette8[int(self.row_banks[row]) * 4 + int(self.history[row][col])]

    def cycle_colors(self, step=1):  # R-K15 ('c' forward, 'C' backward)
        n = len(ARRANGEMENTS)
        if self.review_mode:
            e = self._review_entry()
            if e is None:
                return
            index = (self._review_arrangement.get(e["name"], 0) + step) % n
            self._review_arrangement[e["name"]] = index
            print(f"color set {e['name']} arrangement {index + 1}/{n}")  # R-O9
            return
        index = (self._active_arrangement() + step) % n
        self._arrangement_by_name[self.active_name] = index
        print(f"color set {self.active_name} arrangement {index + 1}/{n}")  # R-O9

    def save_color_set(self):  # R-K16: bake the arrangement into the pool entry, by name
        name = self.active_name
        arranged = self._arranged_active_colors()
        file = self.store.load_color_set_file()
        for e in file["sets"]:
            if e["name"] == name:
                e["colors"] = list(arranged)
                break
        else:
            file["sets"].append({"slot": self.active_set.get("slot"), "name": name, "colors": list(arranged)})
        self.store.save_color_set_file(file)
        self._arrangement_by_name[name] = 0
        self.active_set["colors"] = list(arranged)
        self.color_sets = self.store.load_color_sets()
        self.pool = self._pool_order()
        print(f"saved color set {name}")  # R-O10

    def select_color_set(self, slot):  # R-K9
        if self.review_mode:
            return  # R-V1: digit keys are disabled during review
        s = self.color_sets.get(slot)
        if s is None:
            return  # undefined slot is a no-op
        self.color_set = slot
        self.active_set = {"slot": slot, "name": s["name"], "colors": list(s["colors"])}

    def _show_colors(self, name, colors):
        """Show a saved presentation: its colors become the active set (R-B2, R-W2)."""
        self.active_set = {"slot": None, "name": name, "colors": list(colors)}
        self._arrangement_by_name[name] = 0  # stored colors are already arranged

    def _pool_order(self):
        """The whole pool in review order: digit-bound sets by key, then the rest."""
        file = self.store.load_color_set_file()
        slotted = [e for e in file["sets"] if e["slot"] is not None]
        if not any(e["slot"] == 1 for e in slotted):
            d = DEFAULT_COLOR_SETS[1]
            slotted.append({"slot": 1, "name": d["name"], "colors": list(d["colors"])})
        slotted.sort(key=lambda e: KEY_ORDER.index(e["slot"]) if e["slot"] in KEY_ORDER else 10)
        return slotted + [e for e in file["sets"] if e["slot"] is None]

    def pool_step(self, step):  # R-K17: '[' / ']' walk the whole pool, wrapping
        if not self.pool:
            return
        names = [e["name"] for e in self.pool]
        current = names.index(self.active_name) if self.active_name in names else -1
        e = self.pool[(current + step) % len(self.pool)]
        self.active_set = {"slot": e["slot"], "name": e["name"], "colors": list(e["colors"])}
        if e["slot"] is not None:
            self.color_set = e["slot"]
        print(f"color set {e['name']}")  # R-O15

    # ------------------------------------------------------------------ display

    @property
    def scroll_offset(self):
        """How far the display is scrolled into the top history row, in cells (R-U3).

        0 while the buffer is still filling; 1 (newest row fully shown) when
        paused or at fast speeds; the fraction of the current delay that has
        elapsed when scrolling continuously, so the picture slides up at one
        cell per delay and the newest generation enters from the bottom.
        """
        if self.filled <= self.rows:
            return 0.0
        if self.paused or self.delay <= SMOOTH_SCROLL_DELAY:
            return 1.0
        return min(self._accumulated / self.delay, 1.0)

    def _push(self, row):
        if self.play_mode:
            # R-X5: a new color set takes the idle bank; rows already on
            # screen keep theirs until they scroll off.
            current = self._arranged_active_colors()
            if self._banks is None:
                self._banks = [list(current), list(current)]
            elif current != self._banks[self._bank]:
                self._bank ^= 1
                self._banks[self._bank] = list(current)
        if self.filled < self.rows + 1:
            self.history[self.filled] = row
            self.row_banks[self.filled] = self._bank
            self.filled += 1
        else:
            self.history[:-1] = self.history[1:]
            self.history[-1] = row
            self.row_banks[:-1] = self.row_banks[1:]
            self.row_banks[-1] = self._bank

    def _fill_screen(self):
        """Compute a screenful at once so a navigation shows only the new state (R-V7, R-W8)."""
        for _ in range(self.rows):
            self._advance()

    # ------------------------------------------------------------ evolution

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
            if self.play_mode and self.pairs and self.play_elapsed >= PLAY_TIMEOUT:
                self._next_play_pair(reason)  # R-X3: watchdog expired, a re-init transitions
            else:
                self.init_cells()
                print(f"auto-init ({reason})")  # R-O6

    def _observe(self, row):
        """Classify a computed generation as boring or not (R-A1)."""
        key = row.tobytes()
        # The automaton is deterministic, so a recurring row means the future
        # is periodic forever. Brent's algorithm finds a cycle of any period
        # with a single saved row: compare each new row to the snapshot, and
        # move the snapshot forward whenever the step count reaches a power
        # of two. On a hit, the steps since the snapshot are exactly the period.
        if self.cycle_period is None:
            if self._brent_snapshot is None:
                self._brent_snapshot = key
            else:
                self._brent_steps += 1
                if key == self._brent_snapshot:
                    self.cycle_period = self._brent_steps
                    print(f"cycle period {self.cycle_period}")  # R-O8
                elif self._brent_steps == self._brent_power:
                    self._brent_snapshot = key
                    self._brent_power *= 2
                    self._brent_steps = 0
        repeating = self._recent_counts[key] > 0
        self._recent_rows.append(key)
        self._recent_counts[key] += 1
        if len(self._recent_rows) > REPEAT_SCREENS * self.rows:
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
        elif self.cycle_period is not None:
            reason = f"repeating (period {self.cycle_period})"
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
        self._brent_snapshot = None
        self._brent_power = 1
        self._brent_steps = 0
        self.cycle_period = None

    def tick(self, dt):
        """Advance by elapsed wall-clock seconds (R-U5); call at ~60 Hz."""
        self._drain_search()
        if self.paused:
            # The main accumulator is frozen while paused (no catch-up burst,
            # R-K10); a queued screenful (R-K13) paces on its own accumulator.
            if self.screen_remaining > 0:
                self._zip_accumulated += dt
                delay = self.delay / SCREEN_SPEEDUP
                steps = min(int(self._zip_accumulated / delay), self.screen_remaining, STEP_CAP)
                self._zip_accumulated -= steps * delay
                for _ in range(steps):
                    self._advance()
                self.screen_remaining -= steps
            if self.screen_remaining == 0:
                self._zip_accumulated = 0.0
            return
        self._accumulated += dt
        # Clocks advance before the generations, so a re-seed made by those
        # generations restarts the grace period from this instant (R-X3).
        self.since_init += dt
        if self.play_mode:
            self.play_elapsed += dt
        steps = int(self._accumulated / self.delay)
        self._accumulated -= steps * self.delay
        for _ in range(min(steps, STEP_CAP)):
            self._advance()
        if (self.play_mode and self.pairs  # R-X3: watchdog expired and the grace period observed
                and self.play_elapsed >= PLAY_TIMEOUT and self.since_init >= PLAY_GRACE):
            self._next_play_pair("timeout")

    def _drain_search(self):
        if len(self.candidates) < MAX_CANDIDATES:
            found = self.search.drain()
            if found:
                self.candidates.extend(found)
                del self.candidates[MAX_CANDIDATES:]
                self.store.save_candidates(self.candidates)

    # ------------------------------------------------------------------ rules

    def _set_rule(self, rule):
        self.automaton.rule = rule
        self._reset_boredom()
        self.store.save_rule(rule)
        print(f"rule {rule.id}")  # R-O1

    def _set_unsaved_rule(self, rule):
        """Make `rule` current and the occupant of the cycle's unsaved slot."""
        self.unsaved_rule = rule
        self.unsaved_set = dict(self.active_set)
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

    def _current_pair(self):
        return {"rule": self.automaton.rule.id, "colorset": self.active_name,
                "colors": self._arranged_active_colors()}

    def save_interesting(self):  # R-K5: the rule with its presentation
        pair = self._current_pair()
        self.store.append_interesting(self.automaton.rule, pair["colorset"], pair["colors"])
        print(f"saved rule {pair['rule']} {pair['colorset']}")  # R-O3

    def init_cells(self):  # R-K6
        self.automaton.reset("random")
        self._push(self.automaton.cells)
        self._reset_boredom()
        self.since_init = 0.0  # R-X3: any initialization restarts the grace period

    def select_interesting(self, step):  # R-B2, R-B3
        """Cycle through the saved pairs plus the unsaved slot, if occupied.

        The cycle is [saved pair 0 .. n-1, unsaved rule]; index None means
        the unsaved slot, so from it 'n' selects pair 0 and 'p' pair n-1.
        When no unsaved rule exists (startup matched a saved rule and no
        'r'/'m' has fired), the cycle is just the n saved pairs. A saved pair
        brings its colors along; the unsaved slot brings back the set that
        was showing when the unsaved rule arrived.
        """
        pairs = self.store.load_interesting_pairs()
        if not pairs:
            print("no saved interesting rules")  # R-O5
            return
        n = len(pairs)
        total = n + 1 if self.unsaved_rule is not None else n
        at = n if self.interesting_index is None else self.interesting_index
        to = (at + step) % total
        self.undo_stack.append(self.automaton.rule)
        if to == n:  # only reachable when the unsaved slot is occupied
            self.interesting_index = None
            print("unsaved rule")  # R-O4
            self._set_rule(self.unsaved_rule)
            if self.unsaved_set is not None:
                self._show_colors(self.unsaved_set["name"], self.unsaved_set["colors"])
        else:
            self.interesting_index = to
            pair = pairs[to]
            print(f"interesting {to + 1}/{n} {pair['colorset']}")  # R-O4
            self._set_rule(Rule.from_id(pair["rule"]))
            self._show_colors(pair["colorset"], pair["colors"])

    # -------------------------------------------------------- color set review

    def _load_review(self):  # R-V2
        file = self.store.load_color_set_file()
        slotted = [e for e in file["sets"] if e["slot"] is not None]
        if not any(e["slot"] == 1 for e in slotted):
            d = DEFAULT_COLOR_SETS[1]
            slotted.append({"slot": 1, "name": d["name"], "colors": list(d["colors"])})
        slotted.sort(key=lambda e: KEY_ORDER.index(e["slot"]) if e["slot"] in KEY_ORDER else 10)
        entries = slotted + [e for e in file["sets"] if e["slot"] is None]
        self.dropped_names = list(file["dropped"])
        names = {e["name"] for e in entries}
        dropped = set(file["dropped"])
        for p in self.store.load_candidate_palettes():
            if p["name"] not in names and p["name"] not in dropped:
                entries.append(p)
                names.add(p["name"])
        self.review_entries = entries
        self.review_index = 0
        self._announce_review()

    def _announce_review(self):  # R-O11
        e = self._review_entry()
        if e is None:
            print("review empty")
            return
        print(f"review {self.review_index + 1}/{len(self.review_entries)} {e['name']}")

    def review_step(self, step):  # R-V3
        if not self.review_entries:
            return
        index = self.review_index + step
        if index >= len(self.review_entries):
            index = 0
            print("review wrapped")
        elif index < 0:
            index = len(self.review_entries) - 1
            print("review wrapped")
        self.review_index = index
        self._announce_review()
        self._fill_screen()  # R-V7

    def drop_review(self):  # R-V4
        e = self._review_entry()
        if e is None:
            return
        del self.review_entries[self.review_index]
        self.dropped_names.append(e["name"])
        self._review_arrangement.pop(e["name"], None)
        print(f"dropped {e['name']}")
        if self.review_index >= len(self.review_entries) and self.review_entries:
            self.review_index = 0
            print("review wrapped")
        self._announce_review()
        self.save_review()  # R-V5: every drop is saved at once
        if self.review_entries:
            self._fill_screen()  # R-V7

    def save_review(self):  # R-V5
        """The first ten kept sets in review order own the digit keys (1-9, 0);
        the rest are pool-only; arrangements are preview only (R-V6)."""
        kept = []
        for i, e in enumerate(self.review_entries):
            kept.append({"slot": KEY_ORDER[i] if i < len(KEY_ORDER) else None,
                         "name": e["name"], "colors": list(e["colors"])})
        self.review_entries = kept
        ordered = sorted([e for e in kept if e["slot"] is not None], key=lambda e: e["slot"]) \
            + [e for e in kept if e["slot"] is None]
        self.store.save_color_set_file({"sets": ordered, "dropped": list(self.dropped_names)})
        self.color_sets = self.store.load_color_sets()
        print(f"saved {len(kept)} color sets, {len(self.dropped_names)} dropped")  # R-O11

    # ------------------------------------------------------- screensaver review

    def _load_screensaver(self):  # R-W1, R-W2
        loaded = load_screensaver(self.screensaver_file)
        if loaded is None:
            self.pairs = []
            save_screensaver(self.pairs, self.screensaver_file)  # a new, empty file
        else:
            self.pairs = loaded
        self._rebuild_view_order()
        print(f"screensaver {self.screensaver_file.name}: {len(self.pairs)} pairs")
        if self.pairs:
            self._activate(0)

    def _rebuild_view_order(self):  # R-W7: presentation order only
        if self.group_by_rule:
            groups, rule_order = {}, []
            for i, p in enumerate(self.pairs):
                if p["rule"] not in groups:
                    groups[p["rule"]] = []
                    rule_order.append(p["rule"])
                groups[p["rule"]].append(i)
            self.view_order = [i for r in rule_order for i in groups[r]]
        else:
            self.view_order = list(range(len(self.pairs)))
        self.view_position = (self.view_order.index(self.pair_index)
                              if self.pair_index is not None and self.pair_index in self.view_order else None)

    def _rule_group(self, index):
        seen = []
        for p in self.pairs:
            if p["rule"] not in seen:
                seen.append(p["rule"])
        return seen.index(self.pairs[index]["rule"]) + 1, len(seen)

    def _activate(self, position):  # R-W2, R-W8
        index = self.view_order[position]
        if self.group_by_rule and (self.pair_index is None
                                   or self.pairs[self.pair_index]["rule"] != self.pairs[index]["rule"]):
            g, total = self._rule_group(index)
            print(f"--- rule group {g}/{total} ---")  # R-O12
        self.view_position = position
        pair = self.pairs[index]
        self.pair_index = index
        rule = Rule.from_id(pair["rule"])
        if rule != self.automaton.rule:
            self.undo_stack.append(self.automaton.rule)
            self._set_rule(rule)
        self._show_colors(pair["colorset"], pair["colors"])
        print(f"screensaver {position + 1}/{len(self.pairs)} {pair['colorset']}")  # R-O12
        self._fill_screen()  # R-W8

    def screensaver_step(self, step):  # R-W2: no wrap
        if not self.pairs:
            return
        nxt = (self.view_position if self.view_position is not None else -1) + step
        if not 0 <= nxt < len(self.view_order):
            print("screensaver end")
            return
        self._activate(nxt)

    def _save_screensaver(self):
        save_screensaver(self.pairs, self.screensaver_file)
        n = len(self.pairs)
        print(f"saved {n} pair{'' if n == 1 else 's'} to {self.screensaver_file.name}")  # R-O12

    def save_pair(self):  # R-W4: 's' overwrites the pair under review, in place
        if self.pair_index is None:
            print("no pair under review")
            return
        self.pairs[self.pair_index] = self._current_pair()
        self._rebuild_view_order()  # a changed rule may move it between groups
        self._save_screensaver()
        pos = self.view_position if self.view_position is not None else self.pair_index
        print(f"saved pair {pos + 1}/{len(self.pairs)}")  # R-O12

    def append_pair(self):  # R-W4: 'S' appends; the review position is unchanged
        self.pairs.append(self._current_pair())
        self._rebuild_view_order()
        self._save_screensaver()
        print(f"added pair {len(self.pairs)}/{len(self.pairs)}")  # R-O12

    def delete_pair(self):  # R-W5
        if self.pair_index is None or self.view_position is None:
            return
        position = self.view_position
        del self.pairs[self.pair_index]
        self.pair_index = None
        self._rebuild_view_order()
        self._save_screensaver()
        print(f"deleted pair {position + 1}/{len(self.pairs) + 1}")  # R-O12
        if not self.pairs:
            self.view_position = None
        else:
            self._activate(min(position, len(self.view_order) - 1))

    # --------------------------------------------------------- screensaver play

    def _load_play(self):  # R-X1
        self.pairs = load_screensaver(self.play_file) or []
        print(f"screensaver {self.play_file.name}: {len(self.pairs)} pairs")
        if self.pairs:
            self._play_pair(0, None)

    def _play_pair(self, index, reason):  # R-X4
        pair = self.pairs[index]
        self.pair_index = index
        rule = Rule.from_id(pair["rule"])
        if rule != self.automaton.rule:
            self._set_rule(rule)
        self._show_colors(pair["colorset"], pair["colors"])
        self.init_cells()
        self.play_elapsed = 0.0  # the pair's screen time starts now
        why = f" ({reason})" if reason else ""
        print(f"screensaver {index + 1}/{len(self.pairs)} {pair['colorset']}{why}")  # R-O13

    def _next_play_pair(self, reason):  # R-X2, R-X3: sequential, looping
        self._play_pair(((self.pair_index if self.pair_index is not None else -1) + 1) % len(self.pairs), reason)

    def play_step(self, step):  # R-X6: N/P move through the pairs, wrapping
        if not self.pairs:
            return
        at = self.pair_index if self.pair_index is not None else 0
        self._play_pair((at + step) % len(self.pairs), "next" if step > 0 else "previous")

    # ------------------------------------------------------------------- keys

    def _handle_color_key(self, key):
        """Color and review keys shared by the paused and running states (R-K10)."""
        if key == "c":
            self.cycle_colors(1)
        elif key == "C":
            self.cycle_colors(-1)
        elif key == "S":
            if self.screensaver_mode:
                self.append_pair()
            elif not self.review_mode:
                self.save_color_set()
        elif key == "N":
            if self.play_mode:
                self.play_step(1)
            elif self.screensaver_mode:
                self.screensaver_step(1)
            elif self.review_mode:
                self.review_step(1)
        elif key == "P":
            if self.play_mode:
                self.play_step(-1)
            elif self.screensaver_mode:
                self.screensaver_step(-1)
            elif self.review_mode:
                self.review_step(-1)
        elif key == "X":
            if self.screensaver_mode:
                self.delete_pair()
            elif self.review_mode:
                self.drop_review()
        elif key == "[":
            self.review_step(-1) if self.review_mode else self.pool_step(-1)  # R-K17
        elif key == "]":
            self.review_step(1) if self.review_mode else self.pool_step(1)
        elif len(key) == 1 and key.isdigit():
            self.select_color_set(int(key))
        else:
            return False
        return True

    def handle_key(self, key):
        """Apply a single-character key; return False when the program should quit."""
        if key == "q":
            return False
        if self.paused:  # R-K10: space, Return, s, and the color keys are live
            if key == KEY_SPACE:
                self.paused = False
                self.screen_remaining = 0
                # Resume seamlessly: the paused view shows the newest row fully
                # (offset 1), so start a hair short of the next generation and
                # let the first tick compute it — the picture does not jump.
                self._accumulated = self.delay
                self.screen_counter = 0  # R-K14: resume (re)starts the screen counter
                self._counted = 0
            elif key == KEY_RETURN:
                self._advance()  # R-K11: single step, stay paused
            elif key == "s":
                self.screen_remaining += self.rows  # R-K13: queue a screenful
            else:
                self._handle_color_key(key)
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
            if self.screensaver_mode:
                self.save_pair()  # R-W4
            else:
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
        else:
            self._handle_color_key(key)
        return True
