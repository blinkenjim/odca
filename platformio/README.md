# ODCA — PlatformIO scaffold (early)

The engine (`../REQTS.md` section 1, R-M) is ported; the boring
detector and the display are not yet.

Target: an RP2350-based board (the user's is a Waveshare
RP2350-LCD-1.47-A, chip package RP2350A, 172×320 ST7789V3 display),
via the [earlephilhower Arduino-Pico](https://arduino-pico.readthedocs.io/)
core. PlatformIO's own `raspberrypi` platform does not yet carry RP2350
support, so `platformio.ini` pins the community fork
(`maxgerhardt/platform-raspberrypi`) that arduino-pico's own docs
currently direct people to, targeting the generic `rpipico2` board
definition; no Waveshare-specific board entry exists yet, and none is
needed for this step.

## Build

```sh
pio run
```

The first build downloads the RP2350 toolchain and a full recursive
clone of the arduino-pico framework repository (pico-sdk and its own
dependencies as submodules); expect this to take a long time once,
then be fast. It produces `.pio/build/rpipico2/firmware.uf2`.

## Flash

Not yet run from here: no board has been connected to the machine this
was built on. RP2350 boards take a UF2 image by holding BOOTSEL while
plugging in USB (or double-tapping reset), which mounts the board as a
USB drive; copying `firmware.uf2` onto it flashes and reboots. With
PlatformIO and the board connected, `pio run -t upload` does this for
you; `pio device monitor` reads back the serial heartbeat `src/main.cpp`
prints once it's running.

## What's here

| path | role |
|---|---|
| `src/main.cpp` | firmware: a serial heartbeat, then steps one of `conformance/vectors.json`'s own golden cases and prints each row, so the numbers on the wire can be checked by eye against the file |
| `lib/odca_engine/` | the engine (R-M): rule parsing/emission, wrap and fixed stepping. Portable C, no dynamic allocation, no dependencies. PlatformIO auto-links it into the firmware; nothing else needs to know it's there |
| `host_test/` | proves `lib/odca_engine` against the golden vectors on this machine, no board, no PlatformIO: `./host_test/run` regenerates `conformance/vectors.json` as C data, compiles the engine with plain `cc`, and runs it — `count_vectors`, `valid_rule_ids`, `invalid_rule_ids`, and `evolution` all pass. `lifetimes` (R-E2) waits for the boring detector. |

It deliberately does not blink an LED for the toolchain check: the two
RP2350 boards in play don't share LED wiring (a plain GPIO pin on one,
likely a WS2812 on the other), so a visual smoke test needs a
board-specific follow-up rather than a guess.

## A machine note, not an ODCA one

`cc` on this Mac wouldn't link anything at all while building this
(`ld: tapi error: malformed file`, "unknown architecture
arm64e.x1-macos"). The cause is Xcode/OS version skew, not corruption:
the OS and its Command Line Tools package are macOS 27.0, but Xcode.app
itself is still 26.6 (`xcodebuild -version`), and 26.6's linker doesn't
recognize `arm64e.x1`, a target tag 27.0's SDK declares that didn't
exist when 26.6 shipped. The default `MacOSX.sdk` symlink under
`/Library/Developer/CommandLineTools/SDKs/` points at that 27.0 SDK; an
older 26.5 one sits right next to it and works fine. `host_test/run`
passes an explicit `-isysroot $(xcrun --sdk macosx --show-sdk-path)`
to use it, harmless on a healthy machine. The real fix, when wanted, is
updating Xcode; this just routes around it. It never touched the
firmware build, which uses PlatformIO's own bundled cross-compiler, not
the system one.
