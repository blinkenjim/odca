# ODCA — Requirements

Version 3.58.0 — 2026-09-10
(1.1: startup cycle position matches a saved rule when possible — R-U1,
R-B3. 1.2: pause on spacebar — R-K10. 1.3: single-step on Return while
paused — R-K11. 2.0.0: version unified across the whole code base with
the arrival of the Swift implementation; no behavioral change from 1.3.
2.3.0: auto-initialization mode on `a` — R-K12, section 4a, R-O6.
2.3.1: an extinction does not count while another minority state is
still alive — R-A1. 2.3.2: stagnation detector — R-A1, R-O6. 2.5.0:
paused `s` zips one screenful — R-K13. 2.5.1: screen counter started by
resume — R-K14, R-O7. 2.5.2: repetition window widened to 10 screens —
R-A1. 2.7.0: cycles of any period detected by Brent's algorithm — R-A1,
R-O8. 2.9.0: color sets 3–9 defined — R-U4. 2.11.0: color sets
rearranged and file-backed, `c` arranges, `S` saves — R-U4, R-K9,
R-K15, R-K16, R-P4, R-O9, R-O10. 2.11.1: digits live while paused —
R-K10. 2.11.2: `C` cycles arrangements backward — R-K15. 2.13.0:
auto-initialization is on at startup — R-K12. 2.15.0: continuous
scrolling at slow speeds, seamless resume — R-U3, R-K10. 2.15.1:
clarify that refresh follows the display, not a fixed 60 Hz — R-U5.
2.20.0: the color sets file becomes the pool, with a dropped list —
R-P4; color set review mode behind `--colorset-review` — section 4b;
developer flags permitted — section 10. 2.22.0: screensaver review mode
and file — section 4c, R-P5; color set review saves on every drop and
no longer bakes arrangements — R-V5, R-V6. 2.24.0: consistency check —
R-W7. 2.24.1: every pair activation fills the screen at once — R-W8. 2.24.2:
so does every color set review step — R-V7. 2.26.0: screensaver mode
(sequential study) — section 4d, R-O13. 2.26.1: rows keep their colors
across transitions — R-X5. 2.26.2: watchdog 300 s, restarted by `i` —
R-X3. 2.26.3: `N`/`P` step between pairs — R-X6. 2.28.0: resizable
window and geometry — R-U2, R-U8, R-O14. 2.28.1: pointer hidden in full
screen; frozen during a live resize — R-U2, R-U8. 2.30.0: equal screen
time per pair — watchdog 180 s with a 60 s grace period — R-X2, R-X3.
2.30.1: watchdog 120 s. 2.32.0: `[`/`]` walk the whole pool in every
mode; the active set model everywhere — R-K17, R-K15, R-K16, R-O9,
R-O10, R-O15. 2.34.0: saved rules carry their presentation; the keeper
file is a screensaver-format file — R-K5, R-B2, R-B3, R-P3, R-O3, R-O4.
2.36.0: `--help` — R-U9, section 10. 3.0.0: one program becomes two —
`odca` plays an odca file of pairs (section 4d, `--shuffle`), `odca-select`
composes one (section 4c: n/p over the file's pairs, s/S/X, R with a
screen flash R-U10); the keeper file becomes `interesting.odca` and the
color sets file `library.json` — R-U1, R-U9, R-K5, R-K16, section 4, R-P3,
R-P4, R-P5 merged, R-O3–R-O5, R-O12, R-O13, section 10; color set review
(section 4b) is bound by no program. 3.2.0: rows keep their colors for
good, however many color changes share a screenful — R-X5, the two-bank
limitation withdrawn. 3.4.0: `odca --fullscreen` — R-U2, section 10.
3.6.0: `F` toggles full screen — R-K18, R-K10. 3.8.0: cell size flags
`--4` / `--2` / `--1` on both programs — R-U2, section 10. 3.10.0: the
initial delay halves with the cell size — R-U5, R-U3. 3.12.0: the
shuffle constraints — R-X1. 3.14.0: `--watchdog` and `--grace` — R-X2,
R-X3, R-U9, section 10. 3.16.0: `m` on a pair is an edit of it, recorded
in place by `s` — R-K3, R-K5, R-B3, R-W4. 3.18.0: `U` undoes every change
since the position last moved — R-K19, R-K4. 3.20.0: `--3` — R-U2, R-U5. 3.22.0: a
mutated pair is saved as a new pair, never over the kept rule — R-K3,
R-K5, R-W4. 3.24.0: navigation re-seeds and scrolls the pair in instead
of filling the screen — R-W8, R-B2, R-K10, R-W1. 3.26.0: "look" becomes
"pair" throughout, pairs are named `pair-NNNN` — R-P3, R-O4, R-O12,
R-O13; 2-point cells by default — R-U2, R-U3, R-U5. 3.28.0: play
scripts — `odca` plays a show of one or more files, `.play` scripts with
`import` and `play` or odca files, and `--shuffle` draws the order of
the files — R-X1, R-X7, R-U1, R-U9, R-O13, section 10; the 3.12.0
pair-level shuffle withdrawn. 3.30.0: a script's pairs drawn afresh each
pass under the 3.12.0 constraints — R-X7, R-X1, R-O13. 3.32.0: that is
spelled `shuffle`, a statement in its own right beside `play`, not a
word after it — R-X7. 3.36.0: `odca-evolve`, the search for a rule's
longest-lived seeds — section 4e, R-P3 (the `seeds` section), R-X4
(`odca` plays a pair from its best seed), R-O16, R-U9, section 10;
conformance vectors 1.1 (`lifetimes`). 3.38.0: `odca-evolve` clocks as
`hh:mm:ss` — R-E4, R-O16. 3.38.1: its lines open with the time left on
the rule, not the time of day — R-O16. 3.40.0: the ages of the ten when
a rule is done — R-O16. 3.40.1: the countdown starts at the left margin
— R-E4. 3.42.0: the countdown shows the rule's rate, rows tested per
second — R-E4. 3.42.1: that rate is over the last ten seconds, not
cumulative — R-E4. 3.44.0: `odca --longest`, the show of the recorded
seeds in a fixed-width window — R-X8, R-X1, R-U8, R-O13, R-U9, section
10. 3.46.0: the generation counter in the title under `--longest` —
R-U6. 3.48.0: the counter moves to standard output, in place on a
terminal — R-O17, R-U6. 3.50.0: the `--longest` grid is stretched to the
window's width, aspect kept — R-X8, R-U2. 3.52.0: the generation
counter on screen in full screen — R-U11. 3.52.1: at 12 points — R-U11. 3.52.2: at 18 points, bold, refreshed
every frame — R-U11. 3.54.0: the on-screen count in any window, `o`
hides it — R-U11, R-K20; a title-bar double-click returns a resized
window to its natural size — R-U12. 3.56.0: `odca-select --longest`,
curating the pairs with seeds — R-W9, R-W1, R-O12, R-U9, section 10.
3.58.0: `odca-evolve --parity` — R-E5, R-E1, R-O16, section 10.)

Versioning is semantic and shared by the whole code base: the
specification and every implementation carry the same version and are
released together. MAJOR for incompatible changes (state formats, rule
IDs, conformance vectors), MINOR for new or changed behavior, PATCH for
fixes and clarifications.

This document specifies ODCA, a four-state, count-based, one-dimensional
cellular automaton presented as art, in sufficient detail to re-create the
programs from scratch in any language. There are two programs sharing one
engine and one keyboard vocabulary: `odca <file> ...` plays a show, the
*pairs* (rule + color set) of play scripts and odca files (section 4d),
and `odca-select <file.odca>` composes them (section 4c); a third,
`odca-evolve`, has no window and searches a file's rules for their
longest-lived seeds (section 4e). "The program" below means either
unless a section says which. It is
language-independent; it assumes a unix-like environment (macOS, Ubuntu,
or similar) with a per-user home directory and a graphical display.

Requirements are numbered (R-M1, R-U3, …) so tests and discussion can cite
them. "Must" denotes a requirement; "should" a strong default; "may" an
implementation choice. Companion documents:

- `TESTS.md` — normative test plan (conformance vectors, property tests,
  manual checklist)
- `REQ-<language>.md` — per-language implementation notes (e.g.
  `REQ-python.md`)

Heritage (informative): the automaton reproduces a design originally
written in the 1980s for the 6809E processor of a TRS-80 Color Computer.

---

## 1. The automaton model (R-M)

**R-M1.** A cell holds one of four states, numbered 0, 1, 2, 3.

**R-M2.** The automaton is a fixed-width row of W cells, W ≥ 3.
Implementations must reject W < 3.

**R-M3.** Cells advance in discrete generations. All cells update
simultaneously (synchronous update) as a pure function of the previous
generation.

**R-M4.** A cell's neighborhood is exactly three cells: its left neighbor,
itself, and its right neighbor (radius 1).

**R-M5 (the defining property).** A cell's next state depends only on the
*counts* of each state within its neighborhood — the vector
(n0, n1, n2, n3) where nk is the number of neighborhood cells in state k
and n0+n1+n2+n3 = 3 — and not on which position holds which state.
Consequently any permutation of a neighborhood's three cells yields the
same next state.

**R-M6.** There are exactly 20 possible count vectors. Their canonical
order is ascending lexicographic by (n0, n1, n2, n3):

| index | (n0,n1,n2,n3) | | index | (n0,n1,n2,n3) |
|-------|---------------|-|-------|---------------|
|  0 | (0,0,0,3) | | 10 | (1,0,0,2) |
|  1 | (0,0,1,2) | | 11 | (1,0,1,1) |
|  2 | (0,0,2,1) | | 12 | (1,0,2,0) |
|  3 | (0,0,3,0) | | 13 | (1,1,0,1) |
|  4 | (0,1,0,2) | | 14 | (1,1,1,0) |
|  5 | (0,1,1,1) | | 15 | (1,2,0,0) |
|  6 | (0,1,2,0) | | 16 | (2,0,0,1) |
|  7 | (0,2,0,1) | | 17 | (2,0,1,0) |
|  8 | (0,2,1,0) | | 18 | (2,1,0,0) |
|  9 | (0,3,0,0) | | 19 | (3,0,0,0) |

**R-M7.** A *rule* is a table assigning one next state (0–3) to each of the
20 count vectors. The rule space therefore contains 4^20 =
1,099,511,627,776 rules.

**R-M8 (rule ID).** A rule's canonical, shareable identifier is a string of
exactly 20 characters, each a digit `0`–`3`, where character i (0-based) is
the next state assigned to canonical count vector i. Implementations must
parse and emit this format, and must reject IDs of the wrong length or
containing other characters.

**R-M9 (edge modes).** The engine must support two edge behaviors:

- *wrap* (toroidal): cell 0's left neighbor is cell W−1, and cell W−1's
  right neighbor is cell 0. **This is the mode the interactive program
  uses.**
- *fixed*: cells beyond either edge are treated as permanently state 0.

**R-M10 (mutation).** Mutating a rule produces a new rule identical except
at one table entry, chosen uniformly at random from the 20, whose value is
changed to a state chosen uniformly from the three states *different* from
its current value. A mutation never yields the identical rule.

**R-M11 (random rule).** A random rule assigns each of the 20 entries an
independent, uniformly distributed state 0–3.

*Implementation note (informative).* The historical lookup trick: weight
states 0,1,2,3 as 1, 4, 16, 64 and sum the three neighborhood cells; the
sum's base-4 digits are then exactly (n0, n1, n2, n3), so the sum indexes a
sparse table with 20 live entries. Weighting state 0 as 0 instead (0, 1, 4,
16) drops the redundant n0 digit and shrinks the table to 49 slots. Any
mechanism satisfying R-M5–R-M8 is conforming.

---

## 2. Interactive program: startup and display (R-U)

**R-U1 (startup).** On launch, after reading its file arguments (the
odca file of `odca-select`, section 4c; the show of `odca`, section 4d;
`--help` aside, R-U9), the program must:
1. Load the previously saved current rule (see R-P1); if absent or
   invalid, generate a random rule (R-M11).
2. Persist that rule as the current rule (R-P1) and print it (R-O1).
3. Initialize every cell to an independent uniformly random state 0–3.
4. Begin evolving and displaying immediately, in wrap mode.
5. Load the persisted candidate stash (R-P2) and start the background
   search (R-S).
6. Set the interesting-rule cycle position: if the loaded rule equals a
   saved rule, on that rule's first occurrence with the unsaved slot
   empty; otherwise on the unsaved slot, which holds the loaded rule
   (R-B3). In 3.0.0 this reads: `odca-select` on a file with pairs opens
   on pair 1 with the unsaved slot empty (R-W1); on an empty or missing
   file the loaded rule occupies the unsaved slot. `odca` plays the
   show's first pair at once (R-X1).

**R-U2 (display geometry).** (Under `odca --longest` the grid is scaled
to the window's width, R-X8; the rest of this requirement describes the
natural size.) The display is a grid of square cells,
`cell_size` points on a side: 2 by default (since 3.26.0; 4 before), or
4, 3, or 1 for the run when either program is given `--4`, `--3`, or
`--1` (`--2` names the default; at most one of the four, more is a usage
error, R-U9). Points, never device
pixels: on a high-density display a 1-point cell still covers several
device pixels, and the picture is scaled without smoothing. (The Python
implementation counts its window in pixels, the same unit in practice.)
The window is resizable, including full screen, and the grid holds as
many whole cells as fit: `cols` = ⌊width / cell_size⌋, `rows` =
⌊height / cell_size⌋. The default (and first-launch) window is 1200×800
points, giving 600 × 400 cells at the default size (300 × 200 with `--4`,
400 × 266 with `--3`, 1200 × 800 with `--1`); the minimum is 160×120
points (80 × 60 cells at the default size). Interactive resizing should snap to whole cells (resize
increments of `cell_size`); where a remainder is unavoidable (full screen)
the grid is centered and the margins are painted in the state-0 color.
The window may remember its last size and position through the
platform's standard mechanism. In full screen the mouse pointer is
hidden, and shown again on leaving. `odca --fullscreen` opens the window
full screen at launch, for unattended runs (an installation, a kiosk);
leaving full screen is the platform's own control, as entering it is
without the flag. The automaton's width equals `cols`.

**R-U3 (scrolling).** The display shows the most recent generations as
horizontal rows, newest at the bottom of the filled region. A history
buffer of `rows` + 1 rows starts as all state 0; each new generation is
appended below the previous until the buffer is full, after which the
buffer scrolls: the oldest row is discarded and the new row enters at the
bottom. The initial (seed) generation is displayed.

The window shows `rows` rows of the buffer, scrolled into its top row by
a *scroll offset* of 0 to 1 cell:
- while the buffer is still filling: 0 (rows appear from the top down);
- when paused, or when the delay is at most twice the initial delay
  (60 generations per second or faster at the default 2-point cell): 1 — the newest generation is
  fully visible and each generation advances the picture by one whole
  row (discrete scrolling);
- otherwise (*continuous scrolling*): the fraction of the current delay
  that has elapsed since the last generation, so the picture slides up at
  a constant one cell per delay and the newest generation enters from the
  bottom edge. Cells stay crisp; the offset is quantized to device pixels.

**R-U4 (colors).** Each state maps to an RGB color through the active
*color set*: four colors in state order, state 0 the background. Ten
slots exist, bound to the digit keys `0`–`9`, loaded at startup from the
shared library (R-P4); a slot the file does not define is
undefined, and selecting it is a silent no-op. Slot 1 is the built-in
default, `ODCA default`, defined even without the file, and is active at
startup. The shipped file must define exactly these digit-bound sets
(this table is normative; a review session that changes the slots is a
spec change made here, and a test holds the file to the table):

| slot | name | state 0 | state 1 | state 2 | state 3 |
|------|------|---------|---------|---------|---------|
| 0 | Mysterious Midnight Magic | `#4F5188` | `#D6C0FB` | `#8C7BD0` | `#2C2A48` |
| 1 | ODCA default | `#121218` | `#EBEBE1` | `#FFA136` | `#409CFF` |
| 2 | Fiery Ice Cream Delight | `#102F47` | `#E78531` | `#F3C15F` | `#C53A32` |
| 3 | Golden Autumn Twilight | `#4D9CB9` | `#F4BA41` | `#EC8B33` | `#112F45` |
| 4 | Midnight Sun Dance | `#041523` | `#FCEDD4` | `#2E606B` | `#EE8432` |
| 5 | Seaside Serenity | `#ACCDEE` | `#6C95B7` | `#304B74` | `#E8ECEF` |
| 6 | Cherry Blossom Sky | `#2B2D40` | `#8F99AC` | `#EEF2F4` | `#DC3C44` |
| 7 | Ocean Sunset Vibes | `#325379` | `#DD5471` | `#F8D377` | `#62D3A3` |
| 8 | Jungle Safari Adventure | `#626C3E` | `#FDFAE3` | `#D4A369` | `#2B361C` |
| 9 | Mystic Moonlight Shades | `#333333` | `#A8A29D` | `#D3CCC8` | `#28262B` |

Slots 0 and 2–9 are palettes from coolors.co, recorded with their
sources in `colorsets/`, some already arranged by earlier sessions. The set active in a slot may be *arranged* — its
four colors assigned to the states in any of the 4! = 24 orders — with
`c` (R-K15); the arrangement is per set, kept for the session, and
recorded in the pairs that `s`/`S` save (R-K5).

**R-U5 (timing).** Generation pacing is governed by a *delay* — the
nominal time between generations — independent of the display refresh:

- Initial delay: in proportion to the cell size (R-U2), 1/60 s at 4
  points: 1/120 s at the default 2-point cell, 1/80 s for `--3`, 1/240 s
  for `--1`, so the picture moves at about the same speed in points
  whatever the cell; `+` and `-` (R-K8) work from there.
- The display refreshes at the screen's refresh rate (typically 60 or
  120 Hz), and implementations should pace refreshes from the display
  itself rather than a free-running timer; each refresh advances the
  automaton by ⌊elapsed_time / delay⌋ generations (with the fractional
  remainder carried forward), so rates far above the refresh rate are
  achievable; every generation is computed and enters the scroll buffer
  even when several occur per refresh.
- A per-refresh catch-up cap (implementation-chosen, ≥ 500 generations)
  must prevent a stall from freezing the program.

**R-U8 (resizing).** (Under `odca --longest` the width is fixed and only
the height follows the window, R-X8.) When the geometry changes: the
state vector keeps
its center — when narrower, cells are cropped equally from both edges;
when wider, new cells are added equally at both edges, seeded at random
in the live row and with state 0 in remembered rows — so the picture
stays put while the frame changes around it (the wrap seam moves; that is
accepted). The history remembers up to 2048 rows (never fewer than
`rows` + 1), so a taller window uncovers older generations rather than
showing blank rows; a shorter window hides them. Every boring detector
(R-A) restarts, since a resized automaton is a new system, and the
screenful-based windows take the new `rows`. A resize is not a rule
change: undo and the interesting-rule cycle are untouched. Prints R-O14.
While the window is being resized interactively, the animation and its
computation are frozen (the current state is simply re-fitted as the
frame changes); when the resize ends, time resumes from that moment with
no catch-up.

**R-U6 (window title).** The window title must show the current rule ID
(format: `ODCA — rule <id>`), kept current as the rule changes. (3.46.0
put the `--longest` generation counter here; since 3.48.0 it is on
standard output, R-O17.)

**R-U7 (shutdown).** Pressing `q` or closing the window exits the program
cleanly, stopping all background workers.

**R-U11 (on-screen counter).** Under `odca --longest` (R-X8) the
generation counter of R-O17, `<n>/<m>`, is also drawn on the picture,
full screen or not: in the lower-left corner, inset from the edges, in
yellow with a black outline about a point wide around the glyphs, in a
bold monospaced-digit face of 18 points, over whatever cells are there.
It is refreshed every frame, at the display's rate, while the terminal
counter keeps its five times a second and goes on regardless. It is
shown at startup; `o` (R-K20) hides and shows it. (3.52.0 to 3.52.2
drew it in full screen only.)

**R-U12 (title-bar double-click).** A double-click on the window's
title bar, which the platform treats as zoom (maximize or restore),
first returns a window that is not its natural size — the default
window of R-U2, or under `--longest` the seeds' width by the default
height — to that size, keeping its top-left corner where it was, and
does nothing else; a window already at its natural size zooms as the
platform would. So the first double-click on a resized window puts it
right, and the next toggles the zoomed state as ever. (The Python
implementation cannot see the double-click itself and acts on the
platform's maximize instead: a window that was not its natural size
when maximized is restored to that size at once; one that was stays
maximized, and the platform's next double-click restores it.)

**R-U9 (`--help`).** When `--help` appears anywhere on the command line the
program prints its help text to standard output and exits with status 0,
before reading or writing any persisted state (R-P), starting the
background search (R-S), or opening a window; nothing else is printed and
every other argument is ignored. The texts are the files
`conformance/help-odca.txt`, `conformance/help-odca-select.txt`, and
`conformance/help-odca-evolve.txt`,
reproduced byte for byte (each ends with a single newline); they name
every flag and key. Changing a text is a spec change made in that file.
Other command-line errors: a missing positional argument (or, for
`odca-select`, an extra one) or an
unknown option prints a one-line usage message and exits with status 2,
as does an option that takes a value (`--watchdog`, `--grace`) given
none, or one that is not a positive whole number;
`odca` on a file that does not exist prints `error: <file> does not exist`
and exits with status 1.

**R-U10 (flash).** A change that alters what the keys do without changing
the picture is confirmed by *flashing* the display: every displayed color
is inverted (each channel replaced by 255 minus itself, background
included) for 0.25 s of wall-clock time, paused or not, after which the
normal colors return. The flash is display-only: it neither paces nor
pauses computation. In 3.0.0 only `R` (R-W7) flashes.

---

## 3. Interactive program: keyboard commands (R-K)

All commands are single unmodified keypresses. Unassigned keys are ignored.

**R-K1 (`q`).** Quit (R-U7).

**R-K2 (`r` — new rule).** Obtain a new random rule that passed the
maybe-Class-IV screen: take the oldest rule from the candidate stash
(R-S4); if the stash is empty, search synchronously (R-C6, printing R-O2).
The new rule becomes current per R-B1 and occupies the unsaved slot
(R-B3). Cell contents are *not* reinitialized.

**R-K3 (`m` — mutate).** Replace the current rule with a mutation of it
(R-M10), becoming current per R-B1. In `odca-select` on a pair under
review, the pair is thereby *changed*: the cycle position stays, the
mutated rule shows in the pair's colors, `u`/`U` walk it back, `n`/`p`
discard it, and `s` or `S` save the screen as a new pair at the end of
the file (R-W4) — a kept rule is never overwritten by a mutation, since a
mutant is a different rule. Otherwise the mutation occupies the unsaved
slot (R-B3). Cells are not reinitialized.

**R-K4 (`u` — undo).** Rule changes (from `r`, `m`, `n`, `p`, `u`) push
the outgoing rule onto an unbounded undo stack; `u` pops the stack and
makes that rule current per R-B1. With an empty stack, `u` is a silent
no-op. Undo does not alter the interesting-rule cycle position or the
unsaved slot. `U` undoes many at once (R-K19).

**R-K5 (`s` / `S` — save a pair).** In `odca-select` (section 4c) only.
A *pair* is a rule with the active color set's name and arranged colors
(R-P3): a rule isn't interesting until an interesting way of presenting
it exists, so the two are saved together, and the same rule may be saved
again with other colors. `S` appends a copy of what is on screen — the
current rule and the active set, arranged — as a new pair at the end of
the file. `s` on a pair under review (R-B2) whose rule is still the
pair's own rewrites that pair's color set to the active set, arranged;
on a changed pair (its rule mutated, R-K3) `s` appends the screen as a
new pair, as `S` does, and moves the position onto it, so a further `s`
refines the new pair; `s` on the unsaved slot appends, exactly as `S`. Both write the file at once (R-W4) and print
confirmation (R-O12). Neither moves the cycle position. In `odca` the
file is read-only and both keys do nothing.

**R-K6 (`i` — initialize).** Set every cell to an independent uniformly
random state. The rule, scroll buffer, and all other state are unchanged
(the new row simply enters the scroll).

**R-K7 (`n` / `p` — cycle pairs).** See section 4; in `odca` they act as
`N`/`P` (R-X6).

**R-K8 (`+` / `-` — speed).** `+` halves the delay; `-` doubles it,
clamped to [1/16384 s, 8 s]. Implementations should also accept the
unshifted equivalent of `+` (e.g. `=` on US layouts) and keypad `+`/`-`.

**R-K9 (digits `0`–`9`).** Select the corresponding digit-bound color set
(R-U4) — the "hot ten" — as the active set; an undefined slot is a
silent no-op.

**R-K10 (spacebar — pause).** The spacebar freezes the display animation:
no further generations are computed or shown until the spacebar is pressed
again, which resumes at the normal rate with no catch-up burst (elapsed
pause time is discarded). Resuming computes exactly one generation on the
first refresh so that the picture, which showed the newest row fully while
paused, continues without a jump (R-U3). While paused, every key except
the spacebar, Return (R-K11), `s` (R-K13), `c`/`C` (R-K15), `[`/`]`
(R-K17), the digits (R-K9), the pair keys `S`, `X`, `R` (section 4c) and
`N`/`P` (section 4d), `F` (R-K18), and `q` is ignored; `q` quits normally. Those keys
touch colors and files, never the running computation (the re-seed that
navigation makes, R-W8, is the exception, being part of the navigation;
the new field then waits for the resume), so they remain live. Pausing does not stop the background
search (R-S).

**R-K11 (Return — single step).** While paused, Return computes and
displays exactly one generation, and the program remains paused. When not
paused, Return is ignored. Implementations should also accept keypad
Enter.

**R-K13 (`s` while paused — one screenful).** While paused, `s` queues
one screenful — `rows` generations (R-U2) — which are then computed and
displayed paced at one eighth of the current delay (R-U5), after which the
program is still paused. Each further press queues another screenful.
Resuming with the spacebar discards any queued screenfuls. (When not
paused, `s` saves the rule, R-K5.)

**R-K14 (screen counter).** Resuming from pause with the spacebar
(re)starts a screen counter at zero. From then on, each time `rows` more
generations have been computed — by timed evolution, single step, or a
zipped screenful — the counter increments and its value is printed
(R-O7). Pausing does not stop or reset the counter; only the next resume
resets it. Before the first resume of a run the counter is inactive.

**R-K15 (`c` — arrange colors).** Advance the active color set to the next
of its 24 arrangements — the assignments of its four colors to states 0–3
in lexicographic order of state permutations, starting from the set as
loaded — wrapping after the 24th, and print the position (R-O9). `C` (shift-c)
steps to the previous arrangement, wrapping from the 1st to the 24th.
Each color set keeps its own arrangement (by name) for the session.

**R-K16 (bake an arrangement — unbound).** Replacing the active color
set's colors in its library entry (R-P4) with its current arrangement
(which becomes arrangement 1 of 24; a set not yet in the file is added,
keeping its slot if it has one; prints R-O10) was `S` until 3.0.0. No
program binds it in 3.0.0 — `S` saves a pair (R-K5) — and the behavior is
reserved for the color set tool (section 4b). Implementations may keep
it reachable only where no program is running (tests).

**R-K17 (`[` / `]` — the whole pool).** In every mode, step the active
color set backward / forward through the whole pool in pool order (the
digit-bound sets by key 1–9, 0, then the pool-only sets), wrapping, and
print the name (R-O15). Stepping onto a digit-bound set also makes it the
digit position. In color set review (section 4b) these keys are synonyms
for `P` / `N`. Live while paused, like the other color keys (R-K10).

**R-K18 (`F` — full screen).** In every mode, enter full screen if the
window is not in it, by whatever route it got there, and leave it if it
is (R-U2). A window key, not a session key: nothing about the automaton,
the undo stack, or the pair cycle changes, and it is live while paused
(R-K10). The platform's own controls keep working alongside it.

**R-K20 (`o` — on-screen count).** Under `odca --longest` (R-X8) hide
or show the on-screen generation counter (R-U11); shown at startup, not
persisted. Live while paused, like `F` (R-K18); nothing elsewhere.

**R-K19 (`U` — undo all).** Undo, in one step, every rule change made
since the last *arrival*: the pair under review being selected (R-B2),
`r` bringing a fresh rule to the unsaved slot (R-B3), or, in `odca`, the
pair starting to play (R-X4); before any arrival, since startup. A
mutation is an edit, never an arrival, on the unsaved slot as on a pair. The stack
(R-K4) is unwound to that depth and the rule beneath becomes current per
R-B1; the position, the unsaved slot, and the colors are untouched, so on
a pair under review `U` returns the pair to its recorded rule. With
nothing to unwind, a silent no-op. Not live while paused, like `u`.

**R-K12 (`a` — auto-initialization).** Toggles auto-initialization mode
(section 4a) and prints its new state (R-O6). The mode is on at startup
(since 2.13.0; it was off while the filter was being tuned) and is not
persisted.

---

## 4. The pair cycle (R-B)

**R-B1 (rule change).** Whenever the current rule changes — via `r`, `m`,
`u`, `n`, or `p` — the program must persist it as the current rule (R-P1)
and print it (R-O1).

**R-B2 (the cycle).** In `odca-select`, the pairs of the odca file (R-P3),
in *view order* (file order, or grouped by rule after `R`, R-W7), form a
cycle of n+1 slots: slots 0…n−1 are the pairs and one extra slot holds the
*unsaved rule*. `n` steps forward one slot (mod n+1) and `p` steps backward
one slot; a pair's rule becomes current per R-B1 (pushing undo per R-K4)
and its colors become the active color set at arrangement 1 — a pair is a
presentation, not just a rule — and the position is printed (R-O4). Every
step then re-seeds the cells and scrolls the pair in (R-W8). Pairs appended during the session are
reached in turn.

**R-B3 (the unsaved slot).** The unsaved slot holds the most recent rule
that arrived from outside the file: the startup rule (unless the file
opened on pair 1, R-W1), the last rule produced by `r`, or the last
mutation made while on the slot — together with the color set that was
active when it arrived, which is restored with it. When `r` fires, or `m`
fires on the unsaved slot, the new rule occupies the slot and the cycle
position moves to (or stays on) it; `m` on a pair is an edit of that pair
and moves nothing (R-K3). While the unsaved slot is empty — the file
opened on pair 1 and no `r` has fired yet —
the cycle consists of the n pairs only. When the cycle position is on the
unsaved slot, the first `n` selects the first pair and the first `p` the
last. Deleting the last remaining pair (R-W5) puts the rule on screen into
the unsaved slot so the cycle stays usable.

**R-B4 (no pairs).** If the file has no pairs — or in `odca`, which has no
cycle — `n` and `p` print a notice (R-O5) and change nothing.

---

## 4a. Auto-initialization (R-A)

When enabled (R-K12), the program re-initializes the cells by itself once
the automaton has become *uninteresting* — timed so that the last
interesting row has just scrolled off the top of the display.

**R-A1 (boring generation).** A computed generation is *boring* if either:
- *extinction*: some state that the current rule can produce (i.e. that
  appears among its 20 table entries) has zero cells in the row, **and**
  no other producible state is a *living minority* — present, but in
  fewer than 10% of the cells. A living minority is a shrinking or
  drifting group whose fate is unresolved (two domain walls converging,
  say); the extinction counts only once such groups have vanished, so the
  user sees the collision; or
- *repetition*: the automaton has entered a cycle. Because the automaton
  is deterministic, a row that recurs proves the future periodic forever,
  so once a cycle is recognized every later generation is boring. Two
  mechanisms recognize cycles, and either suffices:
  - a *window*: the row is identical to a row produced within the
    previous 10 × `rows` generations (ten display heights, R-U2), which
    catches cycles of period up to ten screens one period after lock-in;
  - *Brent's algorithm*: a single saved row, compared against each new
    generation and replaced by the current row whenever the number of
    generations since it was saved reaches a power of two. A match means
    a cycle whose period is exactly the generations since the save. This
    finds a cycle of any period with constant memory, within a small
    multiple of transient plus period; the period is printed on detection
    (R-O8) and reported in the reason. Or
- *stagnation*: the minority population — the total number of cells in
  living-minority states — has held steady over the previous 4 × `rows`
  generations: its swing (maximum minus minimum, divided by its mean) is
  below 0.25, with a nonzero mean. A steady minority population is a
  structure drifting in parallel with nothing growing or shrinking: a
  long-period repetition that exact row matching cannot see.
The reason reported (R-O6) is the first of extinction, repetition with a
known period (`repeating (period <n>)`), window repetition (`repeating`),
stagnation that applies.
Generations are classified whenever they are computed, whether by timed
evolution (R-U5) or single step (R-K11); the seed row itself is not
classified.

**R-A2 (trigger).** When the mode is on and the most recent `rows`
consecutive generations were all boring — the display shows nothing but
boring rows — the program re-initializes every cell exactly as `i` does
(R-K6) and prints the reason (R-O6). The reason is the extinction, when
present, else the repetition.

**R-A3 (reset).** The consecutive-boring count and the repetition window
reset on any rule change (R-B1) and on any re-initialization, manual or
automatic, as do the stagnation history and the cycle detector state
(saved row and detected period); a non-boring generation resets the
count. Consequently every
new rule and every fresh seed gets a full screen of generations before it
can be judged. The count is maintained whether or not the mode is on, so
enabling the mode on an already-boring screen may trigger on the next
generation.

**R-A4 (interactions).** Nothing triggers while paused except through
single steps, since no other generations are computed; the background
search (R-S) is unaffected.

---

## 4b. Color set review mode (R-V)

A mode for auditioning the whole color set pool and deciding, one set at
a time, what to keep. **On hold in 3.0.0:** no program binds it (it was
`--colorset-review` until 2.36.0); it will return as its own program when
the color set workflow is taken up again. The behavior stays specified
and tested so the session layer keeps it.

**R-V1 (entry).** Entered by construction of the session in review mode
(no command-line flag in 3.0.0). Everything else behaves as usual, except
that the digit keys (R-K9) are disabled and `S` has no binding.

**R-V2 (review order).** On entry the program builds the review list:
the digit-bound sets in key order 1, 2, …, 9, 0; then the pool-only sets
in file order; then every palette from the candidates file (R-P4) whose
name is neither already present nor in the dropped list, in candidates
order. Slot 1's built-in default is included if the file defines no slot
1. The review position starts at the first set, which is displayed, and
the position is announced (R-O11).

**R-V3 (`N` / `P`).** Step to the next / previous kept set and display
it, announcing the position. Stepping past either end wraps to the other
end and prints `review wrapped` first. Both keys are live while paused,
like the other color keys (R-K10).

**R-V4 (`X` — drop).** Remove the current set from the review list, add
its name to the dropped list, print `dropped <name>`, display the next
kept set (wrapping to the first, with the wrap message, if the dropped
set was last), and save (R-V5). Subsequent `N`/`P` skip dropped sets.
Dropping a digit-bound set is allowed; slots are reassigned on save.

**R-V5 (save).** Every drop, and program exit, write the kept sets to the
color sets file (R-P4): the first ten kept sets in review order are bound
to the digit keys in the order 1, 2, …, 9, 0 — so dropping a bound set
rotates the later ones down and fills the top key from the pool — and the
rest are pool-only. The dropped list is written in full. Prints `saved <k>
color sets, <d> dropped`. `S` has no binding in this mode.

**R-V6 (arrangement).** `c`/`C` arrange the set under review for preview
only, remembered per set for the session and never written to the pool;
arrangements are recorded in pairs instead (R-P3).

**R-V7 (steps fill the screen).** Every `N`/`P` step, and the display of
the next set after `X`, immediately computes and displays a full
screenful (`rows` generations) under the newly shown set, paused or not
(the review keeps the screen fill that `odca-select` gave up in 3.24.0).

---

## 4c. odca-select (R-W)

The workbench: show screened random rules, dress each in a color set,
and collect the results as pairs in an odca file (R-P3).

**R-W1 (entry).** `odca-select <file.odca>` — the file is the one
required argument (R-U9 for errors). If it exists its pairs are loaded;
if not, nothing is written until the first save or exit (R-W4). On entry
the program prints `odca <file>: <n> pairs` (R-O12) and, if the list is
non-empty, activates pair 1 (R-B2: its rule and colors, then a fresh
field, R-W8) with the unsaved slot empty; otherwise the startup rule occupies the
unsaved slot (R-U1). Every ordinary key keeps its meaning except as
redefined here; the pool of color sets is the library loaded at startup
(R-P4).

**R-W2 (`n` / `p`).** The pair cycle of section 4.

**R-W3 (choosing colors).** The digit keys select their bound sets as
usual; `[` and `]` walk the whole pool (R-K17); `c`/`C` arrange the
active set (R-K15). Selecting a set resets its arrangement to 1. Together
with `r`, `m`, `n`, `p`, and `u`, this composes what `s` and `S` record
(R-K5).

**R-W4 (`s` / `S` — record; autosave).** As R-K5: `S` appends a copy of the
screen, the position unchanged; `s` rewrites the pair under review's
colors in place, or, when its rule has been mutated or when on the
unsaved slot, appends the screen as a new pair — moving the position onto
it in the mutated case (an arrival, R-K19). Every `s`, `S`, and `X` writes the whole file at
once, in file order, and prints `saved <n> pairs to <file>`; program exit
writes it again (creating a missing file, empty if need be).

**R-W5 (`X` — delete).** Remove the pair under review, write the file, and
activate the pair now at that view position (the previous one if the last
was removed); if the list becomes empty, the current rule keeps running
and becomes the unsaved rule (R-B3). On the unsaved slot `X` does nothing.

**R-W6 (pause).** `S`, `X`, `R`, `[`, `]`, and the digits remain live
while paused (R-K10); `s` while paused keeps its pause meaning (R-K13).

**R-W7 (`R` — grouped order).** Toggles the view order of the cycle
(R-B2) between file order and *grouped by rule*: all pairs sharing a rule
together, groups in order of each rule's first appearance in the file,
pairs within a group in file order — so that a rule's color sets can be
compared for excessive similarity. Prints `pair order grouped by rule` or
`pair order file order` (R-O12) and flashes the display (R-U10). The pair
under review stays under review across the toggle. In the grouped order,
when an activation crosses into a different rule's group,
`--- rule group <g>/<G> ---` is printed first. The file order is never
changed by the view: `s` and `X` act on the pair at its file position, `S`
appends to the end of the file (the new pair joins its rule's group in the
view, at the end of that group or as a new last group).

**R-W8 (navigation scrolls the pair in).** Every activation by `n`/`p` —
a pair or the unsaved slot — and the activation after `X` re-seeds the
cells as `i` does (R-K6) and lets the activated presentation grow in from
that fresh field below the old rows, exactly as a transition does in
`odca` (R-X4), so the two programs feel alike. The old rows recolor at
once, as everything in `odca-select` does (R-X5); nothing is computed
ahead. (2.24.1 to 3.22.0 filled the screen with a screenful at once
instead; withdrawn as jarring beside `odca`.)

---

## 4d. odca (R-X)

The art: play a *show* — the pairs (R-P3) of one or more files, one
after another.

**R-W9 (`--longest`).** `odca-select <file.odca> --longest` behaves as
without the flag except in which pairs it presents: only those whose
rule has seeds in the file (R-P3, section 4e) at any width, survivors
included — the pairs `odca --longest` (R-X8) can play, plus those whose
seeds all survived. The n/p cycle (R-B2), the grouped order (R-W7), the
`pair <i>/<n>` numbering of R-O4 and R-O12, and the rule groups count
those pairs alone; the unsaved slot (R-B3) is in the cycle as ever. On
entry the program prints `odca <file>: <n> pairs, <k> with seeds`
(R-O12) and opens on the first shown pair; with none shown, the loaded
rule occupies the unsaved slot as for an empty file (R-W1). Nothing is
seeded from the recorded rows: every activation re-seeds at random as
R-W8 says. `s` rewrites the pair under review's colors in place and `S`
appends as R-W4 says; a pair appended here joins the cycle only if its
rule has seeds (a copy of a shown pair does; one made after `r`, or by
`s` after a mutation, does not, and is saved but not shown), and the
position stays on the pair under review rather than moving onto the
new pair.
`X` deletes the rule's seeds from the file, at every width, and leaves
the pair in the file: it prints `deleted seeds of pair <i>/<n> <name>
<colorset>` (R-O12), every pair on that rule leaves the cycle, the file
is written at once with the seeds it has left, and the cycle moves on
as after R-W5 (to the next shown pair, or, with none left, the rule on
screen becomes the unsaved rule). Without the flag the file's seeds are
carried through every write untouched.

**R-X1 (entry and order).** `odca <file> [<file> ...] [--shuffle]` — one
or more files, each a play script (R-X7) or an odca file (R-P3), which
plays as a script that imports it and plays it: `odca a.odca` plays the
pairs of `a.odca` in file order, as it always has. Every file must exist,
and every script must read without error (R-X7), before anything else
happens (R-U9 for the `--help` and usage cases; otherwise exit status 1
after one line, `error: <message>`). On entry the program prints `odca
<file>: <n> pairs` for each file in turn (R-O13) and, if any has pairs,
plays the first. The show is the files' pairs: each file's pairs in
their order, the files in command-line order, looping from the last pair
of the last file back to the first indefinitely; a file with no pairs
takes no turn. With `--shuffle` each *pass* — every file once — is a
fresh uniformly random permutation of the files in which the first file
with pairs is not the file that closed the previous pass (when two or
more files have pairs; the program redraws until it holds), and the
pairs within a file keep their order unless its own script says
`shuffle` (R-X7): the flag is about files, never their
contents. (From 3.0.0 to 3.26.0 `odca` took one odca file and
`--shuffle` permuted its pairs, from 3.12.0 under the constraints that
`shuffle` now carries.) A show with no pairs leaves
the program running as usual; no file is written. `--longest` makes a
different show, of the recorded seeds (R-X8).

**R-X2 (equal screen time).** Every pair gets the same screen time: a
*watchdog* of 120 unpaused seconds by default, or the whole number of
seconds given by `odca --watchdog SECONDS`, counted from the moment the
pair starts and unaffected by re-initializations. Until it expires,
auto-initialization behaves as everywhere else (R-A2): the pair is
re-seeded in place, as often as it takes, and stays on screen.

**R-X3 (transition).** Once the watchdog has expired, the program advances
to the next pair of the pass at the first of: (a) the *grace period*
being satisfied — 60 unpaused seconds by default, or the whole number of
seconds given by `odca --grace SECONDS`, since the pair's last
initialization, automatic or manual — or (b) the boring detector firing,
which then transitions (with its reason) instead of re-seeding in place.
A manual `i` (R-K6) never transitions; it restarts the grace period only,
before or after expiry. Neither clock runs while paused. With
auto-initialization off (R-K12), only (a) applies.

**R-X4 (playing a pair).** Playing a pair sets its rule (a rule change,
R-B1, printed and persisted, but not pushed on the undo stack), makes its
stored colors the active color set at arrangement 1, re-seeds the cells
as `i` does (R-K6) — except that when the file (or, in a script show,
any odca file the script imported) records seeds for the pair's rule at
exactly the current width (R-P3, section 4e), the cells are the
longest-lived of those seeds instead of random; every other
initialization, `i` or auto-init, is random as ever — and starts both
clocks. There is no screen fill: the
previous pair scrolls off the top as the new one grows in from its fresh
field — the transition, until cross-fades exist. Every ordinary key keeps
its meaning; `s`, `S`, `X`, and `R` do nothing.

**R-X5 (rows keep their colors).** In `odca` a change of color set — a
transition, or a digit or arrangement key — applies only to rows
generated from then on; rows already displayed keep the colors they were
painted with for as long as they are remembered (R-U8), so the color set
changes along a row boundary moving up the screen rather than everywhere
at once — however many changes follow each other, even several within
one screenful. (In `odca-select` the whole screen recolors immediately,
as the workbench expects.) *Implementation note (informative):* each row
records an index into a table of the color sets rows have been painted
with; a changed active set adds an entry (or reuses an identical one),
and entries no remembered row uses any more are dropped once the table
grows past a limit.

**R-X6 (`N` / `P`, `n` / `p`).** Step to the next / previous pair of the
pass by hand, exactly as an automatic advance would (R-X4: rule, colors,
fresh seed, watchdog restarted), wrapping at both ends of the pass (a
forward step past the end starts a new pass, R-X1); the announcement's
reason reads `next` or `previous`. Live while paused.

**R-X7 (play scripts).** A play script is a text file, by convention
with the extension `.play` (any extension but `.odca` is read as a
script), of one statement per line; `#` starts a comment that runs to
the end of the line, and blank lines are allowed. The statements:

- `import <file>` — the pairs of an odca file (R-P3), in file order,
  appended to what the script has imported so far. The name is a bare
  word (no blanks, `#`, or `"`) or a double-quoted string (no escapes),
  resolved relative to the script's own directory. The file must exist
  and be an odca file (a JSON object with a `pairs`, or the old `looks`,
  key); its malformed pairs are skipped as R-P3 says.
- `play` — play every pair imported above, once each, in that order.
- `shuffle` — the same pairs, but each *pass* through them is a fresh
  uniformly random permutation of all of them — every pair plays once
  before the next pass — in which no two
  consecutive pairs share a rule or a color set (the same four colors in
  any arrangement), the seam included: the first pair of a pass may
  share neither with the pair that played before it, which in a show of
  several files is the last pair of the file before it in the pass (for
  the pass's first file, the pair still on screen). The program draws a
  permutation and tests it, redrawing the whole sequence on a failure,
  up to a hundred times (six pairs with every rule and every color set
  appearing twice pass a draw one time in twelve, so ten draws would
  miss two passes in five; a hundred, one in six thousand, at no
  measurable cost); a set of pairs that allows no such order (one pair,
  or every pair on one rule, for instance) then plays the last draw as
  it is, so the show never stalls.

A script says `play` or `shuffle` at most once, and never both; either
ends its imports, and a script that says neither plays nothing. Both
words are verbs — the script says what to do with the pairs it has
imported — so `shuffle` stands beside `play` rather than qualifying it.
`import`, `play`, and `shuffle` are reserved: a file of one of those
names must be quoted.

The first error stops the program before any window opens (R-X1): a
syntax error as `error: <script>:<line>:<column>: <message>` — the
messages are `syntax error, unexpected word <word>, expecting import,
play or shuffle`, `syntax error, unexpected end of line, expecting
word`, `syntax error, unexpected <token>, expecting end of line` (and
with a keyword where a name belongs, `expecting word`), `unterminated
quote`, `empty file name`, `<word> given twice` and `<word> after
<word>` for a second `play` or `shuffle`, and `import after <word>`, lines
and columns counted from 1 (`conformance/scripts/` holds the cases,
TESTS.md) — and an import that fails as `error: <script>:<line>: cannot
read <file>` or `error: <script>:<line>: <file> is not an odca file`.
The scanner and parser are one C program generated by flex and bison
from `script/show.l` and `script/show.y` (`script/regen`), emitting JSON
that every implementation consumes; an implementation may parse by any
means that gives the same results, the shared parser being the
reference. The language grows by increments, each a change to this
requirement.

**R-X8 (`--longest`).** `odca <file.odca> [<file.odca> ...] --longest
[--shuffle] [--cells N]` plays a different show: the seeds `odca-evolve`
recorded (section 4e, R-P3) instead of random rows. Only odca files are
accepted (a play script is an error, `error: <file>: --longest plays
odca files only`); `--watchdog` and `--grace` are usage errors with it,
and `--cells` without it (R-U9). A pair's *playable seeds* are its
rule's seeds at the show's width, longest first, less those that
survived the cap (`end` = `survived`, R-E2): a row that never met the
extinction is not interesting almost by definition, so a rule with
nothing but survivors has none and is left out of the show, as is a
pair whose rule has no seeds at all. The width is the one width at which
the files record playable seeds for their pairs' rules; when they record
several, `--cells N` chooses (`error: seeds at 600, 1080 cells: choose
one with --cells` without it; `error: no seeds at N cells (600, 1080)`
for a width that has none); with no playable seed anywhere, `error: no
seeds to play`. All of this is settled before any window opens, exit
status 1.

The show is the sequence of *items*, a pair with one of its playable
seeds: every pair's longest, then every pair's second longest, and so on
until the ranks are exhausted, the pairs in file order and the files in
command-line order; it loops. With `--shuffle` each pass is instead a
fresh uniformly random permutation of all the items under the
constraints of `shuffle` (R-X7): no rule and no color set follows
itself, the seam from the item just played included, a hundred draws
and then the last one as it is (a single pair with seeds allows no such
order and plays its seeds in whatever order the draw gives). Playing an
item is R-X4 with the seed's row as the cells, generation 0, announced
as R-O13 says. There are no clocks: an item plays until the boring
detector fires by extinction (R-A2: a screenful of rows past the
extinction `odca-evolve` measured, which the same detector finds at the
same generation), and the next item begins with that reason; repetition
and stagnation never end an item (the detector restarts instead), and
auto-initialization never re-seeds in place. `i` (R-K6) restarts the
item's seed from its first row; `a` (R-K12), `r`, `m`, `u`, and `U` do
nothing; `s`, `S`, `X`, and `R` do nothing as in every show; the color
keys, `N`/`P` and `n`/`p` (R-X6), speed, pause, and single step keep
their meanings.

The window opens as wide as the seeds, `cols × cell_size` points, its
height the default (or the screen's under `--fullscreen`); the width in
cells never changes. Whatever the window's or screen's width afterwards
(full screen, `F`, a drag), the grid is stretched or shrunk to span it,
in both directions alike so cells stay square: the on-screen cell is
`cell_size × factor` points with `factor` = window width / (`cols` ×
`cell_size`), the rows are as many such cells as fit the height,
`rows` = ⌊height / (`cell_size` × `factor`)⌋ (never fewer than one),
centered with the remainder in black margins above and below, and
scrolling moves in scaled cells. A whole-number factor is drawn with
nearest-neighbor scaling, every cell the same size; a fractional one
with linear filtering, so cells do not alternate in size (a faint
softness at the edges is the price). The rows follow the window (R-U8's
cropping and padding apply to rows alone). The cell size flags set the
natural size, and so the window's width at launch. (3.44.0 to 3.48.1
kept the natural size and showed black bars or a centered crop
instead.)

---

## 4e. odca-evolve (R-E)

The search: which starting rows keep a rule alive longest?

**R-E1 (entry).** `odca-evolve <file.odca> --cells N --time SECONDS
[--cap N] [--parity]` — the file is the one required argument and must exist and
hold at least one pair (else `error: <file> does not exist` / `error:
<file>: no pairs`, exit 1); `--cells`, the width of the rows, a whole
number of 3 or more (R-M2), and `--time`, the budget per rule in whole
seconds, are required; `--cap` (R-E2) is a whole number of generations,
100000 by default (R-U9 for `--help` and the usage errors: a missing
required option prints `odca-evolve: --cells is required`, exit 2). The
program opens no window, starts no background search (R-S), and neither
reads nor writes `$HOME/.odca` (R-P1, R-P2).

**R-E2 (the search).** The program takes up each distinct rule of the
file's pairs in order of first appearance and prints its line (R-O16).
For the budget, one worker per processor repeats independently of the
others: draw a row of `--cells` cells, each uniformly random over the
four states (R-N1), and evolve it in wrap mode generation by generation
until either the first generation that is boring *by extinction* — R-A1's
first clause exactly, some producible state with no cells and no other
producible state a living minority, the seed row itself unclassified —
which gives the row's *lifetime*, the count of generations computed,
and its *end*, the extinction text of R-O6 (`state 3 extinct`, `states
1, 2 extinct`); or the cap, `--cap` generations computed without that,
which gives lifetime `--cap` and end `survived`. Repetition and
stagnation (R-A1) play no part: a row that settles into a cycle with
every producible state alive lives to the cap. A row still evolving
when the budget ends, or when the program is interrupted (R-E4), is
discarded. The conformance vectors (TESTS.md, `lifetimes`) fix the
measure.

**R-E3 (the ten).** For the rule and width in hand the program keeps at
most ten seeds, longest first, ties broken by the row text ascending,
each row at most once. It starts from the seeds the file already
records for that rule and width (R-P3), so runs accumulate: a measured
row joins when fewer than ten are kept or its lifetime exceeds the
shortest kept, which it displaces; a lifetime equal to the shortest does
not join. Each join is printed (R-O16). When the budget ends the file is
rewritten (R-P3): its pairs unchanged, this rule's list at this width
replaced by the ten, every other rule's and width's seeds untouched.
Then the next rule.

**R-E5 (`--parity`).** With the flag, each rule is judged as its turn
comes (R-E2), on the seeds as they stand at that moment — the file's,
and those this run has found and written for the rules before it: if
the rule's *shortest* recorded lifetime at the run's width, times 0.9,
is longer than the *longest* lifetime any other rule of the file's
pairs holds at that width, the rule gives up its turn — it prints its
line with `, skipped: shortest <s> × 0.9 outlives <l>` (R-O16), no
seeds line, and the program takes up the next rule at once, the time
going to the rest. Lifetimes count as recorded, a survivor's as the
cap, so a rule holding nothing but survivors gives up its turn for as
long as another rule holds anything shorter. A rule with fewer than
ten seeds is judged on those it has; one with none never gives up its
turn, and neither does any rule when no other rule holds seeds at the
width. Seeds of rules not among the file's pairs do not count.

**R-E4 (countdown and interruption).** While a rule is searched and
standard output is a terminal, the time left in its budget is shown as
`hh:mm:ss` (two digits each, rounded up to the second, so `00:04:59`
with just under five minutes to go), starting at the left margin so it
sits in the column of the times that open the status lines (R-O16),
followed by two spaces and the rule's recent rate, `<n> seeds/s`: the
rows whose lifetimes finished over the last ten seconds (the last ten
redraws; fewer until ten have passed) divided by the seconds they span,
rounded to a whole number (`0` on the first draw); the whole redrawn in
place about once a second and cleared before any other line is printed;
when output is not a terminal it is not shown. The rate is recent, not
cumulative from the rule's start: a cumulative average carries the rows
in flight, one per worker, as a deficit that shrinks like 1/t and would
creep upward long after the search had settled. On SIGINT (Ctrl-C) the workers are stopped, the rule in hand is
written as R-E3 says with the seeds it has so far, and the program exits
with status 130 without taking up the next rule.

---

## 5. Persistence (R-P)

All per-user state lives in the directory `$HOME/.odca/`, created on
demand. Loaders must treat a missing or malformed file as empty/absent —
never as an error that prevents startup.

**R-P1 (current rule).** File `$HOME/.odca/rule`: the current rule's ID
followed by a newline. Written on every rule change; read at startup
(R-U1). Invalid content → fall back to a random rule.

**R-P2 (candidate stash).** File `$HOME/.odca/candidates`: one rule ID per
line, oldest first — the persisted form of the candidate stash (R-S4).
Rewritten whenever the stash changes; read at startup. Invalid lines are
skipped.

**R-P3 (odca file).** A JSON file, by convention with the extension
`.odca`, named on the command line of both programs: an object with a
`pairs` array; each pair has `rule` (a rule ID, R-M8), `colorset` (the
color set's name, for reference), and `colors` (four `#RRGGBB` strings,
states 0–3, already arranged), so a file plays even if the library is
later edited, and `name`, written first. Names are unique within a file
and generated by `odca-select`: `pair-NNNN`, one past the highest number
in use in the file, four digits and more once they are needed
(`pair-10000`), given to every unnamed pair when the file is loaded and
to every appended pair; the file records them at its next write, at exit
at the latest. `odca` never writes, so a hand-made file's pairs may be
nameless there. Until 3.26.0 the array key was `looks` and the pairs were
called looks; the old key is still read, never written. Since 3.36.0 the
object may also hold `seeds` (section 4e): an object keyed by rule ID,
each an object keyed by width (a whole number as a string), each an
array of at most ten seeds, longest first, each `row` (one digit per
cell, as many as the width), `generations` (the lifetime, R-E2), and
`end` (the extinction text, or `survived`). `odca-evolve` writes it;
`odca` reads it (R-X4); `odca-select` carries it through unchanged when
it rewrites the file. The section is omitted when there are no seeds,
and its rule keys are written sorted, its widths ascending. Malformed
seeds — a row of the wrong width or with a bad digit, a width below 3, a
key that is not a rule ID — are skipped. Malformed pairs
are skipped; an unparseable file loads as empty;
a missing file is distinguishable from an empty one (R-W1). Written in the
layout of R-P4. The repository ships `interesting.odca`, the collection of
pairs kept so far, as an example (until 3.0.0 `interesting-rules.json`
with a `pairs` key, which is no longer read).

---

**R-P4 (library).** File `library.json` in the repository root, shared by
all implementations (each must document how it anchors this path; until
3.0.0 `colorsets/colorsets.json`): the *pool* of every kept color set.
JSON: an object with a `sets` array and a `dropped` array. Each set has
`name` (string), `colors` (four strings `#RRGGBB`, states 0–3), and
optionally `slot` (integer 0–9): sets with a slot are bound to that digit
key (R-U4), sets without one are pool-only. `dropped` lists the names of
sets rejected in review (section 4b), so that re-seeding from the
candidates file never resurrects them; it may be edited by hand. Readers
must ignore malformed sets and treat a missing or unparseable file as
empty; the built-in default (R-U4) always fills slot 1 unless the file
defines it. Writers preserve what they do not change: the review save
(R-V5) rewrites everything; digit-bound sets are written first, sorted by
slot number, then the pool in order. Neither program writes the library
in 3.0.0. The raw source of candidate palettes is
`colorsets/candidates.json` (an object with a `palettes` array of `name`
+ `colors`), which the program only reads.

**R-P5.** Merged into R-P3 in 3.0.0 (the screensaver file and the keeper
file were the same format; the odca file is that format).

---

## 6. Terminal output (R-O)

The program prints single-line, human-readable status to standard output:

- **R-O1.** On every rule change (including startup): `rule <id>`.
- **R-O2.** After a synchronous screening search that rejected k ≥ 1
  rules: `discarded <k> rule` (k = 1) or `discarded <k> rules` (k > 1),
  before the R-O1 line.
- **R-O3.** Retired in 3.0.0 (`s` reports through R-O12).
- **R-O4.** On `n`/`p` selecting the pair at view position i (0-based) of
  n: `pair <i+1>/<n> <name> <colorset>` (the name omitted when the pair
  has none; rule IDs are opaque at a glance and are not printed);
  selecting the unsaved slot: `unsaved rule`. Either
  precedes the R-O1 line.
- **R-O5.** On `n`/`p` with no pairs to cycle: `no pairs`.
- **R-O6.** On `a`: `auto-init on` or `auto-init off`. On an automatic
  re-initialization: `auto-init (<reason>)`, where reason is
  `state <k> extinct` (or `states <k>, <l> extinct`, ascending),
  `repeating (period <n>)`, `repeating`, or `stagnant`;
- **R-O7.** On each completed screenful while the screen counter is active
  (R-K14): `screen <n>`.
- **R-O8.** When Brent's algorithm first detects a cycle since the last
  reset (R-A3), whether or not auto-initialization is on:
  `cycle period <n>`.
- **R-O9.** On `c`/`C`: `color set <name> arrangement <k>/24`, k from 1.
- **R-O10.** On baking an arrangement (R-K16, unbound): `saved color set <name>`.
- **R-O15.** On `[`/`]` (R-K17): `color set <name>`.
- **R-O11.** In review mode (section 4b): on entry and on every step,
  `review <i>/<n> <name>` (1-based position among the kept sets); `review
  wrapped` before a step that wraps; `dropped <name>` on `X`; `review
  empty` when nothing is left; `saved <k> color sets, <d> dropped` on
  save. Arrangement messages (R-O9) name the set instead of a slot.
- **R-O12.** In `odca-select` (section 4c): on entry `odca <file>: <n>
  pairs`; after every write `saved <n> pairs to <file>` (`1 pair`); `saved
  pair <i>/<n>` on `s` over a pair, `added pair <n>/<n>` on an append,
  `deleted pair <i>/<n>` on `X` (under `--longest`, R-W9, `deleted
  seeds of pair <i>/<n> <name> <colorset>`, and the entry line `odca
  <file>: <n> pairs, <k> with seeds`); `pair order grouped by rule` / `pair
  order file order` on `R`; in the grouped order, `--- rule group
  <g>/<G> ---` before an activation that enters a different rule's group.
  Arrangement messages (R-O9) name the set.
- **R-O14.** On a geometry change (R-U8): `resized <cols>x<rows>`.
- **R-O17.** In `odca --longest` (R-X8), on standard output when it is
  a terminal: the generation counter `<n>/<m>`, n the generation on
  screen (the seed's row is 0) and m the seed's recorded lifetime,
  redrawn in place (carriage return, erase to the end of the line, no
  newline) five times a second, and cleared before any other line is
  printed, so the pair and rule lines stand alone; when standard output
  is not a terminal the counter is not shown. Nothing else prints in
  place. In full screen the same counter is also drawn on the picture
  (R-U11).
- **R-O16.** In `odca-evolve` (section 4e), and nothing else, every
  line opening with the time then left on the rule's budget in the
  `hh:mm:ss` of R-E4 and a space, so the lines compare with each other
  and with the countdown: as each rule is taken up, `rule <id>
  (<i>/<n>): <cells> cells` (opening with the whole budget); as each row
  joins the ten, `kept <generations> generations, rank <r> (<end>)` with
  its 1-based place at the moment it joined; under `--parity` (R-E5), a
  rule that gives up its turn prints `rule <id> (<i>/<n>): <cells>
  cells, skipped: shortest <s> × 0.9 outlives <l>` and nothing else;
  when the rule is done
  (budget spent or interrupted), before the file is written and the next
  rule taken up, the ages of the kept rows in generations, longest first,
  as bare numbers separated by `, ` (`4821, 3990, 2210, ...`; no line
  when none was kept); and on a terminal the countdown of R-E4. The R-O1
  rule line is not printed: no rule becomes current.
- **R-O13.** In `odca` (section 4d): on entry `odca <file>: <n> pairs`
  for each file in command-line order, `, shuffled` appended when its
  script said `shuffle` (R-X7), or under `--longest` (R-X8) `odca
  <file>: <n> pairs, <k> seeds at <w> cells` with k the file's playable
  seeds summed over its pairs; there the pair line carries the item, `,
  seed <r>/<k>, <g> generations` after the color set (its rank among the
  pair's k playable seeds and its recorded lifetime), before the reason; in a show of two or more files
  (never with one), `playing <file>` before a pair from a different file
  than the last pair played, the first pair included; on playing pair i
  (0-based, position within its file) of that file's n `pair <i+1>/<n>
  <name> <colorset>` (the name omitted when the pair has none), followed on advances by the reason in parentheses — the
  auto-init reason (R-O6) when a re-init transitions, `timeout` when the
  grace period does, `next`, or `previous`. It precedes the R-O1 line when
  the rule changes.

---

## 7. Maybe-Class-IV screening (R-C)

The screen estimates whether a rule might exhibit Wolfram Class IV
(complex, localized-structure) behavior. It is a heuristic sieve —
false positives are acceptable and expected; the user is the second-stage
filter. Exact class membership is undecidable (Culik & Yu), so these
requirements define the screen *operationally*.

**R-C1 (screening run).** To screen a rule: run it in wrap mode on a row
of 256 cells seeded uniformly at random, for 200 unmeasured transient
generations, then up to 400 measured generations.

**R-C2 (cycle rejection).** During the measured phase, if any complete row
state recurs (comparing entire rows), the rule is rejected (Class I/II
behavior: short transient and period). Detection may stop the run at the
first recurrence.

**R-C3 (input entropy).** For each measured generation, compute the
Shannon entropy (base 2) of the distribution of *rule-table entries fired*:
for each of the 20 count vectors, the fraction of the row's W cells whose
neighborhood realized it this generation. Normalize by log2(20), giving
H_t ∈ [0, 1].

**R-C4 (verdict).** Let mean = mean(H_t) and std = population standard
deviation(H_t) over the measured generations. Then, in order:
- std ≥ 0.055 → **candidate** (maybe Class IV);
- otherwise mean > 0.80 and std < 0.02 → rejected as chaotic (Class III);
- otherwise → rejected as flat.

The score of a screened rule is its std.

**R-C5 (calibration note, informative).** Thresholds were calibrated on
400 random rules (2026-09): ~31% reject as cyclic; std's 95th percentile
among the rest is ≈ 0.055, so ≈ 4% of random rules pass. Re-calibration
may adjust R-C4's constants; document any change.

**R-C6 (synchronous search).** Searching for a candidate: repeatedly
generate a random rule (R-M11) and screen it, up to 200 attempts,
returning the first candidate; if none passes, return the
highest-scoring rule seen. The caller always receives a rule.

---

## 8. Background search (R-S)

**R-S1 (workers).** While the program runs, worker *processes* (or
threads only where they achieve true multicore parallelism) continuously
generate and screen random rules. Worker count: the machine's logical CPU
count minus one (minimum 1), leaving a core for the interface.

**R-S2 (hand-off).** Workers deliver candidates through a bounded queue
(capacity ~32). When the queue is full, workers must block (not busy-poll)
so that a full stash costs no CPU.

**R-S3 (drain).** The interface drains the queue opportunistically (e.g.
once per display refresh) into the in-memory stash, but only while the
stash holds fewer than 64 rules; the stash is truncated to 64. Every stash
change is persisted (R-P2).

**R-S4 (consumption).** `r` takes the *oldest* stashed rule (FIFO) and
persists the shrunken stash. Only an empty stash triggers the synchronous
search (R-C6).

**R-S5 (shutdown).** Workers stop promptly at program exit (R-U7); an
implementation must not leave orphan processes. Stopping a search that was
never started must be safe.

---

## 9. Non-functional requirements (R-N)

**R-N1.** Random choices specified as uniform (cell states, rule entries,
mutation) must be driven by a seedable pseudo-random generator of at least
the quality of a modern 64-bit PRNG (PCG, xoshiro, Mersenne Twister).
Cross-implementation reproducibility of random streams is *not* required.

**R-N2.** The engine must sustain at least 16,384 generations/second on a
300-cell row on commodity hardware (this is the top of the speed range,
R-K8), display included.

**R-N3.** Screening throughput should permit interactive use: a
synchronous `r` (empty stash) should typically return within a few hundred
milliseconds.

**R-N4.** The program must not corrupt user state on abnormal exit; state
files are small and rewritten atomically enough that a torn write at worst
loses one update (loaders already tolerate malformed content, R-P).

---

## 10. Explicit non-requirements

- The command line is the file arguments (one odca file for
  `odca-select` and `odca-evolve`; one or more play scripts or odca
  files for `odca`, R-X1) plus
  `--help` (R-U9), the cell size flags `--4` / `--3` / `--2` / `--1` (R-U2), for
  `odca-select`, `--longest` (R-W9), and,
  for `odca`, `--shuffle` (R-X1), `--fullscreen` (R-U2), `--watchdog`
  (R-X2), `--grace` (R-X3), `--longest` and `--cells` (R-X8), and for `odca-evolve`, `--cells`,
  `--time`, `--cap` (R-E1), and `--parity` (R-E5); no configuration files or menus. No other flags exist (the 2.x developer flags
  `--colorset-review`, `--screensaver-review`, `--consistency-check`, and
  `--screensaver` are gone: the last two became `odca-select` and `odca`,
  the consistency check became `R`, and color set review is on hold).
- No vertical-sync guarantee; visible tearing is acceptable.
- No reproducibility of random sequences across runs, languages, or
  machines.
- Wolfram-class identification is heuristic only; no accuracy guarantee.
