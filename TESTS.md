# ODCA — Test Plan

Version 3.62.0 — 2026-09-10

Companion to `REQTS.md` (requirement IDs cited below are defined there).
This plan is normative for every implementation, in every language, on
every supported OS. It has three layers, chosen by what can be made
uniform:

1. **Conformance vectors** — machine-readable golden data for all
   deterministic behavior. Identical everywhere; this layer *is* the
   cross-language, cross-OS uniformity mechanism.
2. **Property tests** — prose-specified tests for behavior involving
   randomness, files, or program state. Uniform in *what* they assert,
   language-native in execution (random streams are not reproducible
   across languages, so exact outputs cannot be golden data).
3. **Manual checklist** — interactive/visual behavior that cannot be
   automated portably across GUI toolkits.

Language- and OS-specific *how-to-run* notes belong in the corresponding
`REQ-<language>.md`, never here.

---

## Layer 1: Conformance vectors

**File:** `conformance/vectors.json` — normative golden data, shared
verbatim by all implementations. Produced by the reference Python
implementation (whose engine is verified by hand-checked unit tests);
regenerating it is a spec change: bump its `version`, review the diff, and
note the reason in this file's history.

**Schema** (top-level keys):

- `count_vectors`: the 20 canonical count vectors in canonical order
  (R-M6). An implementation must enumerate exactly this sequence.
- `valid_rule_ids`: IDs that must parse and re-emit identically (R-M8).
- `invalid_rule_ids`: strings whose parsing must fail cleanly (R-M8).
- `evolution`: an array of cases, each with:
  - `name` — cite this in failure messages
  - `requirement` — the requirement(s) exercised
  - `rule` — rule ID (R-M8)
  - `wrap` — boolean edge mode (R-M9)
  - `initial` — generation 0 as a string of state digits; its length is
    the row width
  - `generations` — number of steps to run
  - `expected` — the rows after each successive step, same encoding
- `lifetimes` (vectors 1.2, R-E2): an array of cases, each with `name`,
  `requirement`, `rule`, `initial` (as above, wrap mode), `cap`, and the
  expected `generations` and `end` — the seed lifetime `odca-evolve`
  measures: the count of generations before the first one boring by
  extinction (R-A1's first clause) with the R-O6 extinction text, or at
  which Brent's confirms a cycle, with `repeating (period N)` (vectors
  1.2; until then such rows survived to the cap), or `cap` and
  `survived`. Run by every implementation that has section 4e.

**Runner contract.** Each implementation provides a runner that loads the
file, executes every case (no skips, `lifetimes` aside where section 4e
is not implemented), and fails with the case `name` on
any mismatch, exiting nonzero. The runner should be part of the
implementation's normal test suite. Reference:
`python/tests/test_conformance.py` (~50 lines).

Coverage: R-M1–R-M9 (engine), including permutation invariance (paired
reversed-row cases) and both edge modes.

**File:** `library.json` — the shipped digit-bound sets must equal the
R-U4 table of `REQTS.md`, slot by slot, name and colors; the reference
suite parses the table and compares (PT-37).

**Files:** `conformance/scripts/<case>.play` with `<case>.json` — the
play script cases (R-X7): each `.json` is the shared parser's output for
the `.play` beside it, byte for byte, plus one newline —
`{"ok":true,"statements":[...]}` — one object per statement, carrying
its line and the statement as its own key: `{"line":L,"import":"<name>"}`,
`{"line":L,"play":true}`, `{"line":L,"shuffle":true}` — or
`{"ok":false,"line":L,"column":C,"message":"..."}`. Produced by `script/regen`'s parser; adding a case or
changing the grammar is a spec change. Every implementation parses each
`.play` and compares (PT-38); the two checked-in copies of the generated
C (`swift/Sources/CShow/`, `python/odca/cshow/`) must be identical.

**Files:** `conformance/help-odca.txt` and `conformance/help-odca-select.txt`
— the normative `--help` texts (R-U9), printed byte for byte by every
implementation. Editing one is a spec change (bump `REQTS.md`). Each
implementation's suite compares its embedded copies to these files.

---

## Layer 2: Property tests

Every implementation must include automated tests asserting the following,
using its own RNG and a temporary directory for all file paths (never the
user's real state — see the warning in `REQ-python.md`).

| ID | Requirement | Property |
|----|-------------|----------|
| PT-1 | R-M10 | Across ≥ 50 successive mutations, each differs from its parent in exactly one of the 20 entries, and that entry's new value is a valid state different from the old. |
| PT-2 | R-M11 | Random rules are valid (20 entries, states 0–3). |
| PT-3 | R-M2 | Constructing an automaton with width < 3, a malformed seed row, or an out-of-range state fails cleanly. |
| PT-4 | R-C1–R-C4 | Screening the all-zero rule reports a cycle of period 1 and rejects it. |
| PT-5 | R-C6 | The synchronous search always returns a valid rule within its attempt bound, including when forced to its fallback (e.g. bound = 1). |
| PT-6 | R-P1 | Current-rule save/load round-trips; a missing or corrupt file loads as absent (triggering the random-rule fallback), never an error. |
| PT-7 | R-P2 | Candidate stash save/load round-trips in order; invalid lines are skipped. |
| PT-8 | R-P3 | The odca file round-trips pairs (rule, color set name, arranged colors) in order; the loader skips malformed pairs, reads an unparseable file as empty and a missing one as absent, and no longer reads the 2.x `pairs` key. Re-saving the shipped `interesting.odca` is byte-identical. A pair with a `name` round-trips with the name written first; a file under the 3.0.0 key `looks` loads; the next generated name is `pair-0000` for an empty file, one past the highest `pair-NNNN` in use otherwise (`pair-0003` after `pair-0000` and `pair-0002`), `pair-10000` after `pair-9999`, and other names do not count. |
| PT-9 | R-K4, R-K19 | Undo restores rules in LIFO order; undo on an empty stack is a no-op. In `odca-select` on pair 1 of a two-pair file, three `m` then `U` restore pair 1's rule at once with the position unchanged and the stack at its depth on arrival, and a second `U` is a no-op; after `n` two `m` and `U` restore pair 2's rule, unwinding only to that arrival; after `r` two `m` and `U` restore the rule `r` brought, on the unsaved slot; `U` is not live while paused. |
| PT-10 | R-B2, R-B3, R-W1 | `odca-select` on a file of k pairs opens on pair 1 with the unsaved slot empty; after `r` the unsaved slot holds the new rule and the position is on it; `n` selects pair 1; `p` returns to the unsaved slot; a further `p` wraps to pair k; stepping past the last returns to the unsaved slot; `m` there replaces the unsaved rule and stays on the slot. |
| PT-10a | R-U1, R-B3 | Opening on pair 1 with the unsaved slot empty, `n` selects pair 2 and `p` twice wraps to pair k with no unsaved stop; the unsaved slot reappears holding the new rule after `r` (`m` on a pair edits the pair instead, PT-34). |
| PT-11 | R-S5 | Stopping a background search that was started terminates all workers; stopping one never started is safe. |
| PT-12 | R-S2, R-S3 | Candidates delivered by workers are valid rules; the stash never exceeds its cap. |
| PT-13 | R-K10 | While paused, every command key except space, Return, `s`, the color keys, the pair keys, and `q` is a no-op (rule, cells, speed, and cycle position unchanged), while the digits switch slots and `c` re-arranges colors; space resumes; `q` still quits. |
| PT-14 | R-K11 | While paused, Return advances the automaton exactly one generation per press and the program stays paused; when not paused, Return changes nothing. |
| PT-15 | R-K12, R-A2 | With auto-init on (the startup default) and a rule whose rows repeat (e.g. the all-zero rule), the cells are re-initialized exactly when the `rows`-th consecutive boring generation is computed (generation counter returns to 0, reason `repeating (period 1)` printed); after `a` turns the mode off, nothing happens. |
| PT-16 | R-A1, R-A2 | With a rule under which a producible state dies out, the re-initialization reason names that state as extinct. |
| PT-16a | R-A1 | A row with one producible state extinct is boring when the remaining states are all real populations (≥ 10%), but not boring while another producible state survives as a minority (> 0 and < 10% of cells); two extinct states with no minority are boring. |
| PT-18 | R-A1 | Feeding non-repeating rows that carry a constant minority population: nothing is boring until the 4 × `rows` window is full, then every generation is boring with reason `stagnant`; rows whose minority population swings widely are never stagnant. |
| PT-19 | R-K13 | While paused, `s` queues exactly `rows` generations that advance at one eighth the delay (elapsed time t yields ⌊8t/delay⌋ of them) and stop when the screenful is done, still paused; a second `s` queues a second screenful; space cancels the queue; when not paused `s` saves and queues nothing. |
| PT-20 | R-K14 | No counter before the first resume; resume sets it to 0; after exactly `rows` further generations it reads 1 and `screen 1` is printed; generations from running, zipped screenfuls, and single steps all count; a further resume restarts it at 0. |
| PT-21 | R-A1 | A row recurring exactly 10 × `rows` generations after its first appearance is boring (`repeating`); one recurring 10 × `rows` + 1 generations later is not. |
| PT-22 | R-A1, R-O8 | Feeding a transient followed by a cycle of distinct rows whose period exceeds the repetition window, the detected period equals the true period exactly, `cycle period <n>` is printed once, subsequent reasons read `repeating (period <n>)`, and a rule change clears the detector; a short cycle (period 7) is likewise detected exactly. |
| PT-23 | R-K15, R-K9 | With a stubbed color sets file: `c` yields the next lexicographic arrangement (first press swaps states 2 and 3), 24 presses return to the original, `C` steps back and wraps from 1 to 24, the arrangement is remembered per set across set switches, an undefined slot's digit is a no-op, and without a file only slot 1 exists. |
| PT-24 | R-K16, R-P4 | Baking (reachable only without a program) writes the active set's arranged colors into its library entry (reloading shows them) and resets its arrangement to 1; the library loader tolerates malformed entries, out-of-range slots, and unparseable files, always supplying slot 1. |
| PT-33 | R-K17 | Without a program `]` steps from slot 1 through the hot ten in key order into the pool-only sets and wraps, `[` steps back, a slotted set becomes the digit position, digits still select the hot ten, and baking (R-K16) on a pool-only set writes its arrangement into that entry without giving it a slot; in color set review `[`/`]` act as `P`/`N`. |
| PT-25 | R-U3, R-K10 | The history holds `rows` + 1 rows; the scroll offset is 0 while filling, 1 at the default speed once full, the elapsed fraction of the delay (wrapping when a generation is computed) once the delay exceeds twice the initial delay, and 1 while paused; resuming computes exactly one generation on the first tick and returns the offset to 0. The initial delay is a construction parameter (1/60 s at the default cell size, halved per halving of the cell, R-U5): with 1/240 s the session starts at that delay, two `-` presses reach 1/60 s, and that delay scrolls continuously though it is discrete at the default. |
| PT-26 | R-V1–R-V6, R-P4 | With a stubbed pool file (slots 0–9, one pool-only set, one dropped name) and a stubbed candidates file (one duplicate, one dropped, two new): the review order is slots 1–9, 0, the pool set, then the new candidates; `N`/`P` step and wrap with the wrap message, each step computing exactly `rows` generations at once; digits are inert; `X` drops, advances, and wraps when the last set is dropped; each drop writes the first ten kept sets to keys 1–9, 0 (rotating slots down over the drop), the rest pool-only, arrangements not baked in, and the dropped list including the new drops; `S` does nothing; a second review run reloads that order without resurrecting drops; exit saves; outside review mode `N`/`P`/`X` do nothing and exit writes nothing. |
| PT-27 | R-P4 | The pool file round-trips sets with and without slots plus the dropped list; a JSON `null` slot reads as pool-only; the digit-bound save keeps the pool and the dropped list; the candidates file loads by name and colors and skips malformed palettes. |
| PT-28 | R-W1–R-W6, R-P3, R-K5 | `odca-select` on a missing file: nothing is written at entry and no pair is under review; `n` reports no pairs; on the unsaved slot `s` appends (as `S`) the composed pair (current rule, active set name, arranged colors) without changing the position; `S` appends another; `n` activates pair 1 (rule and colors restored, the cells re-seeded at generation 0, nothing computed ahead); `s` on a pair rewrites only its color set, keeping its rule; `n` past the last pair reaches the unsaved slot, where `X` does nothing; `X` on a pair deletes it and activates the neighbor, emptying the list makes the rule on screen the unsaved rule; exit writes the file (empty if need be); startup on a non-empty file activates pair 1 and exit rewrites it; `[`/`]` walk the pool. Outside `odca-select` the pair keys are inert. |
| PT-29 | R-P3 | The odca file round-trips, escapes quotes in names, writes `{"pairs": []}` for an empty list in the shared layout, skips pairs with invalid rule IDs, and loads an unparseable file as empty. |
| PT-30 | R-W7, R-U10 | With a file of pairs whose rules run A, B, A, C, B: `R` switches the view order to A A B B C, keeps the pair under review, prints the order message, and starts a 0.25 s inversion that ends on the wall clock even while paused; crossings into another rule's group print the group marker, steps within a group do not; `S` appends to the file's end but joins its group in the view without moving the position; `s` rewrites the pair at its file position; `X` removes the pair from its file position and activates the pair now at that view position; a second `R` returns to file order on the same pair; the file is written in file order throughout. |
| PT-31 | R-X1–R-X6, R-O13 | With a two-pair file whose rules die at once: entry plays pair 1 (its rule and colors, generation 0, no reason printed); before the watchdog expires, a screenful of boring rows re-seeds in place with an `auto-init` line and no transition; once 120 unpaused seconds have passed, the next firing transitions to pair 2 with a fresh seed and the reason printed; the old rows still read pair 1's colors and the new seed row pair 2's (R-X5); a further expiry and firing loops back to pair 1; `N`/`P` and `n`/`p` step between pairs with a fresh seed and reasons `next`/`previous`, wrapping, also while paused; `s`, `S`, `X` never write the file. With auto-init off: a manual `i` at 100 s resets the grace period but not the watchdog, no transition at 120 s or 159.5 s, transition at 160 s with reason `timeout`, paused time counting for nothing; a quiet pair transitions at 120 s exactly. Constructed with a watchdog of 20 s and a grace period of 10 s (`--watchdog 20 --grace 10`) the same clocks run at those lengths: a quiet pair transitions between 19 and 20.5 s, and an `i` at 15 s into the next pair holds it past 21 s and releases it by 25.5 s. With a three-pair file: `N` twice within one screenful leaves pair 1's rows in pair 1's colors and pair 2's in pair 2's while the newest read pair 3's; returning to pair 1 adds no palette; dozens of further changes (transitions and arrangements, past the table limit) never recolor a remembered row (R-X5). |
| PT-32 | R-U8 | After 40 generations at 32 × 16: narrowing to 20 keeps the middle 20 cells of the live row and of every remembered row, keeps the history, resets the boring count, and prints `resized 20x16`; widening to 30 keeps those 20 centered with state-0 padding in old rows and random cells in the live row; a taller window shows the last rows + 1 remembered rows; a no-op resize returns false; sizes clamp to the minimum. The history never exceeds 2048 rows. |
| PT-34 | R-K5, R-B2, R-B3 | In `odca-select`, `S` appends the current rule with the active set's name and arranged colors and prints it; `n` onto that pair restores both the rule and the colors; stepping onto the unsaved slot restores the unsaved rule with the set that was active when it arrived. Opening on pair 1 of a two-pair file, a digit and `s` rewrite pair 1's colors in place (`saved pair 1/2`); `m` keeps the position on pair 1 and leaves the unsaved slot empty, `u` walks it back there; a second `m`, a digit, and `s` append the screen as pair 3 with the mutated rule and the new set (`added pair 3/3`), pair 1 keeping its rule, and the position moves onto pair 3 where `U` has nothing to unwind and a digit and `s` refine it in place (`saved pair 3/3`); a further `m` is discarded by `n` then `p`; `r` moves to the unsaved slot as before, and `m` there stays there. |
| PT-17 | R-A3, R-K12 | The boring count resets on a rule change; `a` toggles the mode and prints its state; the mode is on at startup. |
| PT-35 | R-U9 | Each of the three programs' embedded help texts equals its conformance file byte for byte and ends with a newline; `--help` among other arguments prints exactly that text, exits 0, and leaves the state directory untouched; a missing file argument or an unknown option exits 2 with a usage line; `odca` on a missing file exits 1; `odca` with a missing file among several exits 1 naming it, and `odca-select` given two files exits 2 with its usage line; `odca` accepts `--shuffle` and `--fullscreen` in either position and `odca-select` rejects both as unknown; both accept one of `--4` / `--3` / `--2` / `--1` in either position, and two of them exit 2 with a one-line message (R-U2); `odca` takes `--watchdog N` and `--grace N` in either position, and a missing value, a non-number, `0`, or a fraction exits 2 with a one-line message; `odca --longest` on a file with playable seeds at one width launches at that width, `--cells N` chooses among several and `--1` is honored, `--watchdog` or `--grace` with `--longest`, `--cells` without it, and `--cells 2` exit 2 with one line, `--cells` naming a width without seeds exits 1 with `error: no seeds at N cells (...)`, and a play script with `--longest` exits 1 with `error: <file>: --longest plays odca files only` (R-X8); `odca-select` rejects them as unknown. |
| PT-37 | R-U4, R-P4 | The digit-bound sets of the shipped `library.json` equal the R-U4 table of `REQTS.md`: same slots, names, and colors in state order. |
| PT-36 | R-X1, R-O13 | With three odca files of two, one, and three pairs, `--shuffle`: entry prints `odca <file>: <n> pairs` for each in command-line order, then `playing <file>` before the first pair line; over ten passes (`N` fifty-nine times) every pass plays every file once, each file whole with its pairs in file order, no pass opens with the file that closed the one before, the orders differ between passes, and `playing <file>` precedes every change of file; `P` steps back within the pass. Without the flag the order is command-line order. With one file with pairs between two empty ones, it plays on. With a single file, `playing` is never printed and every pass is file order. |
| PT-38 | R-X7, R-X1 | The parser gives `import a.odca` / `play` / `shuffle` as statements with their line numbers, an empty or comment-only script as none, a second `play` as the error `3:1: play given twice`, and a `shuffle` after a `play` as `3:1: shuffle after play`. A script in a subdirectory imports `../one.odca` and `"two pairs.odca"` relative to itself and plays their pairs in import order; imports without `play`, and `play` without imports, play nothing; a missing import fails as `<script>:<line>: cannot read <file>`, a text file as `<script>:<line>: <file> is not an odca file`, an import after `shuffle` as `<script>:3:1: import after shuffle`, and an unreadable script as `<script>: cannot read`. `load` gives one segment per command-line file in order — a script's pairs, an odca file's own pairs, an empty file's none — and reads any extension but `.odca` as a script. `odca` given a script and an odca file passes both segments to the session in order; a script error exits 1 with `error: <script>:<line>: cannot read <file>`, a syntax error with `error: <script>:<line>:<column>: <message>`, before any window. |
| PT-39 | R-X7, R-X1, R-O13 | With six pairs on three rules, two each, and three color sets, two each (one of them arranged differently in its second pair), imported by a script that says `shuffle`: the entry line reads `odca <script>: 6 pairs, shuffled`, the session's own shuffle flag is off (the script asked, not the command line), and over ten passes every pass plays each pair exactly once with no two consecutive pairs in the whole sequence, pass seams included, sharing a rule or a color set in any arrangement; `P` steps back within the pass; with `play` instead the order is file order and nothing is called shuffled. With two pairs on one rule, every pass is still a permutation and play continues (the requirement is dropped after a hundred draws). In a show of a plain file whose only pair clashes with one of a shuffled script's two, that pair never opens the script's pass, twenty passes running. |
| PT-40 | R-E2 | `lifetime`: a block of eight 3s in sixteen cells under a rule that keeps a 3 only between 3s lives 4 generations and ends `state 3 extinct`; capped at 3 it lives 3 and ends `survived`; under the all-zero rule (only state 0 producible) a row is all zeros from generation 1 and ends at generation 2 as `repeating (period 1)`, or survives when capped at 1; a stop asked for at the first look abandons the row (nil), and a row narrower than three cells is refused. |
| PT-41 | R-E3, R-E2, R-E4 | Merging twelve distinct rows keeps the ten longest, longest first; merging a list with itself changes nothing; equal lifetimes order by row text; a row would rank first when longest, sixth between the sixth and seventh, nowhere when equal to the shortest of ten, tenth when nine are kept, and nowhere when already kept; merging seeds by rule and width keeps every list. A search of a fast-dying rule at twelve cells with a 1.5 s budget and two workers, started from one recorded seed: measures many rows, ticks at least once with the time left, keeps at most ten longest first with the recorded seed still on top and no row twice, reports every join with a rank in 1–10, the last of the ten having arrived by a join, and is stopped when done; a search of an immortal rule stopped from its first tick returns within seconds with nothing kept (the rows in flight discarded). The clock of R-E4 and R-O16: 0 s is `00:00:00`, 0.2 s rounds up to `00:00:01`, 59.5 s to `00:01:00`, 4 h 5 min 6 s is `04:05:06`, and a negative span is `00:00:00`. |
| PT-42 | R-X4 | With seeds recorded for pair 1's rule at 32 and 33 cells (a longer and a shorter at 32, one at 33) and none for pair 2: arriving on pair 1 at 32 cells gives exactly the longest 32-cell seed at generation 0; pair 2 is random; back on pair 1 the seed again; `i` is random; after a resize to 33 cells, pair 1 gives the 33-cell seed; a script show importing the file seeds the same way. |
| PT-43 | R-P3 | Writing a pair with seeds for two rules at width 8 produces exactly the reference layout (Python's `json.dumps(indent=1)`: rules sorted, widths as strings, each seed as row, generations, end); reading it back gives the pairs and the seeds longest first; rewriting the pairs alone (odca-select's path) carries the seeds through; writing with no seeds omits the section; a row of the wrong width, a bad digit, a width below 3, and a key that is not a rule ID are skipped. |
| PT-44 | R-X8, R-O13, R-U8 | With three pairs A, B, C on three rules and color sets and seeds at 32 cells — two for A (lifetimes 8 and 6, a block of 3s dying under a rule that keeps a 3 only between 3s), a survivor and one of lifetime 5 for B, none for C — plus one for A at 33: the width is an error naming `32, 33` until `--cells` chooses, a width without seeds is an error naming the two, and a file of survivors alone is `no seeds to play`. The session at 32 cells with `--longest`: the entry line reads `odca <file>: 3 pairs, 3 seeds at 32 cells`, the first line `pair 1/3 A, seed 1/2, 8 generations`, the pass is A's first, B's first (its survivor left out), A's second, and the cells are A's longest seed; the title is the rule's alone (R-U6) and the counter reads `0/8`, then `3/8` three generations on, and is absent in an ordinary show (R-O17); the terminal wrapper draws a counter as `\r`, erase-to-end, the text, clears it the same way before an ordinary line, and redraws in place without clearing in between; the fit to the window's width: 1920 × 1080 at 600 cells of 2 points gives a factor of 1.6 (fractional, so linear filtering) and 337 rows, 1200 × 800 gives 1 and 400, 600 × 50 gives 0.5 and 50, and a height of 0 still gives one row; the on-screen counter rendered from `12/40` holds yellow and black pixels and is wider and taller than the plain text by twice the outline width (R-U11); the natural window size is 1200 × 800 at 2-point cells, 1200 × 798 at 3 (whole cells), and 1080 × 800 for a fixed width of 540 (R-U12); `r`, `m`, `u`, `U`, and `a` change nothing while a digit key changes the colors; a resize to 40 × 20 leaves 32 columns, prints `resized 32x20`, and a further width change is a no-op; `i` (once resumed) restores the seed at generation 0; with a one-second watchdog and grace period, six quiet seconds at the slowest delay transition nothing; single-stepping, the seed dies at generation 8 and twenty rows later (a screenful) the next item takes over with `pair 2/3 B, seed 1/1, 5 generations (state 3 extinct)` and B's row at generation 0, with no `auto-init` line; `N`, `n`, `P` walk the items with `(next)` / `(previous)`, wrapping. With three pairs on distinct rules and colors, two seeds each, `--shuffle`: over ten passes every pass plays each of the six items once, no two consecutive items (seams included) share a pair, and the orders differ; without the flag the order is every pair's first, then every pair's second. |
| PT-45 | R-W9, R-O12 | A file of four pairs — two on rule A (with a seed at 32 cells), one on C (no seeds), one on B (a survivor at 40 cells) — opened with `--longest`: the entry line reads `odca <file>: 4 pairs, 3 with seeds` and the first `pair 1/3 <name> A`; the cycle is the two A pairs and B, `n` wrapping among them (the unsaved slot empty) with `pair 2/3` and back to `pair 1/3`; `R` groups within those three; a digit key then `s` prints `saved pair 1/3` and the file's first pair carries the new set; `S` prints `added pair 5/5`, the file has five pairs, and the copy, being on A's rule, joins the cycle as its fourth while the position stays; `m` then `s` prints `added pair 6/6`, the new pair's rule has no seeds so the cycle is unchanged and the position still on the first shown pair; the seeds are untouched so far; `X` on an A pair prints `deleted seeds of pair 1/4 ...`, moves on to `pair 1/1 ... B`, leaves the file its six pairs and only B's seeds; `X` again leaves nothing shown, B's rule in the unsaved slot, no seeds in the file, and `n` says `no pairs`; the same file without the flag shows all six pairs. `odca-select` accepts `--longest` and passes it on. |
| PT-46 | R-E5 | With rules a, b, c and lifetimes at width 8 of {5000, 4000, 3000}, {2000, 1500}, and {100000}: a gives up its turn, reporting shortest 3000 against 2000, b's longest, whatever c holds; c gives up its turn against the same 2000; b, furthest behind, runs; without c's seeds a still gives up its turn and c, with none, runs; a holding {2222, 2221} runs (1998.9 is under 2000) and holding {2223} alone gives up (2000.7); at width 9 a runs (no seeds there); with no other rule holding seeds a runs; a rule outside the file's pairs holding 5000 does not count. |

---

## Layer 3: Manual checklist

Run before calling a port done, on each target OS. Expected results follow
from `REQTS.md`.

- **M-1** Fresh start (no `$HOME/.odca`): program starts, prints a rule,
  shows a random field evolving. Restart: the same rule loads (R-U1, R-P1).
- **M-2** `r` swaps rules near-instantly once the stash has filled;
  terminal shows each rule ID (R-K2, R-S).
- **M-3** `m` visibly perturbs behavior sometimes and not others; `u`
  walks back through every `r`/`m`/`n`/`p` change (R-K3, R-K4).
- **M-4** `+`/`-` speed the scroll up and down across the full range; the
  UI stays responsive at maximum speed (R-K8, R-U5, R-N2).
- **M-5** `0`–`9` each switch palettes instantly; `c` visibly re-colors
  the screen; `[`/`]` reach the pool-only sets (R-K9, R-K15, R-K17, R-U4).
- **M-6** In `odca-select`: `S` then `n`/`p`: the pair is reachable in the
  cycle with its colors; the wrap-to-unsaved behavior matches R-B2/R-B3;
  every step re-seeds and the pair scrolls in below the old rows, as a
  transition does in `odca`; `R` flashes the screen and regroups the
  order; the file on disk changes after each `s`/`S`/`X` and at exit
  (R-K5, R-W4, R-W7, R-W8, R-U10).
- **M-7** With the stash full and the program idle, worker CPU usage falls
  to ~zero; on quit, no orphan processes remain (R-S2, R-S5).
- **M-8** Window title tracks the current rule (R-U6).
- **M-9** At speeds below 30 generations per second the picture slides
  continuously rather than stepping; pausing and resuming produce no
  visible jump (R-U3, R-K10).
- **M-11** `odca --help` and `odca-select --help` print their texts and
  exit at once, with no window, no toolkit banner, and no change to
  `~/.odca`; `odca` alone prints a usage line (R-U9).
- **M-12** `odca interesting.odca` plays the shipped pairs two minutes
  each with the old rows keeping their colors; `odca a.play b.odca
  --shuffle` plays the files in a different order each pass, each file's
  pairs in order, announcing `playing <file>` at each change (R-X).
- **M-15** `odca my.odca --longest` after M-14: the window opens 1200
  points wide (600 cells at the default size) and 800 tall; dragging it
  wider or narrower stretches or shrinks the picture to the width with
  cells staying square, the rows recounted, black above and below for
  the remainder; `F` and `--fullscreen` fill the screen's width the
  same way, crisp at a whole-number factor and slightly soft otherwise;
  the counter `<n>/<m>` also stands in the lower-left corner of the
  window, full screen or not, in yellow with a black outline, following
  every frame; `o` hides it and shows it again, paused or not, while the
  terminal's goes on (R-U11, R-K20); a double-click on the title bar of
  a dragged window returns it to 1200 × 800 with its top-left corner in
  place, and a second double-click zooms it as usual (R-U12); each seed runs to its
  recorded end and the next follows; `r`, `m`, `u`, `U`, `a` do nothing,
  `i` restarts the seed, digits and `c` recolor; `--shuffle` mixes the
  seeds; a file whose seeds all survived the cap is refused (R-X8); on
  the terminal the counter `<n>/<m>` ticks in place about five times a
  second below the last line and steps aside for each new line, and it
  does not appear when output is piped (R-O17).
- **M-14** `odca-evolve my.odca --cells 600 --time 60` on a terminal:
  each rule's line, the countdown (`00:00:59  1234 seeds/s` downward, in
  the column of the times that open the lines, the rate over the last
  ten seconds, settling within them and steady after) ticking in place
  below it, the `kept` lines scrolling up as rows join, every line
  opening with the time then left (`00:01:00 rule ...`, `00:00:41 kept
  ...`), the ten ages on one line (`00:00:00 4821, 3990, ...`) as each
  rule ends, Ctrl-C writing the rule in hand; then
  `odca my.odca` in a 1200-point-wide window (600 cells at the default
  size) opens each pair from its best seed and lives visibly longer than
  a random start (R-E, R-X4).
- **M-13** The default run holds 600 × 400 cells in the 1200×800 window;
  `--4`, `--3`, and `--1` hold 300 × 200, 400 × 266 (a 1-point margin
  top and bottom), and 1200 × 800, crisp at every size and in full
  screen (no smoothing); resizing and the margins behave alike at every
  size, and the picture moves at about the same speed in points, so
  `--1` runs twice the generations per second of the default and `--4`
  half (R-U2, R-U5).
- **M-10** Dragging the window edge resizes in cell-size steps; the picture
  stays centered while cells appear or vanish at the edges; growing
  taller uncovers older rows; the animation freezes during the drag and
  resumes without a burst; full screen centers the grid with thin
  background margins and hides the pointer; the size and position return
  on relaunch; `odca <file> --fullscreen` opens full screen at once with
  the pointer hidden, and the platform's control leaves it; `F` enters and
  leaves full screen in both programs, also while paused, and leaves a
  full screen entered by the platform's control (R-U2, R-U8, R-K18).

---

## Uniformity rules

- The vectors file is copied (or referenced) byte-identical into every
  implementation's repository. A port that cannot pass a vector case has a
  bug or has found a spec bug — either way, stop and reconcile against
  `REQTS.md` before changing anything.
- Property tests may add cases but must not weaken the table above.
- All automated layers must run headless (no display, no real user state)
  so they behave identically in CI on macOS and Linux.
