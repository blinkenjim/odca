#include "odca_engine.h"

// R-M6's table, transcribed verbatim so it can be checked against the spec
// by eye: index i is (n0,n1,n2,n3), n0+n1+n2+n3 == 3.
const unsigned char odca_count_vectors[ODCA_RULE_SIZE][4] = {
    {0, 0, 0, 3}, {0, 0, 1, 2}, {0, 0, 2, 1}, {0, 0, 3, 0},
    {0, 1, 0, 2}, {0, 1, 1, 1}, {0, 1, 2, 0}, {0, 2, 0, 1},
    {0, 2, 1, 0}, {0, 3, 0, 0}, {1, 0, 0, 2}, {1, 0, 1, 1},
    {1, 0, 2, 0}, {1, 1, 0, 1}, {1, 1, 1, 0}, {1, 2, 0, 0},
    {2, 0, 0, 1}, {2, 0, 1, 0}, {2, 1, 0, 0}, {3, 0, 0, 0},
};

// The lookup trick (R-M11's informative note): weight states 0,1,2,3 as
// 0,1,4,16 and sum a neighborhood's three weights. No neighborhood can
// carry more than 3 of any weight, so the sum n1 + 4*n2 + 16*n3 uniquely
// encodes the count vector (n0 is implied, 3 minus the rest), with no
// collisions between distinct vectors — this is why `dense` needs only
// 49 slots (3*16 + 1) though most sit unused between the 20 live ones.
static const unsigned char odca_weight[ODCA_STATES] = {0, 1, 4, 16};

static void build_dense(odca_rule *rule) {
    for (int i = 0; i < ODCA_RULE_SIZE; i++) {
        unsigned char n1 = odca_count_vectors[i][1];
        unsigned char n2 = odca_count_vectors[i][2];
        unsigned char n3 = odca_count_vectors[i][3];
        rule->dense[n1 + 4 * n2 + 16 * n3] = rule->states[i];
    }
}

void odca_rule_from_states(const unsigned char *states, odca_rule *out) {
    for (int i = 0; i < ODCA_RULE_SIZE; i++) {
        out->states[i] = states[i];
    }
    build_dense(out);
}

int odca_rule_from_id(const char *id, odca_rule *out) {
    size_t len = 0;
    while (id[len] != '\0' && len <= ODCA_RULE_SIZE) len++;
    if (len != ODCA_RULE_SIZE) return 0;  // R-M8: exactly 20 characters
    unsigned char states[ODCA_RULE_SIZE];
    for (int i = 0; i < ODCA_RULE_SIZE; i++) {
        char ch = id[i];
        if (ch < '0' || ch > '3') return 0;  // R-M8: only digits 0-3
        states[i] = (unsigned char)(ch - '0');
    }
    odca_rule_from_states(states, out);
    return 1;
}

void odca_rule_to_id(const odca_rule *rule, char *out) {
    for (int i = 0; i < ODCA_RULE_SIZE; i++) {
        out[i] = (char)('0' + rule->states[i]);
    }
    out[ODCA_RULE_SIZE] = '\0';
}

void odca_step_wrap(const unsigned char *cells, int width,
                    const odca_rule *rule, unsigned char *out) {
    for (int i = 0; i < width; i++) {
        int left = (i == 0) ? width - 1 : i - 1;
        int right = (i == width - 1) ? 0 : i + 1;
        unsigned sum = odca_weight[cells[left]] + odca_weight[cells[i]]
                     + odca_weight[cells[right]];
        out[i] = rule->dense[sum];
    }
}

unsigned char odca_rule_producible_mask(const odca_rule *rule) {
    unsigned char mask = 0;
    for (int i = 0; i < ODCA_RULE_SIZE; i++) {
        mask |= (unsigned char)(1u << rule->states[i]);
    }
    return mask;
}

void odca_step_fixed(const unsigned char *cells, int width,
                     const odca_rule *rule, unsigned char *out) {
    for (int i = 0; i < width; i++) {
        unsigned left_w = (i == 0) ? 0 : odca_weight[cells[i - 1]];
        unsigned right_w = (i == width - 1) ? 0 : odca_weight[cells[i + 1]];
        unsigned sum = left_w + odca_weight[cells[i]] + right_w;
        out[i] = rule->dense[sum];
    }
}
