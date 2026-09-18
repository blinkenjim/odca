# ODCA — PlatformIO scaffold

Three boards now, sharing this directory. The RP2350 board (Waveshare
RP2350-LCD-1.47-A) has the real, running firmware: the engine
(`../REQTS.md` section 1, R-M), the boring detector (section 3, R-A),
and the display all running together, the live automaton drawn
continuously by redrawing the whole visible window from a small
history buffer every generation rather than the panel's hardware
scroll (see `src/main.cpp`'s own comment for why — correctness before
speed). Confirmed genuinely running on the board via serial and, for
the display, the user's own eyes.

The ESP32-C6 board (Waveshare ESP32-C6-LCD-1.47) runs the same firmware
(`src/main_esp32c6.cpp`) on the same 172×320 ST7789 panel, and got as
far as engine, detector, display and the BOOT-button speed cycle all
working — but it is **parked, unresolved**: its display permanently
freezes after a while, while serial keeps running and generations keep
counting. That is an SPI transfer corrupting and desyncing the panel's
command/data framing, and it is clock-rate-dependent, so the cause
looks like signal integrity on GPIO-matrix-routed pins. 40MHz died
within a few hundred generations, 20MHz survived 90 seconds once then
died inside 172, and 10MHz (where it sits) ran 920+ generations clean
but is not proven safe, just best known. `src/main_esp32c6.cpp`'s own
comment has the full account and a lead worth trying if it is picked
back up. One other board-specific bug was found and fixed along the
way: this chip runs FreeRTOS under the Arduino core (the RP2350 doesn't)
and a `loop()` that never blocks starves its task watchdog — `yield()`
is not enough, since it never reaches the idle task; `delay()` is.

The CYD board (ESP32-2432S028, a classic ESP32-WROOM-32 with a 2.8"
320×240 ILI9341 panel — a different driver chip from the other two)
runs `src/main_cyd.cpp`, confirmed correct on the real panel on the
first try. Two things about it are worth knowing:

- Its display pins (14/12/13/15) are exactly classic ESP32's **HSPI
  native IOMUX pins**, almost certainly by design. The Arduino core's
  default `SPI` object is VSPI, whose own IOMUX pins are 18/19/23/5, so
  driving this display through the default object routes it the long
  way through the GPIO matrix — the same penalised path the ESP32-C6 is
  permanently stuck on, capped near 40MHz. Using HSPI instead gets the
  direct path and makes 80MHz available.
- This chip has far less usable DRAM than the other two (~100KB once
  the framework's overhead is out, of which the detector's fixed R-A1
  windows claim ~36KB). The history therefore packs four cells to the
  byte — states are 0-3, so two bits was always enough — which is what
  buys the panel's full 240-row height.

Redraw there went 101ms to 22ms (9 to 41 generations/second) across
four measured changes: HSPI at 80MHz, then skipping the driver's
per-pixel endian swap by keeping the palette pre-swapped in wire order,
then a 256-entry table expanding each packed history byte to four
pixels at once. Batching the per-row writes into bands made no
measurable difference, the same null result the RP2350 saw — worth
recording so it isn't retried a third time.

## Build

```sh
pio run                     # RP2350, the real firmware (src/main.cpp)
pio run -e display          # RP2350, the display link test
pio run -e esp32c6          # ESP32-C6, the real firmware
pio run -e esp32c6-hello    # ESP32-C6, the toolchain smoke test
pio run -e cyd              # CYD, the real firmware
pio run -e cyd-hello        # CYD, the toolchain smoke test
pio run -e cyd-display      # CYD, the display link test
```

Each environment names the one `src/main*.cpp` it builds and excludes
the rest, so adding a fourth board's file never needs the other
environments edited.

The RP2350 side, via the
[earlephilhower Arduino-Pico](https://arduino-pico.readthedocs.io/) core:
PlatformIO's own `raspberrypi` platform does not yet carry RP2350
support, so `platformio.ini` pins the community fork
(`maxgerhardt/platform-raspberrypi`) that arduino-pico's own docs
currently direct people to, targeting the generic `rpipico2` board
definition; no Waveshare-specific board entry exists yet, and none is
needed for this step. The first build downloads the RP2350 toolchain
and a full recursive clone of the arduino-pico framework repository
(pico-sdk and its own dependencies as submodules); expect this to take
a long time once, then be fast. It produces
`.pio/build/rpipico2/firmware.uf2`.

The ESP32-C6 side, via `framework-arduinoespressif32`: PlatformIO's own
`espressif32` platform's board definitions still declare only `espidf`
as a supported framework for every ESP32-C6 board entry (a metadata
gap, not a real limitation), so `platformio.ini` pins the
[pioarduino](https://github.com/pioarduino/platform-espressif32) fork
instead, the one its own docs point to for exactly this. This chip also
needs two explicit build flags (`ARDUINO_USB_MODE=1`,
`ARDUINO_USB_CDC_ON_BOOT=1`, see `platformio.ini`'s own comment) or
`Serial` silently goes nowhere a host can see it — it has only the
simpler USB-Serial-JTAG peripheral, not the full USB-OTG PHY some other
ESP32 variants have, and defaults to UART0's GPIO pins otherwise.

## Flash

RP2350 boards take a UF2 image by holding BOOTSEL while plugging in USB
(or double-tapping reset), which mounts the board as a USB drive;
copying `firmware.uf2` onto it flashes and reboots. ESP32-C6 boards
flash directly over their USB port via `esptool`, no button dance
needed. With PlatformIO and a board connected, `pio run -e <env> -t
upload` does this for you on either; `pio device monitor` reads back
each firmware's own serial output once it's running.

## What's here

| path | role |
|---|---|
| `src/main.cpp` | the real RP2350 firmware: engine, boring detector, and display running together at 320 cells (auto-initializing per R-A2 once 172 generations in a row have been boring), a BOOTSEL-driven speed cycle (1x/2x/4x/÷4/÷2), and a rate report over serial |
| `lib/odca_engine/` | the engine (R-M): rule parsing/emission, wrap and fixed stepping, and which states a rule can produce. Portable C, no dynamic allocation, no dependencies |
| `lib/odca_boring/` | the boring detector (R-A): extinction, Brent's cycle detection, and the two now-fixed windows (R-A1, 3.72.0/3.73.0) — this module has no notion of a display at all; `odca_lifetime` is the R-E2 "how long did this seed live" measurement odca-evolve uses, and `odca_detector` is the continuously-running version the firmware plays through. Same portability rules as the engine. PlatformIO auto-links both into the firmware; nothing else needs to know they're there |
| `host_test/` | proves both libraries on this machine, no board, no PlatformIO: `./host_test/run` regenerates `conformance/vectors.json` as C data, compiles each library with plain `cc`, and runs two binaries — `count_vectors`, `valid_rule_ids`, `invalid_rule_ids`, `evolution`, and `lifetimes` all pass against the golden data; the detector's window and precedence behavior, which has no golden vectors of its own on the desktop either, is checked the same way `python/tests` and `swift/Tests` do it, by hand-built cases |
| `src/main_display_test.cpp` | a separate RP2350 firmware, kept apart from `src/main.cpp`: cycles the ST7789 through solid colors, the four ODCA palette colors as vertical stripes, and single corner pixels, over Adafruit_GFX/Adafruit_ST7789. `pio run -e display -t upload` builds and flashes this instead of the real firmware. The six pin numbers and the rotation value at the top of the file started as a guess from two independent sources plus this board's default hardware SPI0 pins, and are confirmed correct: right colors, right orientation, against the real panel |
| `src/main_esp32c6.cpp` | the real ESP32-C6 firmware, ported from `src/main.cpp`: same engine/detector/display/speed-cycle behavior, board-specific pins, RNG (`esp_random()`), and BOOT-button read (a plain GPIO, unlike the RP2350's special BOOTSEL object), plus a `yield()` each loop() and `delay()` instead of a busy-spin at the slow speeds — this chip's FreeRTOS task watchdog needs the yield, something the RP2350 side never had to consider |
| `src/main_esp32c6_hello.cpp` | the ESP32-C6 side's own toolchain smoke test, the same first step the RP2350 side took: a serial heartbeat, nothing more. `pio run -e esp32c6-hello -t upload` builds and flashes this |
| `src/main_cyd.cpp` | the real CYD firmware: same engine/detector/display/speed-cycle behavior as the other two, on an ILI9341 panel over HSPI, with the history packed four cells to the byte and the palette held pre-swapped in wire order (see its own comments — both are memory and speed decisions specific to this board) |
| `src/main_cyd_display_test.cpp` | the CYD's display link test, the same role `main_display_test.cpp` plays for the RP2350: solid colors, palette stripes, corner pixels. This one had more to prove than the others — the driver chip itself was unconfirmed (most CYD units are ILI9341, some later batches ST7789), as were backlight polarity and whether RST is wired at all |
| `src/main_cyd_hello.cpp` | the CYD's toolchain smoke test, a serial heartbeat. Note this board has a real CH340 USB-UART bridge rather than the other two boards' native USB, so reading its serial needs the baud rate set explicitly — plain `cat` on the device gets garbage |

The automaton's width is 320, not the panel's native 172: the display
runs rotated, its long axis as the automaton's width, since a wider
row makes for richer, longer-lived rules than 172 does (the user's own
call, having watched both). Neither toolchain check blinks an LED: the
RP2350 boards in play don't share LED wiring (a plain GPIO pin on one,
likely a WS2812 on the other), and the ESP32-C6 board's RGB LED
(GPIO8, per Waveshare's own wiki) has an unconfirmed protocol — a
visual smoke test needs a board-specific follow-up rather than a guess,
in both cases.

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
