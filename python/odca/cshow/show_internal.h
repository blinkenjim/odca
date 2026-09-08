/* Shared between the scanner and the parser; not part of the API. */
#ifndef SHOW_INTERNAL_H
#define SHOW_INTERNAL_H
#include <stddef.h>

struct show_buf { char *s; size_t len, cap; };

struct show_ctx {
    void *scanner;
    int line, col;        /* position of the next token, from 1 */
    int pending;          /* a statement is open on the current line: its end of line is due */
    const char *played;   /* the play statement seen, "play" or "shuffle", else NULL */
    struct show_buf out;  /* the statements, as JSON, comma separated */
    char *error;          /* the first error's message, or NULL */
    int error_line, error_column;
};

void show_fail(struct show_ctx *ctx, int line, int column, const char *message);
void show_buf_add(struct show_buf *b, const char *text);
void show_buf_add_json_string(struct show_buf *b, const char *text);
#endif
