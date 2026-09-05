# ODCA — Swift/SwiftUI implementation

See the repository root `README.md` for what ODCA is and how to use it,
`../REQTS.md` for the specification, and `../REQ-swift.md` for
implementation notes. macOS 14+ with the Xcode toolchain.

All commands below run from this `swift/` directory.

## Run

```sh
swift run -c release odca
```

Use the release build for viewing. A debug build (`swift run odca`) keeps
every bounds check and skips inlining in the per-frame pixel loop, and the
animation is visibly choppy even on a fast Mac; release is smooth. The
first release build takes about a minute, then it launches at once.

Workbench modes (see the root README): `--colorset-review`,
`--screensaver-review <file>`, `--consistency-check <file>`,
`--screensaver <file>`.

## Tests

```sh
swift test
```

This runs the property/session tests plus the conformance runner, which
checks the engine against the shared golden vectors in
`../conformance/vectors.json`.
