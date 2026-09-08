# ODCA — Swift Implementation Notes

Version 3.24.0 — 2026-09-07 (navigation scrolls the look in; 3.22.0: a mutated look saves as a new look; 3.20.0: `--3`; 3.18.0: `U` undoes all; 3.16.0: `m` edits the look under review; 3.14.0: `--watchdog`, `--grace`; 3.12.0: shuffle constraints; 3.10.0: initial delay scales with the cell; 3.8.0: cell size flags; 3.6.0: `F` toggles full screen; `swift/run` wrapper; 3.4.0: `--fullscreen`; 3.2.0: per-row palette table, rows keep their colors for good; 3.0.1: window fix for file arguments; 3.0.0: two executables, `odca` and `odca-select`, over a shared `ODCAUI` module; odca files and `library.json`)

Non-normative companion to `REQTS.md` describing the Swift/SwiftUI
implementation in `swift/`. macOS only (SwiftUI), macOS 14+.

## Layout

SwiftPM package (`swift/Package.swift`), no external dependencies:

| target | role (spec sections) |
|--------|----------------------|
| `ODCAKit` (library) | engine `Rule`/`Automaton` (R-M), `Classifier` (R-C), `CandidateSearch` (R-S), `Store` + `ColorSet` + `Look` (R-P), `Session` (R-U/K/B/A/W/X/O orchestration), `Xoshiro256` (R-N1), the help texts |
| `ODCAUI` (library) | AppKit/SwiftUI shell shared by both programs: `ViewerModel` (rendering, key translation), `AutomatonView` (display-link pacing, layer presentation), `ODCAApp`/`ContentView`, `parseArguments`/`launch` (Launch.swift) |
| `ODCAPlay` → product `odca`, `ODCASelect` → product `odca-select` | one `main.swift` each: parse arguments, build the `Session`, `launch` |
| `ODCAKitTests` | conformance runner + property tests (TESTS.md layers 1–2) |

## Implementation choices

- **Session/display split**: the toolkit-free orchestration lives in
  `Session` (in `ODCAKit`, no AppKit/SwiftUI imports): undo stack,
  interesting-rule cycle, pause/single-step, speed, stash draining, and
  the timing accumulator. The UI layer translates `NSEvent`s to
  `Session.Key`, calls `tick(_:)` once per screen refresh, and renders
  `Session.history`.
- **Pacing** (2.18.0): a `CADisplayLink` obtained from the view
  (`NSView.displayLink(target:selector:)`, macOS 14+) drives
  `frameTick(dt:)` phase-locked to the display's refresh (60 or 120 Hz),
  with `dt` taken from the link's timestamps. A wall-clock `Timer` drifted
  against the refresh and produced beat-frequency judder at high
  generation rates. This is the architecture recommended in
  TO-DO.md, adopted from the start here.
- **Parallel search** (R-S1): worker *threads* (GCD global queue), not
  processes — Swift has no GIL, so threads give true multicore
  parallelism. The bounded hand-off queue is an `NSCondition`-based
  `BoundedQueue` (capacity 32); workers block on `put` when full (R-S2)
  with a 0.25 s timeout so they notice the stop flag (R-S5).
- **Rendering**: `Session.history` (rows + 1 rows) → RGBA byte buffer →
  `CGImage` once per frame, set as the `contents` of a `CALayer` with
  nearest-neighbor filtering for crisp cells, one row taller than the
  view and positioned at `-scrollOffset * cellSize` with implicit
  animations disabled, inside a clipping layer (R-U3). SwiftUI only hosts
  the view (`NSViewRepresentable`). No per-cell views.
- **Keyboard**: an `NSEvent.addLocalMonitorForEvents(.keyDown)` monitor
  (reliable regardless of focus within the window); Command-modified keys
  pass through to the system. Keypad Enter/+/− map like their main-row
  equivalents (R-K8, R-K11). `charactersIgnoringModifiers` still reflects
  Shift, so `S` and `C` (R-K16, R-K15) arrive as uppercase characters.
- **Auto-init** (R-A): implemented in `Session.observe(_:)` — census-based
  extinction with living-minority patience, a ten-screen repetition
  window (`[[UInt8]: Int]` counts over an array window), stagnation over
  four screens, and Brent's cycle detection with one saved row. Row
  arrays serve directly as dictionary keys.
- **Color sets** (R-U4, R-P4): `Store.loadColorSets()` parses the shared
  JSON with `JSONSerialization` (tolerant of malformed entries) and
  `saveColorSets` hand-formats the same layout as Python's
  `json.dumps(indent=1)` so an `S` from either implementation leaves the
  file byte-stable (a test round-trips the shipped file and asserts
  identity). `Session.palette` yields the arranged `RGB` colors; the 24
  arrangements are generated as lexicographic permutations.
- **Output sink**: `Session.output` (default `print`) carries every R-O
  line; tests capture it instead of stdout.
- **Review mode** (R-V): `Session(reviewMode:)`, bound by no executable in
  3.0.0 (kept for the color set tool and its tests); the review list,
  position, and drops live in `Session`, `Store.loadColorSetFile` /
  `saveColorSetFile` handle the library (entries with optional slot plus
  the dropped list), and `Store.loadCandidatePalettes` reads
  `colorsets/candidates.json`.
- **odca-select** (R-W): `Session(selectFile:)`. `Store.loadOdcaFile` /
  `saveOdcaFile` handle the looks file (R-P3) in the shared JSON layout via
  the static `quoted`/`list` helpers (`loadOdcaFile` returns nil for a
  missing file, so entry writes nothing). The look cycle keeps `looks` in
  file order, `viewOrder` (file indices in n/p order, rebuilt by `R`) and
  `lookIndex`/`viewPosition`; `unsavedRule`/`unsavedSet` are the extra
  slot. Every mode but color set review draws through `Session.activeSet`
  (any pool member); arrangements are remembered per set name; `[`/`]`
  walk `pool`. `ViewerModel.shutDown` calls `Session.finish()` so exit
  writes the file. `R` sets `flashRemaining`, which `tick` counts down
  even while paused; `renderImage` inverts palette and background while
  `inverted` (R-U10).
- **odca** (R-X): `Session(playFile:shuffle:)`. `advance()` routes a firing
  of the boring detector to `nextPlayLook` once `playElapsed` has reached
  `Session.playTimeout`, otherwise re-seeds in place; `tick` accumulates
  `playElapsed` (the look's screen time) and `sinceInit` (the grace clock,
  zeroed by `initCells`) while unpaused and advances when both have run
  out. `playOrder` is the current pass — under `--shuffle`,
  `Array.shuffle(using:)` on the session RNG, redrawn up to
  `shuffleTries` (100) times until `noRepeats` holds: no two consecutive
  looks, the one just played included, share a rule or sorted colors. Program precedence in `Session.init`: play, then
  select, then review. Colors per row (R-X5): `Session.rowPalettes` tags
  each history row with an index into `paletteTable`, the color sets rows
  have been painted with, four `RGB` per entry; in play mode `pushRow`
  appends a changed active set (or reuses an identical entry) and prunes
  entries no remembered row uses once the table passes `paletteLimit`
  (64); other modes have one entry, the active set. The renderer indexes
  `paletteTable[index * 4 + state]`.
- **`--fullscreen`** (R-U2): `launch(fullScreen:)` sets
  `AppDelegate.fullScreenAtLaunch`; once the window exists the delegate
  calls `toggleFullScreen(nil)`, the same path as the green button, so the
  pointer hiding and the frame autosave behave as for a manual entry.
- **`--watchdog` / `--grace`** (R-X2, R-X3): `parseArguments(options:)`
  collects options that take the next argument as a value;
  `wholeSeconds(program:options:_:default:)` validates a positive whole
  number (exit 2 otherwise) and `Session.init(playTimeout:playGrace:)`
  takes the seconds, defaulting to the statics `Session.playTimeout` /
  `playGrace` (120 / 60). To change the defaults: those two statics, the
  help text's prose and flag descriptions, R-X2 / R-X3, the README bullet.
- **Cell size** (R-U2): `chooseCellSize(program:flags:)` in `Launch.swift`
  reads `--4` / `--3` / `--2` / `--1` (two exit 2) and `launch(cellSize:)` stores
  it in `ViewerModel.cellSize`, a static set once before the window
  exists; `defaultCols` / `defaultRows` derive from it, and the view,
  the resize increments, and the image scale read it. The pixel loop in
  `renderImage` is per cell, so smaller cells cost proportionally more per
  frame (1200 × 800 cells at `--1` in the default window). The
  executables pass `initialDelay: Session.initialDelay * cellSize / 4`
  to `Session.init` (R-U5); the continuous-scrolling threshold is the
  instance's `smoothScrollDelay`, twice that.
- **`F`** (R-K18): handled in `ViewerModel`'s key monitor before the
  session mapping — `toggleFullScreen(nil)` on the event's window — so
  the session never sees it and the pause rule needs no case for it.
- **Resizing** (R-U2, R-U8): `AutomatonView.layout()` derives cols/rows
  from its bounds and calls `Session.resize`; the grid lives in a
  clipping `gridLayer` centered in the view, whose background is the
  state-0 color for the margins. The app delegate sets
  `contentResizeIncrements` to the cell size, enables full screen, and
  sets a frame autosave name; SwiftUI supplies `defaultSize` 1200×800 and
  a 160×120 minimum. `Session.history` is a ring of up to
  `Session.historyDepth` rows; `visibleStart` marks the displayed tail.
  During `inLiveResize` the display link only re-renders (no tick) and
  the link timestamp is cleared at `viewDidEndLiveResize` so no interval
  is caught up; full-screen enter/exit notifications hide and unhide
  `NSCursor`.
- **Engine**: plain loops over `[UInt8]` rows — native code needs no numpy
  equivalent; the 0/1/4/16 weighted-sum lookup and 49-slot dense table
  match the reference. Conformance vectors certify equality.
- **RNG** (R-N1): xoshiro256** seeded via SplitMix64; the no-argument
  initializer seeds from OS entropy (each search worker gets its own).
- **File anchors** (R-P3, R-P4): `Store.repoRoot` resolves four levels up
  from `Store.swift` via `#filePath` to the repository root, where
  `library.json` lives; odca files are whatever path the command line
  names. `Store` takes injectable paths, which is also how tests isolate
  state.
- **`--help` and arguments** (R-U9): `ODCAKit.helpOdca` and
  `helpOdcaSelect` (`Help.swift`) are multi-line string literals of the
  conformance files; a literal drops the file's final line break, so each
  carries one extra empty line before the closing quotes. Each executable
  is a `main.swift` (top-level code, so no `@main`): `parseArguments`
  prints help or a usage error and exits before any `Session`, then
  `launch` hands `ViewerModel` a closure that builds the session, registers
  the volatile default `NSTreatUnknownArgumentsAsOpen = NO`, and calls
  `ODCAApp.main()` inside `MainActor.assumeIsolated`. `ViewerModel.shared`
  and its `Session` are created lazily from the SwiftUI scene, after
  NSApplication is running. The default matters (3.0.1): AppKit treats
  unknown command-line arguments — our odca file — as documents to open,
  and SwiftUI then creates no default window at all; 3.0.0 launched with
  text on stdout and no window. `parseArguments` also line-buffers stdout
  (`setlinebuf`) so status lines arrive promptly when piped or logged.
  `HelpTests` compares against the files.
- **Launch via `swift run -c release odca <file.odca>`**, or the `swift/run`
  wrapper that builds release and runs the binary (no app bundle): the app
  delegate sets `NSApp.setActivationPolicy(.regular)` and activates, so the
  window appears and takes keyboard focus. Build release for viewing: the
  debug build leaves `renderImage()`'s per-pixel loop unoptimized (bounds
  checks, no inlining, per-access retain/release) and the animation is
  choppy on any Mac (seen on an M1 Pro, 2026-09-05).

## Testing notes (see TESTS.md for the normative plan)

- Run everything from `swift/`: `swift test`. The conformance runner
  (`Tests/ODCAKitTests/ConformanceTests.swift`) locates
  `../conformance/vectors.json` via `#filePath`.
- Session/property tests construct `Store` instances pointed at temp
  directories — never the user's real `~/.odca` or `library.json` — write
  odca files beside them, and use `CandidateSearch(workers: 0)` so no
  search threads start. The suite covers PT-1..PT-36 (PT-32 Swift-only).
- Tests run headless; no window is created (only `ODCAUI` and the two
  executable targets touch AppKit/SwiftUI).
