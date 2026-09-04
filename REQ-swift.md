# ODCA — Swift Implementation Notes

Version 2.0.0 — implements spec (REQTS.md) 1.3.
2026-09-03

Non-normative companion to `REQTS.md` describing the Swift/SwiftUI
implementation in `swift/`. macOS only (SwiftUI), macOS 14+.

## Layout

SwiftPM package (`swift/Package.swift`), no external dependencies:

| target | role (spec sections) |
|--------|----------------------|
| `ODCAKit` (library) | engine `Rule`/`Automaton` (R-M), `Classifier` (R-C), `CandidateSearch` (R-S), `Store` (R-P), `Session` (R-U/K/B/O orchestration), `Xoshiro256` (R-N1) |
| `ODCA` (executable) | SwiftUI app: `ViewerModel` (timer, rendering, key translation), `ODCAApp`/`ContentView` |
| `ODCAKitTests` | conformance runner + property tests (TESTS.md layers 1–2) |

## Implementation choices

- **Session/display split**: unlike the Python reference, the toolkit-free
  orchestration lives in `Session` (in `ODCAKit`, no AppKit/SwiftUI
  imports): undo stack, interesting-rule cycle, pause/single-step, speed,
  stash draining, and the timing accumulator. The UI layer translates
  `NSEvent`s to `Session.Key`, calls `tick(_:)` at ~60 Hz from a `Timer`,
  and renders `Session.history`. This is the architecture recommended in
  TO-DO.md, adopted from the start here.
- **Parallel search** (R-S1): worker *threads* (GCD global queue), not
  processes — Swift has no GIL, so threads give true multicore
  parallelism. The bounded hand-off queue is an `NSCondition`-based
  `BoundedQueue` (capacity 32); workers block on `put` when full (R-S2)
  with a 0.25 s timeout so they notice the stop flag (R-S5).
- **Rendering**: `Session.history` → RGBA byte buffer → `CGImage` once per
  frame, displayed via SwiftUI `Image` with `.interpolation(.none)` for
  crisp cells. No per-cell views.
- **Keyboard**: an `NSEvent.addLocalMonitorForEvents(.keyDown)` monitor
  (reliable regardless of focus within the window); Command-modified keys
  pass through to the system. Keypad Enter/+/− map like their main-row
  equivalents (R-K8, R-K11).
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
  directories — never the user's real `~/.odca` or the repo keeper file —
  and use `CandidateSearch(workers: 0)` so no search threads start.
- Tests run headless; no window is created (only the `ODCA` executable
  target touches AppKit/SwiftUI).
