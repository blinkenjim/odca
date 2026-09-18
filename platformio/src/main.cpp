// ODCA on an MCU: the engine (R-M) and the boring detector (R-A) running
// continuously, headless — no display yet. Auto-initializes on the same
// terms the desktop programs do (R-A2): once a screenful of generations
// in a row has been boring, start over; "a screenful" here is 172 rows,
// the height the display will show once it's wired up (R-U2, rotated so
// the panel's 320-pixel axis is the automaton's width — the user's own
// call: more cells make for richer, longer-lived rules than the panel's
// native 172).
#include <Arduino.h>
#include <cstring>
#include "odca_boring.h"
#include "odca_engine.h"

static const int WIDTH = 320;
static const int ROWS_FOR_REINIT = 172;  // R-A2's screenful, this board's planned geometry

// A rule already known to live a long time at this width, from the
// desktop's own odca-evolve search (see ../../interesting.odca).
static const char *RULE_ID = "33233022210132010013";

// Large fixed structures: static, never on the stack (see odca_boring.h).
static odca_rule rule;
static odca_detector detector;
static unsigned char cur[WIDTH];
static unsigned char next_row[WIDTH];

static unsigned long generation = 0;             // this seed's age; reset by every reinit
static unsigned long long total_generation = 0;   // never reset — the only thing the rate is measured from
static unsigned long long total_at_last_report = 0;
static unsigned long last_report_ms = 0;
static unsigned long reinit_count = 0;

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

static void reinitialize(const char *reason) {
  seed_random_row(cur, WIDTH);
  odca_detector_reset(&detector);  // R-A3: same rule, fresh field
  generation = 0;
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
  Serial.println("odca platformio: engine + boring detector running, no display yet");

  if (!odca_rule_from_id(RULE_ID, &rule)) {
    Serial.println("engine: rule ID failed to parse (should not happen)");
    return;
  }
  odca_detector_set_rule(&detector, &rule);
  Serial.print("rule ");
  Serial.println(RULE_ID);
  reinitialize(NULL);  // the first field, no reinit line for it
  last_report_ms = millis();
}

void loop() {
  odca_step_wrap(cur, WIDTH, &rule, next_row);
  memcpy(cur, next_row, sizeof cur);
  generation++;
  total_generation++;

  if (odca_detector_observe(&detector, cur, WIDTH) && detector.boring_streak >= ROWS_FOR_REINIT) {
    char reason[ODCA_END_MAX];
    strncpy(reason, detector.boring_reason, sizeof reason);
    Serial.print("generation ");
    Serial.print(generation);
    Serial.print("  ");
    reinitialize(reason);
  }

  unsigned long now = millis();
  if (now - last_report_ms >= 2000) {
    // total_generation is monotonic (unlike generation, which a reinit
    // resets), so this never underflows however many reinits happened
    // since the last report — the bug caught in the first live run,
    // where the subtraction went negative on unsigned integers and the
    // wraparound came out as either an absurdly huge or an implausibly
    // tiny "rate".
    unsigned long long done = total_generation - total_at_last_report;
    unsigned long elapsed_ms = now - last_report_ms;
    Serial.print("generation ");
    Serial.print(generation);
    Serial.print("  (");
    Serial.print((unsigned long)(done * 1000ULL / elapsed_ms));
    Serial.println(" gen/s)");
    total_at_last_report = total_generation;
    last_report_ms = now;
  }
}
