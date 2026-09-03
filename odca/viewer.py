"""Interactive pygame viewer for the four-state count-based automaton.

Generations scroll upward: the newest row appears at the bottom of the window.
On startup the previous rule is loaded (random on first run) and all cells
are initialized to random contents.

Background worker processes continuously screen random rules on all spare
cores; maybe-Class-IV finds are stashed (and persisted to ~/.odca/candidates)
so 'r' answers instantly from the stash.

Controls:
    q   quit
    r   new random rule, screened: candidates that look like Class I-III
        are discarded and regenerated until a maybe-Class-IV rule passes
    m   mutate the rule: change one randomly chosen entry to a new state
    u   undo the last rule change (r or m); repeatable
    s   save the current rule to interesting-rules.txt
    n   next saved interesting rule (first press selects rule 0); stepping
        past the last saved rule returns to the unsaved rule
    p   previous saved interesting rule (first press selects the last rule);
        stepping back from rule 0 returns to the unsaved rule
    i   initialize all cells to random contents
    +   speed up (halve the delay between generations)
    -   slow down (double the delay between generations)
    0-9 select a color set (0: CoCo set 0, 1: CoCo set 1, 2: default)
"""

import numpy as np
import pygame

from .automaton import Automaton, Rule
from .classify import find_candidate
from .search import CandidateSearch
from .store import (
    append_interesting,
    load_candidates,
    load_interesting,
    load_rule,
    save_candidates,
    save_rule,
)

# Color sets, bound to the number keys; each maps states 0-3 to RGB, with
# state 0 as the background. None = not chosen yet. CoCo colors follow the
# usual MC6847 VDG approximations.
COLOR_SETS = [None] * 10
COLOR_SETS[0] = np.array(  # CoCo color set 0
    [
        (0x07, 0xFF, 0x00),  # green
        (0xFF, 0xFF, 0x00),  # yellow
        (0x3B, 0x08, 0xFF),  # blue
        (0xCC, 0x00, 0x3B),  # red
    ],
    dtype=np.uint8,
)
COLOR_SETS[1] = np.array(  # CoCo color set 1
    [
        (0xFF, 0xFF, 0xFF),  # buff
        (0x07, 0xE3, 0x99),  # cyan
        (0xFF, 0x1C, 0xFF),  # magenta
        (0xFF, 0x81, 0x00),  # orange
    ],
    dtype=np.uint8,
)
COLOR_SETS[2] = np.array(  # default
    [
        (18, 18, 24),  # near-black
        (235, 235, 225),  # off-white
        (255, 161, 54),  # amber
        (64, 156, 255),  # blue
    ],
    dtype=np.uint8,
)
DEFAULT_COLOR_SET = 2

FPS = 60  # display refresh rate; generation rate is governed by Viewer.delay

INITIAL_DELAY = 1 / 60  # seconds between generations
MIN_DELAY = 1 / 16384
MAX_DELAY = 8.0

MAX_CANDIDATES = 64  # stash cap; background workers throttle once it's full


class Viewer:
    def __init__(self, width=1200, height=800, cell_size=4):
        self.cell_size = cell_size
        self.cols = width // cell_size
        self.rows = height // cell_size
        rule = load_rule() or Rule.random()
        self.automaton = Automaton(self.cols, rule=rule, seed="random")
        save_rule(rule)
        # history[i] is a row of cells; row 0 is the oldest visible generation
        self.history = np.zeros((self.rows, self.cols), dtype=np.uint8)
        self.filled = 0
        self.delay = INITIAL_DELAY
        self.palette = COLOR_SETS[DEFAULT_COLOR_SET]
        self.undo_stack = []
        # The saved rules form a cycle with one extra slot for the "unsaved"
        # rule — the one running before browsing began. index None = on it.
        self.interesting_index = None
        self.unsaved_rule = rule
        self.candidates = load_candidates()
        self.search = CandidateSearch()
        self._push(self.automaton.cells)
        print(f"rule {rule.id}")

    def _push(self, row):
        if self.filled < self.rows:
            self.history[self.filled] = row
            self.filled += 1
        else:
            self.history[:-1] = self.history[1:]
            self.history[-1] = row

    def _set_rule(self, rule):
        self.automaton.rule = rule
        save_rule(rule)
        print(f"rule {rule.id}")

    def _drain_search(self):
        if len(self.candidates) < MAX_CANDIDATES:
            found = self.search.drain()
            if found:
                self.candidates.extend(found)
                del self.candidates[MAX_CANDIDATES:]
                save_candidates(self.candidates)

    def new_rule(self):
        self.undo_stack.append(self.automaton.rule)
        self._drain_search()
        if self.candidates:
            rule = self.candidates.pop(0)
            save_candidates(self.candidates)
        else:
            # Stash is empty (e.g. first run): search synchronously.
            rule, tries = find_candidate(self.automaton.rng)
            if tries > 1:
                print(f"discarded {tries - 1} rule{'s' if tries > 2 else ''}")
        self._set_unsaved_rule(rule)

    def _set_unsaved_rule(self, rule):
        """Make `rule` current and the occupant of the cycle's unsaved slot."""
        self.unsaved_rule = rule
        self.interesting_index = None
        self._set_rule(rule)

    def mutate_rule(self):
        self.undo_stack.append(self.automaton.rule)
        self._set_unsaved_rule(self.automaton.rule.mutated(self.automaton.rng))

    def undo(self):
        if self.undo_stack:
            self._set_rule(self.undo_stack.pop())

    def select_interesting(self, step):
        """Cycle through the saved rules plus the unsaved slot.

        The cycle is [saved rule 0 .. n-1, unsaved rule]; index None means
        the unsaved slot, so from it 'n' selects rule 0 and 'p' rule n-1.
        """
        rules = load_interesting()
        if not rules:
            print("no saved interesting rules")
            return
        n = len(rules)
        at = n if self.interesting_index is None else self.interesting_index
        to = (at + step) % (n + 1)
        self.undo_stack.append(self.automaton.rule)
        if to == n:
            self.interesting_index = None
            print("unsaved rule")
            self._set_rule(self.unsaved_rule)
        else:
            self.interesting_index = to
            print(f"interesting {to + 1}/{n}")
            self._set_rule(rules[to])

    def init_cells(self):
        self.automaton.reset("random")
        self._push(self.automaton.cells)

    def handle_key(self, key):
        if key == pygame.K_q:
            return False
        elif key == pygame.K_r:
            self.new_rule()
        elif key == pygame.K_m:
            self.mutate_rule()
        elif key == pygame.K_u:
            self.undo()
        elif key == pygame.K_s:
            append_interesting(self.automaton.rule)
            print(f"saved rule {self.automaton.rule.id}")
        elif key == pygame.K_n:
            self.select_interesting(1)
        elif key == pygame.K_p:
            self.select_interesting(-1)
        elif key == pygame.K_i:
            self.init_cells()
        elif key in (pygame.K_PLUS, pygame.K_EQUALS, pygame.K_KP_PLUS):
            self.delay = max(self.delay / 2, MIN_DELAY)
        elif key in (pygame.K_MINUS, pygame.K_KP_MINUS):
            self.delay = min(self.delay * 2, MAX_DELAY)
        elif pygame.K_0 <= key <= pygame.K_9:
            color_set = COLOR_SETS[key - pygame.K_0]
            if color_set is not None:
                self.palette = color_set
        return True

    def draw(self, screen):
        rgb = self.palette[self.history]  # (rows, cols, 3)
        surf = pygame.surfarray.make_surface(rgb.transpose(1, 0, 2))
        pygame.transform.scale(surf, screen.get_size(), screen)

    def run(self):
        self.search.start()
        pygame.init()
        screen = pygame.display.set_mode(
            (self.cols * self.cell_size, self.rows * self.cell_size)
        )
        pygame.display.set_caption(f"ODCA — rule {self.automaton.rule.id}")
        clock = pygame.time.Clock()
        accumulated = 0.0
        running = True
        while running:
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                elif event.type == pygame.KEYDOWN:
                    running = self.handle_key(event.key)

            self._drain_search()
            accumulated += clock.tick(FPS) / 1000.0
            steps = int(accumulated / self.delay)
            accumulated -= steps * self.delay
            # Cap per-frame work so a stall can't freeze the UI catching up.
            for _ in range(min(steps, 2000)):
                self._push(self.automaton.step())
            self.draw(screen)
            pygame.display.set_caption(f"ODCA — rule {self.automaton.rule.id}")
            pygame.display.flip()
        self.search.stop()
        pygame.quit()
