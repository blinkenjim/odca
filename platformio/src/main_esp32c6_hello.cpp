// ODCA on an MCU: proving the ESP32-C6 toolchain before any port work
// begins, the same first step the RP2350 side took. `pio run -e esp32c6
// -t upload` builds and flashes this instead of the RP2350 firmware in
// ../src (build_src_filter, ../platformio.ini).
//
// No LED blink: this board's RGB LED (GPIO8, per Waveshare's own wiki)
// is undocumented as to whether it's WS2812-addressable or something
// simpler, and the RP2350 side already set the precedent of not
// guessing at LED wiring for a toolchain check — a serial heartbeat
// alone confirms the build, upload, and monitor pipeline all work.
#include <Arduino.h>

void setup() {
  Serial.begin(115200);
  uint32_t start = millis();
  while (!Serial && millis() - start < 3000) {
    delay(10);
  }
  Serial.println("odca platformio: ESP32-C6 toolchain check");
}

void loop() {
  static unsigned long count = 0;
  Serial.print("heartbeat ");
  Serial.println(count++);
  delay(1000);
}
