// ODCA engine (REQTS.md section 1, R-M): a four-state, count-based,
// radius-1 cellular automaton. Portable C, no dependencies, no dynamic
// allocation — every buffer is caller-owned, so this compiles unchanged
// for a host test build and for the RP2350 firmware.
//
// A cell's next state depends only on how many of its 3-cell neighborhood
// (left, self, right) are in each of the 4 states (R-M5), never on which
// cell holds which state, so a rule is a table of 20 next-states, one per
// possible count vector (n0,n1,n2,n3) with n0+n1+n2+n3 == 3 (R-M6, R-M7).
// A rule's canonical ID (R-M8) is those 20 states, written as digits '0'
// to '3', in the canonical count-vector order of R-M6.
#ifndef ODCA_ENGINE_H
#define ODCA_ENGINE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ODCA_STATES 4      // R-M1
#define ODCA_RULE_SIZE 20  // R-M6, R-M7: one next-state per count vector
#define ODCA_MIN_WIDTH 3   // R-M2

// The 20 canonical count vectors (n0,n1,n2,n3), in the order R-M6 defines
// and rule IDs are indexed by (ascending lexicographic by n0, n1, n2).
extern const unsigned char odca_count_vectors[ODCA_RULE_SIZE][4];

// A rule: `states[i]` is the next state for odca_count_vectors[i] (R-M8),
// raw values 0-3, not ASCII digits. `dense` is the lookup table `step`
// actually uses, indexed by the weighted neighborhood sum described below;
// built once by odca_rule_from_id / odca_rule_from_states, not touched
// directly.
typedef struct {
    unsigned char states[ODCA_RULE_SIZE];
    unsigned char dense[49];  // index = n1 + 4*n2 + 16*n3 (R-M11's informative note)
} odca_rule;

// Parse a 20-character rule ID (digits '0'-'3') into `out`. Returns 1 and
// fills `out` on success; returns 0, leaving `out` unspecified, on the
// wrong length or any other character (R-M8).
int odca_rule_from_id(const char *id, odca_rule *out);

// Build a rule directly from its 20 next-states (each 0-3, in canonical
// count-vector order), skipping ID parsing. `states` must have
// ODCA_RULE_SIZE entries; behavior is undefined if any exceeds 3.
void odca_rule_from_states(const unsigned char *states, odca_rule *out);

// Write the rule's canonical ID: exactly ODCA_RULE_SIZE digit characters
// followed by a NUL, so `out` must have room for ODCA_RULE_SIZE + 1 bytes.
void odca_rule_to_id(const odca_rule *rule, char *out);

// Advance one generation under `rule`, wrap edges (R-M9: "the mode the
// interactive program uses" — cell 0's left neighbor is cell width-1 and
// cell width-1's right neighbor is cell 0). `cells` and `out` must be
// distinct buffers of `width` entries each (states 0-3); `out` receives
// the new row. width must be >= ODCA_MIN_WIDTH.
void odca_step_wrap(const unsigned char *cells, int width,
                    const odca_rule *rule, unsigned char *out);

// As odca_step_wrap, but the fixed edge mode of R-M9: cells beyond either
// edge count as permanently state 0.
void odca_step_fixed(const unsigned char *cells, int width,
                     const odca_rule *rule, unsigned char *out);

// Which of the 4 states `rule` can ever produce, as a bitmask (bit k set
// iff state k appears anywhere among its 20 table entries) — R-A1's
// "some state that the current rule can produce", computed once per rule.
unsigned char odca_rule_producible_mask(const odca_rule *rule);

#ifdef __cplusplus
}
#endif

#endif
