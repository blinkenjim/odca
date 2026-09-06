# ODCA — Python Implementation Notes

Version 3.1.0 — 2026-09-06 (resizable window with full screen, deep history; 3.0.0: two programs, `odca` and `odca-select`, installed as console scripts; odca files and `library.json`)

Non-normative companion to `REQTS.md` describing the reference Python
implementation in this repository. A re-implementation in Python need not
copy these choices, but they are known to work.

## Environment

- Python ≥ 3.9 on macOS or Linux; dependencies: `numpy`, `pygame`,
  `pytest` (`pyproject.toml`; `requirements.txt` lists the same).
- The implementation lives in the `python/` directory of the monorepo;
  run all commands from there. Setup: `python3 -m venv .venv &&
  .venv/bin/pip install --upgrade pip setuptools && .venv/bin/pip install
  -e '.[test]'`, which installs the console scripts `odca` and
  `odca-select` into the venv (`[project.scripts]`; the stock macOS pip
  21.2 cannot do a PEP 660 editable install, hence the upgrade). Run with
  `.venv/bin/odca <file.odca>` / `.venv/bin/odca-select <file.odca>`, or
  `python -m odca` / `python -m odca.select` without installing.

## Layout

| module | role (spec sections) |
|--------|----------------------|
| `odca/automaton.py` | engine: `Rule`, `Automaton` (R-M) |
| `odca/classify.py` | screening: `evaluate`, `find_candidate` (R-C) |
| `odca/search.py` | background workers: `CandidateSearch` (R-S) |
| `odca/store.py` | persistence: path functions and the injectable `Store` (R-P) |
| `odca/session.py` | toolkit-free orchestration `Session`: keys, undo, the look cycle, odca-select and odca behavior, pause, stash, timing (R-U/K/B/W/X/O) |
| `odca/viewer.py` | pygame display layer: resizable window, key translation, pacing, blit, flash (R-U2/3/5/6/8/10) |
| `odca/cli.py` | shared argument handling and the viewer launch (R-U9) |
| `odca/play.py`, `odca/select.py` | the `odca` and `odca-select` entry points (sections 4d, 4c) |
| `odca/help.py` | the two help texts (copies of `conformance/help-*.txt`) |
| `odca/__main__.py` | `python -m odca` = the player |

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
- **Rendering**: `Session.history` is a `(filled, cols)` uint8 view,
  oldest row first, of a buffer twice `HISTORY_DEPTH` (2048) rows deep
  that is compacted once it runs out, so a push is one row write and the
  view is never copied; `Session.visible_start` indexes the last
  `rows + 1` rows (R-U8). `Viewer.frame` looks those up through the
  two-bank palette (background below them until the buffer fills), wraps
  them with `pygame.surfarray.make_surface`, scales with
  `pygame.transform.scale` to one row taller than the grid, and blits at
  `-scroll_offset * cell_size` inside a clip rectangle on the grid (R-U3).
  No per-cell draw calls.
- **Window** (R-U2, R-U8): `pygame.RESIZABLE`; on `VIDEORESIZE` /
  `WINDOWSIZECHANGED` the viewer calls `Session.resize` with as many whole
  cells as fit (never below 40 × 30: a smaller window crops the grid,
  since pygame 2.6 has no minimum-size call) and passes `dt = 0` for that
  frame, so the interval spent resizing is never caught up. On macOS SDL
  blocks the loop for the whole drag, which freezes the animation as R-U8
  asks (the window's contents are stretched by the OS meanwhile); on Linux
  the events stream and each frame that sees one is frozen. SDL offers no
  resize increments, so `grid_rect` centers the grid and the remainder
  becomes margins in the background color. Full screen is the platform's
  own control (macOS: the green button, which SDL gives every resizable
  window); the pointer hides while `Viewer.is_full_screen` holds — pygame's
  `is_fullscreen()` or a window as wide as a desktop and at least 0.9 of
  its height, since SDL does not flag a full screen Space and a notched
  display's Space is shorter than the desktop. The window size is not
  remembered (R-U2 allows either).
- **`Session.resize`** (R-U8): crops or zero-pads every history row about
  its center with numpy slicing, pads the live row with `rng` cells,
  rebuilds the history buffers at the new width, sets the automaton's
  `width` and `cells` in place (the generation count survives), trims to
  the depth, renews the stagnation window for the new `rows`, resets the
  detectors, and prints R-O14.
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
  anchored to `library.json` and `colorsets/candidates.json` at
  the repo root, injectable for tests (`Store(candidates_file=...)`).
  `Session.palette8` and `Session.row_banks` give the two-bank palette of
  R-X5; `viewer.py` indexes `palette8[row_banks * 4 + history]` each frame
  (outside screensaver mode both banks are the active set). `map_key` takes
  the pygame key code plus `event.unicode` so `S`, `C`, `N`, `P`, `X`, `[`,
  and `]` arrive as typed.
- **`--help` and arguments** (R-U9): `odca/help.py` holds `HELP_ODCA` and
  `HELP_ODCA_SELECT`, copies of the conformance files (`tests/test_main.py`
  checks byte equality). `cli.parse` handles `--help` and usage errors
  before `cli.run` imports `viewer`, because pygame prints its banner at
  import time and R-U9 allows no other output.
- **Programs** (sections 4c, 4d): `Session(select_file=...)` is
  odca-select, `Session(play_file=..., shuffle=...)` is odca; `review_mode`
  (section 4b) survives for tests and the future color set tool. The look
  cycle keeps `looks` in file order, `view_order` (file indices in n/p
  order, regrouped by `R`) and `look_index`/`view_position`; `unsaved_rule`
  and `unsaved_set` are the extra slot. `finish()` writes the odca file at
  exit. Play mode clocks (`play_elapsed`, `since_init`) advance in `tick`
  before the generations, so a re-seed inside a tick restarts the grace
  period from that tick; `play_order` is the current pass (a numpy
  permutation under `--shuffle`, its first entry swapped away from the
  look just played). `flash_remaining` counts down in `tick` even while
  paused; `viewer.draw` inverts the frame while `inverted` (R-U10).
  Display-link pacing stays Swift-only; the window, resizing, and pointer
  hiding reached parity in 3.1.0.
- **File anchors** (R-P3, R-P4): `store.LIBRARY_PATH` resolves three
  levels up from `store.py` to the repository root, where `library.json`
  is shared by all implementations; odca files are whatever path the
  command line names. `load_odca_file` returns None for a missing file
  (odca-select must not create it at entry) and `[]` for an unparseable
  one; `save_odca_file` writes `json.dumps(indent=1)`, the reference layout
  Swift reproduces byte for byte.

## Testing notes (see TESTS.md for the normative plan)

- Run everything: `.venv/bin/python -m pytest`. Layer 1 runner:
  `tests/test_conformance.py`; Layer 2 lives across
  `tests/test_automaton.py`, `test_classify.py`, `test_search.py`,
  `test_store.py`, `test_main.py`, `test_library.py`, and
  `test_session.py` (PT-9/10/10a/13/14 and PT-26, PT-28, PT-30, PT-31,
  PT-32, PT-33, PT-34, PT-36 against a headless `Session` with a temp
  `Store` and `CandidateSearch(workers=0)`; PT-8, PT-27, PT-29 in
  `test_store.py`; PT-35 in `test_main.py`; PT-37 in `test_library.py`),
  using pytest `tmp_path` for all file paths.
- `tests/test_viewer.py` checks the pygame layer's geometry (grid size,
  centering, margins, the visible slice, the inversion) on plain
  `pygame.Surface`s, which need no window; the window itself is M-10.
  Ad-hoc window checks: set `SDL_VIDEODRIVER=dummy`, or drive a copy of
  `Viewer.run`'s loop with `pygame._sdl2.video.Window.size` changes.
- **Warning:** a default-constructed `Session` (or `Viewer`) touches real
  user state (`$HOME/.odca/`, and `library.json` if anything bakes). Any
  ad-hoc script must construct `Session(..., store=Store(state_dir=tmp,
  library_file=tmp/...), select_file=tmp/...)` and pass it to
  `Viewer(session=...)` — a smoke test once leaked a dummy rule into the
  user's real state file.
- CI on Linux needs no X server (dummy SDL driver); on macOS the same
  applies.
