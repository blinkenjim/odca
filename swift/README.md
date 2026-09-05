# ODCA — Swift/SwiftUI implementation

See the repository root `README.md` for what ODCA is and how to use it,
`../REQTS.md` for the specification, and `../REQ-swift.md` for
implementation notes. macOS 14+ with the Xcode toolchain.

All commands below run from this `swift/` directory.

## Run

```sh
swift run odca
```

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
