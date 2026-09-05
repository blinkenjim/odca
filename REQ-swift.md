# ODCA — Swift Implementation Notes

Version 2.26.0 — 2026-09-04 (color set and screensaver review modes; ahead of Python)

Non-normative companion to `REQTS.md` describing the Swift/SwiftUI
implementation in `swift/`. macOS only (SwiftUI), macOS 14+.

## Layout

SwiftPM package (`swift/Package.swift`), no external dependencies:

| target | role (spec sections) |
|--------|----------------------|
| `ODCAKit` (library) | engine `Rule`/`Automaton` (R-M), `Classifier` (R-C), `CandidateSearch` (R-S), `Store` + `ColorSet` (R-P), `Session` (R-U/K/B/A/O orchestration), `Xoshiro256` (R-N1) |
| `ODCA` (executable) | SwiftUI app shell: `ViewerModel` (rendering, key translation), `AutomatonView` (display-link pacing, layer presentation), `ODCAApp`/`ContentView` |
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
- **Review mode** (R-V): `Session(reviewMode:)` is set from
  `CommandLine.arguments.contains("--colorset-review")`; the review list,
  position, and drops live in `Session`, `Store.loadColorSetFile` /
  `saveColorSetFile` handle the pool file (entries with optional slot plus
  the dropped list), and `Store.loadCandidatePalettes` reads
  `colorsets/candidates.json`. `ViewerModel.shutDown` calls
  `Session.finish()` so exit saves.
- **Screensaver review** (R-W): `Session(screensaverFile:)` from
  `--screensaver-review <file>`; `Store.loadScreensaver`/`saveScreensaver`
  handle the pairs file (R-P5) in the shared JSON layout via the static
  `quoted`/`list` helpers. In this mode the palette comes from
  `Session.activeSet` (any pool member) rather than a digit slot.
  `--consistency-check <file>` sets `groupByRule`: `Session.viewOrder`
  holds file indices in presentation order and `viewPosition` the cursor;
  `pairs` and `pairIndex` always refer to file order. The view model
  checks the file exists and exits with an error otherwise.
- **Screensaver mode** (R-X): `Session(playFile:)` from `--screensaver
  <file>` (existence checked by the view model). `advance()` routes a
  firing of the boring detector to `nextPlayPair` instead of the in-place
  re-seed; `tick` accumulates `playElapsed` while unpaused and advances at
  `Session.playTimeout`. Mode precedence in `Session.init`: play, then
  screensaver review, then color set review.
- **Engine**: plain loops over `[UInt8]` rows — native code needs no numpy
  equivalent; the 0/1/4/16 weighted-sum lookup and 49-slot dense table
  match the reference. Conformance vectors certify equality.
- **RNG** (R-N1): xoshiro256** seeded via SplitMix64; the no-argument
  initializer seeds from OS entropy (each search worker gets its own).
- **Keeper-file anchor** (R-P3): `Store.repoRoot` resolves four levels up
  from `Store.swift` via `#filePath` to the repository root. `Store` takes
  injectable paths, which is also how tests isolate state.
- **Launch via `swift run`** (no app bundle): the app delegate sets
  `NSApp.setActivationPolicy(.regular)` and activates, so the window
  appears and takes keyboard focus.

## Testing notes (see TESTS.md for the normative plan)

- Run everything from `swift/`: `swift test`. The conformance runner
  (`Tests/ODCAKitTests/ConformanceTests.swift`) locates
  `../conformance/vectors.json` via `#filePath`.
- Session/property tests construct `Store` instances pointed at temp
  directories — never the user's real `~/.odca`, the repo keeper file, or
  `colorsets/colorsets.json` — and use `CandidateSearch(workers: 0)` so
  no search threads start. The suite covers PT-1..PT-24.
- Tests run headless; no window is created (only the `ODCA` executable
  target touches AppKit/SwiftUI).
