# Graph Report - 02-nucleo_f767zi-thermal-monitor  (2026-10-26)

## Corpus Check
- 18 files · ~7,118 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 9 file(s) not represented in the graph (top: (none) 3, .conf 3, .overlay 2)

## Summary
- 98 nodes · 142 edges · 10 communities (9 shown, 1 thin omitted)
- Extraction: 81% EXTRACTED · 19% INFERRED · 0% AMBIGUOUS · INFERRED: 27 edges (avg confidence: 0.9)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- monitor.c
- Spec: Thermal monitor on NUCLEO-F767ZI
- sim_shell.c
- thermal.c
- sim_devices.c
- main.c
- ADR-0001: Integer milli-°C, 8-sample moving average, hysteresis classifier
- Embedded project profile (embsk)
- monitor.h

## God Nodes (most connected - your core abstractions)
1. `Spec: Thermal monitor on NUCLEO-F767ZI` - 11 edges
2. `Agent toolbox (navigate, verify, debug this project)` - 11 edges
3. `sampler()` - 6 edges
4. `thermal_update()` - 6 edges
5. `report()` - 5 edges
6. `monitor_start()` - 5 edges
7. `ADR-0001: Integer milli-°C, 8-sample moving average, hysteresis classifier` - 5 edges
8. `monitor_set_thresholds()` - 4 edges
9. `cmd_status()` - 4 edges
10. `thermal_init()` - 4 edges

## Surprising Connections (you probably didn't know these)
- `Consequences` --references--> `thermal_update()`  [INFERRED]
  docs/adr/0001-fixed-point-average-and-hysteresis.md → app/src/thermal.c
- `Agent toolbox (navigate, verify, debug this project)` --references--> `thermal_set_thresholds()`  [INFERRED]
  docs/SPEC.md → app/src/thermal.c
- `Agent toolbox (navigate, verify, debug this project)` --references--> `thermal_update()`  [INFERRED]
  docs/SPEC.md → app/src/thermal.c
- `Agent toolbox (navigate, verify, debug this project)` --references--> `settle()`  [INFERRED]
  docs/SPEC.md → app/tests/src/test_thermal.c
- `Review 0001: SIL harness (PLAN task 8)` --references--> `button_work_fn()`  [INFERRED]
  docs/review/0001-sil-harness.md → app/src/monitor.c

## Import Cycles
- None detected.

## Communities (10 total, 1 thin omitted)

### Community 0 - "monitor.c"
Cohesion: 0.23
Nodes (14): leds_show(), monitor_get(), monitor_set_thresholds(), monitor_start(), read_die_temp_mc(), report(), sampler(), watchdog_start() (+6 more)

### Community 1 - "Spec: Thermal monitor on NUCLEO-F767ZI"
Cohesion: 0.12
Nodes (13): Lanes (what runs in parallel), Plan: thermal monitor (tier T1), Assumptions, Boundaries, Budgets, Failure modes, Hardware, Interfaces (+5 more)

### Community 2 - "sim_shell.c"
Cohesion: 0.14
Nodes (11): button_work_fn(), sim_temp_fail(), sim_temp_set(), cmd_fail(), cmd_press(), cmd_temp(), Review 0001: SIL harness (PLAN task 8), gpio (+3 more)

### Community 3 - "thermal.c"
Cohesion: 0.20
Nodes (12): cfg_valid(), classify(), thermal_init(), thermal_set_thresholds(), thermal_update(), before(), settle(), errno (+4 more)

### Community 4 - "sim_devices.c"
Cohesion: 0.17
Nodes (3): atomic, device, watchdog

### Community 5 - "main.c"
Cohesion: 0.33
Nodes (6): main(), reset_cause_str(), app_version, hwinfo, kernel, log

### Community 6 - "ADR-0001: Integer milli-°C, 8-sample moving average, hysteresis classifier"
Cohesion: 0.33
Nodes (5): ADR-0001: Integer milli-°C, 8-sample moving average, hysteresis classifier, Consequences, Context, Decision, Options

### Community 7 - "Embedded project profile (embsk)"
Cohesion: 0.40
Nodes (4): 02-nucleo_f767zi-thermal-monitor — agent rules, Commands (use these; do not re-derive), Embedded project profile (embsk), Hard rules

### Community 8 - "monitor.h"
Cohesion: 0.50
Nodes (3): stdbool, stddef, stdint

## Knowledge Gaps
- **16 isolated node(s):** `Commands (use these; do not re-derive)`, `Hard rules`, `Thermal monitor — NUCLEO-F767ZI (Zephyr)`, `Lanes (what runs in parallel)`, `Objective` (+11 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 39 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Agent toolbox (navigate, verify, debug this project)` connect `monitor.c` to `Spec: Thermal monitor on NUCLEO-F767ZI`, `thermal.c`?**
  _High betweenness centrality (0.302) - this node is a cross-community bridge._
- **Why does `Spec: Thermal monitor on NUCLEO-F767ZI` connect `Spec: Thermal monitor on NUCLEO-F767ZI` to `monitor.c`?**
  _High betweenness centrality (0.264) - this node is a cross-community bridge._
- **Why does `thermal_update()` connect `thermal.c` to `monitor.c`, `ADR-0001: Integer milli-°C, 8-sample moving average, hysteresis classifier`?**
  _High betweenness centrality (0.136) - this node is a cross-community bridge._
- **Are the 10 inferred relationships involving `Agent toolbox (navigate, verify, debug this project)` (e.g. with `leds_show()` and `monitor_set_thresholds()`) actually correct?**
  _`Agent toolbox (navigate, verify, debug this project)` has 10 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `sampler()` (e.g. with `thermal_update()` and `Agent toolbox (navigate, verify, debug this project)`) actually correct?**
  _`sampler()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `thermal_update()` (e.g. with `sampler()` and `settle()`) actually correct?**
  _`thermal_update()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 3 inferred relationships involving `report()` (e.g. with `thermal_fmt_mc()` and `thermal_state_str()`) actually correct?**
  _`report()` has 3 INFERRED edges - model-reasoned connections that need verification._