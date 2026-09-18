# ODCA — PlatformIO scaffold (early)

The engine (`../REQTS.md` section 1, R-M), the boring detector
(section 3, R-A), and now the display are running together: the live
automaton is drawn continuously, redrawing the whole visible window
from a small history buffer every generation rather than the panel's
hardware scroll (see `src/main.cpp`'s own comment for why — correctness
before speed). Confirmed genuinely running on the board via serial; the
picture itself is the user's to confirm, not something this session can
see.

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
| `src/main.cpp` | firmware: steps a known long-lived rule (from `../interesting.odca`) at 320 cells continuously, auto-initializing per R-A2 once 172 generations in a row have been boring (172 being the display's planned row count, rotated — see below), and prints a rate and every re-init over serial. No display yet. |
| `lib/odca_engine/` | the engine (R-M): rule parsing/emission, wrap and fixed stepping, and which states a rule can produce. Portable C, no dynamic allocation, no dependencies |
| `lib/odca_boring/` | the boring detector (R-A): extinction, Brent's cycle detection, and the two now-fixed windows (R-A1, 3.72.0/3.73.0) — this module has no notion of a display at all; `odca_lifetime` is the R-E2 "how long did this seed live" measurement odca-evolve uses, and `odca_detector` is the continuously-running version the firmware plays through. Same portability rules as the engine. PlatformIO auto-links both into the firmware; nothing else needs to know they're there |
| `host_test/` | proves both libraries on this machine, no board, no PlatformIO: `./host_test/run` regenerates `conformance/vectors.json` as C data, compiles each library with plain `cc`, and runs two binaries — `count_vectors`, `valid_rule_ids`, `invalid_rule_ids`, `evolution`, and `lifetimes` all pass against the golden data; the detector's window and precedence behavior, which has no golden vectors of its own on the desktop either, is checked the same way `python/tests` and `swift/Tests` do it, by hand-built cases |
| `src/main_display_test.cpp` | a separate firmware, kept apart from `src/main.cpp`: cycles the ST7789 through solid colors, the four ODCA palette colors as vertical stripes, and single corner pixels, over Adafruit_GFX/Adafruit_ST7789. `pio run -e display -t upload` builds and flashes this instead of the real firmware; a bare `pio run`/`pio run -t upload` (no `-e`) still targets the real one. The six pin numbers and the rotation value at the top of the file started as a guess from two independent sources plus this board's default hardware SPI0 pins, and are confirmed correct: right colors, right orientation, against the real panel |

The automaton's width is 320, not the panel's native 172: the display
will run rotated, its long axis as the automaton's width, since a wider
row makes for richer, longer-lived rules than 172 does (the user's own
call, having watched both). `src/main.cpp` does not blink an LED for the
toolchain check either: the two RP2350 boards in play don't share LED
wiring (a plain GPIO pin on one, likely a WS2812 on the other), so a
visual smoke test needs a board-specific follow-up rather than a guess.

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
