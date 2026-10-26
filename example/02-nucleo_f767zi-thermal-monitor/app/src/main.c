#include <zephyr/app_version.h>
#include <zephyr/drivers/hwinfo.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include "monitor.h"

LOG_MODULE_REGISTER(app, LOG_LEVEL_INF);

/* STM32 also sets the PIN flag on power-on and watchdog resets, so check the specific causes first. */
static const char *reset_cause_str(uint32_t c)
{
	if (c & RESET_WATCHDOG) {
		return "watchdog";
	}
	if (c & RESET_BROWNOUT) {
		return "brownout";
	}
	if (c & RESET_POR) {
		return "power-on";
	}
	if (c & RESET_SOFTWARE) {
		return "software";
	}
	if (c & RESET_PIN) {
		return "pin";
	}
	return "unknown";
}

int main(void)
{
	uint32_t cause = 0;
	int rc;

	if (hwinfo_get_reset_cause(&cause) == 0) {
		(void)hwinfo_clear_reset_cause(); /* so the next boot reports its own cause (REQ-9) */
	}
	LOG_INF("boot ok v%s reset=%s", APP_VERSION_STRING, reset_cause_str(cause));

	rc = monitor_start();
	if (rc != 0) {
		LOG_ERR("monitor start failed (%d)", rc);
		return rc;
	}
	LOG_INF("monitor running: 10 Hz, B1 toggles report, shell: thermal status");
	return 0;
}
