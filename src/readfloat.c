/* Replace the pinned mruby's approximate decimal reader at build time.
 * Keep its decimal-prefix API while using correctly rounded C-locale strtod.
 * This file is compiled instead of upstream src/readfloat.c; no vendor edits.
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <string.h>
#include <float.h>
#include <mruby.h>
#include "../mrbgems/mruby-json/include/decimal.h"

#if defined(MRB_USE_FLOAT32) || defined(MRB_NO_FLOAT)
#error "johnnybt_dsl requires IEEE binary64 floats"
#endif
#if FLT_RADIX != 2 || DBL_MANT_DIG != 53 || DBL_MAX_EXP != 1024
#error "johnnybt_dsl requires IEEE binary64 doubles"
#endif
typedef char johnny_binary64_size[(sizeof(mrb_float) == sizeof(double)) ? 1 : -1];

MRB_API mrb_bool
mrb_read_float(const char *text, char **endp, double *value) {
  const char *start = text;
  while (*start == ' ' || (*start >= '\t' && *start <= '\r')) start++;
  const char *cursor = start;
  if (*cursor == '+' || *cursor == '-') cursor++;
  int digits = 0;
  while (*cursor >= '0' && *cursor <= '9') { cursor++; digits = 1; }
  if (*cursor == '.') {
    cursor++;
    while (*cursor >= '0' && *cursor <= '9') { cursor++; digits = 1; }
  }
  if (!digits) {
    if (endp) *endp = (char *)text;
    *value = 0.0;
    return FALSE;
  }
  if (*cursor == 'e' || *cursor == 'E') {
    const char *exponent = cursor + 1;
    if (*exponent == '+' || *exponent == '-') exponent++;
    if (*exponent >= '0' && *exponent <= '9') {
      do { exponent++; } while (*exponent >= '0' && *exponent <= '9');
      cursor = exponent;
    }
  }
  size_t length = (size_t)(cursor - start);
  char local[128];
  char *decimal = length < sizeof(local) ? local : (char *)malloc(length + 1);
  if (!decimal) {
    if (endp) *endp = (char *)text;
    *value = 0.0;
    return FALSE;
  }
  memcpy(decimal, start, length);
  decimal[length] = '\0';
  char *tail;
  *value = johnny_decimal_read(decimal, &tail);
  mrb_bool converted = tail == decimal + length;
  if (endp) *endp = (char *)(converted ? cursor : text);
  if (decimal != local) free(decimal);
  return converted;
}
