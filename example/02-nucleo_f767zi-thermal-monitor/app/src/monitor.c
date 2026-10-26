/*
 * Hardware shell around the thermal core (thermal.c):
 *   sampler thread (10 Hz) -> die-temp sensor -> thermal core -> LEDs + report + watchdog feed
 *   B1 button ISR -> system work queue (debounce, toggle report)
 * REQ-1, REQ-4, REQ-5, REQ-7, REQ-8
 */
#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/drivers/watchdog.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/atomic.h>

#include "monitor.h"

LOG_MODULE_REGISTER(thermal, LOG_LEVEL_INF);

#define SAMPLE_PERIOD_MS   100
#define REPORT_EVERY       10 /* samples: one report line per second */
#define FAULT_AFTER_ERRORS 10
#define DEBOUNCE_MS        50
#define WDT_TIMEOUT_MS     1000
#define BLINK_HALF_MS      250 /* 2 Hz */
#define LOCK_TIMEOUT       K_MSEC(50)
#define SAMPLER_PRIO       5

static const struct thermal_cfg defaults = {.warm_mc = 45000, .hot_mc = 60000, .hyst_mc = 2000};

static const struct device *const temp_dev = DEVICE_DT_GET(DT_ALIAS(die_temp0));
static const struct device *const wdt_dev = DEVICE_DT_GET(DT_ALIAS(watchdog0));
static const struct gpio_dt_spec led_green = GPIO_DT_SPEC_GET(DT_ALIAS(led0), gpios);
static const struct gpio_dt_spec led_blue = GPIO_DT_SPEC_GET(DT_ALIAS(led1), gpios);
static const struct gpio_dt_spec led_red = GPIO_DT_SPEC_GET(DT_ALIAS(led2), gpios);
static const struct gpio_dt_spec button = GPIO_DT_SPEC_GET(DT_ALIAS(sw0), gpios);

/* th, last_mc, samples, errors, fault: written by the sampler, read by the shell; guarded by th_lock */
static K_MUTEX_DEFINE(th_lock);
static struct thermal th;
static int32_t last_mc;
static uint32_t samples;
static uint32_t errors;
static bool fault;

static atomic_t reporting;
static atomic_t presses;
static int wdt_channel;

static struct gpio_callback button_cb;
static void button_work_fn(struct k_work *work);
static K_WORK_DEFINE(button_work, button_work_fn);

K_THREAD_STACK_DEFINE(sampler_stack, 1536);
static struct k_thread sampler_thread;

static void button_isr(const struct device *dev, struct gpio_callback *cb, uint32_t pins)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(cb);
	ARG_UNUSED(pins);
	k_work_submit(&button_work); /* ISR context: defer only; bounces coalesce into one queued item */
}

static void button_work_fn(struct k_work *work)
{
	static int64_t last_ms = -DEBOUNCE_MS;
	const int64_t now = k_uptime_get();

	ARG_UNUSED(work);
	if (now - last_ms < DEBOUNCE_MS) {
		return;
	}
	last_ms = now;
	atomic_inc(&presses);
	const bool on = !atomic_get(&reporting);

	atomic_set(&reporting, on);
	LOG_INF("report %s", on ? "on" : "off");
}

static void leds_show(enum thermal_state s, bool flt)
{
	const bool blink_on = (k_uptime_get() % (2 * BLINK_HALF_MS)) < BLINK_HALF_MS;

	/* LED writes can't fail in a way we could act on; state is re-applied every 100 ms anyway */
	(void)gpio_pin_set_dt(&led_green, !flt && s == THERMAL_NORMAL);
	(void)gpio_pin_set_dt(&led_blue, !flt && s == THERMAL_WARM);
	(void)gpio_pin_set_dt(&led_red, flt || (s == THERMAL_HOT && blink_on));
}

static int read_die_temp_mc(int32_t *mc)
{
	struct sensor_value v;
	int rc = sensor_sample_fetch(temp_dev);

	if (rc == 0) {
		rc = sensor_channel_get(temp_dev, SENSOR_CHAN_DIE_TEMP, &v);
	}
	if (rc == 0) {
		*mc = (int32_t)sensor_value_to_milli(&v);
	}
	return rc;
}

static void report(int32_t mc, int32_t avg, enum thermal_state s)
{
	char t_str[16], avg_str[16];

	(void)thermal_fmt_mc(t_str, sizeof(t_str), mc);
	(void)thermal_fmt_mc(avg_str, sizeof(avg_str), avg);
	LOG_INF("t=%sC avg=%sC state=%s", t_str, avg_str, thermal_state_str(s));
}

static void sampler(void *p1, void *p2, void *p3)
{
	int64_t next = k_uptime_get();
	uint32_t in_a_row = 0;

	ARG_UNUSED(p1);
	ARG_UNUSED(p2);
	ARG_UNUSED(p3);

	for (;;) {
		int32_t mc = 0;
		int rc = read_die_temp_mc(&mc);

		if (k_mutex_lock(&th_lock, LOCK_TIMEOUT) == 0) {
			if (rc == 0) {
				rc = thermal_update(&th, mc);
			}
			if (rc == 0) {
				last_mc = mc;
				samples++;
				in_a_row = 0;
				if (fault) {
					fault = false;
					LOG_INF("sensor recovered, FAULT cleared");
				}
			} else {
				errors++;
				if (++in_a_row == 1U) {
					LOG_WRN("die temp sample rejected (%d)", rc);
				} else if (in_a_row == FAULT_AFTER_ERRORS) {
					fault = true;
					LOG_ERR("FAULT: %u bad samples in a row", in_a_row);
				}
			}
			const enum thermal_state s = th.state;
			const bool flt = fault;
			const int32_t avg = th.avg_mc;
			const uint32_t n = samples;

			k_mutex_unlock(&th_lock);
			leds_show(s, flt);
			if (rc == 0 && atomic_get(&reporting) && (n % REPORT_EVERY) == 0U) {
				report(mc, avg, s);
			}
		} else {
			LOG_WRN("state lock busy, sample skipped");
		}

		/* Fed only here: if this loop stalls, the IWDG resets the MCU (REQ-8). */
		(void)wdt_feed(wdt_dev, wdt_channel);
		next += SAMPLE_PERIOD_MS;
		k_sleep(K_TIMEOUT_ABS_MS(next)); /* absolute deadline: no drift (REQ-1) */
	}
}

static int watchdog_start(void)
{
	const struct wdt_timeout_cfg cfg = {
		.window = {.min = 0U, .max = WDT_TIMEOUT_MS},
		.callback = NULL, /* IWDG: no early-warning callback without IWDG_STM32_EARLY_WAKEUP */
		.flags = WDT_FLAG_RESET_SOC,
	};

	wdt_channel = wdt_install_timeout(wdt_dev, &cfg);
	if (wdt_channel < 0) {
		return wdt_channel;
	}
	return wdt_setup(wdt_dev, WDT_OPT_PAUSE_HALTED_BY_DBG); /* frozen while a debugger halts the core */
}

int monitor_start(void)
{
	const struct gpio_dt_spec *const leds[] = {&led_green, &led_blue, &led_red};
	int rc;

	if (!device_is_ready(temp_dev) || !device_is_ready(wdt_dev) || !gpio_is_ready_dt(&button)) {
		return -ENODEV;
	}
	for (size_t i = 0; i < ARRAY_SIZE(leds); i++) {
		if (!gpio_is_ready_dt(leds[i])) {
			return -ENODEV;
		}
		rc = gpio_pin_configure_dt(leds[i], GPIO_OUTPUT_INACTIVE);
		if (rc != 0) {
			return rc;
		}
	}
	rc = gpio_pin_configure_dt(&button, GPIO_INPUT);
	if (rc == 0) {
		rc = gpio_pin_interrupt_configure_dt(&button, GPIO_INT_EDGE_TO_ACTIVE);
	}
	if (rc != 0) {
		return rc;
	}
	gpio_init_callback(&button_cb, button_isr, BIT(button.pin));
	rc = gpio_add_callback_dt(&button, &button_cb);
	if (rc != 0) {
		return rc;
	}
	rc = thermal_init(&th, &defaults);
	if (rc != 0) {
		return rc;
	}
	rc = watchdog_start(); /* last: once started, the IWDG cannot be stopped */
	if (rc != 0) {
		return rc;
	}
	k_thread_create(&sampler_thread, sampler_stack, K_THREAD_STACK_SIZEOF(sampler_stack), sampler, NULL,
			NULL, NULL, SAMPLER_PRIO, 0, K_NO_WAIT);
	k_thread_name_set(&sampler_thread, "sampler");
	return 0;
}

int monitor_get(struct monitor_status *out)
{
	if (k_mutex_lock(&th_lock, LOCK_TIMEOUT) != 0) {
		return -EBUSY;
	}
	*out = (struct monitor_status){
		.last_mc = last_mc,
		.avg_mc = th.avg_mc,
		.min_mc = th.min_mc,
		.max_mc = th.max_mc,
		.warm_mc = th.cfg.warm_mc,
		.hot_mc = th.cfg.hot_mc,
		.state = th.state,
		.fault = fault,
		.samples = samples,
		.errors = errors,
	};
	k_mutex_unlock(&th_lock);
	out->reporting = atomic_get(&reporting) != 0;
	out->presses = (uint32_t)atomic_get(&presses);
	return 0;
}

int monitor_set_thresholds(int32_t warm_mc, int32_t hot_mc)
{
	int rc;

	if (k_mutex_lock(&th_lock, LOCK_TIMEOUT) != 0) {
		return -EBUSY;
	}
	rc = thermal_set_thresholds(&th, warm_mc, hot_mc);
	k_mutex_unlock(&th_lock);
	if (rc == 0) {
		LOG_INF("thresholds warm=%d hot=%d mC", warm_mc, hot_mc);
	}
	return rc;
}
