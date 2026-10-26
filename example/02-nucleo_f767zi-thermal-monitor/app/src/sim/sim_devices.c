/*
 * Simulated devices for the SIL build (native_sim only, see boards/native_sim_native_64.overlay).
 * They implement the Zephyr driver APIs that the hardware shell (monitor.c) uses on the board,
 * so monitor.c runs unchanged. The shell (`sim ...`, sim_shell.c) drives them.
 */
#include <errno.h>
#include <zephyr/device.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/drivers/watchdog.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/atomic.h>

#include "sim_devices.h"

LOG_MODULE_REGISTER(sim, LOG_LEVEL_INF);

/* ---------------------------------------------------------------- die-temperature sensor */
#define DT_DRV_COMPAT vnd_sim_temp

struct sim_temp_data {
	atomic_t mc;        /* returned by the next fetch, milli-°C; set by the shell */
	atomic_t fail_left; /* fetches that still fail with -EIO */
	int32_t sample_mc;  /* last fetched value; sampler thread only */
};

static int sim_temp_fetch(const struct device *dev, enum sensor_channel chan)
{
	struct sim_temp_data *d = dev->data;

	if (chan != SENSOR_CHAN_ALL && chan != SENSOR_CHAN_DIE_TEMP) {
		return -ENOTSUP;
	}
	if (atomic_get(&d->fail_left) > 0) { /* one consumer (the sampler): get + dec can't race */
		atomic_dec(&d->fail_left);
		return -EIO;
	}
	d->sample_mc = (int32_t)atomic_get(&d->mc);
	return 0;
}

static int sim_temp_get(const struct device *dev, enum sensor_channel chan, struct sensor_value *val)
{
	const struct sim_temp_data *d = dev->data;

	if (chan != SENSOR_CHAN_DIE_TEMP) {
		return -ENOTSUP;
	}
	return sensor_value_from_milli(val, d->sample_mc);
}

static DEVICE_API(sensor, sim_temp_api) = {
	.sample_fetch = sim_temp_fetch,
	.channel_get = sim_temp_get,
};

void sim_temp_set(const struct device *dev, int32_t mc)
{
	atomic_set(&((struct sim_temp_data *)dev->data)->mc, mc);
}

void sim_temp_fail(const struct device *dev, uint32_t n)
{
	atomic_set(&((struct sim_temp_data *)dev->data)->fail_left, (atomic_val_t)n);
}

#define SIM_TEMP_DEFINE(i)                                                                         \
	static struct sim_temp_data sim_temp_data_##i = {.mc = ATOMIC_INIT(25000)}; /* a desk */   \
	SENSOR_DEVICE_DT_INST_DEFINE(i, NULL, NULL, &sim_temp_data_##i, NULL, POST_KERNEL,         \
				     CONFIG_SENSOR_INIT_PRIORITY, &sim_temp_api);
DT_INST_FOREACH_STATUS_OKAY(SIM_TEMP_DEFINE)
#undef DT_DRV_COMPAT

/* ---------------------------------------------------------------- watchdog */
#define DT_DRV_COMPAT vnd_sim_wdt

struct sim_wdt_data {
	struct k_timer timer;
	uint32_t timeout_ms;
	bool installed;
	bool running;
};

static void sim_wdt_expired(struct k_timer *timer)
{
	const struct sim_wdt_data *d = CONTAINER_OF(timer, struct sim_wdt_data, timer);

	LOG_ERR("watchdog expired: not fed for %u ms (a real IWDG resets the MCU here)", d->timeout_ms);
}

static int sim_wdt_install_timeout(const struct device *dev, const struct wdt_timeout_cfg *cfg)
{
	struct sim_wdt_data *d = dev->data;

	if (d->installed) {
		return -ENOMEM; /* one channel, like the IWDG */
	}
	if (cfg->window.min != 0U || cfg->window.max == 0U) {
		return -EINVAL;
	}
	d->timeout_ms = cfg->window.max;
	d->installed = true;
	return 0;
}

static int sim_wdt_setup(const struct device *dev, uint8_t options)
{
	struct sim_wdt_data *d = dev->data;

	ARG_UNUSED(options); /* PAUSE_HALTED_BY_DBG: there is no debugger halt in SIL */
	if (!d->installed) {
		return -EINVAL;
	}
	d->running = true;
	k_timer_start(&d->timer, K_MSEC(d->timeout_ms), K_NO_WAIT);
	return 0;
}

static int sim_wdt_feed(const struct device *dev, int channel)
{
	struct sim_wdt_data *d = dev->data;

	if (channel != 0 || !d->running) {
		return -EINVAL;
	}
	k_timer_start(&d->timer, K_MSEC(d->timeout_ms), K_NO_WAIT);
	return 0;
}

static int sim_wdt_disable(const struct device *dev)
{
	struct sim_wdt_data *d = dev->data;

	k_timer_stop(&d->timer);
	d->installed = false;
	d->running = false;
	return 0;
}

static DEVICE_API(wdt, sim_wdt_api) = {
	.setup = sim_wdt_setup,
	.disable = sim_wdt_disable,
	.install_timeout = sim_wdt_install_timeout,
	.feed = sim_wdt_feed,
};

static int sim_wdt_init(const struct device *dev)
{
	struct sim_wdt_data *d = dev->data;

	k_timer_init(&d->timer, sim_wdt_expired, NULL);
	return 0;
}

#define SIM_WDT_DEFINE(i)                                                                          \
	static struct sim_wdt_data sim_wdt_data_##i;                                               \
	DEVICE_DT_INST_DEFINE(i, sim_wdt_init, NULL, &sim_wdt_data_##i, NULL, POST_KERNEL,         \
			      CONFIG_KERNEL_INIT_PRIORITY_DEVICE, &sim_wdt_api);
DT_INST_FOREACH_STATUS_OKAY(SIM_WDT_DEFINE)
#undef DT_DRV_COMPAT
