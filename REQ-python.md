# ODCA — Python Implementation Notes

Version 2.15.2 — 2026-09-05 (format compatibility only: pool-preserving color set save, keeper file as pairs; no review or screensaver modes)

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
- **Color sets** (R-U4, R-P4): `Session` loads `{slot: {name, colors}}`
  via `Store.load_color_sets` (anchored to `colorsets/colorsets.json` at
  the repo root, injectable for tests) and exposes `Session.palette`, the
  active set's four RGB tuples after arrangement; `viewer.py` builds its
  numpy palette from that each frame. `map_key` takes the pygame key code
  plus `event.unicode` so shift-s (`S`) and shift-c (`C`) are distinguishable
  from `s` and `c`.
- **Keeper-file anchor** (R-P3): `store.INTERESTING_PATH` resolves three
  levels up from `store.py` to the repository root, where
  `interesting-rules.json` is shared by all implementations. Every port
  must make an equivalent anchoring decision. Python writes pairs with the
  active slot's arranged colors (`json.dumps(indent=1)`, the reference
  layout); its `n`/`p` apply the rule only, not the saved colors, since
  Python still draws through a digit slot.

## Testing notes (see TESTS.md for the normative plan)

- Run everything: `.venv/bin/python -m pytest`. Layer 1 runner:
  `tests/test_conformance.py`; Layer 2 lives across
  `tests/test_automaton.py`, `test_classify.py`, `test_search.py`,
  `test_store.py`, and `test_session.py` (PT-9/10/10a/13/14 against a
  headless `Session` with a temp `Store` and `CandidateSearch(workers=0)`),
  using pytest `tmp_path` for all file paths.
- Headless UI checks: set `SDL_VIDEODRIVER=dummy` and drive
  `Viewer.handle_key` directly.
- **Warning:** a default-constructed `Session` (or `Viewer`) touches real
  user state (`$HOME/.odca/`, `interesting-rules.json`). Any ad-hoc script
  must construct `Session(..., store=Store(state_dir=tmp, keeper_file=tmp/...))`
  and pass it to `Viewer(session=...)` — a smoke test once leaked a dummy
  rule into the user's real state file.
- CI on Linux needs no X server (dummy SDL driver); on macOS the same
  applies.
