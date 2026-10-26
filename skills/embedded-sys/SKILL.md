---
name: embedded-sys
description: >
  End-to-end agentic workflow for embedded firmware (Zephyr RTOS, bare metal, FreeRTOS on MCUs):
  project profile (board/MCU/probe/safety), spec, design, plan, minimal "ponytail" coding,
  host + on-target verification, embedded code review, debugging, graphify-based low-token
  navigation and documentation, release. Use for any firmware/MCU/Zephyr/devicetree/Kconfig/
  driver/ISR/RTOS/linker/flash/debug-probe task, when creating an embedded project from a
  description, or when the user says "embsk", "firmware", "bring up the board", "write a driver".
argument-hint: "[new <description> | task <description> | review | debug <symptom> | doc | release | menu]"
license: MIT
---

# embedded-sys

One skill, five upstream sources merged and de-duplicated:
**LibreEmbed** (domain knowledge) · **ponytail** (how much code, review) · **agent-skills** (process) · **graphify** (cheap context) · **Pi subagents** (parallel roles).
The bench is the source of truth: generated C is a hypothesis until a build, a test and (if hardware is attached) a log line prove it.

`SKILL_DIR` = the directory holding this file. `embsk` = the `embsk` command on PATH (install.py puts it there; Windows too). Fallback: `python3 $SKILL_DIR/scripts/embsk.py` (Windows: `py -3 …`).

## 0. Profile first (every session, 1 command)

1. Read the `embsk` block in the project's `AGENTS.md`. It holds target, probe, safety level and the exact build/test/flash/log commands. Use those commands; do not re-derive them.
2. No block / no `.embsk/profile.json`: ask the user to press **Alt+A** (Pi, Claude Code, tmux) or run `/embsk` (Claude Code / Codex prompt: checkbox questions → `embsk set ...`) or `embsk menu` in a terminal. With a structured-question tool you may ask yourself: values from `embsk schema`, boards from `embsk boards <mcu>`, then one `embsk set k=v ...`. Never guess a board.
3. Run `embsk doctor`. An `ERR` (board doesn't exist, MCU ≠ board SoC, probe not a runner for this board) blocks hardware work until fixed. Show the user the error and the suggested fix.
4. Zephyr: `embsk setup` owns the west workspace — run it after a new profile or any board/feature change (scaffold if needed → `app/west.yml` revision + **name-allowlist of only the modules this board needs** → `west init -l app` → shallow `west update` → Python deps → Zephyr SDK check → build). Never hand-run `west init` elsewhere or edit the allowlist; extra modules go through `embsk set extra_modules=a,b`. Details: `references/zephyr.md` §Workspace.
5. The **Zephyr SDK is a user prerequisite**, found through `PATH` (a `*zephyr-*-gcc` inside an SDK). The skill never ships, downloads or installs it. Missing (doctor `ERR`, setup exit 3): show the user the printed fix line and wait; don't run `west sdk install` or `setup.sh` yourself.

## 1. Pick the tier (scale ceremony to stakes)

| Tier | When | Phases |
|---|---|---|
| **T0 trivial** | one Kconfig line, a typo, a log message, a pin in an overlay | Build → Verify(L1) → done. No spec, no plan. |
| **T1 standard** | new driver, thread, protocol, feature, bug fix | Map → Spec-lite → Plan → Build → Verify → Review |
| **T2 critical** | bootloader/OTA/flash layout, anything that can brick a unit, security, **any change to a safety function when `safety ≠ none`** | All phases + independent review + safety audit + release checklist |

Announce the tier in one line. The user may override it.

## 2. Phases

Each phase has a gate. Do not enter the next phase until the gate holds.

| # | Phase | Do | Gate | Load |
|---|---|---|---|---|
| 1 | **Map** | `graphify update .` (AST-only, no LLM cost). Answer "where/how" with `graphify query/explain/path/affected`; after any build that changes DT/Kconfig run `embsk export build`. | You can name the files and symbols the change touches | `context-graphify.md` |
| 2 | **Specify** | From the description write `docs/SPEC.md` from `templates/SPEC.md`: behaviour, pins/peripherals, timing, memory, power, failure modes, numbered `REQ-n`. Vague ask: max 5 questions, one at a time. | User approved the spec (T1: a 10-line spec-lite in chat is enough) | `spec-plan.md` |
| 3 | **Design** | Concurrency model (threads/ISRs/priorities/stacks), DT overlay + Kconfig plan, driver vs. app split, error strategy. ADR (`templates/ADR.md`) for each non-obvious choice. T2 + safety: hazard table. | Every REQ maps to a component | platform ref + feature refs |
| 4 | **Plan** | Ordered vertical slices. Bring-up first (boots + logs), then driver, service, app. Each task names its files, its test and its verify command. | Each task ≤ 1 commit and independently verifiable | `spec-plan.md` |
| 5 | **Build** | Per task: write a failing test (host) → smallest code that passes → target build → size check. Follow `coding.md`. | Task's verify command passes | `coding.md` |
| 6 | **Verify** | Climb the evidence ladder L1→L5 as far as the setup allows. Flash only with explicit user OK. Talk to the firmware with `embsk uart` (board, or the SIL build on native_sim); transcripts land in `artifacts/*.txt`. | Highest level reached is stated with the evidence | `testing-verification.md` |
| 7 | **Review** | Fresh-context review of the diff + connected code (see `review.md`). T2: add the safety audit. Fix "Must fix" items and re-verify. | Verdict: Ship | `review.md` (+ `safety.md`) |
| 8 | **Document** | `graphify update .` (+ `graphify export wiki` on milestones), update README/ADRs, T2: traceability REQ→code→test. | Docs match code | `docs-release.md` |
| 9 | **Release** (T2 / on request) | Version, changelog, signed image, artifact hashes, rollback path. | Release checklist all green | `docs-release.md`, `boot-ota-security.md` |

Bug instead of feature: run `debugging.md` (reproduce → minimize → one hypothesis → instrument → fix root cause → regression test), then phases 6–7.

## 3. New project from a description (`new <description>`)

1. Profile (section 0). 2. Spec (phase 2), approved by the user.
3. Zephyr: `embsk setup` (scaffolds the minimal template `app/{west.yml,CMakeLists.txt,prj.conf,src/main.cpp}`, fetches only the needed modules, builds). Bare metal: `embsk scaffold` (template with Unity host tests wired), then copy startup + linker + device headers from the vendor CMSIS pack/SDK into `app/vendor/`; don't hand-write them. Worked examples: `<repo>/example/` (template + a medium nucleo_f767zi project).
4. First slice is always **bring-up**: build for the target, boot, one log line (`LOG_INF("boot ok")`), host test target green. Commit.
5. Continue with phases 3–8 per slice.

## 4. Non-negotiable rules

1. **Hardware safety.** Never flash, erase, mass-erase, change option bytes/fuses/RDP/readout protection, or touch the bootloader partition without the user's explicit OK *for this action*. The `flash-guard` hook enforces this; don't work around it.
2. **Evidence or it didn't happen.** Never write "done", "works", "fixed" without the command output. Name the level: L1 builds · L2 host tests pass · L3 static analysis clean · L4 runs on target with the expected log line · L5 HIL/automated on-target test. No hardware attached? Stop at L2/L3 and say so.
3. **Datasheet-driven.** Every register, bit field, timing or electrical value cites its source (RM/datasheet section, DT binding, Zephyr API doc). Unknown → say so and ask; never invent register addresses or DT properties.
4. **Query, don't crawl.** Use graphify/`rg` to find code; read only the files you'll change and their direct callers. Never read `build/` except the exported files in `docs/generated/`.
5. **Smallest complete change** (ponytail level from the profile). Never cut: input validation, error paths, timeouts on every wait, watchdog/fault handling, calibration, safety mechanisms.
6. **Platform first.** Zephyr: an existing driver/subsystem/devicetree binding beats new code. Bare metal: vendor LL/CMSIS beats hand-written registers when the project already uses it.
7. **One task = one commit** that builds. Message: `<area>: <what> (REQ-n)`. Auto-commit only if the profile says so; otherwise propose the commit.

## 5. Subagents (if the profile has `subagents on` and the tool has them)

Role cards are in `agents/`. Read `references/subagents.md` for how each tool spawns them (Pi `spawn_agent`, Claude Code Task/agents, Codex sequential fallback).

| Role | When | Context |
|---|---|---|
| `fw-scout` | Map phase, datasheet/DT/API lookups, "where is X" | read-only, cheap model, returns paths + facts |
| `fw-builder` | Parallel tasks with **disjoint files** (or separate git worktrees) | one task card each |
| `fw-verifier` | Build/test/log capture while you continue | runs commands, edits nothing |
| `fw-reviewer` | Phase 7, always fresh context (`fork_turns: none`) | diff + spec only, read-only |
| `fw-safety` | T2 with `safety ≠ none` | read-only, MISRA/hazard/traceability |

No subagent tool: do the roles yourself, in order, and for the review re-read only the diff and the spec (simulated fresh context).

## 6. Reference routing (load only what the task needs)

| File | Load when |
|---|---|
| `references/coding.md` | writing any C/DT/Kconfig/CMake (always in Build) |
| `references/review.md` | reviewing a diff, PR, or your own work before "done" |
| `references/testing-verification.md` | writing tests, verifying, HIL, CI test setup |
| `references/debugging.md` | crash, fault, hang, reset, wrong output, flashing/probe trouble |
| `references/context-graphify.md` | first session in a repo, token budget, docs generation |
| `references/spec-plan.md` | new project, new feature, vague request |
| `references/zephyr.md` | `platform=zephyr` |
| `references/baremetal.md` | `platform=baremetal` or `freertos` (startup, linker, clocks, Cortex-M/RISC-V) |
| `references/rtos.md` | threads, ISRs, queues, priorities, stacks, watchdog, timing |
| `references/peripherals.md` | I2C/SPI/UART/CAN/USB/ADC/DMA, sensors, displays |
| `references/power-memory.md` | low power, memory budget, map file, stack/heap, filesystems/flash wear |
| `references/boot-ota-security.md` | MCUboot/bootloader, OTA, signing, secure boot, debug-port lock, keys |
| `references/connectivity.md` | BLE, Wi-Fi, Ethernet/IP, MQTT/CoAP, LoRaWAN, Thread |
| `references/safety.md` | `safety ≠ none`, MISRA/CERT, hazard analysis, traceability |
| `references/docs-release.md` | docs, ADRs, git workflow, CI, versioning, release |
| `references/subagents.md` | spawning roles, parallel work, worktrees |

## 7. Reply format

End every work reply with:
- `Verified: L<n>` + the command(s) that prove it (or `Unverified:` + why).
- `Skipped / not checked:` one line (ponytail). Any risk to hardware or field units: one line.
