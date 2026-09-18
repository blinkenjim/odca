// Host-side check for platformio/lib/odca_boring (REQTS R-A, R-E2):
// odca_lifetime against conformance/vectors.json's own lifetimes cases,
// exactly like test_engine.c does for the engine, plus hand-built cases
// for the interactive detector (odca_detector), which has no golden
// vectors of its own — R-A2/R-A3's auto-init behavior isn't pinned
// cross-language on the desktop either, only property-tested there, so
// this mirrors the same scenarios python/tests and swift Tests use.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "odca_boring.h"
#include "odca_engine.h"
#include "vectors_data.h"

static int failures = 0;

static void fail(const char *what, const char *detail) {
    printf("FAIL %s: %s\n", what, detail);
    failures++;
}

// ------------------------------------------------------------ R-E2 lifetimes

static void test_lifetimes(void) {
    int ok = 0;
    for (int i = 0; i < gen_lifetimes_count; i++) {
        const gen_lifetime_case *c = &gen_lifetimes[i];
        odca_rule rule;
        if (!odca_rule_from_id(c->rule, &rule)) {
            fail(c->name, "rule ID in the vector itself did not parse");
            continue;
        }
        int width = (int)strlen(c->initial);
        unsigned char row[ODCA_MAX_WIDTH];
        for (int k = 0; k < width; k++) row[k] = (unsigned char)(c->initial[k] - '0');

        odca_lifetime_result got;
        odca_lifetime(row, width, &rule, c->cap, &got);
        if (got.generations != c->generations || strcmp(got.end, c->end) != 0) {
            char msg[160];
            snprintf(msg, sizeof msg, "got %d generations, %s; want %d generations, %s",
                     got.generations, got.end, c->generations, c->end);
            fail(c->name, msg);
            continue;
        }
        ok++;
    }
    if (ok == gen_lifetimes_count) printf("PASS lifetimes (%d cases)\n", ok);
}

// ------------------------------------------------------- helpers for the detector tests

// A row that never collides across the many thousands drawn in the
// repetition/Brent tests below: cell k of row i is digit k of i in base 4
// (mask 0 keeps extinction out of the way, so only the mechanism under
// test can make a generation boring).
static void indexed_row(long i, unsigned char *row, int width) {
    for (int k = 0; k < width; k++) {
        row[k] = (unsigned char)((i >> (2 * k)) & 3);
    }
}

static odca_rule make_dummy_rule(void) {
    unsigned char states[ODCA_RULE_SIZE] = {0};
    odca_rule rule;
    odca_rule_from_states(states, &rule);
    return rule;
}

// -------------------------------------------------------------- R-A1 extinction

static void test_extinction(void) {
    // producible = {1, 2}: state 0 never appears in the rule at all, so it
    // is never "producible" and never enters the census.
    unsigned char states[ODCA_RULE_SIZE];
    for (int i = 0; i < ODCA_RULE_SIZE; i++) states[i] = (unsigned char)(1 + i % 2);
    odca_rule rule;
    odca_rule_from_states(states, &rule);
    unsigned char mask = odca_rule_producible_mask(&rule);
    if (mask != ((1u << 1) | (1u << 2))) { fail("extinction", "producible mask"); return; }

    // 1 as a small (5%) living minority, 2 filling the rest: not boring yet.
    unsigned char row[20];
    row[0] = 1;
    for (int i = 1; i < 20; i++) row[i] = 2;
    char end[ODCA_END_MAX];
    int minority = -1;
    if (odca_census(row, 20, mask, end, &minority)) fail("extinction", "1 is still a living minority");
    if (minority != 1) fail("extinction", "minority population should be 1");

    // Now 1 is gone entirely: boring, "state 1 extinct".
    for (int i = 0; i < 20; i++) row[i] = 2;
    if (!odca_census(row, 20, mask, end, NULL)) fail("extinction", "should be boring now");
    else if (strcmp(end, "state 1 extinct") != 0) fail("extinction", end);

    // Two producible states both gone (only a third survives): ascending order.
    unsigned char states3[ODCA_RULE_SIZE];
    for (int i = 0; i < ODCA_RULE_SIZE; i++) states3[i] = (unsigned char)(1 + i % 3);  // {1,2,3}
    odca_rule rule3;
    odca_rule_from_states(states3, &rule3);
    unsigned char mask3 = odca_rule_producible_mask(&rule3);
    unsigned char row3[20];
    for (int i = 0; i < 20; i++) row3[i] = 3;
    if (!odca_census(row3, 20, mask3, end, NULL)) fail("extinction", "1 and 2 both gone: should be boring");
    else if (strcmp(end, "states 1, 2 extinct") != 0) fail("extinction", end);
    else printf("PASS extinction\n");
}

// ------------------------------------------------------- R-A1 repetition window

static void test_repetition_window(void) {
    odca_rule dummy = make_dummy_rule();
    static odca_detector det;
    odca_detector_set_rule(&det, &dummy);
    det.producible_mask = 0;  // isolate from extinction

    static unsigned char rows[ODCA_REPEAT_WINDOW + 1][8];
    for (long i = 0; i <= ODCA_REPEAT_WINDOW; i++) indexed_row(i, rows[i], 8);

    for (int i = 0; i < ODCA_REPEAT_WINDOW; i++) {
        if (odca_detector_observe(&det, rows[i], 8)) { fail("repetition_window", "boring before any repeat"); return; }
    }
    if (det.boring_streak != 0) { fail("repetition_window", "streak should be 0 so far"); return; }
    int boring = odca_detector_observe(&det, rows[0], 8);  // exactly ODCA_REPEAT_WINDOW generations later
    if (!boring || strcmp(det.boring_reason, "repeating") != 0) {
        fail("repetition_window", "row 0 should read as repeating exactly ODCA_REPEAT_WINDOW later");
        return;
    }

    odca_detector_set_rule(&det, &dummy);
    det.producible_mask = 0;
    for (int i = 0; i <= ODCA_REPEAT_WINDOW; i++) odca_detector_observe(&det, rows[i], 8);  // one extra pushes row 0 out
    boring = odca_detector_observe(&det, rows[0], 8);
    if (boring) { fail("repetition_window", "row 0 should be forgotten beyond the window"); return; }
    printf("PASS repetition_window\n");
}

// --------------------------------------------------------- R-A1 stagnation window

static unsigned char stagnation_row[64];

static void fill_row_with_minority(int count) {
    static int order[64];
    for (int i = 0; i < 64; i++) order[i] = i;
    for (int i = 63; i > 0; i--) {
        int j = rand() % (i + 1);
        int t = order[i]; order[i] = order[j]; order[j] = t;
    }
    for (int i = 0; i < 64; i++) stagnation_row[i] = (rand() % 2) ? 2 : 3;
    for (int i = 0; i < count; i++) stagnation_row[order[i]] = 1;
}

static void test_stagnation_window(void) {
    srand(3);
    unsigned char states[ODCA_RULE_SIZE];
    for (int i = 0; i < ODCA_RULE_SIZE; i++) states[i] = (unsigned char)(1 + i % 3);  // producible {1,2,3}
    odca_rule rule;
    odca_rule_from_states(states, &rule);

    static odca_detector det;
    odca_detector_set_rule(&det, &rule);
    for (int g = 0; g < ODCA_STAGNATION_WINDOW - 1; g++) {
        fill_row_with_minority(3);  // 3/64 = 4.7%: a living minority throughout
        if (odca_detector_observe(&det, stagnation_row, 64)) { fail("stagnation_window", "boring before the window fills"); return; }
    }
    if (det.boring_streak != 0) { fail("stagnation_window", "streak should be 0 before the window fills"); return; }
    int fired = 0;
    for (int g = 0; g < 7; g++) {
        fill_row_with_minority(3);
        fired = odca_detector_observe(&det, stagnation_row, 64);
    }
    if (!fired || strcmp(det.boring_reason, "stagnant") != 0) { fail("stagnation_window", "should read stagnant once filled"); return; }
    if (det.boring_streak != 7) { fail("stagnation_window", "streak should be 7"); return; }

    static odca_detector det2;
    odca_detector_set_rule(&det2, &rule);
    for (int g = 0; g < ODCA_STAGNATION_WINDOW + 20; g++) {
        fill_row_with_minority((g % 2 == 0) ? 1 : 5);  // both under 6.4 (10% of 64): swing (5-1)/3 = 1.33, never stagnant
        if (odca_detector_observe(&det2, stagnation_row, 64)) { fail("stagnation_window", "a swinging minority should never be stagnant"); return; }
    }
    printf("PASS stagnation_window\n");
}

// --------------------------------------------------------------- Brent's algorithm

static void test_brent_beyond_the_window(void) {
    odca_rule dummy = make_dummy_rule();
    static odca_detector det;
    odca_detector_set_rule(&det, &dummy);
    det.producible_mask = 0;

    const long transient = 37;
    const long period = ODCA_REPEAT_WINDOW + 500;  // past the fixed repetition window
    static unsigned char rows[ODCA_REPEAT_WINDOW + 500 + 37][8];
    for (long i = 0; i < transient + period; i++) indexed_row(i, rows[i], 8);

    for (long i = 0; i < transient; i++) odca_detector_observe(&det, rows[i], 8);
    long g = 0;
    while (det.brent.period == 0 && g < 10 * period) {
        odca_detector_observe(&det, rows[transient + (g % period)], 8);
        g++;
    }
    if (det.brent.period != period) { fail("brent_beyond_window", "period did not match"); return; }
    char want[ODCA_END_MAX];
    snprintf(want, sizeof want, "repeating (period %ld)", period);
    if (strcmp(det.boring_reason, want) != 0) { fail("brent_beyond_window", det.boring_reason); return; }

    odca_detector_set_rule(&det, &dummy);
    det.producible_mask = 0;
    static unsigned char seven[7][8];
    for (long i = 0; i < 7; i++) indexed_row(i, seven[i], 8);
    for (int i = 0; i < 200; i++) odca_detector_observe(&det, seven[i % 7], 8);
    if (det.brent.period != 7) { fail("brent_beyond_window", "short period (7) not detected exactly"); return; }
    printf("PASS brent_beyond_window\n");
}

// ----------------------------------------------------------------------- R-A3 reset

static void test_reset_clears_everything(void) {
    odca_rule dummy = make_dummy_rule();
    static odca_detector det;
    odca_detector_set_rule(&det, &dummy);
    det.producible_mask = 0;

    static unsigned char rows[ODCA_REPEAT_WINDOW][8];
    for (long i = 0; i < ODCA_REPEAT_WINDOW; i++) indexed_row(i, rows[i], 8);
    for (int i = 0; i < 100; i++) odca_detector_observe(&det, rows[i], 8);
    odca_detector_observe(&det, rows[0], 8);  // a real repeat: streak should be nonzero

    odca_detector_reset(&det);
    if (det.boring_streak != 0 || det.repeat_filled != 0 || det.stagnation_filled != 0 ||
        det.brent.period != 0 || det.brent.has_snapshot != 0 || det.boring_reason[0] != '\0') {
        fail("reset", "reset left state behind");
        return;
    }
    // The same row that just repeated is unremarkable again straight after a reset.
    if (odca_detector_observe(&det, rows[0], 8)) { fail("reset", "should not be boring immediately after a reset"); return; }
    printf("PASS reset\n");
}

int main(void) {
    test_lifetimes();
    test_extinction();
    test_repetition_window();
    test_stagnation_window();
    test_brent_beyond_the_window();
    test_reset_clears_everything();
    if (failures == 0) {
        printf("all boring-detector cases passed\n");
        return 0;
    }
    printf("%d failure(s)\n", failures);
    return 1;
}
