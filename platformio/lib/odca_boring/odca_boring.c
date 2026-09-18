#include "odca_boring.h"

#include <stdio.h>
#include <string.h>

int odca_census(const unsigned char *row, int width, unsigned char producible_mask,
                char *end, int *minority_population) {
    int counts[ODCA_STATES] = {0, 0, 0, 0};
    for (int i = 0; i < width; i++) counts[row[i]]++;

    int extinct[ODCA_STATES], extinct_count = 0;
    int minority_count = 0, population = 0;
    for (int s = 0; s < ODCA_STATES; s++) {
        if (!(producible_mask & (unsigned char)(1u << s))) continue;
        if (counts[s] == 0) {
            extinct[extinct_count++] = s;
        } else if ((double)counts[s] < 0.10 * (double)width) {  // R-A1: a living minority, < 10%
            minority_count++;
            population += counts[s];
        }
    }
    if (minority_population) *minority_population = population;
    if (extinct_count == 0 || minority_count != 0) return 0;  // R-A1: extinction only counts once no minority remains

    // At most 3 states can ever be reported (generation 1 onward, cells
    // hold only producible states, so at least one survives): the longest
    // possible message, "states 0, 1, 2 extinct", is nowhere near
    // ODCA_END_MAX, so no truncation bookkeeping is needed here.
    int pos = snprintf(end, ODCA_END_MAX, "state%s ", extinct_count > 1 ? "s" : "");
    for (int i = 0; i < extinct_count; i++) {
        pos += snprintf(end + pos, (size_t)(ODCA_END_MAX - pos), "%s%d", i ? ", " : "", extinct[i]);
    }
    snprintf(end + pos, (size_t)(ODCA_END_MAX - pos), " extinct");
    return 1;
}

// FNV-1a 64-bit: simple, dependency-free, and at ODCA_REPEAT_WINDOW (4000)
// entries a collision is astronomically unlikely (this is art, not a
// security boundary) — storing a hash instead of the full row is what
// keeps the window's memory in the tens of KB instead of hundreds.
static unsigned long long hash_row(const unsigned char *row, int width) {
    unsigned long long h = 1469598103934665603ULL;
    for (int i = 0; i < width; i++) {
        h ^= row[i];
        h *= 1099511628211ULL;
    }
    return h;
}

static void brent_reset(odca_brent_state *b) {
    b->has_snapshot = 0;
    b->power = 1;
    b->steps = 0;
    b->period = 0;
}

// Returns 1 the generation a cycle is confirmed; does nothing once
// already confirmed (matching the reference implementations, which stop
// comparing once cycle_period/cyclePeriod is set).
static int brent_step(odca_brent_state *b, const unsigned char *row, int width) {
    if (b->period != 0) return 0;
    if (!b->has_snapshot) {
        memcpy(b->snapshot, row, (size_t)width);
        b->has_snapshot = 1;
        return 0;
    }
    b->steps++;
    if (memcmp(row, b->snapshot, (size_t)width) == 0) {
        b->period = b->steps;
        return 1;
    }
    if (b->steps == b->power) {
        memcpy(b->snapshot, row, (size_t)width);
        b->power *= 2;
        b->steps = 0;
    }
    return 0;
}

void odca_lifetime(const unsigned char *row, int width, const odca_rule *rule,
                   int cap, odca_lifetime_result *out) {
    unsigned char producible_mask = odca_rule_producible_mask(rule);
    unsigned char a[ODCA_MAX_WIDTH], b[ODCA_MAX_WIDTH];
    unsigned char *cur = a, *next = b;
    memcpy(cur, row, (size_t)width);

    odca_brent_state brent;
    brent_reset(&brent);

    for (int gen = 0; gen < cap; gen++) {
        odca_step_wrap(cur, width, rule, next);

        char end[ODCA_END_MAX];
        if (odca_census(next, width, producible_mask, end, NULL)) {
            out->generations = gen + 1;
            strncpy(out->end, end, ODCA_END_MAX - 1);
            out->end[ODCA_END_MAX - 1] = '\0';
            return;
        }
        if (brent_step(&brent, next, width)) {
            out->generations = gen + 1;
            snprintf(out->end, ODCA_END_MAX, "repeating (period %d)", brent.period);
            return;
        }
        unsigned char *tmp = cur; cur = next; next = tmp;
    }
    out->generations = cap;
    strcpy(out->end, "survived");
}

static void detector_clear_state(odca_detector *det) {
    brent_reset(&det->brent);
    det->repeat_next = 0;
    det->repeat_filled = 0;
    det->stagnation_next = 0;
    det->stagnation_filled = 0;
    det->boring_streak = 0;
    det->boring_reason[0] = '\0';
}

void odca_detector_set_rule(odca_detector *det, const odca_rule *rule) {
    det->producible_mask = odca_rule_producible_mask(rule);
    detector_clear_state(det);
}

void odca_detector_reset(odca_detector *det) {
    detector_clear_state(det);
}

int odca_detector_observe(odca_detector *det, const unsigned char *row, int width) {
    char extinction_end[ODCA_END_MAX];
    int minority_population = 0;
    int extinct_now = odca_census(row, width, det->producible_mask, extinction_end, &minority_population);

    int cycle_confirmed_now = brent_step(&det->brent, row, width);
    (void)cycle_confirmed_now;  // the reason only needs det->brent.period, not the instant it was set

    // Window repetition (R-A1's first repetition mechanism): checked
    // against the window as it stood before this row, so a row is never
    // seen as recurring against itself.
    unsigned long long h = hash_row(row, width);
    int window_repeating = 0;
    for (int i = 0; i < det->repeat_filled; i++) {
        if (det->repeat_hashes[i] == h) { window_repeating = 1; break; }
    }
    det->repeat_hashes[det->repeat_next] = h;
    det->repeat_next = (det->repeat_next + 1) % ODCA_REPEAT_WINDOW;
    if (det->repeat_filled < ODCA_REPEAT_WINDOW) det->repeat_filled++;

    // Stagnation: the minority population over the fixed window; only
    // evaluated once the window has fully filled (R-A1).
    det->stagnation_counts[det->stagnation_next] = (unsigned short)minority_population;
    det->stagnation_next = (det->stagnation_next + 1) % ODCA_STAGNATION_WINDOW;
    if (det->stagnation_filled < ODCA_STAGNATION_WINDOW) det->stagnation_filled++;
    int stagnant = 0;
    if (det->stagnation_filled == ODCA_STAGNATION_WINDOW) {
        unsigned short lo = det->stagnation_counts[0], hi = det->stagnation_counts[0];
        long sum = 0;
        for (int i = 0; i < ODCA_STAGNATION_WINDOW; i++) {
            unsigned short v = det->stagnation_counts[i];
            if (v < lo) lo = v;
            if (v > hi) hi = v;
            sum += v;
        }
        double mean = (double)sum / (double)ODCA_STAGNATION_WINDOW;
        stagnant = mean > 0.0 && ((double)(hi - lo) / mean) < 0.25;
    }

    // R-A1's order of precedence: extinction, confirmed cycle, window
    // repetition, stagnation.
    det->boring_reason[0] = '\0';
    int boring = 1;
    if (extinct_now) {
        strncpy(det->boring_reason, extinction_end, ODCA_END_MAX - 1);
        det->boring_reason[ODCA_END_MAX - 1] = '\0';
    } else if (det->brent.period != 0) {
        snprintf(det->boring_reason, ODCA_END_MAX, "repeating (period %d)", det->brent.period);
    } else if (window_repeating) {
        strcpy(det->boring_reason, "repeating");
    } else if (stagnant) {
        strcpy(det->boring_reason, "stagnant");
    } else {
        boring = 0;
    }

    det->boring_streak = boring ? det->boring_streak + 1 : 0;
    return boring;
}
