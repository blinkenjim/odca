// ODCA on an MCU: the engine (R-M), boring detector (R-A), and display,
// on the ESP32-C6 board — the same firmware src/main.cpp runs on the
// RP2350 board, ported rather than shared, since only a handful of
// lines are genuinely board-specific (pins, the RNG call, the boot
// button read) and the two boards' main files already followed that
// separate-file precedent (this one alongside main_display_test.cpp).
// See main.cpp's own comments for the reasoning behind the full-redraw
// display approach, the R-A2 auto-init terms, and R-U2's width choice;
// none of that changes here.
#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <Arduino.h>
#include <SPI.h>
#include <esp_random.h>
#include <cstring>
#include "odca_boring.h"
#include "odca_engine.h"

static const int WIDTH = 320;
static const int HEIGHT = 172;  // R-A2's screenful, and the display's visible window

// Display wiring (Waveshare's own wiki: LCD_DC, LCD_CS, LCD_RST, LCD_BL,
// SCLK, MOSI). Confirmed from the manufacturer's own pin table, but not
// yet against the real panel — pending the user's own eyes, the same
// way the RP2350 pins started out.
static const int PIN_DC = 15;
static const int PIN_CS = 14;
static const int PIN_RST = 21;
static const int PIN_BL = 22;
static const int PIN_SCK = 7;
static const int PIN_MOSI = 6;
static const int PANEL_NATIVE_WIDTH = 172;
static const int PANEL_NATIVE_HEIGHT = 320;
static const uint8_t ROTATION = 1;  // same panel and driver chip as the RP2350 board, so the same value is expected to give the same landscape orientation — unconfirmed until seen

// This board's BOOT button: GPIO9 on every ESP32-C6, since it's the
// chip's own strapping pin for serial-bootloader entry, not a
// board-specific wiring choice — confirmed against Espressif's own
// ESP32-C6-DevKitC-1 docs ("BOOT button is connected to IO9... after
// reset, can be used for software input"). Active low.
static const int PIN_BOOT = 9;

Adafruit_ST7789 tft(&SPI, PIN_CS, PIN_DC, PIN_RST);

// The desktop's own default palette (library.json, "ODCA default").
static uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b) {
  return (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
}
static const uint16_t PALETTE[4] = {
    rgb565(0x12, 0x12, 0x18), rgb565(0xEB, 0xEB, 0xE1),
    rgb565(0xFF, 0xA1, 0x36), rgb565(0x40, 0x9C, 0xFF),
};

// A rule already known to live a long time at this width, from the
// desktop's own odca-evolve search (see ../../interesting.odca).
static const char *RULE_ID = "33233022210132010013";

// Large fixed structures: static, never on the stack (see odca_boring.h).
static odca_rule rule;
static odca_detector detector;
static unsigned char cur[WIDTH];
static unsigned char next_row[WIDTH];

// History for the display: only ever the visible HEIGHT rows are kept,
// no deep scrollback like the desktop's 2048. A ring buffer of raw
// states; colors are computed per redraw, not stored.
static unsigned char history[HEIGHT][WIDTH];
static int history_count = 0;   // rows filled so far, caps at HEIGHT
static int history_next = 0;    // the ring's next write slot

// The whole frame's colors, built once per redraw then sent in a single
// writePixels() burst — the RP2350 side found this removed most of the
// per-redraw cost there (arduino-pico's writePixels toggled a register
// on every one-row call); untested here yet, but there's no reason to
// start from the slower shape known to be wrong on the other board.
static uint16_t frame_pixels[HEIGHT][WIDTH];

static unsigned long generation = 0;             // this seed's age; reset by every reinit
static unsigned long long total_generation = 0;   // never reset — the only thing the rate is measured from
static unsigned long long total_at_last_report = 0;
static unsigned long last_report_ms = 0;
static unsigned long reinit_count = 0;

// Boot-button-driven speed: see main.cpp's own comment on Speed/
// next_speed/steps_per_redraw — identical logic, board-agnostic.
enum Speed { SPEED_BASE, SPEED_X2, SPEED_X4, SPEED_DIV4, SPEED_DIV2 };
static Speed speed = SPEED_BASE;
static bool boot_was_pressed = false;

static const char *speed_name(Speed s) {
  switch (s) {
    case SPEED_BASE: return "1x";
    case SPEED_X2:   return "2x";
    case SPEED_X4:   return "4x";
    case SPEED_DIV4: return "1/4x";
    case SPEED_DIV2: return "1/2x";
  }
  return "?";
}

static Speed next_speed(Speed s) {
  switch (s) {
    case SPEED_BASE: return SPEED_X2;
    case SPEED_X2:   return SPEED_X4;
    case SPEED_X4:   return SPEED_DIV4;
    case SPEED_DIV4: return SPEED_DIV2;
    case SPEED_DIV2: return SPEED_BASE;
  }
  return SPEED_BASE;
}

static int steps_per_redraw(Speed s) {
  switch (s) {
    case SPEED_X2: return 2;
    case SPEED_X4: return 4;
    default:       return 1;
  }
}

// Unlike the RP2350's BOOTSEL (no normal GPIO, a special slow read),
// this board's BOOT button is a plain GPIO once past reset — a normal
// digitalRead() with the internal pull-up, active low. Same
// once-per-loop-iteration polling and press-then-wait-for-release
// debounce as the RP2350 side, though the reason for polling only once
// per iteration here is just to match that speed, not any per-read cost.
static void poll_boot_button() {
  bool pressed = digitalRead(PIN_BOOT) == LOW;
  if (pressed && !boot_was_pressed) {
    while (digitalRead(PIN_BOOT) == LOW) delay(1);
    speed = next_speed(speed);
    Serial.print("speed ");
    Serial.println(speed_name(speed));
  }
  boot_was_pressed = pressed;
}

static void seed_random_row(unsigned char *row, int width) {
  for (int i = 0; i < width; i += 16) {
    uint32_t bits = esp_random();  // hardware RNG (R-N1's "seedable" doesn't apply here: this is a live seed, not a mutation/session stream)
    int n = (width - i < 16) ? (width - i) : 16;
    for (int k = 0; k < n; k++) {
      row[i + k] = (unsigned char)(bits & 3);
      bits >>= 2;
    }
  }
}

// Redraw the whole visible window, oldest row at the top, newest at the
// bottom — the same sense the desktop scrolls in — from whatever the
// ring buffer currently holds; blank (state 0's color) below the newest
// row until the history first fills, matching R-U3's "filled rows from
// the top, background below" on the desktop.
static void redraw_history() {
  for (int y = 0; y < HEIGHT; y++) {
    if (y < history_count) {
      int slot = (history_next - history_count + y + HEIGHT) % HEIGHT;
      for (int x = 0; x < WIDTH; x++) frame_pixels[y][x] = PALETTE[history[slot][x]];
    } else {
      for (int x = 0; x < WIDTH; x++) frame_pixels[y][x] = PALETTE[0];
    }
  }
  tft.startWrite();
  tft.setAddrWindow(0, 0, WIDTH, HEIGHT);
  tft.writePixels(&frame_pixels[0][0], (uint32_t)WIDTH * HEIGHT);
  tft.endWrite();
}

static void push_history(const unsigned char *row) {
  memcpy(history[history_next], row, WIDTH);
  history_next = (history_next + 1) % HEIGHT;
  if (history_count < HEIGHT) history_count++;
}

static void reinitialize(const char *reason) {
  seed_random_row(cur, WIDTH);
  odca_detector_reset(&detector);  // R-A3: same rule, fresh field
  generation = 0;
  // No clear here: the fresh field grows in from below like any other
  // generation, and the old rows keep their colors and scroll off the
  // top as usual — the desktop's own re-seed-in-place (help.py: "grows
  // in from a fresh field below the old rows, which keep their
  // colors"). The caller's own redraw (loop()'s, after the batch; or
  // setup()'s, once, for the very first field) is what actually paints
  // this row; a blank-then-refill is only right once, at startup.
  push_history(cur);
  reinit_count++;
  if (reason) {
    Serial.print("reinit #");
    Serial.print(reinit_count);
    Serial.print(" (");
    Serial.print(reason);
    Serial.println(")");
  }
}

void setup() {
  Serial.begin(115200);
  uint32_t start = millis();
  while (!Serial && millis() - start < 3000) {
    delay(10);
  }
  Serial.println("odca platformio: ESP32-C6 engine + boring detector + display running");

  pinMode(PIN_BOOT, INPUT_PULLUP);
  pinMode(PIN_BL, OUTPUT);
  digitalWrite(PIN_BL, HIGH);

  // This board's SCK/MOSI aren't the generic esp32-c6-devkitc-1 target's
  // default SPI pins (we're not using a Waveshare-specific board
  // definition), so they need spelling out explicitly before tft.init()
  // rather than relying on a default that doesn't match this wiring.
  SPI.begin(PIN_SCK, /* MISO */ -1, PIN_MOSI, PIN_CS);
  tft.init(PANEL_NATIVE_WIDTH, PANEL_NATIVE_HEIGHT);
  tft.setRotation(ROTATION);
  // UNRESOLVED (2026-09-19). This board's display permanently freezes
  // after a while — serial keeps running and generations keep counting,
  // but the panel never updates again. That is the signature of a
  // corrupted SPI transfer desyncing the ST7789's command/data framing:
  // a partial write leaves it expecting more pixel data, so the next
  // command bytes get read as pixels, and nothing here ever resyncs it.
  //
  // It is clock-rate-dependent, which points at signal integrity: these
  // pins are GPIO-matrix-routed rather than dedicated hardware SPI
  // pins, and that path has a real, lower reliable ceiling. 40MHz died
  // within a few hundred generations, reliably. 20MHz survived 90+
  // seconds once and then died in under 172 generations. 10MHz ran
  // 920+ generations clean in the longest test it got, so it is the
  // best-known value and what this is set to — but "best known" is not
  // "safe", and it was slow and shimmery besides.
  //
  // Parked here at the user's call rather than chased further. If it is
  // picked back up: the CYD board (main_cyd.cpp) later hit the same
  // class of problem and found its display pins were the *native IOMUX*
  // pins of a different SPI peripheral than the one being used, which
  // removed the GPIO-matrix penalty entirely. Worth checking whether
  // this board has an equivalent escape before assuming it doesn't.
  tft.setSPISpeed(10000000);
  tft.fillScreen(PALETTE[0]);

  if (!odca_rule_from_id(RULE_ID, &rule)) {
    Serial.println("engine: rule ID failed to parse (should not happen)");
    return;
  }
  odca_detector_set_rule(&detector, &rule);
  Serial.print("rule ");
  Serial.println(RULE_ID);
  reinitialize(NULL);  // the first field, no reinit line for it
  redraw_history();    // the one place a clear-then-fill is right: startup
  last_report_ms = millis();
}

void loop() {
  // Unlike the RP2350's bare-metal Arduino-Pico core, this chip runs
  // FreeRTOS underneath, with a task watchdog that only clears when the
  // IDLE task actually gets to run. yield() (taskYIELD()) only yields
  // to tasks of equal or higher priority, never to IDLE, so it didn't
  // fix this — the same stall recurred at nearly the same generation
  // count with it in place. delay(1) actually blocks this task, which
  // is what lets IDLE run and feed the watchdog; that's the documented
  // fix for this exact "Task watchdog got triggered (IDLE)" case on
  // arduino-esp32. A 1ms cost once per redraw-bound (~34ms) loop is
  // noise.
  delay(1);

  poll_boot_button();

  // At x2/x4, step several generations before the one redraw that shows
  // them — see main.cpp's own comment; identical reasoning, board-
  // agnostic. A reinit cuts the batch short rather than continuing to
  // step a suddenly-different seed.
  int n = steps_per_redraw(speed);
  for (int i = 0; i < n; i++) {
    odca_step_wrap(cur, WIDTH, &rule, next_row);
    memcpy(cur, next_row, sizeof cur);
    generation++;
    total_generation++;
    push_history(cur);

    if (odca_detector_observe(&detector, cur, WIDTH) && detector.boring_streak >= HEIGHT) {
      char reason[ODCA_END_MAX];
      strncpy(reason, detector.boring_reason, sizeof reason);
      Serial.print("generation ");
      Serial.print(generation);
      Serial.print("  ");
      reinitialize(reason);
      break;
    }
  }

  unsigned long redraw_start = millis();
  redraw_history();
  unsigned long redraw_ms = millis() - redraw_start;

  // /2 and /4: a plain delay(), not the RP2350 side's busy-spin. That
  // spin was a deliberate, measured trade for a display-shimmer fix on
  // the RP2350 (keeping CPU power draw level through the wait); here it
  // would be an unyielding loop on top of a FreeRTOS scheduler, the
  // exact shape of the watchdog problem above, and untested as a real
  // need on this board yet. delay() on this core is the correct,
  // yielding wait (vTaskDelay underneath).
  unsigned long wait_ms = (speed == SPEED_DIV2) ? redraw_ms
                         : (speed == SPEED_DIV4) ? redraw_ms * 3
                                                  : 0;
  if (wait_ms) {
    delay(wait_ms);
  }

  unsigned long now = millis();
  if (now - last_report_ms >= 2000) {
    // total_generation is monotonic (unlike generation, which a reinit
    // resets), so this never underflows however many reinits happened
    // since the last report.
    unsigned long long done = total_generation - total_at_last_report;
    unsigned long elapsed_ms = now - last_report_ms;
    Serial.print("generation ");
    Serial.print(generation);
    Serial.print("  (");
    Serial.print((unsigned long)(done * 1000ULL / elapsed_ms));
    Serial.print(" gen/s, ");
    Serial.print(speed_name(speed));
    Serial.print(", redraw ");
    Serial.print(redraw_ms);
    Serial.println("ms)");
    total_at_last_report = total_generation;
    last_report_ms = now;
  }
}
