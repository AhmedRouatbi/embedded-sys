# ADR-0001: Integer milli-°C, 8-sample moving average, hysteresis classifier

Date: 2026-10-25 · Status: accepted · REQ: REQ-2, REQ-3, REQ-7

## Context
The die sensor is noisy (±1–2 °C between consecutive conversions) and the LEDs must not flicker at a threshold. The Zephyr sensor API returns `struct sensor_value` (integer + micro part). The logic has to run in host tests.

## Options
1. **float °C + exponential moving average** — tiny code, but floats in logs need `CONFIG_CBPRINTF_FP_SUPPORT` (+ several KB), and EMA step responses are harder to assert exactly in tests.
2. **int32 milli-°C + 8-sample moving average + hysteresis band** — exact integer arithmetic (sum ≤ 8 × 125000 fits int32), deterministic tests, no float printing; 8 × 100 ms = 0.8 s lag.
3. Median filter — better spike rejection, more code; spikes are already caught by the plausibility check.

## Decision
Option 2. `sensor_value_to_milli()` converts once at the boundary; everything after that is integer.

## Consequences
- Filter latency 0.8 s, fine for thermal trends; reaction time budget (≤ 1 s) holds.
- A 2 °C hysteresis band stops LED flicker; thresholds must be ≥ 2 °C + 1 m°C apart (validated).
- Revisit if the sampling rate or the noise changes (median/EMA are drop-in replacements behind `thermal_update()`).
