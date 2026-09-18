// ODCA boring detector (REQTS.md section 3, R-A). Portable C, no
// dependencies, no dynamic allocation: every buffer is fixed-size and
// caller-owned, sized by the constants below.
//
// This module has no notion of a display. Since 3.72.0/3.73.0, R-A1's
// two windows are fixed generation counts, the same on every run and
// every implementation, never derived from rows or touched by a resize;
// the only two places screen size legitimately enters auto-initialization
// (R-A2's re-init trigger, R-K13's paused zip) are the caller's concern,
// not this module's — it just classifies generations and tracks a
// consecutive-boring streak.
#ifndef ODCA_BORING_H
#define ODCA_BORING_H

#include "odca_engine.h"

#ifdef __cplusplus
extern "C" {
#endif

// The largest row this module supports: fixed-size internal storage, no
// allocation. Comfortably covers the MCU's own 320-cell width and every
// conformance vector.
#define ODCA_MAX_WIDTH 512

// R-A1's two windows (3.72.0): fixed, independent of the display.
#define ODCA_REPEAT_WINDOW 4000
#define ODCA_STAGNATION_WINDOW 1600

// Room for the longest R-O6 / R-E2 end text this module writes
// ("repeating (period <n>)" for any period a real run will ever reach,
// "states 1, 2, 3 extinct", or "survived").
#define ODCA_END_MAX 48

// odca_detector and odca_lifetime_result below are large fixed structs
// (the repetition window alone is ODCA_REPEAT_WINDOW * 8 bytes): give
// them static or global storage, never a stack local, especially on the
// MCU.

// ---------------------------------------------------------------- R-A1 census

// Which of the 4 states `rule` can ever produce (R-A1: "some state that
// the current rule can produce"), as a bitmask, bit k set iff state k
// appears anywhere among the rule's 20 table entries — see odca_engine.h.

// R-A1's extinction clause on one row: writes the R-O6 message
// ("state 3 extinct", "states 1, 2 extinct") to `end` (room for
// ODCA_END_MAX bytes) and returns 1 when some producible state is
// extinct and none is a living minority (present, under 10% of the
// row); returns 0, leaving `end` untouched, otherwise.
// `minority_population`, if not NULL, always receives the total cells in
// living-minority states (R-A1's stagnation input) regardless of the
// return value.
int odca_census(const unsigned char *row, int width, unsigned char producible_mask,
                char *end, int *minority_population);

// -------------------------------------------------------------- R-E2 lifetime

typedef struct {
    int generations;         // the count of generations computed
    char end[ODCA_END_MAX];  // the R-O6 extinction text, "repeating (period N)", or "survived"
} odca_lifetime_result;

// Evolve `row` (width cells) under `rule`, wrap mode, until the first
// generation boring by extinction (R-A1's first clause) or that confirms
// a cycle by Brent's algorithm — as the interactive detector below runs
// it from a fresh seed, so this and a live session agree on the
// generation a repeating seed is measured at — or `cap` generations
// without either (R-E2). Does not modify `row`. width must be
// <= ODCA_MAX_WIDTH.
void odca_lifetime(const unsigned char *row, int width, const odca_rule *rule,
                   int cap, odca_lifetime_result *out);

// Brent's cycle detection (R-A1's second repetition mechanism): one saved
// row, refreshed at powers of two; shared by odca_lifetime (a fresh,
// local instance each call) and odca_detector (one persisting across
// calls), so the two can never disagree about when a cycle is confirmed.
typedef struct {
    unsigned char has_snapshot;
    unsigned char snapshot[ODCA_MAX_WIDTH];
    int power;
    int steps;
    int period;  // 0 until confirmed; fixed thereafter until reset
} odca_brent_state;

// ------------------------------------------------------- R-A interactive detector

// The full boring detector (R-A1), tracked continuously across many
// generations of one running automaton.
typedef struct {
    unsigned char producible_mask;
    odca_brent_state brent;

    // Window repetition: the last ODCA_REPEAT_WINDOW rows, as hashes
    // (R-A1's first repetition mechanism; a 64-bit hash makes a false
    // match astronomically unlikely at this window size, and this module
    // never stores full rows across the window for exactly that reason —
    // ODCA_REPEAT_WINDOW full rows would be tens of times bigger for no
    // detection benefit).
    unsigned long long repeat_hashes[ODCA_REPEAT_WINDOW];
    int repeat_next;    // where the next hash is written, wrapping
    int repeat_filled;  // how many of the array's slots are currently valid (caps at the window)

    // Stagnation: minority population over the last ODCA_STAGNATION_WINDOW
    // generations.
    unsigned short stagnation_counts[ODCA_STAGNATION_WINDOW];
    int stagnation_next;
    int stagnation_filled;

    // R-A2's input: how many generations in a row have been boring, and
    // why the most recent one was (R-A1's order of precedence). The
    // caller decides what "boring long enough" means (R-A2, R-K13); this
    // struct has no rows of its own.
    int boring_streak;
    char boring_reason[ODCA_END_MAX];
} odca_detector;

// Set the rule and reset everything below (R-A3) — call once at startup
// and on every rule change.
void odca_detector_set_rule(odca_detector *det, const odca_rule *rule);

// R-A3: reset without changing the rule — call on every re-initialization,
// manual or automatic.
void odca_detector_reset(odca_detector *det);

// Classify one newly computed generation (R-A1) and fold it into the
// detector's running state, extending or resetting the consecutive-
// boring streak. `row` is the generation just computed, not the seed row
// (R-A1: "the seed row itself is not classified" — do not call this for
// generation 0). Returns 1 if this generation was boring (and
// det->boring_reason says why), 0 otherwise.
int odca_detector_observe(odca_detector *det, const unsigned char *row, int width);

#ifdef __cplusplus
}
#endif

#endif
