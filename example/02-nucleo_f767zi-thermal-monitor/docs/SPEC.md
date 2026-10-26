# Spec: Thermal monitor on NUCLEO-F767ZI

Status: approved (example) · Profile: see the `embsk` block in AGENTS.md (zephyr, `nucleo_f767zi`, ST-LINK, UART logs)

## Objective
Watch the MCU die temperature, show its state on the three user LEDs and report over the ST-LINK virtual COM port, so an operator (or an agent reading `artifacts/uart.txt`) can see at a glance whether the board runs NORMAL, WARM or HOT.
Success: on the bench, warming the chip with a finger/hot air moves the LEDs green → blue → blinking red and back, with matching log lines.

## Assumptions
1. Only on-board hardware: no wiring, no external sensor (internal sensor on ADC1 channel 18). — confirmed
2. Thresholds are application settings, not safety limits (no safety standard). — confirmed
3. Thresholds do not need to survive a reset (no flash storage in this version). — confirmed

## Hardware
| Item | Part / value | Source |
|---|---|---|
| Board / MCU | NUCLEO-F767ZI, STM32F767ZI (Cortex-M7, 2 MB flash, 512 KB RAM; Zephyr exposes 384 KB) | Zephyr `boards/st/nucleo_f767zi`, ST UM1974 |
| Temperature | internal sensor, factory calibration TS_CAL1/TS_CAL2 in OTP | DT node `die_temp` (`st,stm32-temp-cal`) in `dts/arm/st/f7/stm32f7.dtsi` |
| Watchdog | IWDG (LSI clocked, independent of the main clock) | DT alias `watchdog0` |

| Signal | MCU pin | Use | Source |
|---|---|---|---|
| LD1 green | PB0 | NORMAL | board DTS alias `led0` |
| LD2 blue | PB7 | WARM | alias `led1` |
| LD3 red | PB14 | HOT (blinking) / FAULT (steady) | alias `led2` |
| B1 user button | PC13 | toggle periodic report | alias `sw0` |
| USART3 TX/RX | PD8/PD9 | console + shell via ST-LINK VCP, 115200 8N1 | `zephyr,console` / `zephyr,shell-uart` |

## Requirements
| ID | Requirement | Verification |
|---|---|---|
| REQ-1 | Sample the die temperature every 100 ms (10 Hz) through the Zephyr sensor API, drift-free (absolute timeouts). | review + target log timestamps (L4) |
| REQ-2 | Filter with an 8-sample moving average in milli-°C (integer math); during warm-up average the samples available. | host test `test_average_during_warmup_and_rolling` |
| REQ-3 | Classify NORMAL / WARM (≥ 45.000 °C) / HOT (≥ 60.000 °C); leave a state only below threshold − 2.000 °C (hysteresis). | host tests `test_hysteresis_*` + SIL (50 → 65 → 59 → 57 °C) |
| REQ-4 | Exactly one state LED active: green NORMAL, blue WARM, red blinking 2 Hz HOT; red steady on FAULT. | SIL `sim leds` in NORMAL / WARM / HOT / FAULT + target visual (L4) |
| REQ-5 | B1 toggles a report line once per second: `thermal: t=<°C> avg=<°C> state=<STATE>`. Debounce 50 ms; no work in the ISR beyond deferring. | SIL (`sim press` with contact bounce → `presses=1`, report lines) + target log (L4) |
| REQ-6 | Shell `thermal status` prints temperature, average, min/max, state, counters; `thermal thresholds <warm_mC> <hot_mC>` changes thresholds; reject unless −40000 ≤ warm < hot ≤ 125000 and hot − warm > hysteresis. | host test `test_set_thresholds_validates` + SIL shell steps |
| REQ-7 | Samples outside −40..125 °C are rejected (state unchanged). 10 consecutive read/plausibility failures → FAULT (red steady, logged); first valid sample clears it. | host test `test_rejects_implausible_sample` + SIL (130 °C samples, `sim fail 10`) |
| REQ-8 | IWDG 1000 ms, fed only by the sampling loop, frozen while the debugger halts the core. A hung sampler resets the MCU. | review + target (halt-free run, L4); the SIL watchdog only reports a stall |
| REQ-9 | Boot line `boot ok v<version> reset=<cause>`; the reset cause comes from hwinfo and is cleared after reading. | SIL boot line + target log (L4) |

## Budgets
| Resource | Budget | Measured (v0.1.0) |
|---|---|---|
| Flash | ≤ 128 KB | see `embsk verify` size step |
| RAM | ≤ 32 KB | see `embsk verify` size step |
| Sampler period / jitter | 100 ms / ≤ 1 ms | not measured (log timestamps only) |
| Power | not constrained (USB powered) | — |

## Interfaces
- Log lines (the verifier greps these): `boot ok v`, `monitor running`, `thermal: t=`, `report on|off`, `FAULT`.
- Shell: `thermal status`, `thermal thresholds <warm_mC> <hot_mC>`.
- SIL only (native_sim build, `app/src/sim/`): `sim temp <mC>` sets the simulated die temperature, `sim fail <n>` makes the next n reads fail, `sim press` presses B1 with contact bounce, `sim leds` prints `leds green=<0|1> blue=<0|1> red=<0|1>`. Scenario: `app/sil/thermal.sil`.

## Failure modes
| Fault | Detection | Reaction | Reaction time |
|---|---|---|---|
| Sampler thread hangs | IWDG not fed | MCU reset, `reset=watchdog` at boot | ≤ 1 s |
| Sensor/ADC read fails | API error or implausible value | count; FAULT after 10 in a row | 1 s |
| Device not ready at boot | `device_is_ready()` | log error, monitor not started | boot |

## Boundaries
- Always: host tests green before target build; check every API return.
- Ask first: flashing the board, adding modules to `west.yml`, changing pins.
- Never: option bytes / RDP, disabling the watchdog to "fix" resets.

## Out of scope
Persisting thresholds (would add `settings` + NVS), Ethernet reporting, low-power modes.

## Agent toolbox (navigate, verify, debug this project)
Commands come from the `embsk` block in AGENTS.md. Outputs below are from this repository; the full session is in [WALKTHROUGH.md](WALKTHROUGH.md).

**Navigate with graphify** (`graphify update .` once, ~0.3 s, no LLM; then open `graphify-out/graph.html`):

| Question | Command | Answer in this repo |
|---|---|---|
| Where do I start? | `graphify god-nodes --top 8` | `sampler()`, `thermal_update()`, `monitor_start()`, `report()`, plus this spec and ADR-0001 (docs are indexed too) |
| What does the sampler touch? (REQ-1, 4, 7, 8) | `graphify explain "sampler()"` | `monitor.c:L114` → `read_die_temp_mc()`, `thermal_update()`, `leds_show()`, `report()` |
| Who drives the LEDs? (REQ-4) | `graphify explain "leds_show()"` | `monitor.c:L81`, called only by `sampler()` (L154) |
| Where is the hysteresis? (REQ-3) | `graphify explain "classify()"` | `thermal.c`, called by `thermal_update()` |
| What breaks if I change the core update? | `graphify affected "thermal_update()"` | `sampler()`, the host tests (`settle()`), ADR-0001 |
| Who is affected by an LED change? | `graphify affected "leds_show()"` | `sampler()` only |
| How does a shell command reach the core? (REQ-6) | `graphify path "cmd_thresholds()" "thermal_set_thresholds()"` | `cmd_thresholds()` → `monitor_set_thresholds()` → `thermal_set_thresholds()` |
| Is `die_temp` really enabled? (DT is not in the graph) | `embsk export build && rg -n "die_temp" docs/generated/dt-nodes-and-status.txt` | `status = "okay"` from `app/boards/nucleo_f767zi.overlay:13` |

`sampler()` runs as a thread (`k_thread_create`), so `graphify path "main()" "leds_show()"` finds no call chain: ask from the entry (`explain "sampler()"`), see `context-graphify.md`.

**Verify and talk to the firmware**

| Need | Command |
|---|---|
| Build + 7 host tests + SIL scenario + size | `embsk verify` |
| Run the SIL scenario only | the `sil` row: `west build -b native_sim/native/64 -p auto -d build-sim app && embsk uart --exec build-sim/zephyr/zephyr.exe --script app/sil/thermal.sil` |
| Ask the SIL app something | `embsk uart --exec build-sim/zephyr/zephyr.exe --send "thermal status" --expect "state="` |
| Ask the board (after a flash you approved) | `embsk uart --send "thermal status" --expect "state="` (port from the profile) |
| Resolved devicetree / Kconfig | `embsk export build` → `docs/generated/` |

**The other skill parts, by request**

| You say | What runs | Skill part |
|---|---|---|
| Alt+A · `/embsk` · `embsk set board=...` | profile, doctor, AGENTS.md block | embsk |
| `task 3 from docs/PLAN.md` | failing test → smallest code → build → verify | `coding.md` (ponytail), `testing-verification.md` |
| `run tasks 2 and 8 in parallel` | two `fw-builder` subagents on disjoint files | `subagents.md`, `agents/fw-builder.md` |
| `debug: LEDs wrong in FAULT` | reproduce over UART → graphify → one hypothesis → fix → re-run | `debugging.md` (UART loop) |
| `review` | fresh-context `fw-reviewer` on the diff + this spec | `review.md`, `agents/fw-reviewer.md` |
| `flash it` | `west flash` after the flash guard asks you | `hooks/flash-guard.sh` |
| `doc` | `graphify update .`, ADR/README check, `graphify export wiki` | `docs-release.md`, `context-graphify.md` |
