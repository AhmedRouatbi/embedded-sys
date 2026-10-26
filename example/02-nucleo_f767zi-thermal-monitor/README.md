# Thermal monitor — NUCLEO-F767ZI (Zephyr)

Die temperature at 10 Hz → 8-sample average → NORMAL / WARM / HOT (2 °C hysteresis) on LD1/LD2/LD3. B1 toggles a 1 Hz report. Shell `thermal status|thresholds`. IWDG watchdog, reset cause at boot.
Built with the `embedded-sys` skill, phase by phase; **[docs/WALKTHROUGH.md](docs/WALKTHROUGH.md)** replays the whole session: what you type, what the agent does, real outputs.

```bash
cp -r <skill repo>/example/02-nucleo_f767zi-thermal-monitor ~/work/thermal && cd ~/work/thermal
embsk setup     # west workspace (zephyr + cmsis_6 + hal_stm32 only) + board build
embsk verify    # build + 7 host tests + SIL scenario over the UART (21 checks) + size
```

No board needed for the above: the SIL target runs the same application on `native_sim` with simulated devices, and the agent drives it over its UART with `embsk uart`. With a board attached:

```bash
west flash -d build                                   # the agent asks you first (flash guard)
embsk uart --timeout 15 --expect "boot ok v" --send "thermal status" --expect "state="   # press RESET (B2) after it starts
```

The `sim ...` steps of `app/sil/thermal.sil` exist only in the simulator; on the board you warm the chip and press B1 yourself (walkthrough §8).

| Read | For |
|---|---|
| [docs/WALKTHROUGH.md](docs/WALKTHROUGH.md) | the session step by step: configure the board, spec, plan with parallel agents, TDD, SIL + UART loop, debugging, review, graphify |
| [docs/SPEC.md](docs/SPEC.md) | requirements REQ-1..9, budgets, failure modes, and the agent toolbox (graphify navigation, verify/uart commands) |
| [docs/PLAN.md](docs/PLAN.md) | 9 tasks, parallel lanes, spawn plan |
| [docs/adr/](docs/adr/) | ADR-0001: integer milli-°C, moving average, hysteresis |
| [docs/review/](docs/review/) | review 0001 of the SIL harness: 2 findings, proven by mutation, fixed |
| `graphify-out/graph.html` | the code graph (open in a browser); screenshot in [docs/img/graphify-graph.png](docs/img/graphify-graph.png) |
| `app/src/thermal.c` → `app/src/monitor.c` | functional core (host-tested) → hardware shell |
| `app/src/sim/`, `app/sil/thermal.sil` | SIL devices and scenario (native_sim only) |
| `AGENTS.md` | the `embsk` block the agent reads every session (generated) |
