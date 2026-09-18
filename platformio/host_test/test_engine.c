// Host-side conformance runner for platformio/lib/odca_engine (REQTS R-M):
// checks it against conformance/vectors.json's count_vectors, valid and
// invalid rule IDs, and evolution cases — everything the engine touches.
// lifetimes (R-E2) waits for the boring detector, a later increment.
//
// Per TESTS.md's runner contract: every case runs (no skips among the
// ones in scope here), and any mismatch is reported by the case's own
// name, with the program exiting nonzero.
#include <stdio.h>
#include <string.h>

#include "odca_engine.h"
#include "vectors_data.h"

#define MAX_WIDTH 128  // every evolution case's row is well under this

static int failures = 0;

static void fail(const char *what, const char *detail) {
    printf("FAIL %s: %s\n", what, detail);
    failures++;
}

static void row_to_string(const unsigned char *cells, int width, char *out) {
    for (int i = 0; i < width; i++) out[i] = (char)('0' + cells[i]);
    out[width] = '\0';
}

static void test_count_vectors(void) {
    for (int i = 0; i < gen_count_vectors_count; i++) {
        for (int k = 0; k < 4; k++) {
            if (odca_count_vectors[i][k] != gen_count_vectors[i][k]) {
                char msg[64];
                snprintf(msg, sizeof msg, "index %d component %d: got %d, want %d",
                         i, k, odca_count_vectors[i][k], gen_count_vectors[i][k]);
                fail("count_vectors", msg);
                return;
            }
        }
    }
    printf("PASS count_vectors (%d)\n", gen_count_vectors_count);
}

static void test_valid_rule_ids(void) {
    int ok = 0;
    for (int i = 0; i < gen_valid_rule_ids_count; i++) {
        const char *id = gen_valid_rule_ids[i];
        odca_rule rule;
        if (!odca_rule_from_id(id, &rule)) {
            fail("valid_rule_ids", id);
            continue;
        }
        char reemitted[ODCA_RULE_SIZE + 1];
        odca_rule_to_id(&rule, reemitted);
        if (strcmp(reemitted, id) != 0) {
            char msg[128];
            snprintf(msg, sizeof msg, "%s round-tripped as %s", id, reemitted);
            fail("valid_rule_ids", msg);
            continue;
        }
        ok++;
    }
    if (ok == gen_valid_rule_ids_count) printf("PASS valid_rule_ids (%d)\n", ok);
}

static void test_invalid_rule_ids(void) {
    int ok = 0;
    for (int i = 0; i < gen_invalid_rule_ids_count; i++) {
        const char *id = gen_invalid_rule_ids[i];
        odca_rule rule;
        if (odca_rule_from_id(id, &rule)) {
            fail("invalid_rule_ids", id[0] ? id : "(empty string)");
            continue;
        }
        ok++;
    }
    if (ok == gen_invalid_rule_ids_count) printf("PASS invalid_rule_ids (%d)\n", ok);
}

static void test_evolution(void) {
    int ok = 0;
    for (int i = 0; i < gen_evolution_count; i++) {
        const gen_evolution_case *c = &gen_evolution[i];
        odca_rule rule;
        if (!odca_rule_from_id(c->rule, &rule)) {
            fail(c->name, "rule ID in the vector itself did not parse");
            continue;
        }
        int width = (int)strlen(c->initial);
        unsigned char a[MAX_WIDTH], b[MAX_WIDTH];
        unsigned char *cur = a, *next = b;
        for (int i0 = 0; i0 < width; i0++) cur[i0] = (unsigned char)(c->initial[i0] - '0');

        int case_ok = 1;
        for (int g = 0; g < c->generations; g++) {
            if (c->wrap) odca_step_wrap(cur, width, &rule, next);
            else odca_step_fixed(cur, width, &rule, next);
            char got[MAX_WIDTH + 1];
            row_to_string(next, width, got);
            if (strcmp(got, c->expected[g]) != 0) {
                char msg[256];
                snprintf(msg, sizeof msg, "generation %d: got %s, want %s",
                         g + 1, got, c->expected[g]);
                fail(c->name, msg);
                case_ok = 0;
                break;
            }
            unsigned char *tmp = cur; cur = next; next = tmp;
        }
        if (case_ok) ok++;
    }
    if (ok == gen_evolution_count) printf("PASS evolution (%d cases)\n", ok);
}

int main(void) {
    test_count_vectors();
    test_valid_rule_ids();
    test_invalid_rule_ids();
    test_evolution();
    if (failures == 0) {
        printf("all conformance cases passed\n");
        return 0;
    }
    printf("%d failure(s)\n", failures);
    return 1;
}
