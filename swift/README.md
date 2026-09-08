# ODCA — Swift/SwiftUI implementation

See the repository root `README.md` for what ODCA is and how to use it,
`../REQTS.md` for the specification, and `../REQ-swift.md` for
implementation notes. macOS 14+ with the Xcode toolchain.

All commands below run from this `swift/` directory. The shortcut is
`./run odca <file.odca>` (or `run odca-select`, `run test`), which builds
release on first use and then runs the binary; it can be called from
anywhere, as `swift/run` from the repository root.

## Run

```sh
swift run -c release odca ../interesting.odca          # play a file of looks (--shuffle, --fullscreen, --3 / --2 / --1 optional)
swift run -c release odca-select ../my-looks.odca      # compose looks into a file (--3 / --2 / --1 optional)
```

Use the release build for viewing. A debug build (`swift run odca`) keeps
every bounds check and skips inlining in the per-frame pixel loop, and the
animation is visibly choppy even on a fast Mac; release is smooth. The
first release build takes about a minute, then it launches at once.

`--help` on either program prints its flags and keys.

## Tests

```sh
swift test
```

This runs the property/session tests plus the conformance runner, which
checks the engine against the shared golden vectors in
`../conformance/vectors.json`.
