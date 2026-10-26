/* Functional core: no device access, so it runs in host tests. */
#ifndef BUILD_INFO_H_
#define BUILD_INFO_H_

#include <stddef.h>
#include <stdint.h>

/* Writes "<major>.<minor>.<patch>" into buf. Returns length, or -ENOSPC if buf is too small. */
int build_info_format(char *buf, size_t len, uint8_t major, uint8_t minor, uint8_t patch);

#endif
