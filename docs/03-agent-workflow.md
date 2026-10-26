# 03 — How an agent works with the skill

Authoritative source: [`skills/embedded-sys/SKILL.md`](../skills/embedded-sys/SKILL.md). This page is a condensed map of it.

## Session start (always)

1. Read the `embsk` block in the project's `AGENTS.md`: target, probe, logs, tests, HIL, safety, features, west workspace line, **commands table**, hard rules, references to load.
2. No profile: ask the user for **Alt+A** / `/embsk` / `embsk menu`. With a structured-question tool, the agent may ask itself, using values from `embsk schema` and boards from `embsk boards <mcu>`, then a single `embsk set k=v …`. **Never guess a board.**
3. `embsk doctor`: any `ERR` blocks hardware work until fixed.
4. Zephyr: `embsk setup` after a new profile or any board/feature change. It owns `west init`/`update` and the module allowlist (see [05](05-zephyr-workspace.md)).
5. The Zephyr SDK is the user's, found via PATH. Missing (doctor `ERR`, setup exit 3): show the printed fix line and wait. Never install it.

## Tiers

| Tier | When | Phases |
|---|---|---|
| T0 trivial | one Kconfig line, typo, log message, a pin in an overlay | Build → Verify (L1) |
| T1 standard | new driver, thread, protocol, feature, bug fix | Map → Spec-lite → Plan → Build → Verify → Review |
| T2 critical | bootloader/OTA/flash layout, can brick a unit, security, **any safety function when safety ≠ none** | all phases + independent review + safety audit + release checklist |

## Phases and gates

As a graph (nodes, gates, loops, artifacts): [11-flow.md §B](11-flow.md#b-the-work-graph-spec--doc).

| # | Phase | Gate | Reference |
|---|---|---|---|
| 1 | Map: `graphify update .`, `graphify query/explain/path/affected`; `embsk export build` after DT/Kconfig changes | can name the files/symbols the change touches | `context-graphify.md` |
| 2 | Specify: `docs/SPEC.md` from template; numbered `REQ-n`, budgets, failure modes; ≤ 5 one-at-a-time questions if vague | user approved (T1: 10-line spec-lite in chat) | `spec-plan.md` |
| 3 | Design: concurrency table, DT/Kconfig plan, core/shell split, ADRs; T2+safety: hazard table | every REQ maps to a component | platform + feature refs |
| 4 | Plan: vertical slices; bring-up first; each task = files + test + verify command | each task ≤ 1 commit, independently verifiable | `spec-plan.md` |
| 5 | Build: failing host test → smallest code → target build → size | task's verify command passes | `coding.md` |
| 6 | Verify: climb L1→L5; flash only with explicit OK; talk to the firmware with `embsk uart` (board or SIL), transcripts in `artifacts/*.txt` | highest level stated with evidence | `testing-verification.md` |
| 7 | Review: fresh-context, diff + connected code; T2 adds safety audit and doubt loop | "Verdict: Ship" | `review.md` (+ `safety.md`) |
| 8 | Document: graphify update/wiki, README/ADRs, traceability (T2) | docs match code | `docs-release.md` |
| 9 | Release (T2/on request): version, changelog, signed image, hashes, rollback | checklist green | `docs-release.md`, `boot-ota-security.md` |

Bugs: `debugging.md` method (reproduce → minimize → one hypothesis → instrument → fix root cause → regression test), then phases 6–7.

New project from a description: profile → spec → `embsk setup` (Zephyr: scaffolds the template and builds) or `embsk scaffold` (bare metal) → first slice = **bring-up** (boots, one log line, host test target green) → continue per slice.

## Non-negotiable rules

1. **Hardware safety:** no flash/erase/mass-erase/option bytes/RDP/fuses/bootloader-partition changes without explicit user OK for that action (hook enforced).
2. **Evidence or it didn't happen:** name the level reached (L1 build, L2 host tests, L3 static analysis, L4 on-target log, L5 HIL). No hardware → stop at L2/L3 and say so.
3. **Datasheet-driven:** every register/bit/timing value cites RM/datasheet section, DT binding or API doc; unknown → ask.
4. **Query, don't crawl:** graph/`rg` first; read only files to change + direct callers; never read `build/` except `docs/generated/`.
5. **Smallest complete change** (ponytail level from the profile). Never cut: input validation, error paths, timeouts on every wait, watchdog/fault handling, calibration, safety mechanisms.
6. **Platform first:** an in-tree Zephyr driver/subsystem/binding beats new code; on bare metal, the vendor LL/CMSIS beats hand-written registers.
7. **One task = one commit** that builds: `<area>: <what> (REQ-n)`. Auto-commit only if the profile says so.

## Evidence ladder

| Level | Evidence |
|---|---|
| L1 | target build passes, no new warnings |
| L2 | host unit tests pass (ztest on `native_sim/native/64`, Unity/CMocka) |
| L3 | static analysis clean on changed files (cppcheck/clang-tidy/`ZEPHYR_SCA_VARIANT`, MISRA checker if configured) |
| L4 | flashed with OK, expected log line in `artifacts/uart.txt`/`rtt.txt`, no `<err>/ASSERT/FATAL` |
| L5 | automated on-target test (twister `--device-testing`, pytest harness, Renode) |

## Subagents (when `subagents on` and the tool supports them)

| Role | Writes? | Context | Returns |
|---|---|---|---|
| `fw-scout` | no | question + where to look | file:line facts |
| `fw-builder` | only listed files | one task card | diff summary + verify output |
| `fw-verifier` | only `artifacts/` | AGENTS.md commands | PASS/FAIL per level |
| `fw-reviewer` | no | diff + spec, **fresh context** (Pi `fork_turns: "none"`) | review.md report |
| `fw-safety` | no | diff + safety reqs + standard/level | MISRA/hazard/traceability findings |

Parallel writers need disjoint files or git worktrees. A probe or serial port has a single owner. No subagent tool: run the roles sequentially and simulate fresh context for review. Details: `references/subagents.md`.

## Reference routing

| File | Load when |
|---|---|
| `coding.md` | writing any C/DT/Kconfig/CMake |
| `review.md` | reviewing a diff or before "done" |
| `testing-verification.md` | tests, verification, HIL, CI tests |
| `debugging.md` | crash, fault, hang, reset, wrong output, probe trouble |
| `context-graphify.md` | first session in a repo, token budget, docs generation |
| `spec-plan.md` | new project/feature, vague request |
| `zephyr.md` | platform=zephyr (includes §Workspace) |
| `baremetal.md` | platform=baremetal/freertos (startup, linker, clocks, cores) |
| `rtos.md` | threads, ISRs, queues, priorities, stacks, watchdog, timing, DSP |
| `peripherals.md` | buses, DMA, ADC, sensors, displays |
| `power-memory.md` | low power, memory budget, storage/flash wear |
| `boot-ota-security.md` | MCUboot, OTA, signing, secure boot, debug lock, keys |
| `connectivity.md` | BLE, Wi-Fi, Ethernet/IP, MQTT/CoAP/LwM2M, LoRaWAN, Thread |
| `safety.md` | safety ≠ none or coding standard set |
| `docs-release.md` | docs, git, CI, versioning, release |
| `subagents.md` | spawning roles, parallel work |

`embsk` writes the subset relevant to the profile into the AGENTS.md block (rule 6). See `refs_for()` in [04](04-embsk-cli.md).

## Reply format

Every work reply ends with:
- `Verified: L<n>` + the proving command(s), or `Unverified:` + reason.
- `Skipped / not checked:` one line, plus any risk to hardware or field units.
