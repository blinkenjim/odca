/* Play script grammar (REQTS R-X7). Regenerate with script/regen.

   One statement per line; `#` starts a comment; blank lines are allowed.
     import <file>   a bare word or a double-quoted string
     play            at most once, after every import
   The parser emits JSON (show.h); the first error ends the parse. */
%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "show.h"
#include "show_internal.h"
#include "show.tab.h"
#include "show.lex.h"
#define scanner ctx->scanner

static void showyyerror(YYLTYPE *loc, struct show_ctx *ctx, const char *msg);
static void emit(struct show_ctx *ctx, const char *prefix, const char *text);
static char *copy_prefix(const char *s, size_t n) {  /* strndup, which C11 lacks */
    char *out = malloc(n + 1);
    if (out) { memcpy(out, s, n); out[n] = '\0'; }
    return out;
}
%}

%pure-parser
%name-prefix="showyy"
%locations
%error-verbose
%parse-param { struct show_ctx *ctx }
%lex-param { void *scanner }
%union { char *str; }

%token END 0 "end of file"
%token IMPORT "import"
%token PLAY "play"
%token NEWLINE "end of line"
%token <str> WORD "word"
%destructor { free($$); } WORD

%%

script
    : /* empty */
    | script statement NEWLINE
    ;

statement
    : IMPORT WORD
        {
            if (ctx->played) show_fail(ctx, @1.first_line, @1.first_column, "import after play");
            else if (!*$2) show_fail(ctx, @2.first_line, @2.first_column, "empty file name");
            else { char line[32]; snprintf(line, sizeof line, "{\"line\":%d,\"import\":", @1.first_line);
                   emit(ctx, line, $2); }
            free($2);
            if (ctx->error) YYABORT;
        }
    | PLAY
        {
            if (ctx->played) show_fail(ctx, @1.first_line, @1.first_column, "play given twice");
            else { char line[32]; snprintf(line, sizeof line, "{\"line\":%d,\"play\":true}", @1.first_line);
                   show_buf_add(&ctx->out, ctx->out.len ? "," : ""); show_buf_add(&ctx->out, line); }
            ctx->played = 1;
            if (ctx->error) YYABORT;
        }
    ;

%%

/* Bison's message, made to read well: an unexpected word is quoted as
   written, and "end of file" drops out of an expectation list that has
   anything else in it (it is always allowed between statements). */
static void showyyerror(YYLTYPE *loc, struct show_ctx *ctx, const char *msg) {
    struct show_buf b = { NULL, 0, 0 };
    const char *word = strstr(msg, "unexpected word");
    const char *eof = strstr(msg, "expecting end of file or ");
    const char *p = msg;
    if (word) {
        show_buf_add(&b, "");
        size_t head = (size_t)(word - msg) + strlen("unexpected word");
        char *start = copy_prefix(msg, head);
        show_buf_add(&b, start);
        free(start);
        show_buf_add(&b, " ");
        show_buf_add(&b, showyyget_text(scanner));
        p = word + strlen("unexpected word");
    }
    if (eof && eof >= p) {
        char *middle = copy_prefix(p, (size_t)(eof - p));
        show_buf_add(&b, middle);
        free(middle);
        show_buf_add(&b, "expecting ");
        p = eof + strlen("expecting end of file or ");
    }
    show_buf_add(&b, p);
    show_fail(ctx, loc->first_line, loc->first_column, b.s);
    free(b.s);
}

static void emit(struct show_ctx *ctx, const char *prefix, const char *text) {
    show_buf_add(&ctx->out, ctx->out.len ? "," : "");
    show_buf_add(&ctx->out, prefix);
    show_buf_add_json_string(&ctx->out, text);
    show_buf_add(&ctx->out, "}");
}

void show_fail(struct show_ctx *ctx, int line, int column, const char *message) {
    if (ctx->error) return;  /* the first error stands */
    ctx->error = strdup(message);
    ctx->error_line = line;
    ctx->error_column = column;
}

void show_buf_add(struct show_buf *b, const char *text) {
    size_t n = strlen(text);
    if (b->len + n + 1 > b->cap) {
        size_t cap = b->cap ? b->cap : 256;
        while (b->len + n + 1 > cap) cap *= 2;
        char *s = realloc(b->s, cap);
        if (!s) return;
        b->s = s;
        b->cap = cap;
    }
    memcpy(b->s + b->len, text, n + 1);
    b->len += n;
}

/* A JSON string literal: quotes and backslashes escaped, control
   characters as \u00XX, everything else (UTF-8 included) as it is. */
void show_buf_add_json_string(struct show_buf *b, const char *text) {
    show_buf_add(b, "\"");
    for (const unsigned char *p = (const unsigned char *)text; *p; p++) {
        char piece[8];
        if (*p == '"') strcpy(piece, "\\\"");
        else if (*p == '\\') strcpy(piece, "\\\\");
        else if (*p < 0x20) snprintf(piece, sizeof piece, "\\u%04x", *p);
        else { piece[0] = (char)*p; piece[1] = '\0'; }
        show_buf_add(b, piece);
    }
    show_buf_add(b, "\"");
}

#undef scanner
char *show_parse(const char *text) {
    struct show_ctx ctx;
    memset(&ctx, 0, sizeof ctx);
    ctx.line = ctx.col = 1;
    showyylex_init_extra(&ctx, &ctx.scanner);
    YY_BUFFER_STATE buf = showyy_scan_string(text, ctx.scanner);
    int status = showyyparse(&ctx);
    showyy_delete_buffer(buf, ctx.scanner);
    showyylex_destroy(ctx.scanner);
    struct show_buf out = { NULL, 0, 0 };
    if (status == 0 && !ctx.error) {
        show_buf_add(&out, "{\"ok\":true,\"statements\":[");
        show_buf_add(&out, ctx.out.s ? ctx.out.s : "");
        show_buf_add(&out, "]}");
    } else {
        char where[64];
        snprintf(where, sizeof where, "{\"ok\":false,\"line\":%d,\"column\":%d,\"message\":",
                 ctx.error ? ctx.error_line : 0, ctx.error ? ctx.error_column : 0);
        show_buf_add(&out, where);
        show_buf_add_json_string(&out, ctx.error ? ctx.error : "parse failed");
        show_buf_add(&out, "}");
    }
    free(ctx.out.s);
    free(ctx.error);
    return out.s;
}

void show_free(char *json) { free(json); }
