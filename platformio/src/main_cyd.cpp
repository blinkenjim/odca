// ODCA on an MCU: the engine (R-M), boring detector (R-A), and display,
// on the CYD (ESP32-2432S028) board. See main.cpp's own comments for
// the R-A2 auto-init terms and the general shape; the engine and
// detector are identical here, and only the display differs.
//
// This board's display works differently from the RP2350 board's, and
// deliberately so. That one redraws the whole visible window every
// generation, which on this panel took 22ms — long enough for the
// panel's own refresh to scan through a half-written frame, producing
// a drifting diagonal tear the user could see at every speed. The fix
// is not to write faster but to write less: the panel has a hardware
// vertical scroll, so writing the ONE new row and moving the scroll
// start by one line does the whole job. 480 bytes per generation
// instead of 154,000, a write window of microseconds rather than
// milliseconds, and the tear stops being possible rather than being
// reduced.
//
// The cost, and it was the user's call (2026-09-19): hardware scroll
// moves along the panel's native long axis, and that axis has to be
// the direction the picture scrolls. So this board runs PORTRAIT, and
// the automaton is 240 cells wide rather than the RP2350's 320 (R-U2).
// Portrait is the orientation the eventual installation is aimed at
// anyway.
#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h>
#include <Arduino.h>
#include <SPI.h>
#include <esp_random.h>
#include <cstring>
#include "odca_boring.h"
#include "odca_engine.h"

// Portrait, so the automaton's width is the panel's short axis and the
// history scrolls down its long axis — which is the axis hardware
// scroll acts on.
static const int WIDTH = 240;
static const int HEIGHT = 320;  // R-A2's screenful, and the scroll ring's depth

// SPI pin mapping (community documentation, bus shared with the XPT2046
// touch controller on a separate CS — untouched here, so it stays idle).
// Confirmed against the real panel in main_cyd_display_test.cpp.
//
// These four are exactly classic ESP32's HSPI (SPI2) IOMUX pins: CLK 14,
// MISO 12, MOSI 13, CS 15. That is almost certainly deliberate on the
// board designer's part, and it matters: driven through HSPI they get
// direct IOMUX routing, while the Arduino core's default global SPI
// object is VSPI (SPI3), whose own IOMUX pins are 18/19/23/5 — driving
// these pins from VSPI instead sends them the long way round, through
// the GPIO matrix, which caps the usable clock near 40MHz.
static const int PIN_MISO = 12;
static const int PIN_MOSI = 13;
static const int PIN_SCK = 14;
static const int PIN_CS = 15;
static const int PIN_DC = 2;
static const int PIN_BL = 21;
static const int PIN_RST = -1;  // no separate GPIO found for this; tied to EN, confirmed fine in the display test

// This board's BOOT button: GPIO0, the classic ESP32's own strapping
// pin for serial-bootloader entry. Active low.
static const int PIN_BOOT = 0;

// HSPI rather than the default global SPI (VSPI) — see the pin comment.
SPIClass hspi(HSPI);
Adafruit_ILI9341 tft(&hspi, PIN_DC, PIN_CS, PIN_RST);  // note the (spi, dc, cs, rst) order — different from Adafruit_ST7789's (spi, cs, dc, rst)

static uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b) {
  return (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
}

// The desktop's own default palette (library.json, "ODCA default"),
// stored BYTE-SWAPPED. The panel wants each RGB565 pixel big-endian on
// the wire; this CPU stores little-endian, so the driver would
// otherwise swap every pixel in software on the way out. Pre-swapping
// the four entries once lets writePixels() be told the data is already
// in wire order (bigEndian=true) and hand the bytes straight to SPI.
//
// These are therefore NOT valid for ordinary Adafruit_GFX calls like
// fillScreen() — see BACKGROUND below for that.
static uint16_t rgb565_swapped(uint8_t r, uint8_t g, uint8_t b) {
  uint16_t v = rgb565(r, g, b);
  return (uint16_t)((v >> 8) | (v << 8));
}
// Shimmer experiments on the 0/3 pair (2026-09-19).
//
// This rule reliably ends with states 1 and 2 extinct (every reinit
// line says so), leaving 0 and 3 alternating row by row — exactly the
// region the user sees strobing worst. Flicker visibility tracks
// luminance contrast, and the desktop palette puts these two far
// apart: #121218 sits around relative luminance 19, #409CFF around 140.
// Closing that gap all but stops the strobing, confirmed on the screen.
//
// First attempt lifted state 0 to #275080, about 45% of the way toward
// state 3. Strobing nearly vanished, but pulling the dark state that
// far up cost contrast against states 1 and 2 as well (the user's read).
//
// This is the opposite approach: state 0 goes back to the desktop's own
// value and state 3 comes down to pure black instead. The 0/3 pair
// still ends up close enough to stop strobing, but both are now dark,
// so states 1 and 2 keep their full contrast against the field rather
// than everything washing toward mid-blue. The cost moves rather than
// disappearing: where 0 and 3 alternate, that structure is now nearly
// invisible instead of merely low-contrast.
static const uint8_t S0_R = 0x12, S0_G = 0x12, S0_B = 0x18;  // desktop's own
static const uint8_t S3_R = 0x00, S3_G = 0x00, S3_B = 0x00;  // desktop's own: 0x40, 0x9C, 0xFF

static const uint16_t PALETTE_WIRE[4] = {
    rgb565_swapped(S0_R, S0_G, S0_B), rgb565_swapped(0xEB, 0xEB, 0xE1),
    rgb565_swapped(0xFF, 0xA1, 0x36), rgb565_swapped(S3_R, S3_G, S3_B),
};
// State 0's color in normal byte order, for the one-off fillScreen().
static const uint16_t BACKGROUND = rgb565(S0_R, S0_G, S0_B);

// A rule already known to live a long time, from the desktop's own
// odca-evolve search (see ../../interesting.odca).
static const char *RULE_ID = "33233022210132010013";

// Large fixed structures: static, never on the stack (see odca_boring.h).
static odca_rule rule;
static odca_detector detector;
static unsigned char cur[WIDTH];
static unsigned char next_row[WIDTH];

// One row of color, the only pixel buffer this board needs: the panel
// itself holds every other row, so there is no history buffer and no
// full-frame redraw here at all.
static uint16_t line_pixels[WIDTH];

// The scroll ring. Generation g is written to panel line g % HEIGHT;
// the scroll start address then names the line that should appear at
// the top of the screen, which is always the oldest row still held.
static int write_line = 0;  // panel line the next row goes to
static int filled = 0;      // rows written so far, caps at HEIGHT

static unsigned long generation = 0;             // this seed's age; reset by every reinit
static unsigned long long total_generation = 0;   // never reset — the only thing the rate is measured from
static unsigned long long total_at_last_report = 0;
static unsigned long last_report_ms = 0;
static unsigned long reinit_count = 0;
static unsigned long next_due_ms = 0;

// Speed. On the RP2350 the redraw itself paces the loop, so "faster"
// there means stepping several generations between redraws. Here a
// row costs microseconds and paces nothing, so the pacing is explicit:
// a target period per generation, multiplied or divided from a base.
static const unsigned long BASE_PERIOD_MS = 20;  // ~50 generations/second

// Generations drawn per frame, and why it is 2 rather than 1.
//
// With one row per frame, any region of the automaton that settles into
// single-pixel alternating rows (one color, the next, back again — what
// this rule does once two states go extinct) makes every pixel on
// screen swap color on every frame. The whole region strobes at half
// the frame rate, which at ~50fps lands near 26Hz, close to the peak of
// human flicker sensitivity. It reads as shimmer with no structure to
// it, everywhere at once, worst exactly where those alternating bands
// are (the user's own observation, and their suggested fix).
//
// Scrolling several lines per frame maps such a pattern onto itself:
// the content that arrives at a given pixel is the same color that was
// already there, so it holds still instead of toggling. The region
// still moves and evolves; only the strobing stops.
//
// In general a vertical pattern of period p, scrolled s rows per frame
// at f frames per second, makes each pixel cycle at f*gcd(p,s)/p — zero
// only when s is a multiple of p, and no single value satisfies every p
// the automaton produces.
//
// 2 is the value that survived testing. 4 was tried, on the reasoning
// that it settles period-4 bands as well as period-2, and it was worse
// (user: "too much strobing"): holding the generation rate fixed, 4
// rows per frame means 12.5 frames per second, and a frame rate that
// low is itself well inside the range the eye objects to. The step size
// is not the only thing that matters — the frame rate it implies
// matters at least as much, and pushing it down to buy period matching
// is a losing trade.
static const int ROWS_PER_FRAME = 2;
static_assert(HEIGHT % ROWS_PER_FRAME == 0, "the scroll ring must hold a whole number of frames");

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

static unsigned long speed_period_ms(Speed s) {
  switch (s) {
    case SPEED_X2:   return BASE_PERIOD_MS / 2;
    case SPEED_X4:   return BASE_PERIOD_MS / 4;
    case SPEED_DIV2: return BASE_PERIOD_MS * 2;
    case SPEED_DIV4: return BASE_PERIOD_MS * 4;
    default:         return BASE_PERIOD_MS;
  }
}

// A plain GPIO once past reset — digitalRead() with the internal
// pull-up, active low. Same press-then-wait-for-release debounce as
// the RP2350 board.
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

// Write one generation as one panel line, then move the scroll start.
//
// Until the ring has filled, the scroll start stays at 0, so rows land
// from the top downward with background below — R-U3's "filled rows
// from the top, background below", as on the desktop. Once full, the
// start follows the write position, so the oldest row sits at the top
// and the newest at the bottom, and the panel does the scrolling. The
// two cases agree exactly at the moment the ring fills, so the
// transition is seamless.
static void put_row(const unsigned char *row) {
  for (int x = 0; x < WIDTH; x++) line_pixels[x] = PALETTE_WIRE[row[x]];

  tft.startWrite();
  tft.setAddrWindow(0, write_line, WIDTH, 1);
  tft.writePixels(line_pixels, WIDTH, true, true);  // already wire order
  tft.endWrite();

  if (filled < HEIGHT) filled++;
  write_line = (write_line + 1) % HEIGHT;
}

// Moved once per frame, after every row of that frame is in place, so
// the frame's rows appear together rather than one at a time.
static void commit_scroll() {
  tft.scrollTo(filled < HEIGHT ? 0 : write_line);
}

static void reinitialize(const char *reason) {
  seed_random_row(cur, WIDTH);
  odca_detector_reset(&detector);  // R-A3: same rule, fresh field
  generation = 0;
  // No clear: the fresh field scrolls in from below like any other
  // generation, and the old rows keep their colors and scroll off the
  // top as usual — the desktop's own re-seed-in-place (help.py: "grows
  // in from a fresh field below the old rows, which keep their
  // colors").
  put_row(cur);
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
  Serial.println("odca platformio: CYD engine + boring detector + display running");

  pinMode(PIN_BOOT, INPUT_PULLUP);
  pinMode(PIN_BL, OUTPUT);
  digitalWrite(PIN_BL, HIGH);

  hspi.begin(PIN_SCK, PIN_MISO, PIN_MOSI, PIN_CS);
  // 80MHz, available because the display sits on HSPI's native IOMUX
  // pins (see the pin comment). A clock beyond what the routing
  // supports does not merely glitch: it permanently desyncs the panel's
  // command/data framing, with nothing to resync it. So the number is
  // only trusted after a long soak, which this one has had.
  tft.begin(80000000);
  tft.setRotation(0);  // portrait: the scroll axis must be the direction the picture moves
  tft.fillScreen(BACKGROUND);

  // Whole screen scrolls, no fixed margins top or bottom.
  tft.setScrollMargins(0, 0);
  tft.scrollTo(0);

  if (!odca_rule_from_id(RULE_ID, &rule)) {
    Serial.println("engine: rule ID failed to parse (should not happen)");
    return;
  }
  odca_detector_set_rule(&detector, &rule);
  Serial.print("rule ");
  Serial.println(RULE_ID);
  reinitialize(NULL);  // the first field, no reinit line for it
  commit_scroll();
  last_report_ms = millis();
  next_due_ms = millis();
}

void loop() {
  poll_boot_button();

  // Timed narrowly around the panel writes only, not the whole frame:
  // this is the window during which the panel could catch a partly
  // written picture, so it is the number that governs tearing. Folding
  // the detector into it would muddy that (its repeat-window scan grows
  // as the window fills, which is expected and harmless here).
  unsigned long write_us = 0;
  for (int i = 0; i < ROWS_PER_FRAME; i++) {
    odca_step_wrap(cur, WIDTH, &rule, next_row);
    memcpy(cur, next_row, sizeof cur);
    generation++;
    total_generation++;

    unsigned long t0 = micros();
    put_row(cur);
    write_us += micros() - t0;

    if (odca_detector_observe(&detector, cur, WIDTH) && detector.boring_streak >= HEIGHT) {
      char reason[ODCA_END_MAX];
      strncpy(reason, detector.boring_reason, sizeof reason);
      Serial.print("generation ");
      Serial.print(generation);
      Serial.print("  ");
      reinitialize(reason);
    }
  }
  unsigned long t0 = micros();
  commit_scroll();
  write_us += micros() - t0;

  // Explicit pacing, since drawing no longer costs enough to pace
  // anything. The period is per generation, so the frame period scales
  // with how many rows a frame carries — the speed setting keeps
  // meaning generations per second either way. The delay also covers
  // this chip's FreeRTOS task watchdog, which only clears when the idle
  // task runs: yield() only yields to tasks of equal or higher priority
  // and never reaches idle, so it does not clear the watchdog; delay()
  // actually blocks this task, which does.
  long slack = (long)(next_due_ms - millis());
  delay(slack > 1 ? (unsigned long)slack : 1);
  next_due_ms = millis() + speed_period_ms(speed) * ROWS_PER_FRAME;

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
    Serial.print(", write ");
    Serial.print(write_us);
    Serial.println("us)");
    total_at_last_report = total_generation;
    last_report_ms = now;
  }
}
