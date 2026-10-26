/*
 * Thermal core: moving average, plausibility and hysteresis classification in milli-degC.
 * Pure C, no Zephyr headers: runs unchanged in host tests (native_sim). REQ-2, REQ-3, REQ-6, REQ-7
 */
#ifndef THERMAL_H_
#define THERMAL_H_

#include <stddef.h>
#include <stdint.h>

#define THERMAL_AVG_LEN 8U
/* Plausibility window for a die sensor (industrial junction range); also the threshold range. */
#define THERMAL_MIN_MC (-40000)
#define THERMAL_MAX_MC 125000

enum thermal_state {
	THERMAL_NORMAL,
	THERMAL_WARM,
	THERMAL_HOT,
};

struct thermal_cfg {
	int32_t warm_mc; /* enter WARM at or above */
	int32_t hot_mc;  /* enter HOT at or above */
	int32_t hyst_mc; /* leave a state only below its threshold minus this */
};

struct thermal {
	struct thermal_cfg cfg;
	int32_t win[THERMAL_AVG_LEN];
	int32_t sum; /* <= 8 * 125000: fits int32 */
	uint8_t idx;
	uint8_t count;
	int32_t avg_mc;
	int32_t min_mc;
	int32_t max_mc;
	enum thermal_state state;
};

/* Returns 0, or -EINVAL for an invalid configuration. */
int thermal_init(struct thermal *t, const struct thermal_cfg *cfg);
/* Keeps the hysteresis; -EINVAL unless MIN <= warm < hot <= MAX and hot - warm > hysteresis. */
int thermal_set_thresholds(struct thermal *t, int32_t warm_mc, int32_t hot_mc);
/* Adds one sample. -ERANGE for an implausible sample (state and average unchanged). */
int thermal_update(struct thermal *t, int32_t sample_mc);
const char *thermal_state_str(enum thermal_state s);
/* "31.250" / "-0.005". Returns the length, or -ENOSPC if buf is too small. */
int thermal_fmt_mc(char *buf, size_t len, int32_t mc);

#endif /* THERMAL_H_ */
