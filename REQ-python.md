# ODCA — Python Implementation Notes

Version 2.17.0 — 2026-09-05 (catch-up: active-set pool model with `[`/`]`, color set review, screensaver review and consistency check, screensaver play, saved presentations by n/p; gallery polish stays Swift-only)

Non-normative companion to `REQTS.md` describing the reference Python
implementation in this repository. A re-implementation in Python need not
copy these choices, but they are known to work.

## Environment

- Python ≥ 3.9 on macOS or Linux; dependencies: `numpy`, `pygame`,
  `pytest` (see `python/requirements.txt`).
- The implementation lives in the `python/` directory of the monorepo;
  run all commands from there. Setup: `python3 -m venv .venv &&
  .venv/bin/pip install -r requirements.txt`; run with
  `.venv/bin/python -m odca`.

## Layout

| module | role (spec sections) |
|--------|----------------------|
| `odca/automaton.py` | engine: `Rule`, `Automaton` (R-M) |
| `odca/classify.py` | screening: `evaluate`, `find_candidate` (R-C) |
| `odca/search.py` | background workers: `CandidateSearch` (R-S) |
| `odca/store.py` | persistence: path functions and the injectable `Store` (R-P) |
| `odca/session.py` | toolkit-free orchestration `Session`: keys, undo, cycle, pause, stash, timing (R-U/K/B/O) |
| `odca/viewer.py` | pygame display layer: window, key translation, pacing, blit (R-U2/3/5/6) |
| `odca/__main__.py` | entry point (R-U1) |

(Paths are relative to `python/`.)

## Implementation choices

- **Session/display split** (2.1.0): all behavior lives in `Session`
  (`session.py`, no pygame import) — undo stack, interesting-rule cycle,
  pause/single-step, speed, stash draining, and the timing accumulator.
  Keys are single characters (`'r'`, `'+'`, `' '`, `'\n'`, `'0'`–`'9'`).
  `viewer.py` translates pygame key codes via `map_key`, calls
  `Session.tick(dt)` each refresh, and renders `Session.history` through
  the color set for `Session.color_set`. Same boundary as the Swift port's
  `Session`/`ViewerModel`.
- **Rule lookup** uses the 0/1/4/16 weighting (see the informative note
  under R-M11): `step()` computes per-cell weighted neighborhood sums with
  `np.roll` (wrap) or zero-padding (fixed) and indexes a 49-slot dense
  `uint8` table built from the 20-entry rule. The whole row updates in a
  few vectorized operations; the same sums feed the classifier's
  input-entropy measurement (R-C3) via `np.bincount`.
- **Rendering**: the scroll buffer is a `(rows + 1, cols)` uint8 array; a
  palette lookup yields RGB, wrapped by `pygame.surfarray.make_surface`,
  scaled with `pygame.transform.scale` to one row taller than the window,
  and blitted at `-scroll_offset * cell_size` (R-U3). No per-cell draw
  calls.
- **Timing** (R-U5): `pygame.time.Clock().tick(60)` paces refreshes; a
  float accumulator converts elapsed time to whole generations. Catch-up
  cap: 2000 steps/refresh.
- **Parallel search** (R-S1): `multiprocessing` processes, not threads —
  the GIL serializes CPU-bound Python threads, and the screening loop's
  many small numpy calls hold the GIL between array ops. Workers are
  daemons; a `multiprocessing.Event` signals stop, joins have timeouts,
  and `terminate()` is the backstop. The queue is a bounded
  `multiprocessing.Queue(maxsize=32)`; workers `put` with a 0.25 s timeout
  in a loop so they notice the stop event while blocked (R-S2, R-S5).
- On macOS, `multiprocessing` uses the *spawn* start method: worker code
  must live at module top level in a module importable without side
  effects (`odca/search.py` imports no pygame).
- **Keys**: pygame keycodes; `+` is accepted as `K_PLUS`, `K_EQUALS`
  (unshifted on US layouts), and `K_KP_PLUS`; likewise `K_MINUS` /
  `K_KP_MINUS` (R-K8).
- **RNG** (R-N1): `numpy.random.default_rng()` (PCG64). Worker processes
  seed from OS entropy so their streams differ.
- **Color sets** (R-U4, R-P4, R-K17): `Session` keeps an *active set*
  (`active_set`: slot or None, name, colors) that may be any pool member;
  digits pick the hot ten through `Store.load_color_sets`, `[`/`]` walk the
  whole pool in review order (`Session.pool`), and arrangements are
  remembered per set name; `S` bakes the arrangement into the pool entry by
  name through `Store.load_color_set_file`/`save_color_set_file`. Paths are
  anchored to `colorsets/colorsets.json` and `colorsets/candidates.json` at
  the repo root, injectable for tests (`Store(candidates_file=...)`).
  `Session.palette8` and `Session.row_banks` give the two-bank palette of
  R-X5; `viewer.py` indexes `palette8[row_banks * 4 + history]` each frame
  (outside screensaver mode both banks are the active set). `map_key` takes
  the pygame key code plus `event.unicode` so `S`, `C`, `N`, `P`, `X`, `[`,
  and `]` arrive as typed.
- **Modes** (REQTS 4b–4d): `python -m odca --colorset-review`,
  `--screensaver-review <file>`, `--consistency-check <file>` (must exist;
  the grouped view of R-W7), `--screensaver <file>` (must exist; play, with
  precedence over the review flags). `__main__.py` parses them by hand and
  passes `review_mode`, `screensaver_file`, `group_by_rule`, `play_file` to
  `Session`; `Viewer.run` calls `Session.finish()` at exit so color set
  review saves (R-V5). Play mode clocks (`play_elapsed`, `since_init`)
  advance in `tick` before the generations, so a re-seed inside a tick
  restarts the grace period from that tick. Pygame's window is fixed-size;
  display-link pacing, resizing, and pointer hiding are Swift-only by
  decision (TO-DO, 2026-09-05).
- **Keeper-file anchor** (R-P3): `store.INTERESTING_PATH` resolves three
  levels up from `store.py` to the repository root, where
  `interesting-rules.json` is shared by all implementations. Every port
  must make an equivalent anchoring decision. Python writes pairs with the
  active set's name and arranged colors (`json.dumps(indent=1)`, the
  reference layout, shared with `store.save_screensaver`); `n`/`p` apply a
  saved pair's colors as the active set, and the unsaved slot restores the
  set that was showing when the unsaved rule arrived (`unsaved_set`).

## Testing notes (see TESTS.md for the normative plan)

- Run everything: `.venv/bin/python -m pytest`. Layer 1 runner:
  `tests/test_conformance.py`; Layer 2 lives across
  `tests/test_automaton.py`, `test_classify.py`, `test_search.py`,
  `test_store.py`, and `test_session.py` (PT-9/10/10a/13/14 and
  PT-26–PT-31, PT-33, PT-34 against a headless `Session` with a temp
  `Store` and `CandidateSearch(workers=0)`; PT-27 and PT-29 in
  `test_store.py`), using pytest `tmp_path` for all file paths. PT-32
  (resizing) is Swift-only.
- Headless UI checks: set `SDL_VIDEODRIVER=dummy` and drive
  `Viewer.handle_key` directly.
- **Warning:** a default-constructed `Session` (or `Viewer`) touches real
  user state (`$HOME/.odca/`, `interesting-rules.json`). Any ad-hoc script
  must construct `Session(..., store=Store(state_dir=tmp, keeper_file=tmp/...))`
  and pass it to `Viewer(session=...)` — a smoke test once leaked a dummy
  rule into the user's real state file.
- CI on Linux needs no X server (dummy SDL driver); on macOS the same
  applies.
