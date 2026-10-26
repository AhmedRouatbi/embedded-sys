# Spec & plan — from a description to verifiable slices

> Load when: new project, new feature (T1/T2), vague request, or before a multi-file change.
> Profile keys: `platform`, `board`/`mcu`, `safety`, `features`, `hil`.

Code without a spec is guessing; firmware guessing ends up on a PCB. But scale it: T0 has no spec, T1 gets a spec-lite in chat, T2 gets `docs/SPEC.md` + ADRs.

## 1. Interview (only if the ask is vague)

- Before asking, state your hypothesis and confidence: *"I think you want X for Y (60% sure)."*
- Ask **one question at a time**, each with your best guess attached, max ~5 total. Firmware questions that most often change the design:
  1. What triggers the behaviour and how fast (sample rate, event rate, worst-case burst)?
  2. Power source and budget (battery mAh + target lifetime, or mains)?
  3. What must happen on failure (safe state, retry, report, reboot)?
  4. What hardware is fixed (board/schematic, sensor part numbers, pins) vs. open?
  5. How is it updated and debugged in the field (OTA, UART, none)?
- Listen for *want vs. should-want* (the user asks for MQTT because "IoT", the need is "send 1 value/hour"). Restate the intent in their words; get an explicit yes.

## 2. Surface assumptions before writing

```
ASSUMPTIONS (correct me or I proceed):
1. Board nucleo_f401re, sensor BMI270 on I2C1 @400 kHz (from profile / schematic?)
2. 100 Hz sampling, data logged over UART, no radio
3. Brown-out → reboot and resume; no persisted state
```

## 3. SPEC.md (from `templates/SPEC.md`)

Sections and what makes them firmware-grade:

| Section | Must contain |
|---|---|
| Objective | user-visible behaviour, success in one measurable sentence |
| Hardware | board/MCU (from profile), parts + datasheet links, pin/peripheral table, voltage levels, external clocks |
| Requirements | numbered `REQ-n`, each testable: *"REQ-3: sample accel at 100 Hz ±1 %, jitter < 200 µs"* |
| Budgets | flash/RAM (from `embsk doctor` board RAM/flash), CPU load, latency/deadlines, power (µA per mode, duty cycle) |
| Interfaces | external protocols/frames, shell commands, log format (log lines the verifier can grep) |
| Failure modes | each fault → detection → reaction → reaction time (watchdog, brown-out, bus stuck, sensor absent, flash full) |
| Safety (if profile) | safety functions, hazards, `SR-n` safety requirements with integrity level, safe state |
| Verification | per REQ: host test / target test / measurement / review |
| Boundaries | **Always** (run tests, check returns) · **Ask first** (new dependency, flash layout, Kconfig defaults, pin changes) · **Never** (flash without OK, touch bootloader/option bytes, commit secrets) |
| Out of scope | named explicitly |
| Agent toolbox | the template's table, filled for this project: graphify questions per REQ, the verify/uart/SIL commands, the prompts per phase |

Multiple independent capabilities (e.g. sensing, BLE, OTA)? First a **capability map**: module table + dependency direction + build order, approved by the user, then one spec per module (`docs/SPEC-<module>.md`).

## 4. Design notes (phase 3, before planning)

- **Concurrency model table:** context (ISR/thread/work-queue) · priority · period/trigger · deadline · stack (initial guess, measured later) · shared data + lock.
- **Hardware config plan:** DT overlay nodes/properties (Zephyr) or clock/pin/peripheral init list (bare metal), Kconfig symbols to enable.
- **Layering:** functional core (host-testable C) vs. hardware shell (drivers, ISRs).
- **ADR** (`templates/ADR.md`) for: RTOS vs. superloop, driver choice, bus/DMA strategy, memory layout/partitions, update strategy, anything you'd have to explain twice.

## 5. Plan: vertical slices

Order is fixed for new projects:

1. **Bring-up** — builds for target, boots, logs `boot ok`, host-test target exists and passes (even with a trivial test). Proves toolchain + probe + log path.
2. **Each peripheral alone** — driver reads/writes the real part; host test on the conversion/parsing core; on-target smoke log.
3. **Services** — threads, queues, state machines over the drivers.
4. **Application behaviour** — REQ by REQ.
5. **Robustness** — fault paths, watchdog, power modes, stress.
6. **Release items** — version, signing, docs (T2).

Task format (≤ 1 commit each, independently verifiable):

```
## Task 4: BMI270 raw→SI conversion + I2C read (REQ-3)
Files: src/imu.c, src/imu.h, tests/src/test_imu.c
Test first: conversion incl. ±16 g saturation and sign extension
Verify: <test_host cmd from AGENTS.md> && <build cmd>
Acceptance: test passes; target build passes; flash delta < 4 KB
Depends on: Task 2 (I2C bus up)
```

- Risk-first inside a phase: the part most likely to kill the design (timing, a sensor you've never used) goes first.
- Mark parallel-safe tasks (disjoint files) for `fw-builder` subagents, and write the lanes into PLAN.md: which tasks run together, which wait (shared file, single board/serial port). `subagents.md` has the spawn commands.
- Checkpoint after each phase: all tests green, user sees a demo/log, plan adjusted.
- Save as `docs/PLAN.md` for T2; T1 keeps it in chat/todo list.

## 6. Increment cycle (phase 5, per task)

1. Test that fails for the right reason. 2. Smallest code that passes (`coding.md`). 3. Target build + size. 4. Run the task's verify command. 5. Commit (`<area>: <what> (REQ-n)`). 6. Next task.
Keep the tree compilable after every step. Incomplete features stay behind a Kconfig symbol defaulting to `n`. Never mix a refactor and a behaviour change in one commit.

## Anti-patterns

- Spec that says "fast", "low power", "robust" without numbers.
- Plans whose first task is the application logic while the board has never logged a line.
- Horizontal slices ("all drivers, then all services") that verify nothing until the end.
- Asking 15 questions in one message; asking what the profile already answers.
- Silent assumptions about pins, voltages or part numbers.

## Sources
agent-skills `spec-driven-development`, `planning-and-task-breakdown`, `incremental-implementation`, `interview-me`, `idea-refine`, `documentation-and-adrs`.
