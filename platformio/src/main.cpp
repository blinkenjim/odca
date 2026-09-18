// ODCA on an MCU: the engine (R-M), the boring detector (R-A), and now
// the display — the first version, correctness before speed: the whole
// visible window is redrawn from a small history buffer every
// generation, rather than the panel's hardware vertical scroll. Scroll
// interacts with rotation (MADCTL) in ways that can't be verified
// without seeing the screen, and a full redraw is still a perfectly
// watchable pace (SPI bandwidth alone caps it somewhere in the tens of
// generations per second, plenty for the eye); scrolling is a layer to
// add once this is confirmed correct, the same order used throughout —
// proven simple first, then optimized.
//
// Auto-initializes on the same terms the desktop programs do (R-A2):
// once a screenful of generations in a row has been boring, start over.
// "A screenful" is 172 rows, this board's native short axis; the
// automaton's width is the panel's long axis, 320, rotated (R-U2 — the
// user's own call: more cells make for richer, longer-lived rules than
// the panel's native 172).
#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <Arduino.h>
#include <SPI.h>
#include <cstring>
#include "odca_boring.h"
#include "odca_engine.h"

static const int WIDTH = 320;
static const int HEIGHT = 172;  // R-A2's screenful, and the display's visible window

// Display wiring: see src/main_display_test.cpp for how these six pins
// and the rotation were arrived at and confirmed against the real panel.
static const int PIN_DC = 16;
static const int PIN_CS = 17;
static const int PIN_RST = 20;
static const int PIN_BL = 21;
static const int PANEL_NATIVE_WIDTH = 172;
static const int PANEL_NATIVE_HEIGHT = 320;
static const uint8_t ROTATION = 1;

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

// History for the display (R-U3-ish, but MCU-local: only ever the
// visible HEIGHT rows are kept, no deep scrollback like the desktop's
// 2048). A ring buffer of raw states; colors are computed per redraw,
// not stored, so this costs HEIGHT*WIDTH bytes, not double that.
static unsigned char history[HEIGHT][WIDTH];
static int history_count = 0;   // rows filled so far, caps at HEIGHT
static int history_next = 0;    // the ring's next write slot

// The whole frame's colors, built once per redraw then sent in a single
// writePixels() burst (see redraw_history()): 172 separate one-row calls
// each carried a fixed per-call cost (arduino-pico's writePixels toggles
// the SPI peripheral's word-size register on every call), which turned
// out to be roughly half of the total redraw time even at a fast SPI
// clock — one call instead of 172 removes nearly all of it.
static uint16_t frame_pixels[HEIGHT][WIDTH];

static unsigned long generation = 0;             // this seed's age; reset by every reinit
static unsigned long long total_generation = 0;   // never reset — the only thing the rate is measured from
static unsigned long long total_at_last_report = 0;
static unsigned long last_report_ms = 0;
static unsigned long reinit_count = 0;

// BOOTSEL-driven speed: the display redraw is what actually paces the
// loop (SPI bandwidth is the ceiling), so "faster" means stepping more
// generations between redraws, and "slower" means an explicit extra
// delay after a normal one, sized off of that redraw's own measured
// cost rather than a guessed constant.
enum Speed { SPEED_BASE, SPEED_X2, SPEED_X4, SPEED_DIV4, SPEED_DIV2 };
static Speed speed = SPEED_BASE;
static bool bootsel_was_pressed = false;

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

// BOOTSEL isn't a normal GPIO (it shares a pin with flash CS, read via a
// special, relatively slow core routine — arduino-pico's Bootsel.h), so
// this is polled once per loop() iteration, not per generation, and
// debounced by waiting out the release the same way the core's own
// example does.
static void poll_bootsel() {
  bool pressed = BOOTSEL;
  if (pressed && !bootsel_was_pressed) {
    while (BOOTSEL) delay(1);
    speed = next_speed(speed);
    Serial.print("speed ");
    Serial.println(speed_name(speed));
  }
  bootsel_was_pressed = pressed;
}

static void seed_random_row(unsigned char *row, int width) {
  for (int i = 0; i < width; i += 16) {
    uint32_t bits = rp2040.hwrand32();  // hardware RNG (R-N1's "seedable" doesn't apply here: this is a live seed, not a mutation/session stream)
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
  Serial.println("odca platformio: engine + boring detector + display running");

  pinMode(PIN_BL, OUTPUT);
  digitalWrite(PIN_BL, HIGH);
  tft.init(PANEL_NATIVE_WIDTH, PANEL_NATIVE_HEIGHT);
  tft.setRotation(ROTATION);
  // This panel exposes no TE (tearing-effect) pin, so a write can't be
  // synced to the controller's own internal refresh; at 40MHz a full
  // 172-row redraw measured ~28ms (see the serial rate report's "redraw
  // Xms"), long enough for the panel's own refresh to scan through it
  // more than once mid-write, each pass catching a different amount
  // finished — a moving seam rather than one steady tear line, which
  // fit the user's report of shimmering all up and down the display
  // better than classic tearing. Measured clean, close to linear
  // scaling from 20 to 80MHz (53ms, 28ms, ~15ms) with no sign of a
  // fixed floor in that range, and 80MHz is where the user confirmed
  // the shimmering gone ("that's perfect").
  tft.setSPISpeed(80000000);
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
  poll_bootsel();

  // At x2/x4, step several generations before the one redraw that shows
  // them — the redraw is the SPI-bound cost, so this is the only way to
  // go faster than the base pace, at the cost of several new rows
  // appearing at once instead of one at a time (the same "more than one
  // generation per refresh" the desktop's own fast speeds do, R-U5). A
  // reinit is a discrete event in its own right, so it cuts the batch
  // short rather than continuing to step a suddenly-different seed.
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

  // /2 and /4: redraw_ms is this run's own measured cost of one base
  // (single-generation) cycle, so scaling the extra wait off of it stays
  // correct however that cost drifts, rather than trusting a guessed
  // constant.
  //
  // 2026-09-18: /2 and /4 showed shimmering that base/2x/4x didn't. The
  // redraw path is identical in every mode, and this wait runs only
  // after a write has already finished, so the panel-refresh race isn't
  // an obvious fit. What IS different: only /2 and /4 let the CPU go
  // idle for a long stretch between SPI bursts, dropping the loop's
  // repetition rate into a range (roughly 33Hz, 16Hz) a human eye can
  // perceive as distinct pulses rather than a blur. Busy-spinning
  // instead of delay() keeps CPU power draw level through the wait
  // instead of dropping during it — measurably better (user: "a bit of
  // shimmer, but it seems better... good enough for now"), not fully
  // gone. Left as a real, open lead for later, not a solved problem.
  unsigned long wait_ms = (speed == SPEED_DIV2) ? redraw_ms
                         : (speed == SPEED_DIV4) ? redraw_ms * 3
                                                  : 0;
  if (wait_ms) {
    unsigned long wait_until = millis() + wait_ms;
    while (millis() < wait_until) {}
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
