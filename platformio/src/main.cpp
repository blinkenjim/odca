// ODCA on an MCU: engine smoke test on the actual target, not yet the
// boring detector or the display.
//
// This steps one of conformance/vectors.json's own golden cases
// ("mixed neighborhood (0,1,1,1)->2 on width-3 wrap", R-M5) and prints
// each row over serial, so the firmware's cross-compiled engine can be
// checked by eye against the same numbers platformio/host_test/run
// already proved on the host: rule 00000200000000000000, wrap, row "123"
// should read "222" then "000".
#include <Arduino.h>
#include <cstring>
#include "odca_engine.h"

static odca_rule rule;
static unsigned char cur[3] = {1, 2, 3};   // "123"
static unsigned char next_row[3];
static int generation = 0;

static void print_row(const unsigned char *cells, int width) {
  for (int i = 0; i < width; i++) Serial.print((char)('0' + cells[i]));
  Serial.println();
}

void setup() {
  Serial.begin(115200);
  uint32_t start = millis();
  while (!Serial && millis() - start < 3000) {
    delay(10);
  }
  Serial.println("odca platformio hello: toolchain is alive");

  if (!odca_rule_from_id("00000200000000000000", &rule)) {
    Serial.println("engine: rule ID failed to parse (should not happen)");
  }
  char id[ODCA_RULE_SIZE + 1];
  odca_rule_to_id(&rule, id);
  Serial.print("engine: rule round-trips as ");
  Serial.println(id);
  Serial.print("engine: generation 0 (seed)  ");
  print_row(cur, 3);
}

void loop() {
  if (generation < 2) {
    odca_step_wrap(cur, 3, &rule, next_row);
    memcpy(cur, next_row, sizeof cur);
    generation++;
    Serial.print("engine: generation ");
    Serial.print(generation);
    Serial.print("           ");
    print_row(cur, 3);
    if (generation == 2) {
      Serial.println("engine: expect 222 then 000 above, per conformance/vectors.json");
    }
  }
  delay(1000);
}
