// ODCA on an MCU: proving the CYD (ESP32-2432S028) toolchain before any
// port work begins, the same first step the RP2350 board took.
// `pio run -e cyd -t upload` builds and flashes this instead of the
// other boards' firmware (build_src_filter, ../platformio.ini).
//
// No LED blink, no display touch yet: this is a serial heartbeat only,
// to confirm the build/upload/monitor pipeline works before anything
// board-specific (the display driver chip is not even confirmed yet —
// most CYD units are ILI9341, some later batches ST7789).
#include <Arduino.h>

void setup() {
  Serial.begin(115200);
  uint32_t start = millis();
  while (!Serial && millis() - start < 3000) {
    delay(10);
  }
  Serial.println("odca platformio: CYD (ESP32-2432S028) toolchain check");
}

void loop() {
  static unsigned long count = 0;
  Serial.print("heartbeat ");
  Serial.println(count++);
  delay(1000);
}
