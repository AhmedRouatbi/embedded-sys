#include <errno.h>
#include <zephyr/ztest.h>

#include "thermal.h"

static const struct thermal_cfg cfg = {.warm_mc = 45000, .hot_mc = 60000, .hyst_mc = 2000};
static struct thermal th;

static void before(void *fixture)
{
	ARG_UNUSED(fixture);
	zassert_ok(thermal_init(&th, &cfg));
}

/* Fill the whole averaging window, so avg == mc afterwards. */
static void settle(int32_t mc)
{
	for (unsigned int i = 0; i < THERMAL_AVG_LEN; i++) {
		zassert_ok(thermal_update(&th, mc));
	}
}

ZTEST_SUITE(thermal, NULL, NULL, before, NULL, NULL);

ZTEST(thermal, test_init_rejects_bad_config)
{
	struct thermal t;
	const struct thermal_cfg bad[] = {
		{.warm_mc = 60000, .hot_mc = 45000, .hyst_mc = 2000},  /* warm >= hot */
		{.warm_mc = 45000, .hot_mc = 60000, .hyst_mc = 15000}, /* hysteresis >= band */
		{.warm_mc = 45000, .hot_mc = 130000, .hyst_mc = 2000}, /* hot above range */
		{.warm_mc = -50000, .hot_mc = 60000, .hyst_mc = 2000}, /* warm below range */
		{.warm_mc = 45000, .hot_mc = 60000, .hyst_mc = -1},    /* negative hysteresis */
	};

	for (size_t i = 0; i < ARRAY_SIZE(bad); i++) {
		zassert_equal(thermal_init(&t, &bad[i]), -EINVAL, "case %zu", i);
	}
}

ZTEST(thermal, test_average_during_warmup_and_rolling) /* REQ-2 */
{
	zassert_ok(thermal_update(&th, 30000));
	zassert_equal(th.avg_mc, 30000);
	zassert_ok(thermal_update(&th, 32000));
	zassert_equal(th.avg_mc, 31000, "warm-up averages the samples seen so far");
	settle(40000);
	zassert_equal(th.avg_mc, 40000);
	zassert_ok(thermal_update(&th, 48000));
	zassert_equal(th.avg_mc, 41000, "newest sample replaces the oldest");
	zassert_equal(th.min_mc, 30000);
	zassert_equal(th.max_mc, 48000);
}

ZTEST(thermal, test_rejects_implausible_sample) /* REQ-7 */
{
	settle(30000);
	zassert_equal(thermal_update(&th, 200000), -ERANGE);
	zassert_equal(thermal_update(&th, -60000), -ERANGE);
	zassert_equal(th.avg_mc, 30000, "rejected samples don't touch the average");
	zassert_equal(th.state, THERMAL_NORMAL);
}

ZTEST(thermal, test_hysteresis_warm) /* REQ-3 */
{
	settle(44999);
	zassert_equal(th.state, THERMAL_NORMAL);
	settle(45000);
	zassert_equal(th.state, THERMAL_WARM);
	settle(43500);
	zassert_equal(th.state, THERMAL_WARM, "inside the hysteresis band: stay WARM");
	settle(42999);
	zassert_equal(th.state, THERMAL_NORMAL);
}

ZTEST(thermal, test_hysteresis_hot) /* REQ-3 */
{
	settle(60000);
	zassert_equal(th.state, THERMAL_HOT);
	settle(58500);
	zassert_equal(th.state, THERMAL_HOT, "inside the hysteresis band: stay HOT");
	settle(57999);
	zassert_equal(th.state, THERMAL_WARM);
	settle(30000);
	zassert_equal(th.state, THERMAL_NORMAL);
}

ZTEST(thermal, test_set_thresholds_validates) /* REQ-6 */
{
	zassert_equal(thermal_set_thresholds(&th, 50000, 50000), -EINVAL);
	zassert_equal(thermal_set_thresholds(&th, 50000, 51000), -EINVAL, "band must exceed hysteresis");
	zassert_ok(thermal_set_thresholds(&th, 35000, 50000));
	settle(36000);
	zassert_equal(th.state, THERMAL_WARM);
}

ZTEST(thermal, test_format_milli_degrees)
{
	char buf[16];

	zassert_equal(thermal_fmt_mc(buf, sizeof(buf), 31250), 6);
	zassert_str_equal(buf, "31.250");
	zassert_equal(thermal_fmt_mc(buf, sizeof(buf), -5), 6);
	zassert_str_equal(buf, "-0.005");
	zassert_equal(thermal_fmt_mc(buf, 4, 31250), -ENOSPC);
}
