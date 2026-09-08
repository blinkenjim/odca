/* The play script parser (REQTS R-X7), one C parser shared by every
   implementation: flex/bison sources in script/, generated C checked in
   beside each implementation (script/regen). show_parse returns a malloc'd
   JSON string describing the script or its first error:

     {"ok":true,"statements":[{"line":1,"import":"a.odca"},{"line":2,"play":true}]}
     {"ok":false,"line":3,"column":1,"message":"syntax error, ..."}

   Lines and columns count from 1. Free the string with show_free. */
#ifndef SHOW_H
#define SHOW_H
char *show_parse(const char *text);
void show_free(char *json);
#endif
