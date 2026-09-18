// ODCA on an MCU: proving the display link before any automaton touches
// it. `pio run -e display -t upload` builds and flashes this instead of
// the real firmware in ../src.
//
// The pin numbers and rotation below started as a best guess from two
// independent sources plus this board's default hardware SPI0 pins, and
// are now confirmed correct against the real panel: right colors, right
// orientation, the user's own words "it looks amazing" once this reached
// the real automaton in src/main.cpp.
#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <Arduino.h>
#include <SPI.h>

static const int PIN_DC = 16;
static const int PIN_CS = 17;
// PIN_CLK (18) and PIN_MOSI (19) are this board's default hardware SPI0
// pins (framework-arduinopico/variants/rpipico2/pins_arduino.h), so the
// default SPI object needs no explicit remapping.
static const int PIN_RST = 20;
static const int PIN_BL = 21;

// The panel's native order (Waveshare's own spec, R-U2 units aside):
// 172(H) x 320(V), portrait.
static const int PANEL_NATIVE_WIDTH = 172;
static const int PANEL_NATIVE_HEIGHT = 320;

// ODCA wants 320 as the automaton's width (see ../README.md), so this
// rotates to landscape; confirmed correct (see above). WIDTH/HEIGHT
// below are in this rotated, logical orientation.
static const uint8_t ROTATION = 1;
static const int WIDTH = 320;
static const int HEIGHT = 172;

Adafruit_ST7789 tft(&SPI, PIN_CS, PIN_DC, PIN_RST);

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
  Serial.println("odca platformio: display link test");

  pinMode(PIN_BL, OUTPUT);
  digitalWrite(PIN_BL, HIGH);  // backlight on; if this pin is wrong, the panel may just stay dark

  tft.init(PANEL_NATIVE_WIDTH, PANEL_NATIVE_HEIGHT);  // always the panel's native size, pre-rotation
  tft.setRotation(ROTATION);
  tft.setSPISpeed(40000000);

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
  tft.fillScreen(ST77XX_BLACK);
  tft.drawPixel(0, 0, ST77XX_WHITE);
  tft.drawPixel(WIDTH - 1, 0, ST77XX_WHITE);
  tft.drawPixel(0, HEIGHT - 1, ST77XX_WHITE);
  tft.drawPixel(WIDTH - 1, HEIGHT - 1, ST77XX_WHITE);
  delay(4000);
}
