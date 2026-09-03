# ODCA — Requirements

Version 1.0 — 2026-09-03

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

**R-U2 (display geometry).** The display is a grid of square cells,
`cell_size` pixels on a side (default 4). Defaults: a 1200×800-pixel
window, giving 300 columns × 200 rows. The row count of the automaton
equals the column count of the display.

**R-U3 (scrolling).** The display shows the most recent generations as
horizontal rows, newest at the bottom of the filled region. A display
buffer of `rows` rows starts as all state 0; each new generation is
appended below the previous until the buffer is full, after which the
buffer scrolls: the oldest visible row is discarded and the new row enters
at the bottom. The initial (seed) generation is displayed.

**R-U4 (colors).** Each state maps to an RGB color through the active
*color set*; state 0 is the background. Ten color-set slots exist, bound to
the digit keys `0`–`9`. Three are defined; the rest are reserved
(selecting an undefined slot is a silent no-op):

| slot | name | state 0 | state 1 | state 2 | state 3 |
|------|------|---------|---------|---------|---------|
| 0 | CoCo set 0 | green `#07FF00` | yellow `#FFFF00` | blue `#3B08FF` | red `#CC003B` |
| 1 | CoCo set 1 | buff `#FFFFFF` | cyan `#07E399` | magenta `#FF1CFF` | orange `#FF8100` |
| 2 | default | near-black `#121218` | off-white `#EBEBE1` | amber `#FFA136` | blue `#409CFF` |

Slot 2 is active at startup. (CoCo values are the customary MC6847 VDG
approximations.)

**R-U5 (timing).** Generation pacing is governed by a *delay* — the
nominal time between generations — independent of the display refresh:

- Initial delay: 1/60 s.
- The display refreshes at approximately 60 Hz; each refresh advances the
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

**R-K9 (digits `0`–`9`).** Select the corresponding color set (R-U4).

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
that arrived from outside the saved set: the startup rule, or the last
rule produced by `r` or `m`. When `r` or `m` fires, its new rule occupies
the unsaved slot and the cycle position moves to that slot. At startup the
cycle position is the unsaved slot; therefore the first `n` selects saved
rule 0 and the first `p` selects saved rule n−1.

**R-B4 (empty keeper file).** If no saved rules exist, `n` and `p` print a
notice (R-O5) and change nothing.

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

**R-P3 (keeper file).** File `interesting-rules.txt` in the project root
(the directory containing the program's source; an implementation may
document a different fixed, user-visible location). Each saved rule is a
line of the form `rule <id>`. `s` appends; the file is never otherwise
modified by the program, and users may hand-edit it. Readers must ignore
any line that is not exactly `rule` + whitespace + a valid rule ID, so
comments and notes are permitted.

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

- No command-line arguments, configuration files, or menus.
- No vertical-sync guarantee; visible tearing is acceptable.
- No reproducibility of random sequences across runs, languages, or
  machines.
- Wolfram-class identification is heuristic only; no accuracy guarantee.
