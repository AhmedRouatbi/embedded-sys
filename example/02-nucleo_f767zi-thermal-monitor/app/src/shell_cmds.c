/* Shell commands over the ST-LINK VCP: a query surface for humans and agents. REQ-6 */
#include <zephyr/shell/shell.h>
#include <zephyr/shell/shell_string_conv.h>

#include "monitor.h"

static int cmd_status(const struct shell *sh, size_t argc, char **argv)
{
	struct monitor_status st;
	char t[16], avg[16], lo[16], hi[16];
	const int rc = monitor_get(&st);

	ARG_UNUSED(argc);
	ARG_UNUSED(argv);
	if (rc != 0) {
		shell_error(sh, "state busy (%d), try again", rc);
		return rc;
	}
	(void)thermal_fmt_mc(t, sizeof(t), st.last_mc);
	(void)thermal_fmt_mc(avg, sizeof(avg), st.avg_mc);
	(void)thermal_fmt_mc(lo, sizeof(lo), st.min_mc);
	(void)thermal_fmt_mc(hi, sizeof(hi), st.max_mc);
	shell_print(sh, "t=%sC avg=%sC min=%sC max=%sC state=%s%s", t, avg, lo, hi,
		    thermal_state_str(st.state), st.fault ? " FAULT" : "");
	shell_print(sh, "warm=%d hot=%d mC samples=%u errors=%u presses=%u report=%s", st.warm_mc,
		    st.hot_mc, st.samples, st.errors, st.presses, st.reporting ? "on" : "off");
	return 0;
}

static int cmd_thresholds(const struct shell *sh, size_t argc, char **argv)
{
	int err = 0;
	const long warm = shell_strtol(argv[1], 10, &err);
	const long hot = (err == 0) ? shell_strtol(argv[2], 10, &err) : 0;

	ARG_UNUSED(argc);
	if (err != 0 || warm < INT32_MIN || warm > INT32_MAX || hot < INT32_MIN || hot > INT32_MAX) {
		shell_error(sh, "usage: thermal thresholds <warm_mC> <hot_mC>");
		return -EINVAL;
	}
	const int rc = monitor_set_thresholds((int32_t)warm, (int32_t)hot);

	if (rc == -EINVAL) {
		shell_error(sh, "rejected: need -40000 <= warm < hot <= 125000 and hot - warm > hysteresis");
	} else if (rc != 0) {
		shell_error(sh, "failed (%d)", rc);
	} else {
		shell_print(sh, "ok");
	}
	return rc;
}

SHELL_STATIC_SUBCMD_SET_CREATE(thermal_cmds,
	SHELL_CMD(status, NULL, "Temperature, state and counters", cmd_status),
	SHELL_CMD_ARG(thresholds, NULL, "Set thresholds: <warm_mC> <hot_mC>", cmd_thresholds, 3, 0),
	SHELL_SUBCMD_SET_END);
SHELL_CMD_REGISTER(thermal, &thermal_cmds, "Thermal monitor", NULL);
