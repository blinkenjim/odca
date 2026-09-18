// ODCA on an MCU: toolchain smoke test, not yet a port of the engine.
//
// Prints a counting heartbeat over USB serial so the toolchain (compiler,
// upload, and the serial link) can be verified without knowing anything
// about this board's LED wiring: the RP2350 boards in play here don't
// share it (a plain GPIO LED on some, a WS2812 on others), so a visual
// blink would need a board-specific follow-up rather than a safe default.
#include <Arduino.h>

void setup() {
  Serial.begin(115200);
  // Arduino-Pico's USB CDC attaches asynchronously; give a host a moment
  // to open the port, without hanging forever if none does.
  uint32_t start = millis();
  while (!Serial && millis() - start < 3000) {
    delay(10);
  }
  Serial.println("odca platformio hello: toolchain is alive");
}

void loop() {
  static uint32_t n = 0;
  Serial.print("heartbeat ");
  Serial.println(n++);
  delay(1000);
}
