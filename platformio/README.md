# ODCA — PlatformIO scaffold (early)

This is a toolchain scaffold, not yet a port of the engine or the
boring detector described in `../REQTS.md`. It exists to prove the
build-and-flash path works before any ODCA logic is written.

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

`src/main.cpp` prints a counting heartbeat over USB serial once a
second. It deliberately does not blink an LED: the two RP2350 boards in
play don't share LED wiring (a plain GPIO pin on one, likely a WS2812 on
the other), so a visual smoke test needs a board-specific follow-up
rather than a guess.
