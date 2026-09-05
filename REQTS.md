# ODCA — Requirements

Version 2.24.1 — 2026-09-04
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
R-W7. 2.24.1: every pair activation fills the screen at once — R-W8.)

Versioning is semantic and shared by the whole code base: the
specification and every implementation carry the same version and are
released together. MAJOR for incompatible changes (state formats, rule
IDs, conformance vectors), MINOR for new or changed behavior, PATCH for
fixes and clarifications.

This document specifies ODCA, an interactive viewer for a four-state,
count-based, one-dimensional cellular automaton, in sufficient detail to
re-create the program from scratch in any language. It is
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

**R-U1 (startup).** On launch, with no command-line arguments required, the
program must:
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
   (R-B3).

**R-U2 (display geometry).** The display is a grid of square cells,
`cell_size` pixels on a side (default 4). Defaults: a 1200×800-pixel
window, giving 300 columns × 200 rows. The row count of the automaton
equals the column count of the display.

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
  (30 generations per second or faster): 1 — the newest generation is
  fully visible and each generation advances the picture by one whole
  row (discrete scrolling);
- otherwise (*continuous scrolling*): the fraction of the current delay
  that has elapsed since the last generation, so the picture slides up at
  a constant one cell per delay and the newest generation enters from the
  bottom edge. Cells stay crisp; the offset is quantized to device pixels.

**R-U4 (colors).** Each state maps to an RGB color through the active
*color set*: four colors in state order, state 0 the background. Ten
slots exist, bound to the digit keys `0`–`9`, loaded at startup from the
shared color sets file (R-P4); a slot the file does not define is
undefined, and selecting it is a silent no-op. Slot 1 is the built-in
default, `ODCA default`, defined even without the file, and is active at
startup. The file as shipped defines:

| slot | name | state 0 | state 1 | state 2 | state 3 |
|------|------|---------|---------|---------|---------|
| 0 | Ocean Sunset Vibes | `#325379` | `#DD5471` | `#F8D377` | `#62D3A3` |
| 1 | ODCA default | `#121218` | `#EBEBE1` | `#FFA136` | `#409CFF` |
| 2 | Meadow Sunflower Glow | `#D6E0A2` | `#F6F4D5` | `#CFDEC0` | `#E5A07F` |
| 3 | Candy Floss Dreams | `#F2AAA1` | `#F9F3DF` | `#C4F0E6` | `#B7D8DF` |
| 4 | Fiery Ice Cream Delight | `#102F47` | `#C53A32` | `#E78531` | `#F3C15F` |
| 5 | Golden Autumn Twilight | `#4D9CB9` | `#112F45` | `#F4BA41` | `#EC8B33` |
| 6 | Midnight Sun Dance | `#041523` | `#2E606B` | `#FCEDD4` | `#EE8432` |
| 7 | Seaside Serenity | `#E8ECEF` | `#304B74` | `#6C95B7` | `#ACCDEE` |
| 8 | Cherry Blossom Sky | `#2B2D40` | `#8F99AC` | `#EEF2F4` | `#DC3C44` |
| 9 | Cotton Candy Skies | `#8AD4FB` | `#EE79A5` | `#F19C78` | `#F8D87F` |

Slots 0 and 2–9 are palettes from coolors.co, recorded with their
sources in `colorsets/`. The set active in a slot may be *arranged* — its
four colors assigned to the states in any of the 4! = 24 orders — with
`c` (R-K15); the arrangement is per slot, kept for the session, and
written to the file by `S` (R-K16).

**R-U5 (timing).** Generation pacing is governed by a *delay* — the
nominal time between generations — independent of the display refresh:

- Initial delay: 1/60 s.
- The display refreshes at the screen's refresh rate (typically 60 or
  120 Hz), and implementations should pace refreshes from the display
  itself rather than a free-running timer; each refresh advances the
  automaton by ⌊elapsed_time / delay⌋ generations (with the fractional
  remainder carried forward), so rates far above the refresh rate are
  achievable; every generation is computed and enters the scroll buffer
  even when several occur per refresh.
- A per-refresh catch-up cap (implementation-chosen, ≥ 500 generations)
  must prevent a stall from freezing the program.

**R-U6 (window title).** The window title must show the current rule ID
(format: `ODCA — rule <id>`), kept current as the rule changes.

**R-U7 (shutdown).** Pressing `q` or closing the window exits the program
cleanly, stopping all background workers.

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
(R-M10), becoming current per R-B1 and occupying the unsaved slot (R-B3).
Cells are not reinitialized.

**R-K4 (`u` — undo).** Rule changes (from `r`, `m`, `n`, `p`, `u`) push
the outgoing rule onto an unbounded undo stack; `u` pops the stack and
makes that rule current per R-B1. With an empty stack, `u` is a silent
no-op. Undo does not alter the interesting-rule cycle position or the
unsaved slot.

**R-K5 (`s` — save).** Append the current rule to the keeper file (R-P3)
and print confirmation (R-O3). No other state changes.

**R-K6 (`i` — initialize).** Set every cell to an independent uniformly
random state. The rule, scroll buffer, and all other state are unchanged
(the new row simply enters the scroll).

**R-K7 (`n` / `p` — cycle interesting rules).** See section 4.

**R-K8 (`+` / `-` — speed).** `+` halves the delay; `-` doubles it,
clamped to [1/16384 s, 8 s]. Implementations should also accept the
unshifted equivalent of `+` (e.g. `=` on US layouts) and keypad `+`/`-`.

**R-K9 (digits `0`–`9`).** Select the corresponding color set (R-U4); an
undefined slot is a silent no-op.

**R-K10 (spacebar — pause).** The spacebar freezes the display animation:
no further generations are computed or shown until the spacebar is pressed
again, which resumes at the normal rate with no catch-up burst (elapsed
pause time is discarded). Resuming computes exactly one generation on the
first refresh so that the picture, which showed the newest row fully while
paused, continues without a jump (R-U3). While paused, every key except the spacebar,
Return (R-K11), `s` (R-K13), `c`/`C` (R-K15), `S` (R-K16), the digits
(R-K9), and `q` is ignored; `q` quits normally. The digits, `c`, and `S`
touch only colors, never computation, so they remain live (as does `C`). Pausing does not
stop the background search (R-S).

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
Each slot keeps its own arrangement for the session.

**R-K16 (`S`, shift-s — save color set).** Replace the active slot's
colors with its current arrangement (which becomes arrangement 1 of 24),
write all color sets to the file (R-P4), and print confirmation (R-O10).

**R-K12 (`a` — auto-initialization).** Toggles auto-initialization mode
(section 4a) and prints its new state (R-O6). The mode is on at startup
(since 2.13.0; it was off while the filter was being tuned) and is not
persisted.

---

## 4. The interesting-rule cycle (R-B)

**R-B1 (rule change).** Whenever the current rule changes — via `r`, `m`,
`u`, `n`, or `p` — the program must persist it as the current rule (R-P1)
and print it (R-O1).

**R-B2 (the cycle).** The saved rules in the keeper file (R-P3), in file
order, form a cycle of n+1 slots: slots 0…n−1 are the saved rules and one
extra slot holds the *unsaved rule*. The keeper file is re-read on every
`n`/`p` press, so rules saved during the session are immediately
reachable. `n` steps forward one slot (mod n+1) and `p` steps backward
one slot; the selected slot's rule becomes current per R-B1 (pushing undo
per R-K4). Position output per R-O4.

**R-B3 (the unsaved slot).** The unsaved slot holds the most recent rule
that arrived from outside the saved set: the startup rule (unless it
matched a saved rule, see R-U1 step 6), or the last rule produced by `r`
or `m`. When `r` or `m` fires, its new rule occupies the unsaved slot and
the cycle position moves to that slot. While the unsaved slot is empty —
startup matched a saved rule and no `r`/`m` has fired yet — the cycle
consists of the n saved rules only. When the cycle position starts on the
unsaved slot, the first `n` selects saved rule 0 and the first `p`
selects saved rule n−1.

**R-B4 (empty keeper file).** If no saved rules exist, `n` and `p` print a
notice (R-O5) and change nothing.

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

A hidden mode for auditioning the whole color set pool and deciding, one
set at a time, what to keep.

**R-V1 (entry).** Started by the command-line flag `--colorset-review`.
Everything else behaves as usual, except that the digit keys (R-K9) are
disabled and `S` takes the meaning in R-V5.

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
arrangements are recorded in screensaver pairs instead (section 4c).

---

## 4c. Screensaver review mode (R-W)

A hidden mode for composing a screensaver file (R-P5): an ordered list of
rule / color set pairs, each pair carrying its colors already arranged.

**R-W1 (entry).** Started by the command-line flag
`--screensaver-review <file>`. If the file does not exist it is created
empty; otherwise its pairs are loaded. If both review flags are given,
this mode wins and color set review is not entered. On entry the program
prints `screensaver <file>: <n> pairs` and, if the list is non-empty,
activates pair 1. Every ordinary key keeps its meaning except as redefined
below; the pool of color sets is the one loaded at startup (R-P4).

**R-W2 (`N` / `P` — step).** Activate the next / previous pair: set its
rule (as a rule change, R-B1, so undo applies) and make its stored colors
the active color set, at arrangement 1; the cells are not re-seeded. The
list does not wrap: at either end print `screensaver end` and stay. Pairs
appended during the session are reached in turn. With an empty list the
keys do nothing.

**R-W3 (choosing colors).** The digit keys select their bound sets as
usual; `[` and `]` step backward and forward through the whole pool in
review order (digit-bound sets by key, then pool-only sets), wrapping,
and print `color set <name>`. Selecting a set resets its arrangement to
1; `c`/`C` arrange the active set. Together with `r`, `m`, `n`, `p`, and
`u`, this composes the pair that `s` or `S` records: the current rule,
the active set's name, and its arranged colors.

**R-W4 (`s` / `S` — record).** `s` overwrites the pair under review with
the composed pair (`no pair under review` if none is active); `S`
appends the composed pair to the end of the list without changing the
review position. Both write the file immediately. In this mode `s` does
not append to the keeper file (R-K5) and `S` does not save a color set
(R-K16).

**R-W5 (`X` — delete).** Remove the pair under review, write the file, and
activate the pair now at that position (the previous one if the last was
removed); if the list becomes empty, no pair is under review and the
current rule keeps running.

**R-W6 (pause).** `S`, `N`, `P`, `X`, `[`, `]`, and the digits remain live
while paused, like the other color keys (R-K10); `s` while paused keeps
its pause meaning (R-K13).

**R-W7 (consistency check).** The flag `--consistency-check <file>`
enters screensaver review on an *existing* file (a missing file is an
error and the program exits) with one difference, for presentation only:
pairs are viewed grouped by rule — all pairs sharing a rule together,
groups in order of each rule's first appearance in the file, pairs within
a group in file order — so that a rule's color sets can be compared for
excessive similarity. `N`/`P` follow this view order and positions are
announced in it; when a step crosses into a different rule's group,
`--- rule group <g>/<G> ---` is printed first (R-O12). The file order is
never changed by the view: `s` and `X` act on the pair at its existing
file position, `S` appends to the end of the file (while the new pair
joins its rule's group in the view, at the end of that group or as a new
last group), and the file is always written in file order.

**R-W8 (activation fills the screen).** Every activation by `N`/`P`
(sections 4c, R-W2 and R-W7) immediately computes and displays a full
screenful (`rows` generations) under the activated pair, paused or not,
so that navigation looks the same whether or not the rule changed: the
whole screen is the new pair's output rather than a re-colored old one
or a slowly arriving new one. Generations so computed count for auto-init
(R-A) and the screen counter (R-K14) as usual.

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

**R-P3 (keeper file).** File `interesting-rules.txt` in the repository
root, shared by all implementations (each must document how it anchors
this path). Each saved rule is a
line of the form `rule <id>`. `s` appends; the file is never otherwise
modified by the program, and users may hand-edit it. Readers must ignore
any line that is not exactly `rule` + whitespace + a valid rule ID, so
comments and notes are permitted.

---

**R-P4 (color sets file).** File `colorsets/colorsets.json` in the
repository root, shared by all implementations: the *pool* of every kept
color set. JSON: an object with a `sets` array and a `dropped` array.
Each set has `name` (string), `colors` (four strings `#RRGGBB`, states
0–3), and optionally `slot` (integer 0–9): sets with a slot are bound to
that digit key (R-U4), sets without one are pool-only. `dropped` lists
the names of sets rejected in review (section 4b), so that re-seeding
from the candidates file never resurrects them; it may be edited by hand.
Readers must ignore malformed sets and treat a missing or unparseable
file as empty; the built-in default (R-U4) always fills slot 1 unless the
file defines it. Writers preserve what they do not change: `S` (R-K16)
rewrites the digit-bound sets and keeps the pool and the dropped list;
the review save (R-V5) rewrites everything. Digit-bound sets are written
first, sorted by slot number, then the pool in order. The raw source of
candidate palettes is `colorsets/candidates.json` (an object with a
`palettes` array of `name` + `colors`), which the program only reads.

**R-P5 (screensaver file).** A JSON file named on the command line
(R-W1): an object with a `pairs` array; each pair has `rule` (a rule ID,
R-M8), `colorset` (the color set's name, for reference), and `colors`
(four `#RRGGBB` strings, states 0–3, already arranged), so a screensaver
plays even if the pool is later edited. Malformed pairs are skipped; an
unparseable file loads as empty. Written in the same layout as R-P4.

---

## 6. Terminal output (R-O)

The program prints single-line, human-readable status to standard output:

- **R-O1.** On every rule change (including startup): `rule <id>`.
- **R-O2.** After a synchronous screening search that rejected k ≥ 1
  rules: `discarded <k> rule` (k = 1) or `discarded <k> rules` (k > 1),
  before the R-O1 line.
- **R-O3.** On `s`: `saved rule <id>`.
- **R-O4.** On `n`/`p` selecting saved rule i (0-based) of n:
  `interesting <i+1>/<n>`; selecting the unsaved slot: `unsaved rule`.
  Either precedes the R-O1 line.
- **R-O5.** On `n`/`p` with no saved rules: `no saved interesting rules`.
- **R-O6.** On `a`: `auto-init on` or `auto-init off`. On an automatic
  re-initialization: `auto-init (<reason>)`, where reason is
  `state <k> extinct` (or `states <k>, <l> extinct`, ascending),
  `repeating (period <n>)`, `repeating`, or `stagnant`;
- **R-O7.** On each completed screenful while the screen counter is active
  (R-K14): `screen <n>`.
- **R-O8.** When Brent's algorithm first detects a cycle since the last
  reset (R-A3), whether or not auto-initialization is on:
  `cycle period <n>`.
- **R-O9.** On `c`: `color set <slot> arrangement <k>/24`, k from 1.
- **R-O10.** On `S`: `saved color set <slot> <name>`.
- **R-O11.** In review mode (section 4b): on entry and on every step,
  `review <i>/<n> <name>` (1-based position among the kept sets); `review
  wrapped` before a step that wraps; `dropped <name>` on `X`; `review
  empty` when nothing is left; `saved <k> color sets, <d> dropped` on
  save. Arrangement messages (R-O9) name the set instead of a slot.
- **R-O12.** In screensaver review mode (section 4c): on entry
  `screensaver <file>: <n> pairs`; on activation `screensaver <i>/<n>
  <colorset>` (rule IDs are opaque at a glance and are not printed);
  `screensaver end` at either end; `saved pair <i>/<n>`, `added pair
  <n>/<n>`, `deleted pair <i>/<n>`, `no pair under review`; after every
  write, `saved <n> pairs to <file>`; `color set <name>` on `[`/`]`; in a
  consistency check, `--- rule group <g>/<G> ---` before an activation
  that enters a different rule's group. Arrangement messages (R-O9) name
  the set. this precedes nothing else (cells change, the rule does not).

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

- No command-line arguments are required for ordinary use, and no
  configuration files or menus; hidden developer flags (such as
  `--colorset-review`, section 4b, `--screensaver-review <file>` and
  `--consistency-check <file>`, section 4c) are permitted.
- No vertical-sync guarantee; visible tearing is acceptable.
- No reproducibility of random sequences across runs, languages, or
  machines.
- Wolfram-class identification is heuristic only; no accuracy guarantee.
