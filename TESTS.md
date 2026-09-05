# ODCA — Test Plan

Version 2.26.0 — 2026-09-04

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

**Runner contract.** Each implementation provides a runner that loads the
file, executes every case (no skips), and fails with the case `name` on
any mismatch, exiting nonzero. The runner should be part of the
implementation's normal test suite. Reference:
`python/tests/test_conformance.py` (~50 lines).

Coverage: R-M1–R-M9 (engine), including permutation invariance (paired
reversed-row cases) and both edge modes.

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
| PT-8 | R-P3 | Keeper-file append matches the `rule <id>` line format exactly and preserves prior content; the loader returns saved rules in order and ignores non-conforming lines. |
| PT-9 | R-K4 | Undo restores rules in LIFO order; undo on an empty stack is a no-op. |
| PT-10 | R-B2, R-B3 | With a stubbed keeper file of k rules and a startup rule not in it: first `n` selects rule 0; first `p` selects rule k−1; stepping past either end reaches the unsaved slot; after `m` (or `r`) the unsaved slot holds the new rule and the position is on it. |
| PT-10a | R-U1, R-B3 | With a startup rule equal to saved rule j: the cycle position starts at j (`n` selects j+1, `p` selects j−1), the cycle wraps over the k saved rules with no unsaved slot, and the unsaved slot reappears holding the new rule after `m`/`r`. |
| PT-11 | R-S5 | Stopping a background search that was started terminates all workers; stopping one never started is safe. |
| PT-12 | R-S2, R-S3 | Candidates delivered by workers are valid rules; the stash never exceeds its cap. |
| PT-13 | R-K10 | While paused, every command key except space, Return, `s`, `c`, `S`, the digits, and `q` is a no-op (rule, cells, speed, and cycle state unchanged), while the digits switch slots, `c` re-arranges colors, and `S` saves; space resumes; `q` still quits. |
| PT-14 | R-K11 | While paused, Return advances the automaton exactly one generation per press and the program stays paused; when not paused, Return changes nothing. |
| PT-15 | R-K12, R-A2 | With auto-init on (the startup default) and a rule whose rows repeat (e.g. the all-zero rule), the cells are re-initialized exactly when the `rows`-th consecutive boring generation is computed (generation counter returns to 0, reason `repeating (period 1)` printed); after `a` turns the mode off, nothing happens. |
| PT-16 | R-A1, R-A2 | With a rule under which a producible state dies out, the re-initialization reason names that state as extinct. |
| PT-16a | R-A1 | A row with one producible state extinct is boring when the remaining states are all real populations (≥ 10%), but not boring while another producible state survives as a minority (> 0 and < 10% of cells); two extinct states with no minority are boring. |
| PT-18 | R-A1 | Feeding non-repeating rows that carry a constant minority population: nothing is boring until the 4 × `rows` window is full, then every generation is boring with reason `stagnant`; rows whose minority population swings widely are never stagnant. |
| PT-19 | R-K13 | While paused, `s` queues exactly `rows` generations that advance at one eighth the delay (elapsed time t yields ⌊8t/delay⌋ of them) and stop when the screenful is done, still paused; a second `s` queues a second screenful; space cancels the queue; when not paused `s` saves and queues nothing. |
| PT-20 | R-K14 | No counter before the first resume; resume sets it to 0; after exactly `rows` further generations it reads 1 and `screen 1` is printed; generations from running, zipped screenfuls, and single steps all count; a further resume restarts it at 0. |
| PT-21 | R-A1 | A row recurring exactly 10 × `rows` generations after its first appearance is boring (`repeating`); one recurring 10 × `rows` + 1 generations later is not. |
| PT-22 | R-A1, R-O8 | Feeding a transient followed by a cycle of distinct rows whose period exceeds the repetition window, the detected period equals the true period exactly, `cycle period <n>` is printed once, subsequent reasons read `repeating (period <n>)`, and a rule change clears the detector; a short cycle (period 7) is likewise detected exactly. |
| PT-23 | R-K15, R-K9 | With a stubbed color sets file: `c` yields the next lexicographic arrangement (first press swaps states 2 and 3), 24 presses return to the original, `C` steps back and wraps from 1 to 24, the arrangement is remembered per slot across slot switches, an undefined slot's digit is a no-op, and without a file only slot 1 exists. |
| PT-24 | R-K16, R-P4 | `S` writes the active slot's arranged colors to the file (reloading shows them), resets its arrangement to 1, and the file loader tolerates malformed entries, out-of-range slots, and unparseable files, always supplying slot 1. |
| PT-25 | R-U3, R-K10 | The history holds `rows` + 1 rows; the scroll offset is 0 while filling, 1 at the default speed once full, the elapsed fraction of the delay (wrapping when a generation is computed) once the delay exceeds twice the initial delay, and 1 while paused; resuming computes exactly one generation on the first tick and returns the offset to 0. |
| PT-26 | R-V1–R-V6, R-P4 | With a stubbed pool file (slots 0–9, one pool-only set, one dropped name) and a stubbed candidates file (one duplicate, one dropped, two new): the review order is slots 1–9, 0, the pool set, then the new candidates; `N`/`P` step and wrap with the wrap message, each step computing exactly `rows` generations at once; digits are inert; `X` drops, advances, and wraps when the last set is dropped; each drop writes the first ten kept sets to keys 1–9, 0 (rotating slots down over the drop), the rest pool-only, arrangements not baked in, and the dropped list including the new drops; `S` does nothing; a second review run reloads that order without resurrecting drops; exit saves; outside review mode `N`/`P`/`X` do nothing and exit writes nothing. |
| PT-27 | R-P4 | The pool file round-trips sets with and without slots plus the dropped list; a JSON `null` slot reads as pool-only; the digit-bound save keeps the pool and the dropped list; the candidates file loads by name and colors and skips malformed palettes. |
| PT-28 | R-W1–R-W6, R-P5 | With a missing screensaver file: entry creates it empty and no pair is active; `N` does nothing and `s` reports no pair; `S` appends the composed pair (current rule, active set name, arranged colors) without changing the position; `N` activates pair 1 (rule and colors restored, and exactly `rows` generations computed at once), `P` at the start prints the end message; `s` overwrites the active pair; stepping past the last prints the end message; `X` deletes and activates the neighbor, emptying the list clears the position; startup with a non-empty file activates pair 1; `[`/`]` walk the pool. Outside the mode the keys are inert. |
| PT-29 | R-P5 | The screensaver file round-trips, escapes quotes in names, writes `{"pairs": []}` for an empty list in the shared layout, skips pairs with invalid rule IDs, and loads an unparseable file as empty. |
| PT-30 | R-W7 | With a file of pairs whose rules run A, B, A, C, B: the grouped view order is A A B B C; entry and each crossing into another rule's group print the group marker, steps within a group do not; `S` appends to the file's end but joins its group in the view without moving the position; `s` rewrites the pair at its file position; `X` removes the pair from its file position and activates the pair now at that view position; the file is written in file order throughout. |
| PT-31 | R-X1–R-X4, R-O13 | With a two-pair file whose rules die at once: entry plays pair 1 (its rule and colors, generation 0, no reason printed); the 17th generation (a screenful of boring rows) advances to pair 2 with a fresh seed and the reason printed, and no `auto-init` line; a further screenful loops back to pair 1. With auto-init off, a pair advances with reason `timeout` after 60 unpaused seconds, paused time not counting, and the clock restarts. |
| PT-17 | R-A3, R-K12 | The boring count resets on a rule change; `a` toggles the mode and prints its state; the mode is on at startup. |

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
  the screen; `S` then a restart shows the arranged colors (R-K9, R-K15,
  R-K16, R-U4).
- **M-6** `s` then `n`/`p`: the saved rule is reachable in the cycle; the
  wrap-to-unsaved behavior matches R-B2/R-B3.
- **M-7** With the stash full and the program idle, worker CPU usage falls
  to ~zero; on quit, no orphan processes remain (R-S2, R-S5).
- **M-8** Window title tracks the current rule (R-U6).
- **M-9** At speeds below 30 generations per second the picture slides
  continuously rather than stepping; pausing and resuming produce no
  visible jump (R-U3, R-K10).

---

## Uniformity rules

- The vectors file is copied (or referenced) byte-identical into every
  implementation's repository. A port that cannot pass a vector case has a
  bug or has found a spec bug — either way, stop and reconcile against
  `REQTS.md` before changing anything.
- Property tests may add cases but must not weaken the table above.
- All automated layers must run headless (no display, no real user state)
  so they behave identically in CI on macOS and Linux.
