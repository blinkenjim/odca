# ODCA — Test Plan

Version 1.0 — 2026-09-03

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
| PT-13 | R-K10 | While paused, every command key except space and `q` is a no-op (rule, cells, speed, palette, and cycle state unchanged); space resumes; `q` still quits. |

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
- **M-5** `0`/`1`/`2` switch palettes instantly; `3`–`9` do nothing
  (R-K9, R-U4).
- **M-6** `s` then `n`/`p`: the saved rule is reachable in the cycle; the
  wrap-to-unsaved behavior matches R-B2/R-B3.
- **M-7** With the stash full and the program idle, worker CPU usage falls
  to ~zero; on quit, no orphan processes remain (R-S2, R-S5).
- **M-8** Window title tracks the current rule (R-U6).

---

## Uniformity rules

- The vectors file is copied (or referenced) byte-identical into every
  implementation's repository. A port that cannot pass a vector case has a
  bug or has found a spec bug — either way, stop and reconcile against
  `REQTS.md` before changing anything.
- Property tests may add cases but must not weaken the table above.
- All automated layers must run headless (no display, no real user state)
  so they behave identically in CI on macOS and Linux.
