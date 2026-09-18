// ODCA on an MCU: the engine (R-M), boring detector (R-A), and display,
// on the ESP32-C6 board. See main.cpp's own comments for the R-A2
// auto-init terms and the general shape; the engine and detector are
// identical here and only the display differs.
//
// This board draws the way main_cyd.cpp does, and for the same reasons.
// It used to repaint the whole window every generation — 110,080 bytes
// over the SPI bus — and that single fact caused both of its problems.
// It was slow (9 generations/second at the only clock that never
// corrupted a transfer), and the sheer volume of data was what exposed
// it to the corruption that would eventually desync the panel's
// command/data framing and freeze the picture for good, with serial
// still running and generations still counting.
//
// Now it writes only the new rows and lets the panel's own hardware
// vertical scroll do the shifting: a few hundred bytes per generation
// instead of a hundred thousand. That is fast enough at the safe clock
// with room to spare, so the clock stays where it is rather than being
// pushed back toward the rate that caused the corruption.
//
// The cost, and it was the user's call (2026-09-19): hardware scroll
// only moves along the panel's native long axis, and that axis has to
// be the direction the picture scrolls. So this board runs PORTRAIT and
// the automaton is 172 cells wide rather than the 320 it used to be
// (R-U2) — the width the user had originally rejected. They chose it
// knowingly here, on the grounds that scrolling the same way on every
// platform matters more than the extra cells. A sweeping write line
// was built first as the alternative that keeps 320, looked at, and
// rejected outright.
#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <Arduino.h>
#include <SPI.h>
#include <esp_random.h>
#include <cstring>
#include "odca_boring.h"
#include "odca_engine.h"

// Portrait, so the automaton's width is the panel's short axis and the
// history scrolls down its long axis — which is the axis hardware
// scroll acts on.
static const int WIDTH = 172;
static const int HEIGHT = 320;  // R-A2's screenful, and the scroll ring's depth

// Display wiring (Waveshare's own wiki: LCD_DC, LCD_CS, LCD_RST, LCD_BL,
// SCLK, MOSI), confirmed against the real panel.
static const int PIN_DC = 15;
static const int PIN_CS = 14;
static const int PIN_RST = 21;
static const int PIN_BL = 22;
static const int PIN_SCK = 7;
static const int PIN_MOSI = 6;
static const int PANEL_NATIVE_WIDTH = 172;
static const int PANEL_NATIVE_HEIGHT = 320;

// This board's BOOT button: GPIO9 on every ESP32-C6, since it is the
// chip's own strapping pin for serial-bootloader entry rather than a
// board-specific wiring choice — confirmed against Espressif's own
// ESP32-C6-DevKitC-1 docs. Active low.
static const int PIN_BOOT = 9;

// ST7789 scroll commands. Unlike Adafruit_ILI9341, the ST77xx driver
// exposes no scroll helpers of its own, so these go out through
// Adafruit_SPITFT's sendCommand directly. Same command numbers.
static const uint8_t ST7789_VSCRDEF = 0x33;   // scroll area definition
static const uint8_t ST7789_VSCSAD = 0x37;    // scroll start address

Adafruit_ST7789 tft(&SPI, PIN_CS, PIN_DC, PIN_RST);

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
static const uint16_t PALETTE_WIRE[4] = {
    rgb565_swapped(0x12, 0x12, 0x18), rgb565_swapped(0xEB, 0xEB, 0xE1),
    rgb565_swapped(0xFF, 0xA1, 0x36), rgb565_swapped(0x40, 0x9C, 0xFF),
};
// State 0's color in normal byte order, for the one-off fillScreen().
static const uint16_t BACKGROUND = rgb565(0x12, 0x12, 0x18);

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

// Pacing. The full redraw used to pace the loop by simply being slow; a
// row costs microseconds and paces nothing, so the rate is asked for.
static const unsigned long BASE_PERIOD_MS = 20;  // ~50 generations/second

// Generations drawn per frame, and why it is 2 rather than 1. Carried
// over from main_cyd.cpp, where the same rule on the same kind of panel
// showed the problem plainly: where the automaton settles into
// single-pixel alternating rows (which this rule does once two states
// go extinct), a one-row-per-frame scroll makes every pixel on screen
// swap color every frame, strobing the region at half the frame rate,
// near the peak of human flicker sensitivity. A two-row step maps a
// period-2 pattern onto itself so it holds still.
//
// 4 was tried there and was worse: holding the generation rate fixed, it
// drops the frame rate to 12.5/second, which is itself well inside the
// range the eye objects to.
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
// pull-up, active low. Same press-then-wait-for-release debounce as the
// other two boards.
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

// The whole panel scrolls: no fixed area above or below. TFA + VSA +
// BFA must add up to the controller's 320 lines, which is exactly this
// panel's height, so the scrolling area is all of it.
static void set_scroll_area() {
  uint8_t data[6] = {0, 0,
                     (uint8_t)(HEIGHT >> 8), (uint8_t)(HEIGHT & 0xFF),
                     0, 0};
  tft.sendCommand(ST7789_VSCRDEF, data, 6);
}

static void scroll_to(uint16_t line) {
  uint8_t data[2] = {(uint8_t)(line >> 8), (uint8_t)(line & 0xFF)};
  tft.sendCommand(ST7789_VSCSAD, data, 2);
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

// Write one generation as one panel line. The scroll start is moved
// separately, once a frame, so a frame's rows appear together.
static void put_row(const unsigned char *row) {
  for (int x = 0; x < WIDTH; x++) line_pixels[x] = PALETTE_WIRE[row[x]];

  tft.startWrite();
  tft.setAddrWindow(0, write_line, WIDTH, 1);
  tft.writePixels(line_pixels, WIDTH, true, true);  // already wire order
  tft.endWrite();

  if (filled < HEIGHT) filled++;
  write_line = (write_line + 1) % HEIGHT;
}

// Until the ring has filled, the scroll start stays at 0, so rows land
// from the top downward with background below — R-U3's "filled rows
// from the top, background below", as on the desktop. Once full, the
// start follows the write position, so the oldest row sits at the top
// and the newest at the bottom, and the panel does the scrolling. The
// two cases agree exactly at the moment the ring fills, so the
// transition is seamless.
static void commit_scroll() {
  scroll_to(filled < HEIGHT ? 0 : (uint16_t)write_line);
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
  Serial.println("odca platformio: ESP32-C6 engine + boring detector + display running");

  pinMode(PIN_BOOT, INPUT_PULLUP);
  pinMode(PIN_BL, OUTPUT);
  digitalWrite(PIN_BL, HIGH);

  // This board's SCK/MOSI aren't the generic esp32-c6-devkitc-1 target's
  // default SPI pins (there is no Waveshare-specific board definition),
  // so they need spelling out explicitly rather than relying on a
  // default that doesn't match this wiring.
  SPI.begin(PIN_SCK, /* MISO */ -1, PIN_MOSI, PIN_CS);
  tft.init(PANEL_NATIVE_WIDTH, PANEL_NATIVE_HEIGHT);
  tft.setRotation(0);  // portrait: the scroll axis must be the direction the picture moves

  // 10MHz, deliberately left where it is. This board's display pins are
  // GPIO-matrix-routed rather than dedicated hardware SPI pins, and that
  // path has a real, lower reliable ceiling: 40MHz corrupted transfers
  // within a few hundred generations, reliably, and 20MHz survived 90
  // seconds once and then died inside 172. 10MHz was the best-behaved
  // value and is now also fast enough by a wide margin, since a
  // generation costs a few hundred bytes rather than a hundred thousand.
  // There is nothing left to buy by raising it.
  tft.setSPISpeed(10000000);
  tft.fillScreen(BACKGROUND);

  set_scroll_area();
  scroll_to(0);

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
  // written picture. Folding the detector into it would muddy that (its
  // repeat-window scan grows as the window fills, which is expected and
  // harmless here).
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
  // task runs: yield() does not reach it, delay() does.
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
