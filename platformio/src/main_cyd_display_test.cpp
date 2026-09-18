// ODCA on an MCU: proving the CYD's display link before any automaton
// touches it — the same role src/main_display_test.cpp plays for the
// RP2350 board. `pio run -e cyd-display -t upload` builds and flashes
// this instead of the real firmware.
//
// More unconfirmed here than either other board started with: the
// driver chip itself (most CYD units are ILI9341, some later batches
// ST7789 — genuinely different command sets, not just different pins,
// per community documentation), backlight polarity, and whether RST is
// wired to a GPIO at all (not listed in the community pin tables this
// was built from, so guessed tied to the chip's own EN/reset line,
// i.e. no separate control needed — passed as -1).
#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h>
#include <Arduino.h>
#include <SPI.h>

// SPI pin mapping (community documentation, VSPI bus shared with the
// XPT2046 touch controller on a separate CS — untouched here, so it
// stays idle).
static const int PIN_MISO = 12;
static const int PIN_MOSI = 13;
static const int PIN_SCK = 14;
static const int PIN_CS = 15;
static const int PIN_DC = 2;
static const int PIN_BL = 21;
static const int PIN_RST = -1;  // unconfirmed: guessed tied to EN, no separate GPIO

// Native ILI9341 size (fixed, unlike the ST7789 boards' variable GRAM):
// 240(W) x 320(H), portrait.
static const int PANEL_NATIVE_WIDTH = 240;
static const int PANEL_NATIVE_HEIGHT = 320;

// Same rotation convention as the RP2350 board's display; unconfirmed
// against this panel specifically.
static const uint8_t ROTATION = 1;
static const int WIDTH = 320;
static const int HEIGHT = 240;

// Note the parameter order: (spi, dc, cs, rst) — Adafruit_ILI9341's own
// constructor order, different from Adafruit_ST7789's (spi, cs, dc, rst).
Adafruit_ILI9341 tft(&SPI, PIN_DC, PIN_CS, PIN_RST);

// The desktop's own default palette (library.json, "ODCA default"),
// states 0-3, converted to RGB565.
static uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b) {
  return (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
}
static const uint16_t PALETTE[4] = {
    rgb565(0x12, 0x12, 0x18),  // state 0
    rgb565(0xEB, 0xEB, 0xE1),  // state 1
    rgb565(0xFF, 0xA1, 0x36),  // state 2
    rgb565(0x40, 0x9C, 0xFF),  // state 3
};

static int step_num = 0;

static void announce(const char *what) {
  Serial.print("display: step ");
  Serial.print(step_num);
  Serial.print(": ");
  Serial.println(what);
  step_num++;
}

void setup() {
  Serial.begin(115200);
  uint32_t start = millis();
  while (!Serial && millis() - start < 3000) delay(10);
  Serial.println("odca platformio: CYD display link test");

  pinMode(PIN_BL, OUTPUT);
  digitalWrite(PIN_BL, HIGH);  // backlight on; if this pin or its polarity is wrong, the panel may just stay dark

  SPI.begin(PIN_SCK, PIN_MISO, PIN_MOSI, PIN_CS);
  tft.begin(10000000);  // deliberately conservative for a first look at an unproven panel; the real firmware runs 80MHz once the wiring is known good
  tft.setRotation(ROTATION);

  Serial.print("reports width ");
  Serial.print(tft.width());
  Serial.print(" height ");
  Serial.println(tft.height());
}

void loop() {
  announce("solid red");
  tft.fillScreen(rgb565(255, 0, 0));
  delay(2000);

  announce("solid green");
  tft.fillScreen(rgb565(0, 255, 0));
  delay(2000);

  announce("solid blue");
  tft.fillScreen(rgb565(0, 0, 255));
  delay(2000);

  announce("four ODCA palette colors, one quarter-width vertical stripe each (checks orientation: should read left to right, not top to bottom)");
  for (int s = 0; s < 4; s++) {
    tft.fillRect(s * (WIDTH / 4), 0, WIDTH / 4, HEIGHT, PALETTE[s]);
  }
  delay(4000);

  announce("single pixels at all four corners, white on black (checks exact bounds and rotation direction)");
  tft.fillScreen(ILI9341_BLACK);
  tft.drawPixel(0, 0, ILI9341_WHITE);
  tft.drawPixel(WIDTH - 1, 0, ILI9341_WHITE);
  tft.drawPixel(0, HEIGHT - 1, ILI9341_WHITE);
  tft.drawPixel(WIDTH - 1, HEIGHT - 1, ILI9341_WHITE);
  delay(4000);
}
