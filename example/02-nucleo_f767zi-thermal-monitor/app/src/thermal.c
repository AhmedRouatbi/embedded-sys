#include <errno.h>
#include <stdio.h>
#include <string.h>

#include "thermal.h"

static int cfg_valid(const struct thermal_cfg *c)
{
	return c->warm_mc >= THERMAL_MIN_MC && c->hot_mc <= THERMAL_MAX_MC && c->warm_mc < c->hot_mc &&
	       c->hyst_mc >= 0 && c->hyst_mc < (c->hot_mc - c->warm_mc);
}

int thermal_init(struct thermal *t, const struct thermal_cfg *cfg)
{
	if (!cfg_valid(cfg)) {
		return -EINVAL;
	}
	memset(t, 0, sizeof(*t));
	t->cfg = *cfg;
	t->state = THERMAL_NORMAL;
	return 0;
}

int thermal_set_thresholds(struct thermal *t, int32_t warm_mc, int32_t hot_mc)
{
	const struct thermal_cfg c = {.warm_mc = warm_mc, .hot_mc = hot_mc, .hyst_mc = t->cfg.hyst_mc};

	if (!cfg_valid(&c)) {
		return -EINVAL;
	}
	t->cfg = c;
	return 0;
}

/* Rising edges use the thresholds, falling edges threshold - hysteresis (no LED flicker). */
static enum thermal_state classify(const struct thermal *t)
{
	const struct thermal_cfg *c = &t->cfg;
	const int32_t a = t->avg_mc;

	if (a >= c->hot_mc || (t->state == THERMAL_HOT && a >= c->hot_mc - c->hyst_mc)) {
		return THERMAL_HOT;
	}
	if (a >= c->warm_mc || (t->state != THERMAL_NORMAL && a >= c->warm_mc - c->hyst_mc)) {
		return THERMAL_WARM;
	}
	return THERMAL_NORMAL;
}

int thermal_update(struct thermal *t, int32_t sample_mc)
{
	if (sample_mc < THERMAL_MIN_MC || sample_mc > THERMAL_MAX_MC) {
		return -ERANGE;
	}
	if (t->count == THERMAL_AVG_LEN) {
		t->sum -= t->win[t->idx];
	} else {
		t->count++;
	}
	t->win[t->idx] = sample_mc;
	t->sum += sample_mc;
	t->idx = (uint8_t)((t->idx + 1U) % THERMAL_AVG_LEN);
	t->avg_mc = t->sum / (int32_t)t->count;

	if (t->count == 1U) { /* count saturates at AVG_LEN, so 1 only for the very first sample */
		t->min_mc = sample_mc;
		t->max_mc = sample_mc;
	} else if (sample_mc < t->min_mc) {
		t->min_mc = sample_mc;
	} else if (sample_mc > t->max_mc) {
		t->max_mc = sample_mc;
	}
	t->state = classify(t);
	return 0;
}

const char *thermal_state_str(enum thermal_state s)
{
	switch (s) {
	case THERMAL_NORMAL:
		return "NORMAL";
	case THERMAL_WARM:
		return "WARM";
	case THERMAL_HOT:
		return "HOT";
	default:
		return "?";
	}
}

int thermal_fmt_mc(char *buf, size_t len, int32_t mc)
{
	const uint32_t a = (mc < 0) ? (uint32_t)(-(int64_t)mc) : (uint32_t)mc;
	const int n = snprintf(buf, len, "%s%u.%03u", (mc < 0) ? "-" : "", (unsigned int)(a / 1000U),
			       (unsigned int)(a % 1000U));

	return (n < 0 || (size_t)n >= len) ? -ENOSPC : n;
}
