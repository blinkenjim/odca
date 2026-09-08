/* Play script scanner (REQTS R-X7). Regenerate with script/regen. */
%{
#include <stdlib.h>
#include <string.h>
#include "show_internal.h"
#include "show.tab.h"
#define YY_USER_ACTION \
    yylloc->first_line = yyextra->line; yylloc->first_column = yyextra->col; yyextra->col += (int)yyleng;
static char *show_strndup(const char *s, size_t n) {
    char *out = malloc(n + 1);
    if (out) { memcpy(out, s, n); out[n] = '\0'; }
    return out;
}
/* Only a line with a statement on it ends in an end-of-line token, so blank
   and comment-only lines are nothing to the grammar. */
#define TOKEN(t) { yyextra->pending = 1; return t; }
#pragma GCC diagnostic ignored "-Wunused-function"
%}
%option reentrant bison-bridge bison-locations noyywrap nounput noinput
%option prefix="showyy"
%option extra-type="struct show_ctx *"

%%
"import"            TOKEN(IMPORT);
"play"              TOKEN(PLAY);
"shuffle"           TOKEN(SHUFFLE);
\"[^"\n]*\"         { yylval->str = show_strndup(yytext + 1, yyleng - 2); TOKEN(WORD); }
\"[^"\n]*           { show_fail(yyextra, yylloc->first_line, yylloc->first_column, "unterminated quote"); return 0; }
[^ \t\r\n#"]+       { yylval->str = strdup(yytext); TOKEN(WORD); }
"#"[^\n]*           ;
[ \t\r]+            ;
\n                  { yyextra->line++; yyextra->col = 1; if (yyextra->pending) { yyextra->pending = 0; return NEWLINE; } }
<<EOF>>             { if (yyextra->pending) { yyextra->pending = 0; return NEWLINE; } return 0; }
%%
