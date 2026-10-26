/*
 * SIL shell (native_sim only): drive the simulated devices so an agent can run scenarios over the
 * UART, e.g. `embsk uart --exec build-sim/zephyr/zephyr.exe --script app/sil/thermal.sil`.
 */
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/gpio/gpio_emul.h>
#include <zephyr/kernel.h>
#include <zephyr/shell/shell.h>
#include <zephyr/shell/shell_string_conv.h>

#include "sim_devices.h"

static const struct device *const temp_dev = DEVICE_DT_GET(DT_ALIAS(die_temp0));
static const struct gpio_dt_spec led_green = GPIO_DT_SPEC_GET(DT_ALIAS(led0), gpios);
static const struct gpio_dt_spec led_blue = GPIO_DT_SPEC_GET(DT_ALIAS(led1), gpios);
static const struct gpio_dt_spec led_red = GPIO_DT_SPEC_GET(DT_ALIAS(led2), gpios);
static const struct gpio_dt_spec button = GPIO_DT_SPEC_GET(DT_ALIAS(sw0), gpios);

static int cmd_temp(const struct shell *sh, size_t argc, char **argv)
{
	int err = 0;
	const long mc = shell_strtol(argv[1], 10, &err);

	ARG_UNUSED(argc);
	if (err != 0 || mc < INT32_MIN || mc > INT32_MAX) {
		shell_error(sh, "usage: sim temp <milli_degC>");
		return -EINVAL;
	}
	sim_temp_set(temp_dev, (int32_t)mc);
	shell_print(sh, "sim: die temperature now %ld mC", mc);
	return 0;
}

static int cmd_fail(const struct shell *sh, size_t argc, char **argv)
{
	int err = 0;
	const unsigned long n = shell_strtoul(argv[1], 10, &err);

	ARG_UNUSED(argc);
	if (err != 0 || n > UINT32_MAX) {
		shell_error(sh, "usage: sim fail <reads>");
		return -EINVAL;
	}
	sim_temp_fail(temp_dev, (uint32_t)n);
	shell_print(sh, "sim: next %lu sensor reads fail", n);
	return 0;
}

/* One press of a real contact: 3 bounces (2 ms closed / 2 ms open), then closed for 30 ms, i.e. 4 rising
 * edges within 12 ms. The app must count ONE press (REQ-5 debounce). Each edge runs the ISR, and the
 * higher-priority work queue runs right after it. Spacing uses k_busy_wait: native_sim ticks at 100 Hz,
 * so k_msleep(2) would last 10-20 ms. */
static int cmd_press(const struct shell *sh, size_t argc, char **argv)
{
	int rc = 0;

	ARG_UNUSED(argc);
	ARG_UNUSED(argv);
	for (int i = 0; i < 3 && rc == 0; i++) {
		rc = gpio_emul_input_set_dt(&button, 1); /* rising edge = GPIO_INT_EDGE_TO_ACTIVE */
		k_busy_wait(2000);
		if (rc == 0) {
			rc = gpio_emul_input_set_dt(&button, 0);
		}
		k_busy_wait(2000);
	}
	if (rc == 0) {
		rc = gpio_emul_input_set_dt(&button, 1);
		k_msleep(30); /* held */
		rc = (rc == 0) ? gpio_emul_input_set_dt(&button, 0) : rc;
	}
	if (rc != 0) {
		shell_error(sh, "sim: button failed (%d)", rc);
		return rc;
	}
	shell_print(sh, "sim: B1 pressed (with contact bounce)");
	return 0;
}

static int cmd_leds(const struct shell *sh, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);
	shell_print(sh, "leds green=%d blue=%d red=%d", gpio_emul_output_get_dt(&led_green),
		    gpio_emul_output_get_dt(&led_blue), gpio_emul_output_get_dt(&led_red));
	return 0;
}

SHELL_STATIC_SUBCMD_SET_CREATE(sim_cmds,
	SHELL_CMD_ARG(temp, NULL, "Set the simulated die temperature: <milli_degC>", cmd_temp, 2, 0),
	SHELL_CMD_ARG(fail, NULL, "Make the next <reads> sensor reads fail (-EIO)", cmd_fail, 2, 0),
	SHELL_CMD(press, NULL, "Press and release the simulated B1 button", cmd_press),
	SHELL_CMD(leds, NULL, "Print the simulated LED outputs (1 = on)", cmd_leds),
	SHELL_SUBCMD_SET_END);
SHELL_CMD_REGISTER(sim, &sim_cmds, "SIL: drive the simulated devices", NULL);
