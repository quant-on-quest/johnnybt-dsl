/* Locale-independent binary64 conversion shared by the compiler and JSON.
 * Define _GNU_SOURCE before any system header in callers on glibc.
 */
#ifndef JOHNNY_DSL_DECIMAL_H
#define JOHNNY_DSL_DECIMAL_H

#include <locale.h>
#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#ifdef __APPLE__
#include <xlocale.h>
#endif

static double johnny_decimal_read(const char *text, char **tail) {
#ifdef _WIN32
  _locale_t numeric = _create_locale(LC_NUMERIC, "C");
  if (!numeric) { if (tail) *tail = (char *)text; return 0.0; }
  double value = _strtod_l(text, tail, numeric);
  _free_locale(numeric);
#else
  locale_t numeric = newlocale(LC_NUMERIC_MASK, "C", (locale_t)0);
  if (!numeric) { if (tail) *tail = (char *)text; return 0.0; }
  double value = strtod_l(text, tail, numeric);
  freelocale(numeric);
#endif
  return value;
}

static int johnny_decimal_write(char *text, size_t capacity, double value) {
#ifdef _WIN32
  _locale_t numeric = _create_locale(LC_NUMERIC, "C");
  if (!numeric) return -1;
  int length = _snprintf_l(text, capacity, "%.17g", numeric, value);
  _free_locale(numeric);
#else
  locale_t numeric = newlocale(LC_NUMERIC_MASK, "C", (locale_t)0);
  if (!numeric) return -1;
  locale_t previous = uselocale(numeric);
  if (!previous) { freelocale(numeric); return -1; }
  int length = snprintf(text, capacity, "%.17g", value);
  uselocale(previous);
  freelocale(numeric);
#endif
  return length;
}

#endif
