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

// Fast button sampling, for a multi-press gesture vocabulary that does
// not exist yet. OFF, and worth understanding before switching on.
//
// Turning it on bands the redraw and samples the button between bands
// and part way through the frame fill, bringing the sampling interval
// from ~16ms down to ~5ms. It also brings back the diagonal tearing
// this board took a long time to be rid of, and the reason is instructive:
// the shimmer fix here was never structural. It worked because the
// ~16ms write happened to land near the panel's own refresh period, so
// the two ran roughly rate-matched. Sampling mid-write breaks that two
// ways — it lengthens the write, and worse, each ~40us pause gives the
// panel's scan a fixed point to catch a step at. Four pauses, four
// seams. Lowering the sample rate to 4ms helped and did not cure it.
//
// The measured numbers say the fast path was never needed. A real tap on
// this button runs 88-158ms, so sampling once per loop at ~16ms still
// catches a press five to ten times over — ample for press and release
// edges, and so for counting clicks. The 8ms figure this was built
// around came from assuming 30-40ms taps, which this button does not
// see. So with this off, the gesture work is not blocked; it simply gets
// 16ms sampling instead of 5ms, which is enough.
//
// The one board where fast sampling would be free is the CYD: its write
// window is 210us because the panel does the scrolling, so there is no
// long transfer to interrupt in the first place.
// Why a sample is expensive enough to ration at all: BOOTSEL is not a
// normal GPIO. It sits on the flash chip-select line, so arduino-pico's
// read floats flash CS, stalls the other core, disables interrupts and
// busy-waits ~33us for the line to settle — about 35-40us a read, some
// 2000x a normal pin read.
#define ODCA_FAST_BUTTON_SAMPLING 0

static const unsigned long DEBOUNCE_MS = 20;

static bool button_raw = false;         // last raw sample
static unsigned long button_raw_ms = 0; // when the raw state last changed
static bool button_down = false;        // debounced state
static unsigned long press_began_ms = 0;  // when the press in flight began

// Edges, set here and consumed by gesture_tick(). Kept as flags rather
// than acted on directly because this runs inside the display's SPI
// transaction when fast sampling is on, and talking to serial or
// changing state belongs in loop().
static bool edge_pressed = false;
static bool edge_released = false;

// Sampling interval actually achieved, so the 2ms claim can be checked
// rather than assumed. Reset at every report.
static unsigned long last_sample_us = 0;
static unsigned long worst_gap_us = 0;

// The read is gated by time so its cost stays bounded however many
// places call it. Only relevant when fast sampling is on; with it off,
// the once-per-loop call is already slower than this floor.
static const unsigned long SAMPLE_INTERVAL_US = 4000;

static void button_tick() {
  unsigned long now_us = micros();
  if (last_sample_us != 0 && (now_us - last_sample_us) < SAMPLE_INTERVAL_US) {
    return;  // too soon to be worth 40us
  }
  if (last_sample_us != 0) {
    unsigned long gap = now_us - last_sample_us;
    if (gap > worst_gap_us) worst_gap_us = gap;
  }
  last_sample_us = now_us;

  bool raw = BOOTSEL;
  unsigned long now = millis();
  if (raw != button_raw) {
    button_raw = raw;
    button_raw_ms = now;
  }
  // A mechanical button bounces for a few milliseconds. The old code
  // swallowed that by waiting out the release before acting; sampling
  // at 2ms would instead see one press as two or three, so the state
  // only counts once it has held still for DEBOUNCE_MS.
  if (raw != button_down && (now - button_raw_ms) >= DEBOUNCE_MS) {
    button_down = raw;
    if (button_down) {
      press_began_ms = now;
      edge_pressed = true;
    } else {
      edge_released = true;
    }
  }
}

// Gestures: one, two or three presses, each either ending in a normal
// tap or in a press held two seconds. Six in all, from one button.
//
// The window is the gap BETWEEN presses, not a budget for the whole
// gesture. Three presses inside one 250ms total would be brutal to
// perform and worse to sample; three presses each within 250ms of the
// last is comfortable, and it is how double-click detection is normally
// done. Measured on this board, a tap runs 88-158ms, so the 250ms gap
// has real headroom either side.
//
// The cost, accepted deliberately: a single press can no longer act
// immediately, because until the window lapses it might yet be the first
// of two. Speed cycling is therefore ~250ms slower to respond than it
// was.
static const unsigned long MULTI_GAP_MS = 250;
static const unsigned long LONG_HOLD_MS = 2000;

static int burst_presses = 0;               // presses counted so far in the gesture under way
static unsigned long burst_released_ms = 0; // when the last of them ended
static bool burst_open = false;             // a gesture is being collected
static bool burst_spent = false;            // its long form already fired; ignore the release

// A running count of each gesture since boot, [presses][long], reported
// periodically. Gestures are done by hand at human pace and serial is
// only read in bursts, so a tally that survives between reads is the
// difference between a testable feature and one nobody can catch in the
// act. Index 0 is unused; a burst of more than three presses lands in
// the last slot and is reported as-is rather than silently dropped.
static unsigned long gesture_tally[5][2];

static void on_gesture(int presses, bool held) {
  Serial.print("gesture: ");
  Serial.print(presses);
  Serial.print(presses == 1 ? " press, " : " presses, ");
  Serial.println(held ? "long" : "short");

  // Only the plainest of the six is bound to anything so far: one short
  // press still cycles the speed, as it always has. The other five
  // report themselves and do nothing, until they are given jobs.
  if (presses == 1 && !held) {
    speed = next_speed(speed);
    Serial.print("speed ");
    Serial.println(speed_name(speed));
  }

  int slot = presses < 4 ? presses : 4;
  gesture_tally[slot][held ? 1 : 0]++;
}

static void gesture_tick() {
  unsigned long now = millis();

  if (edge_pressed) {
    edge_pressed = false;
    burst_presses++;
    burst_open = true;
    burst_spent = false;
  }

  // The long form is recognised while the button is still down, rather
  // than on release. That is deliberate: it makes the moment of
  // recognition available for feedback, which six gestures on one button
  // will want, and it means a long gesture never has to be told apart
  // from a short one after the fact.
  if (burst_open && button_down && !burst_spent &&
      (now - press_began_ms) >= LONG_HOLD_MS) {
    on_gesture(burst_presses, true);
    burst_spent = true;
  }

  if (edge_released) {
    edge_released = false;
    burst_released_ms = now;
    if (burst_spent) {  // its long form already fired; the release ends it
      burst_open = false;
      burst_presses = 0;
    }
  }

  // Nothing in flight and the window has lapsed: it was the short form.
  if (burst_open && !button_down && !burst_spent &&
      (now - burst_released_ms) >= MULTI_GAP_MS) {
    on_gesture(burst_presses, false);
    burst_open = false;
    burst_presses = 0;
  }
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
  // Building the frame is 55,000 palette lookups and takes longer than a
  // band of SPI does — measured, it was the single longest unsampled
  // stretch in the loop once the writes were banded, so it gets sampled
  // through on the same rhythm.
  for (int y = 0; y < HEIGHT; y++) {
    if (y < history_count) {
      int slot = (history_next - history_count + y + HEIGHT) % HEIGHT;
      for (int x = 0; x < WIDTH; x++) frame_pixels[y][x] = PALETTE[history[slot][x]];
    } else {
      for (int x = 0; x < WIDTH; x++) frame_pixels[y][x] = PALETTE[0];
    }
#if ODCA_FAST_BUTTON_SAMPLING
    if (y % 22 == 0) button_tick();
#endif
  }
  // Sent in bands rather than one burst, purely to create moments to
  // sample the button in. The redraw is ~15ms of blocking SPI and used
  // to be the whole loop, so sampling could only happen once per frame;
  // 22 rows is about 2ms of transfer, which brings sampling to roughly
  // that. It costs nothing measurable: per-row writes were tried on
  // this board early on and made no difference to redraw time either
  // way, so band size is free to choose on other grounds.
  //
  // Sampling between bands, inside the transaction, is safe — no
  // transfer is in flight at a band boundary, and the button read
  // touches the flash chip-select line, not this display's.
  tft.startWrite();
  tft.setAddrWindow(0, 0, WIDTH, HEIGHT);
#if ODCA_FAST_BUTTON_SAMPLING
  static const int BAND_ROWS = 22;  // ~2ms of transfer, so ~2ms sampling
  for (int top = 0; top < HEIGHT; top += BAND_ROWS) {
    int rows = (HEIGHT - top < BAND_ROWS) ? (HEIGHT - top) : BAND_ROWS;
    tft.writePixels(&frame_pixels[top][0], (uint32_t)WIDTH * rows);
    button_tick();
  }
#else
  // One uninterrupted burst. The pauses a banded write leaves are what
  // the panel's refresh catches as seams, so there are none.
  tft.writePixels(&frame_pixels[0][0], (uint32_t)WIDTH * HEIGHT);
#endif
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
  button_tick();

  gesture_tick();  // turns the sampled edges into one of six gestures

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
    while (millis() < wait_until) {
#if ODCA_FAST_BUTTON_SAMPLING
      button_tick();  // the other long stretch worth sampling through
#endif
    }
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
#if ODCA_FAST_BUTTON_SAMPLING
    Serial.print("ms, button gap <=");
    Serial.print(worst_gap_us);
    Serial.println("us)");
    worst_gap_us = 0;
#else
    Serial.println("ms)");
#endif
    unsigned long any = 0;
    for (int i = 1; i < 5; i++) any += gesture_tally[i][0] + gesture_tally[i][1];
    if (any) {
      Serial.print("gestures so far:");
      for (int i = 1; i <= 3; i++) {
        Serial.print(' ');
        Serial.print(i);
        Serial.print("s=");
        Serial.print(gesture_tally[i][0]);
        Serial.print(' ');
        Serial.print(i);
        Serial.print("L=");
        Serial.print(gesture_tally[i][1]);
      }
      if (gesture_tally[4][0] || gesture_tally[4][1]) {
        Serial.print("  (4+ presses: ");
        Serial.print(gesture_tally[4][0] + gesture_tally[4][1]);
        Serial.print(')');
      }
      Serial.println();
    }

    total_at_last_report = total_generation;
    last_report_ms = now;
  }
}
