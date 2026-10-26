#include <errno.h>
#include <stdio.h>
#include "build_info.h"

int build_info_format(char *buf, size_t len, uint8_t major, uint8_t minor, uint8_t patch)
{
	int n = snprintf(buf, len, "%u.%u.%u", major, minor, patch);

	return (n < 0 || (size_t)n >= len) ? -ENOSPC : n;
}
