"""Toolkit-free orchestration layer (spec R-U, R-K, R-B, R-A, R-V, R-W, R-X, R-O).

Everything the two programs do except rendering pixels and reading raw key
events lives here, so it runs headlessly in tests and the pygame layer
(viewer.py) stays thin. The UI translates toolkit key events into the
single-character keys below, calls tick(dt) at its refresh rate, and draws
`history` through `palette_table` and `row_palettes` (inverted while `inverted`).

Programs (spec sections 4c, 4d), selected at construction:
    select_file   odca-select: compose looks (rule + color set) in an odca
                  file; n/p cycle the file's looks and the unsaved rule, s
                  rewrites the look under review's color set (or appends
                  when on the unsaved rule), S appends a copy of the screen,
                  X deletes, R toggles the n/p order between file order and
                  grouped by rule (with a brief inversion of the screen);
                  the file is written after every change and at exit
    play_file     odca: play the file's looks one at a time, each for a
                  watchdog of PLAY_TIMEOUT seconds, then hand over after
                  PLAY_GRACE quiet seconds or at the next re-init; rows
                  keep the colors they were painted with; shuffle=True
                  plays each pass in a fresh random order; N/P step by hand
    review_mode   color set review (section 4b; on hold, no program binds it)

Keys (single characters), common to both programs:
    q   quit
    r   new random rule, screened: candidates that look like Class I-III
        are discarded and regenerated until a maybe-Class-IV rule passes
        (served from the background-search stash when available)
    m   mutate the rule: change one randomly chosen entry to a new state
    u   undo the last rule change (r, m, n, p, u); repeatable
    i   initialize all cells to random contents
    +   speed up (halve the delay between generations)
    -   slow down (double the delay between generations)
    0-9 select a digit-bound color set — the "hot ten" (library.json)
    [ ] step backward / forward through the whole color set pool
    c   cycle the active color set through the 24 ways of assigning its
        four colors to the four states (remembered per set)
    C   the same cycle in reverse
    ' ' pause / resume; while paused every key but space, Return, s, the
        color keys, the look keys, and q is ignored
    '\\n' (Return) while paused: compute and display one generation
        (single step), remaining paused; ignored when not paused
    s   while paused: run one screenful of generations at one eighth the
        current delay, then remain paused; each press queues another
    a   toggle auto-init (on at startup): once every row on screen is
        boring, re-initialize the cells as 'i' does

Resuming from pause with space (re)starts a screen counter: from then on,
every completed screenful of generations prints 'screen N'.
"""

from collections import Counter, deque
from itertools import permutations
from pathlib import Path

import numpy as np

from .automaton import N_STATES, Automaton, Rule
from .classify import find_candidate
from .search import CandidateSearch
from .store import DEFAULT_COLOR_SETS, Store, load_odca_file, save_odca_file

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
PLAY_TIMEOUT = 120.0  # odca: a look's screen time before it may advance (R-X2)
PLAY_GRACE = 60.0  # odca: no transition within this long of an initialization (R-X3)
SHUFFLE_TRIES = 100  # odca --shuffle: shuffles tried for an order without repeats before giving up (R-X1)
FLASH_SECONDS = 0.25  # the screen inverts this long as a mode cue (R-U10)
HISTORY_DEPTH = 2048  # rows remembered beyond the screen (R-U8)
PALETTE_LIMIT = 64  # odca: prune the per-row palette table past this many entries (R-X5)
MIN_COLS = 3  # R-M2

KEY_SPACE = " "
KEY_RETURN = "\n"


def _rgb(c):
    return tuple(int(c[j:j + 2], 16) for j in (1, 3, 5))


class Session:
    def __init__(self, cols, rows, store=None, search=None, rng=None,
                 review_mode=False, select_file=None, play_file=None, shuffle=False,
                 initial_delay=INITIAL_DELAY, play_timeout=PLAY_TIMEOUT, play_grace=PLAY_GRACE):
        self.cols = cols
        self.rows = rows
        # odca's clocks (R-X2, R-X3), whole seconds from --watchdog / --grace
        # or the defaults above.
        self.play_timeout = float(play_timeout)
        self.play_grace = float(play_grace)
        # R-U5: the starting delay, 1/60 s at the default cell size and halved
        # per halving of the cell, so the picture moves at the same speed in
        # points; the continuous-scrolling threshold is twice it (R-U3).
        self.initial_delay = initial_delay
        self.store = store if store is not None else Store()
        self.search = search if search is not None else CandidateSearch()
        self.rng = rng if rng is not None else np.random.default_rng()
        # Program precedence: odca (play), then odca-select, then color set review.
        self.play_file = Path(play_file) if play_file else None
        self.shuffle = bool(shuffle) and self.play_file is not None
        if self.play_file is not None:
            select_file = None
        self.select_file = Path(select_file) if select_file else None
        self.review_mode = bool(review_mode) and self.select_file is None and self.play_file is None

        # Startup per R-U1: previous rule (random fallback), random cells.
        rule = self.store.load_rule() or Rule.random(self.rng)
        self.automaton = Automaton(cols, rule=rule, seed="random", rng=self.rng)
        self.store.save_rule(rule)

        # Remembered generations, oldest first, up to HISTORY_DEPTH (never
        # fewer than rows + 1). The display shows the last rows + 1: one more
        # than the window, so continuous scrolling has a row to slide in; a
        # taller window uncovers older rows (R-U8). `history` and
        # `row_palettes` (the palette each row was painted with, R-X5) are
        # views into a buffer twice the depth, compacted once it runs out, so
        # a push is a single row write.
        self._buf = np.zeros((2 * self._keep(), cols), dtype=np.uint8)
        self._buf_palettes = np.zeros(2 * self._keep(), dtype=np.uint16)
        self._end = 0  # one past the newest row in the buffers
        self._count = 0  # rows remembered
        # odca (R-X5): the color sets rows were painted with, as hex lists;
        # row_palettes indexes this table. Other modes use one entry, index 0.
        self._palettes = []
        self._palette_index = 0
        self.delay = initial_delay
        self.paused = False
        self.screen_remaining = 0  # generations still to zip after a paused 's'
        self.screen_counter = None  # screenfuls since the last resume; None = inactive
        self._counted = 0  # generations since the counter started
        self.undo_stack = []
        self._accumulated = 0.0
        self._zip_accumulated = 0.0
        self.flash_remaining = 0.0  # seconds of screen inversion left (R-U10)
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

        # The look cycle (R-B): the file's looks in view order plus one slot
        # for the unsaved rule — the one being explored. look_index None = on
        # the unsaved slot (or no look). The startup rule fills the unsaved
        # slot unless odca-select opens on a file with looks (R-W1).
        self.looks = []  # always in file order
        self.look_index = None  # file index of the look under review
        self.view_order = []  # file indices in n/p order
        self.view_position = None  # position of look_index within view_order
        self.grouped = False  # R: n/p order grouped by rule (R-W7)
        self.unsaved_rule = rule
        self.unsaved_set = dict(self.active_set)  # the set shown with the unsaved rule (R-B3)

        # Color set review (R-V)
        self.review_entries = []
        self.review_index = 0
        self.dropped_names = []
        self._review_arrangement = {}
        # odca (R-X)
        self.play_order = []  # file indices in the order of the current pass
        self.play_position = None
        self.play_elapsed = 0.0  # unpaused seconds on the current look
        self.since_init = 0.0  # unpaused seconds since the last (re)initialization

        self.candidates = self.store.load_candidates()
        self._push(self.automaton.cells)
        print(f"rule {rule.id}")
        if self.review_mode:
            self._load_review()
        if self.select_file is not None:
            self._load_select()
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
    def select_mode(self):
        return self.select_file is not None

    @property
    def play_mode(self):
        return self.play_file is not None

    @property
    def inverted(self):
        """The display shows inverted colors while a flash runs (R-U10)."""
        return self.flash_remaining > 0

    def start_search(self):
        self.search.start()

    def stop_search(self):
        self.search.stop()

    def finish(self):
        """Call at program exit: odca-select writes its file, review saves (R-V5)."""
        if self.select_mode:
            self._save_looks()
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
    def palette_table(self):
        """RGB for every (palette, state) as one list, entry palette * 4 + state
        (R-X5). Outside odca there is one palette, the active set, so the
        whole screen recolors at once."""
        if self.play_mode and self._palettes:
            return [_rgb(c) for p in self._palettes for c in p]
        return self.palette

    def color(self, row, col):
        """Display color of a history cell: its state through its row's palette."""
        return self.palette_table[int(self.row_palettes[row]) * 4 + int(self.history[row][col])]

    # ----------------------------------------------------------------- history

    def _keep(self):
        return max(HISTORY_DEPTH, self.rows + 1)

    @property
    def history(self):
        """Remembered rows of cells, oldest first: a (filled, cols) view (R-U8)."""
        return self._buf[self._end - self._count:self._end]

    @property
    def row_palettes(self):
        """Index into palette_table of the palette each history row was painted with (R-X5)."""
        return self._buf_palettes[self._end - self._count:self._end]

    @property
    def filled(self):
        """Rows remembered so far."""
        return self._count

    @property
    def visible_start(self):
        """Index of the first history row the display shows (R-U3, R-U8)."""
        return max(0, self._count - (self.rows + 1))

    def _trim_history(self):
        keep = self._keep()
        if self._count > keep:
            self._count = keep

    def resize(self, cols, rows):
        """Change the geometry (R-U8). Returns whether anything changed.

        The state vector keeps its center: cropped from both edges when
        narrower, padded at both edges when wider, the new cells seeded at
        random in the live row and with state 0 in remembered rows. The
        boring detectors start afresh; undo and the look cycle are untouched.
        """
        cols, rows = max(MIN_COLS, cols), max(1, rows)
        if cols == self.cols and rows == self.rows:
            return False
        if cols != self.cols:
            old = self.history
            if cols < self.cols:
                left = (self.cols - cols) // 2
                fitted = old[:, left:left + cols]
                cells = self.automaton.cells[left:left + cols]
            else:
                add = cols - self.cols
                pad = (add // 2, add - add // 2)
                fitted = np.pad(old, ((0, 0), pad))
                cells = np.concatenate((
                    self.rng.integers(0, N_STATES, pad[0], dtype=np.uint8),
                    self.automaton.cells,
                    self.rng.integers(0, N_STATES, pad[1], dtype=np.uint8)))
            palettes = self.row_palettes.copy()
            self.cols = cols
            self.rows = rows
            self._buf = np.zeros((2 * self._keep(), cols), dtype=np.uint8)
            self._buf_palettes = np.zeros(2 * self._keep(), dtype=np.uint16)
            self._end = self._count = 0
            for row, index in zip(fitted, palettes):
                self._append(row, index)
            self.automaton.width = cols
            self.automaton.cells = np.ascontiguousarray(cells)
            if self._count:
                self._buf[self._end - 1] = cells
        self.rows = rows
        self._trim_history()
        self._minority_counts = deque(maxlen=STAGNATION_SCREENS * rows)
        self._reset_boredom()
        print(f"resized {self.cols}x{self.rows}")  # R-O14
        return True

    def _append(self, row, palette):
        if self._end == len(self._buf):  # out of room: slide the kept rows to the front
            keep = min(self._count, self._keep())
            self._buf[:keep] = self._buf[self._end - keep:self._end]
            self._buf_palettes[:keep] = self._buf_palettes[self._end - keep:self._end]
            self._end, self._count = keep, keep
        self._buf[self._end] = row
        self._buf_palettes[self._end] = palette
        self._end += 1
        self._count += 1
        self._trim_history()

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

    def save_color_set(self):  # R-K16: bake the arrangement into the library entry, by name
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
        """Show a stored presentation: its colors become the active set (R-B2)."""
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

    def flash(self):  # R-U10: invert the screen briefly as a cue
        self.flash_remaining = FLASH_SECONDS

    # ------------------------------------------------------------------ display

    @property
    def scroll_offset(self):
        """How far the display is scrolled into the top history row, in cells (R-U3).

        0 while the buffer is still filling; 1 (newest row fully shown) when
        paused or at fast speeds; the fraction of the current delay that has
        elapsed when scrolling continuously, so the picture slides up at one
        cell per delay and the newest generation enters from the bottom.
        """
        if self._count <= self.rows:
            return 0.0
        if self.paused or self.delay <= 2 * self.initial_delay:
            return 1.0
        return min(self._accumulated / self.delay, 1.0)

    def _push(self, row):
        if self.play_mode:
            # R-X5: a row keeps the colors it was painted with. A changed
            # active set becomes a new table entry for the rows from now on.
            current = self._arranged_active_colors()
            if not self._palettes:
                self._palettes.append(list(current))
            elif current != self._palettes[self._palette_index]:
                if current in self._palettes:  # a set seen before: share its entry
                    self._palette_index = self._palettes.index(current)
                else:
                    if len(self._palettes) >= PALETTE_LIMIT:
                        self._prune_palettes()
                    self._palettes.append(list(current))
                    self._palette_index = len(self._palettes) - 1
        self._append(row, self._palette_index)

    def _prune_palettes(self):
        """Drop table entries no remembered row uses any more, renumbering the rest."""
        used = set(int(i) for i in np.unique(self.row_palettes)) | {self._palette_index}
        keep = sorted(used)
        lut = np.zeros(len(self._palettes), dtype=np.uint16)
        for new, old in enumerate(keep):
            lut[old] = new
        view = self._buf_palettes[self._end - self._count:self._end]
        view[:] = lut[view]
        self._palettes = [self._palettes[i] for i in keep]
        self._palette_index = int(lut[self._palette_index])

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
            if self.play_mode and self.looks and self.play_elapsed >= self.play_timeout:
                self._next_play_look(reason)  # R-X3: watchdog expired, a re-init transitions
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
        self.flash_remaining = max(0.0, self.flash_remaining - dt)  # display only: runs while paused
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
        if (self.play_mode and self.looks  # R-X3: watchdog expired and the grace period observed
                and self.play_elapsed >= self.play_timeout and self.since_init >= self.play_grace):
            self._next_play_look("timeout")

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
        """Make `rule` current and the occupant of the cycle's unsaved slot (R-B3)."""
        self.unsaved_rule = rule
        self.unsaved_set = dict(self.active_set)
        self.look_index = None
        self.view_position = None
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

    def _current_look(self):
        return {"rule": self.automaton.rule.id, "colorset": self.active_name,
                "colors": self._arranged_active_colors()}

    def init_cells(self):  # R-K6
        self.automaton.reset("random")
        self._push(self.automaton.cells)
        self._reset_boredom()
        self.since_init = 0.0  # R-X3: any initialization restarts the grace period

    # ------------------------------------------------------------ look cycle

    def _rebuild_view_order(self):  # R-W7: n/p order, file order or grouped by rule
        if self.grouped:
            groups, rule_order = {}, []
            for i, p in enumerate(self.looks):
                if p["rule"] not in groups:
                    groups[p["rule"]] = []
                    rule_order.append(p["rule"])
                groups[p["rule"]].append(i)
            self.view_order = [i for r in rule_order for i in groups[r]]
        else:
            self.view_order = list(range(len(self.looks)))
        self.view_position = (self.view_order.index(self.look_index)
                              if self.look_index is not None and self.look_index in self.view_order else None)

    def _rule_group(self, index):
        seen = []
        for p in self.looks:
            if p["rule"] not in seen:
                seen.append(p["rule"])
        return seen.index(self.looks[index]["rule"]) + 1, len(seen)

    def _activate_look(self, position, push_undo=True):  # R-B2, R-W8
        index = self.view_order[position]
        look = self.looks[index]
        if self.grouped and (self.look_index is None
                             or self.looks[self.look_index]["rule"] != look["rule"]):
            g, total = self._rule_group(index)
            print(f"--- rule group {g}/{total} ---")  # R-O12
        self.view_position = position
        self.look_index = index
        rule = Rule.from_id(look["rule"])
        if rule != self.automaton.rule:
            if push_undo:
                self.undo_stack.append(self.automaton.rule)
            self._set_rule(rule)
        self._show_colors(look["colorset"], look["colors"])
        print(f"look {position + 1}/{len(self.looks)} {look['colorset']}")  # R-O4
        self._fill_screen()  # R-W8

    def select_look(self, step):  # R-B2, R-B3: n/p
        """Cycle through the looks in view order plus the unsaved slot, if occupied.

        The cycle is [look at view position 0 .. n-1, unsaved rule]; on the
        unsaved slot 'n' selects the first look and 'p' the last. A look
        brings its colors along; the unsaved slot brings back the set that
        was showing when the unsaved rule arrived. Only odca-select has a
        file of looks; elsewhere n/p report that there are none.
        """
        n = len(self.view_order)
        total = n + 1 if self.unsaved_rule is not None else n
        if n == 0:
            print("no looks")  # R-O5
            return
        at = n if self.look_index is None else self.view_position
        to = (at + step) % total
        self.undo_stack.append(self.automaton.rule)
        if to == n:  # only reachable when the unsaved slot is occupied
            self.look_index = None
            self.view_position = None
            print("unsaved rule")  # R-O4
            self._set_rule(self.unsaved_rule)
            if self.unsaved_set is not None:
                self._show_colors(self.unsaved_set["name"], self.unsaved_set["colors"])
            self._fill_screen()  # R-W8: every n/p step shows a screenful of the selection
        else:
            self._activate_look(to, push_undo=False)

    # ------------------------------------------------------------ odca-select

    def _load_select(self):  # R-W1
        loaded = load_odca_file(self.select_file)
        self.looks = loaded or []  # a missing file is created by the first save or at exit
        self._rebuild_view_order()
        print(f"odca {self.select_file.name}: {len(self.looks)} looks")  # R-O12
        if self.looks:
            # Open on look 1; the unsaved slot stays empty until r or m fires.
            self.unsaved_rule = None
            self.unsaved_set = None
            self._activate_look(0, push_undo=False)

    def _save_looks(self):
        save_odca_file(self.looks, self.select_file)
        n = len(self.looks)
        print(f"saved {n} look{'' if n == 1 else 's'} to {self.select_file.name}")  # R-O12

    def save_look(self):  # R-W4: 's' rewrites the look under review's color set, or appends
        if self.look_index is None:
            self.append_look()
            return
        i = self.look_index
        self.looks[i] = {"rule": self.looks[i]["rule"], "colorset": self.active_name,
                         "colors": self._arranged_active_colors()}
        self._save_looks()
        print(f"saved look {self.view_position + 1}/{len(self.looks)}")  # R-O12

    def append_look(self):  # R-W4: 'S' appends a copy of the screen; the position is unchanged
        self.looks.append(self._current_look())
        self._rebuild_view_order()
        self._save_looks()
        print(f"added look {len(self.looks)}/{len(self.looks)}")  # R-O12

    def delete_look(self):  # R-W5
        if self.look_index is None:
            return
        position = self.view_position
        del self.looks[self.look_index]
        self.look_index = None
        self._rebuild_view_order()
        self._save_looks()
        print(f"deleted look {position + 1}/{len(self.looks) + 1}")  # R-O12
        if self.looks:
            self._activate_look(min(position, len(self.view_order) - 1))
        else:
            # Nothing left to review: the rule on screen becomes the unsaved rule.
            self.view_position = None
            self.unsaved_rule = self.automaton.rule
            self.unsaved_set = dict(self.active_set)

    def toggle_grouped(self):  # R-W7: 'R'
        self.grouped = not self.grouped
        self._rebuild_view_order()
        print(f"look order {'grouped by rule' if self.grouped else 'file order'}")  # R-O12
        self.flash()  # R-U10

    # ------------------------------------------------------------------- odca

    def _load_play(self):  # R-X1
        self.looks = load_odca_file(self.play_file) or []
        print(f"odca {self.play_file.name}: {len(self.looks)} looks")  # R-O13
        if self.looks:
            self._new_pass()
            self._play_look(self.play_order[0], None)

    def _new_pass(self):  # R-X1: file order, or a fresh shuffle per pass
        n = len(self.looks)
        order = list(range(n))
        if self.shuffle and n > 1:
            # A fresh permutation in which no rule and no color set follows
            # itself, the seam from the look just played included; a file
            # that allows no such order plays the last shuffle as it is.
            for _ in range(SHUFFLE_TRIES):
                order = [int(i) for i in self.rng.permutation(n)]
                if self._no_repeats(order, self.look_index):
                    break
        self.play_order = order
        self.play_position = 0

    def _no_repeats(self, order, previous):
        chain = ([previous] if previous is not None else []) + order
        return not any(self._clash(a, b) for a, b in zip(chain, chain[1:]))

    def _clash(self, a, b):
        """Two looks repeat if they share the rule or the color set (in any arrangement)."""
        la, lb = self.looks[a], self.looks[b]
        return la["rule"] == lb["rule"] or sorted(la["colors"]) == sorted(lb["colors"])

    def _play_look(self, index, reason):  # R-X4
        look = self.looks[index]
        self.look_index = index
        rule = Rule.from_id(look["rule"])
        if rule != self.automaton.rule:
            self._set_rule(rule)
        self._show_colors(look["colorset"], look["colors"])
        self.init_cells()
        self.play_elapsed = 0.0  # the look's screen time starts now
        why = f" ({reason})" if reason else ""
        print(f"look {index + 1}/{len(self.looks)} {look['colorset']}{why}")  # R-O13

    def _next_play_look(self, reason):  # R-X2, R-X3: on through the pass, then a new pass
        self.play_position += 1
        if self.play_position >= len(self.play_order):
            self._new_pass()
        self._play_look(self.play_order[self.play_position], reason)

    def play_step(self, step):  # R-X6: N/P move through the pass by hand, wrapping
        if not self.looks:
            return
        if step > 0:
            self._next_play_look("next")
        else:
            self.play_position = (self.play_position - 1) % len(self.play_order)
            self._play_look(self.play_order[self.play_position], "previous")

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

    # ------------------------------------------------------------------- keys

    def _handle_color_key(self, key):
        """Color and look keys shared by the paused and running states (R-K10)."""
        if key == "c":
            self.cycle_colors(1)
        elif key == "C":
            self.cycle_colors(-1)
        elif key == "S":
            if self.select_mode:
                self.append_look()  # R-W4
            elif not self.review_mode and not self.play_mode:
                self.save_color_set()  # R-K16: no program binds this in 3.0.0
        elif key == "N":
            if self.play_mode:
                self.play_step(1)
            elif self.review_mode:
                self.review_step(1)
        elif key == "P":
            if self.play_mode:
                self.play_step(-1)
            elif self.review_mode:
                self.review_step(-1)
        elif key == "X":
            if self.select_mode:
                self.delete_look()
            elif self.review_mode:
                self.drop_review()
        elif key == "R":
            if self.select_mode:
                self.toggle_grouped()
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
            if self.select_mode:
                self.save_look()  # R-W4
        elif key == "n":
            self.play_step(1) if self.play_mode else self.select_look(1)
        elif key == "p":
            self.play_step(-1) if self.play_mode else self.select_look(-1)
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
