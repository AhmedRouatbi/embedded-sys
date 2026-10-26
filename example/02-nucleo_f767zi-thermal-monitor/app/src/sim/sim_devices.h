/* SIL-only controls for the simulated devices (native_sim build). */
#ifndef SIM_DEVICES_H_
#define SIM_DEVICES_H_

#include <stdint.h>
#include <zephyr/device.h>

/* Value returned by the next sensor reads, in milli-°C. */
void sim_temp_set(const struct device *dev, int32_t mc);

/* Make the next n sensor reads fail with -EIO. */
void sim_temp_fail(const struct device *dev, uint32_t n);

#endif /* SIM_DEVICES_H_ */
