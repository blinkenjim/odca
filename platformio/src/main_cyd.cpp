// ODCA on an MCU: the engine (R-M), boring detector (R-A), and display,
// on the CYD (ESP32-2432S028) board — ported from src/main.cpp (RP2350)
// and src/main_esp32c6.cpp the same way those two relate to each
// other: only the genuinely board-specific pieces change (pins, driver
// chip, RNG call, BOOT-button pin, SPI clock). See main.cpp's own
// comments for the reasoning behind the full-redraw display approach,
// the R-A2 auto-init terms, and R-U2's width choice; none of that
// changes here. Confirmed against the real panel first, in
// main_cyd_display_test.cpp: right colors, right orientation, right
// bounds, on the first try.
#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h>
#include <Arduino.h>
#include <SPI.h>
#include <esp_random.h>
#include <cstring>
#include "odca_boring.h"
#include "odca_engine.h"

// This board's native 320x240 landscape IS the automaton's width
// directly — unlike the other two boards' 172-wide panels, no rotation
// is needed to reach 320, though the panel's native orientation is
// still portrait and setRotation() still does the work (see below).
static const int WIDTH = 320;
static const int HEIGHT = 240;  // R-A2's screenful: this panel's full height, all of it drawn

// Classic ESP32 has far less usable DRAM than the other two boards
// (~100KB once the framework's own overhead is out), and the boring
// detector's fixed R-A1 windows already claim ~36KB of that (4000
// hashes + 1600 counts + a snapshot row — spec-mandated, identical on
// every board, not something to shrink). A byte-per-cell history at
// this board's full 240 rows would not fit alongside them.
//
// So the history packs four cells to the byte instead: states are 0-3,
// two bits each, which is what they always needed. 19,200 bytes rather
// than 76,800, and the screen gets its full height. WIDTH divisible by
// 4 is what keeps rows byte-aligned, so no cell ever straddles a byte.
static_assert(WIDTH % 4 == 0, "packed history assumes 4 cells per byte, rows byte-aligned");
static const int HISTORY_STRIDE = WIDTH / 4;

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
// the GPIO matrix. That is the same routing the ESP32-C6 board was
// stuck with, where it capped the usable SPI clock hard enough to
// corrupt transfers. Here it is avoidable: use HSPI, get the fast path.
static const int PIN_MISO = 12;
static const int PIN_MOSI = 13;
static const int PIN_SCK = 14;
static const int PIN_CS = 15;
static const int PIN_DC = 2;
static const int PIN_BL = 21;
static const int PIN_RST = -1;  // no separate GPIO found for this; guessed tied to EN, confirmed fine in the display test

// This board's BOOT button: GPIO0, the classic ESP32's own strapping
// pin for serial-bootloader entry (confirmed via community
// documentation), same role GPIO9 plays on the ESP32-C6. Active low.
static const int PIN_BOOT = 0;

// HSPI rather than the default global SPI (VSPI) — see the pin comment
// above for why that choice is worth making deliberately.
SPIClass hspi(HSPI);

// Native ILI9341 size is fixed (240x320, unlike the ST7789 boards'
// variable GRAM), so begin() needs no width/height arguments.
Adafruit_ILI9341 tft(&hspi, PIN_DC, PIN_CS, PIN_RST);  // note the (spi, dc, cs, rst) order — different from Adafruit_ST7789's (spi, cs, dc, rst)

// The desktop's own default palette (library.json, "ODCA default"),
// stored BYTE-SWAPPED. The panel wants each RGB565 pixel big-endian on
// the wire; this CPU stores little-endian, so the driver would normally
// swap all 76,800 pixels in software every frame. Pre-swapping the four
// palette entries once means the band buffer is already in wire order
// and writePixels() can be told so (bigEndian=true), which hands the
// bytes straight to the SPI transfer instead.
//
// These values are therefore NOT valid to pass to ordinary Adafruit_GFX
// calls like fillScreen() — they are only ever fed to writePixels()
// below, in wire order.
static uint16_t rgb565_swapped(uint8_t r, uint8_t g, uint8_t b) {
  uint16_t v = (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
  return (uint16_t)((v >> 8) | (v << 8));
}
static const uint16_t PALETTE_WIRE[4] = {
    rgb565_swapped(0x12, 0x12, 0x18), rgb565_swapped(0xEB, 0xEB, 0xE1),
    rgb565_swapped(0xFF, 0xA1, 0x36), rgb565_swapped(0x40, 0x9C, 0xFF),
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
// states, packed two bits per cell (see HISTORY_STRIDE above); colors
// are computed per redraw, not stored.
static unsigned char history[HEIGHT][HISTORY_STRIDE];
static int history_count = 0;   // rows filled so far, caps at HEIGHT
static int history_next = 0;    // the ring's next write slot

// Colors for a band of rows at a time, sent in one writePixels() call
// per band. Not a full HEIGHT x WIDTH frame buffer — that would be
// 150KB, which this board's DRAM has no room for — but not one call
// per row either: measured here, per-call cost was about 19ms of a
// 35ms redraw across 240 calls (~67us each, DMA setup and an endian
// swap per call), dwarfing the ~3ms the palette unpacking actually
// costs. Six calls instead of 240, for 25KB.
static const int BAND_ROWS = 40;
static_assert(HEIGHT % BAND_ROWS == 0, "bands must divide the screen height evenly");
static uint16_t band_pixels[BAND_ROWS][WIDTH];

// One packed history byte holds four cells, so every possible byte
// expands to exactly four wire-order pixels. Precomputing all 256
// expansions turns the redraw's inner loop into one table lookup per
// byte instead of a shift, mask and lookup per pixel — 80 iterations
// per row rather than 320. 2KB, built once in setup().
static uint16_t quad_pixels[256][4];

static void build_quad_table() {
  for (int b = 0; b < 256; b++) {
    for (int k = 0; k < 4; k++) {
      quad_pixels[b][k] = PALETTE_WIRE[(b >> (k * 2)) & 3];
    }
  }
}

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

// A plain GPIO once past reset — digitalRead() with the internal
// pull-up, active low. Same press-then-wait-for-release debounce as
// the other two boards.
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
  tft.startWrite();
  tft.setAddrWindow(0, 0, WIDTH, HEIGHT);
  for (int top = 0; top < HEIGHT; top += BAND_ROWS) {
    for (int dy = 0; dy < BAND_ROWS; dy++) {
      int y = top + dy;
      uint16_t *out = band_pixels[dy];
      if (y < history_count) {
        int slot = (history_next - history_count + y + HEIGHT) % HEIGHT;
        const unsigned char *packed = history[slot];
        for (int xb = 0; xb < HISTORY_STRIDE; xb++) {
          const uint16_t *q = quad_pixels[packed[xb]];
          out[0] = q[0];
          out[1] = q[1];
          out[2] = q[2];
          out[3] = q[3];
          out += 4;
        }
      } else {
        for (int x = 0; x < WIDTH; x++) out[x] = PALETTE_WIRE[0];
      }
    }
    // block=true, bigEndian=true: the buffer is already in wire order,
    // so this skips the driver's per-pixel software swap.
    tft.writePixels(&band_pixels[0][0], (uint32_t)WIDTH * BAND_ROWS, true, true);
  }
  tft.endWrite();
}

static void push_history(const unsigned char *row) {
  unsigned char *packed = history[history_next];
  for (int x = 0; x < WIDTH; x += 4) {
    packed[x >> 2] = (unsigned char)(row[x] | (row[x + 1] << 2) |
                                     (row[x + 2] << 4) | (row[x + 3] << 6));
  }
  history_next = (history_next + 1) % HEIGHT;
  if (history_count < HEIGHT) history_count++;
}

static void reinitialize(const char *reason) {
  seed_random_row(cur, WIDTH);
  odca_detector_reset(&detector);  // R-A3: same rule, fresh field
  generation = 0;
  // No clear here: the fresh field grows in from below like any other
  // generation — see main.cpp's own comment (help.py: "grows in from a
  // fresh field below the old rows, which keep their colors").
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
  Serial.println("odca platformio: CYD engine + boring detector + display running");

  pinMode(PIN_BOOT, INPUT_PULLUP);
  pinMode(PIN_BL, OUTPUT);
  digitalWrite(PIN_BL, HIGH);

  build_quad_table();

  hspi.begin(PIN_SCK, PIN_MISO, PIN_MOSI, PIN_CS);
  // 40MHz, on HSPI's native IOMUX pins (see the pin comment above), is
  // the clock this board is routinely driven at by other projects. The
  // ESP32-C6's hard lesson (main_esp32c6.cpp's comment) was that a
  // too-fast clock doesn't merely glitch, it permanently desyncs the
  // display's command/data framing with no self-recovery — but there
  // the pins had no fast path available at all. The lesson that carries
  // over is the test method, not the number: a clock is only trusted
  // here after a long soak, since that failure took minutes to appear.
  tft.begin(80000000);
  tft.setRotation(1);

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
  // This chip runs FreeRTOS under the Arduino core, same as the
  // ESP32-C6 — the same task-watchdog lesson applies (main_esp32c6.cpp's
  // comment): yield() doesn't reach the IDLE task, only delay() does.
  // Included from the start here rather than rediscovering it.
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

  // /2 and /4: a plain delay(), not the RP2350 side's busy-spin — see
  // main_esp32c6.cpp's own comment on why that trade doesn't carry over
  // to a FreeRTOS-based board.
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
