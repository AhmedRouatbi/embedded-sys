/* Thermal monitor service: owns the sampler thread, LEDs, button and watchdog. */
#ifndef MONITOR_H_
#define MONITOR_H_

#include <stdbool.h>
#include <stdint.h>

#include "thermal.h"

struct monitor_status {
	int32_t last_mc;
	int32_t avg_mc;
	int32_t min_mc;
	int32_t max_mc;
	int32_t warm_mc;
	int32_t hot_mc;
	enum thermal_state state;
	bool fault;
	bool reporting;
	uint32_t samples;
	uint32_t errors;
	uint32_t presses;
};

/* Checks devices, configures LEDs/button/watchdog, starts sampling. 0 or negative errno. */
int monitor_start(void);
/* Snapshot for the shell. -EBUSY if the state lock is not available in time. */
int monitor_get(struct monitor_status *out);
/* -EINVAL (see thermal_set_thresholds) or -EBUSY. */
int monitor_set_thresholds(int32_t warm_mc, int32_t hot_mc);

#endif /* MONITOR_H_ */
