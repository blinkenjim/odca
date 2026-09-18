# The ESP32-C6 board, and why it was dropped

A Waveshare ESP32-C6-LCD-1.47 was a supported target here for one day,
2026-09-18 to 2026-09-19, and was then abandoned: its display corrupted
and froze permanently, repeatedly, and nothing tried cured it. The user's
verdict was "it's not worth carrying around support for a board that
barely works."

This file is the full account, kept because several things learned on
this board were expensive to find, are load-bearing elsewhere in
`platformio/`, and would otherwise have to be rediscovered. It also
records what was *not* tried, for anyone who picks the board up again.

## The board

Waveshare ESP32-C6-LCD-1.47. ESP32-C6FH8, single RISC-V core at 160MHz,
8MB flash, 512KB HP SRAM, no PSRAM. Display is a 1.47" 172×320 ST7789
over SPI — the same panel and driver chip as the RP2350 board, which is
why it looked like an easy second port.

Pin mapping, from Waveshare's own wiki and confirmed correct against the
real panel on the first try:

| signal | GPIO |
|---|---|
| MOSI | 6 |
| SCLK | 7 |
| LCD_CS | 14 |
| LCD_DC | 15 |
| LCD_RST | 21 |
| LCD_BL | 22 |
| BOOT button | 9 |
| RGB LED | 8 |

No MISO is wired to the panel, so the display cannot be read back, and no
TE (tearing-effect) pin is exposed. Both matter below.

## Two toolchain obstacles, both solved

**PlatformIO's official platform would not build Arduino for this chip.**
Every ESP32-C6 board definition in `espressif32` 7.1.3 declares only
`espidf` in its `frameworks` list — checked directly, and it is true of
`esp32-c6-devkitc-1`, `esp32-c6-devkitm-1`, `seeed_xiao_esp32c6` and both
`cezerio` entries. So `framework = arduino` fails outright with "This
board doesn't support arduino framework!" This is a metadata gap rather
than a real limitation, since arduino-esp32 itself supports the chip.
The fix was to pin the [pioarduino](https://github.com/pioarduino/platform-espressif32)
community fork, which declares both frameworks. Same shape of problem as
the RP2350 side has with the official `raspberrypi` platform, and the
same shape of fix.

**Serial produced nothing at all, then would not compile.** After a
successful flash, the port was silent. This chip has no separate
USB-UART bridge, only the internal USB-Serial-JTAG peripheral, and
without `ARDUINO_USB_CDC_ON_BOOT` the Arduino core points `Serial` at
UART0's GPIO pins rather than the USB port actually connected — so
everything printed went somewhere no host could see. Adding that flag
alone then broke the build: `HardwareSerial.h` selects
`Serial = USBSerial` when `ARDUINO_USB_MODE` is 0, and `USBSerial` is
undeclared on this chip, which has no USB-OTG PHY (only the simpler
USB-Serial-JTAG controller, as on the C3 and H2). Both flags are needed
together:

```ini
build_flags =
    -D ARDUINO_USB_MODE=1        ; select the HWCDC path: Serial = HWCDCSerial
    -D ARDUINO_USB_CDC_ON_BOOT=1 ; point Serial at USB, not UART0
```

## What worked

The engine (R-M) and boring detector (R-A) needed no changes at all —
they are portable C with no board dependencies, and linked unmodified.
Pins and rotation were right first time. The BOOT button worked as a
plain GPIO with `INPUT_PULLUP`, active low (GPIO9 is the chip's own
strapping pin for bootloader entry, not a board-specific choice), and
drove the speed cycle exactly as on the other boards. Extinction
detection and auto-reinitialization behaved correctly throughout.

## Bug one: the FreeRTOS task watchdog

**Symptom.** A garbled serial line followed by a stall of roughly two
seconds, after which it recovered by itself and ran on normally. It
recurred at nearly the same generation count — around 230 — on every
run, which is what made it look deterministic rather than random.

**First fix, which did not work.** Adding `yield()` once per `loop()`.
The same stall recurred at nearly the same point.

**Why it did not work, and the real fix.** `yield()` compiles to
`taskYIELD()`, which only yields to tasks of equal or higher priority.
It never reaches the IDLE task, and the IDLE task is precisely what
feeds the task watchdog. `delay(1)` actually blocks the calling task, so
idle gets to run and the watchdog clears. With `delay(1)` in place: 60
seconds clean, 1,700+ generations, two correct reinits, no garbling.

**Worth keeping.** This applies to any Arduino sketch on these chips, not
just this board. A `loop()` that never blocks will eventually trip the
watchdog, and `yield()` is not a substitute for `delay()` here.

## Bug two: display corruption, which killed the board

**Symptom.** The panel stops updating, permanently. Serial keeps
printing and the generation counter keeps advancing at a normal rate, so
the CPU is fine — it is the display's own state that is wrecked.

**Mechanism.** A corrupted or short SPI transfer desyncs the ST7789's
command/data framing. The controller is left expecting more pixel data,
so the next command bytes it receives are consumed as pixels instead,
and every subsequent write compounds the error. Nothing in the firmware
ever resyncs it, so it never recovers.

**Clock dependence, measured.** This is what pointed at signal integrity
rather than software:

| SPI clock | redraw | rate | survival |
|---|---|---|---|
| 10MHz | ~101ms | 9 gen/s | 920+ generations clean in the longest run; failed later |
| 20MHz | ~56ms | 17 gen/s | 90s and 1,500+ generations once, then died inside 172 on the next run |
| 40MHz | ~35ms | 28 gen/s | died within a few hundred generations, reliably |

Redraw time scaled almost exactly linearly with the clock, confirming
the transfer was genuinely clock-bound. Survival time fell as the clock
rose, which is the signature of marginal signalling rather than a logic
error. The suspected cause is that these pins are routed through the
GPIO matrix rather than being a SPI peripheral's native IOMUX pins, and
that path has a real, lower reliable ceiling on ESP32 parts.

## The rewrites, and their results

**Insight that came out of it.** Exposure to whatever corrupts the bus
scales with the number of bytes moved, not with the clock rate. A full
repaint of the window pushed 110,080 bytes per generation. Writing only
the new row pushes a few hundred. That reframing is why both rewrites
below went after volume instead of hunting for a faster safe clock, and
it is why the CYD board writes single rows today.

**Attempt one: a sweeping write line.** Write each generation to a line
that cycles down the screen and wraps, with no scroll register involved.
Keeps the automaton at 320 cells. Result: 50 generations/second at the
unchanged 10MHz, up from 9, and a 151-second soak of roughly 7,500
generations with no stall or corruption, while the user was actively
cycling speeds. **Rejected on sight** — with no scrolling, a write line
marches down the screen leaving the previous pass's rows visible below it
until it catches them, and that is not the piece. The user's standing
position, worth recording: scrolling identically on every platform
matters more than the cell count.

**Attempt two: portrait, with hardware vertical scroll, at 172 cells.**
Write the new rows, move the scroll start, let the panel do the
shifting. This required portrait orientation, because hardware scroll
only moves along the panel's native long axis and that axis has to be
the direction the picture scrolls — which on a 172×320 panel forces the
automaton down to 172 cells, the width the user had rejected at the
outset when choosing 320. They took it knowingly on the consistency
argument above. Dropping the history and full-frame buffers took memory
from 163KB to 53KB. Result: 50 generations/second, a 705µs write window,
and a 180-second soak of roughly 9,000 generations with seven correct
reinits and no fault.

**And then it locked up anyway.** Which ended it. Writing 200x less data
moved the failure from "a couple of hundred generations" out to
"thousands", but did not remove it, and the user had run out of patience
for a board that needed this much work to still not be reliable.

## What was never tried

If this board is ever picked back up, this is the unexplored ground.

- **Whether its display pins can reach a native IOMUX SPI peripheral.**
  This is the most promising lead by far and was never checked. The CYD
  board hit the same class of corruption, and the escape there was
  discovering that its display pins (14/12/13/15) are exactly classic
  ESP32's HSPI native IOMUX pins, while the Arduino core's default `SPI`
  object is VSPI — so the default object was routing them through the
  GPIO matrix and capping the clock, and simply using the right
  peripheral removed the penalty and made 80MHz reliable. Nobody
  established what SPI2's IOMUX pin assignments are on the C6, or
  whether this board's SCK=7/MOSI=6 match them. If they do, the whole
  fault may be an avoidable routing choice.
- **A periodic display re-initialization as a self-heal.** Offered twice
  and never taken up. Since a desync never recovers on its own,
  re-issuing the init sequence on a timer would convert a permanent
  freeze into a brief glitch. Once the firmware writes only a few
  hundred bytes per generation, the spare time budget for this is
  enormous.
- **Detecting the desync rather than just surviving it.** Not possible
  on this board as wired: no MISO to the panel, so the controller's
  status and scanline registers cannot be read back. The CYD does have
  MISO wired, so the same idea is available there.
- **Syncing writes to the panel's refresh.** No TE pin is exposed, so
  there is no hardware signal to sync against.
