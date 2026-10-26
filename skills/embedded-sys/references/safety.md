# Functional safety & coding standards

> Load when: profile `safety ≠ none` or `coding_standard ≠ none`; hazard analysis; safety mechanisms; MISRA/CERT questions; T2 reviews of safety functions.
> Profile keys: `safety`, `safety_level`, `coding_standard`, `ponytail`.

**The agent produces evidence; humans and assessors decide compliance.** Never write "compliant with ISO 26262" or "SIL 2 certified". Write "MISRA checker reports 0 required-rule violations in changed files; deviation DEV-4 recorded".
Every change touching a safety function is tier **T2**: spec'd (SR-n), reviewed by `fw-safety` + `fw-reviewer` with fresh context, traced, tested including fault paths. Ponytail still applies — but defensive checks and safety mechanisms are never "lean findings".

## Standards at a glance (confirm details against the standard text + your safety plan)

| Standard | Domain | Levels (low → high) | Typical structural coverage expectation (unit level) | Notable software demands |
|---|---|---|---|---|
| IEC 61508-3 | industrial / generic | SIL 1–4 | statement (SIL 2+ HR), branch (SIL 3+ HR), MC/DC (SIL 4 HR) | coding standard, defensive programming, static analysis, tool qualification (T1–T3) |
| ISO 26262-6 | automotive | QM, ASIL A–D | statement (A/B), branch (B–D), MC/DC (D highly recommended) | MISRA, FFI between ASIL/QM parts, unit + integration tests, ASPICE-style process |
| IEC 62304 | medical device SW | class A–C | not numeric; unit verification for B/C | SOUP management, risk control (ISO 14971), traceability |
| DO-178C | airborne | DAL E–A | statement (C), decision (B), MC/DC (A) | independence of verification, requirements-based tests, tool qualification (DO-330) |
| IEC 60730-1 Annex H | appliances | class A–C | — | class B self-tests: CPU registers, RAM, flash CRC, clock, I/O (vendor class-B libraries) |
| EN 50128 / EN 50716 | railway | SIL 0–4 | by SIL table | defensive programming, formal methods recommended at high SIL |

## Lifecycle artifacts the agent can draft (human-owned)

| Artifact | File | Agent's job |
|---|---|---|
| Safety requirements `SR-n` (with level, safe state, reaction time) | `docs/safety/SRS.md` | derive from hazards; each testable |
| Hazard analysis / FMEA | `docs/safety/hazards.md` | table below; propose detections/mechanisms |
| Architecture + freedom from interference | ADRs, `docs/safety/architecture.md` | MPU regions, priorities, time partitioning, data ownership |
| Deviation log | `docs/safety/deviations.md` | `DEV-n`: rule, location, reason, risk, approver (human) |
| Traceability matrix | generated | `rg` SR ids in code/tests (below) |
| Verification report | `docs/safety/verification.md` | ladder evidence + coverage numbers + analyzer output |
| Change impact analysis | PR description | which SRs/mechanisms a change touches |

Hazard table (FMEA-lite):

```
| Function | Failure mode | Effect | Sev | Detection | Mechanism / safe state | Reaction time | SR |
| Heater control | output stuck on | overheat | 4 | temp > limit, plausibility vs. 2nd sensor | cut relay via independent GPIO, latch fault | < 500 ms | SR-3 |
```

## Coding standard — what agents must do

MISRA C:2012/2023 (licensed rule texts; categories mandatory / required / advisory — e.g. Rule 15.5 single exit is **advisory**, Rule 17.3 implicit declarations is mandatory):

- No undefined/unspecified behaviour (Dir 1.1/Rule 1.3): uninitialized reads, signed overflow, shifts ≥ width, out-of-bounds, unsequenced side effects (13.2).
- Essential types: no implicit narrowing/sign changes; explicit casts with range checks; `U` suffix on unsigned literals; booleans are `bool`, conditions are boolean (`ptr != NULL`, not `ptr`).
- Control flow: no `goto` into blocks, all `switch` with `default` + `break`, `if…else if` chains end in `else`, no invariant conditions, bounded loops.
- Memory: no dynamic allocation after init (Dir 4.12), no recursion (17.2), no `setjmp/longjmp`, no `<stdio.h>` in production paths.
- Functions: return values used or cast to `(void)` (17.7); parameters validated; prototypes visible (17.3).
- Pointer casts between object types avoided (11.3) — `memcpy` for type punning; no pointer arithmetic outside arrays.
- Deviations: in code `/* MISRA C:2012 Rule 11.5 deviation DEV-7: <reason> */` + entry in `docs/safety/deviations.md`. Never an anonymous suppression.

CERT C: INT30/31/32-C (wrap/convert/overflow), ARR30/38-C (bounds), STR31-C, MEM30/35-C, ERR33-C (check returns), CON (data races).

Checking (L3): `cppcheck --addon=misra --enable=all --inline-suppr` (rule texts file needed for messages) · clang-tidy `cert-*,bugprone-*,clang-analyzer-*` · commercial (PC-lint Plus, Helix QAC, Polyspace, Parasoft, LDRA, ECLAIR — Zephyr supports `-DZEPHYR_SCA_VARIANT=eclair`/`cpptest`/`polyspace`). Run on changed files every task; full scan per milestone. Analyzer output saved to `artifacts/sca.txt`.

Zephyr note: Zephyr's own coding guidelines are a MISRA C:2012 subset and the project pursues IEC 61508 certification for a scoped kernel subset on LTS releases — check the current scope before claiming anything; out-of-scope subsystems need your own justification (SOUP / proven-in-use / additional verification).

## Safety mechanism catalog

| Mechanism | Detects | Implementation hints |
|---|---|---|
| Windowed watchdog + heartbeat aggregation | stuck/runaway threads | `rtos.md` §Watchdog; independent clock source (LSI); never kicked from ISR |
| Startup self-tests | RAM stuck-at/coupling (March C), flash corruption (CRC over image vs. stored), CPU registers, clock | prefer vendor certified self-test libraries (e.g. ST X-CUBE-STL/CLASSB, NXP/Microchip class-B libs); RAM test before `.bss` init or on a reserved region |
| Runtime memory protection | stack overflow, wild writes | MPU regions per partition (Zephyr userspace/memory domains), stack guards, canaries |
| Redundant storage of critical variables | RAM bit flips | value + one's complement (or two copies + CRC), checked on every read → fault reaction |
| CRC/ECC | NVM/message corruption | CRC-16/32 with sequence counters for messages (E2E profiles in automotive); enable hardware ECC where available |
| Range + plausibility checks | sensor faults, wiring | min/max, rate-of-change, cross-check redundant sensors, timeouts on fresh data |
| Clock & voltage monitoring | oscillator failure, brown-out | CSS/clock monitor IRQ, BOR/PVD levels, fault on loss |
| Program flow monitoring | skipped/reordered steps | checkpoint signatures verified by the supervisor |
| Safe state + fault latch | any detected fault | defined outputs (de-energize), stored fault record (reset cause + code), no auto-restart unless the SR allows |
| Diverse/dual channel | systematic + random faults at high SIL | separate MCU/core or diverse algorithm; compare results |

Fault reaction time = detection interval + reaction latency; must be < process safety time from the SR.

## Traceability

- Tag code: `/* SR-3, REQ-12 */` on the function implementing it; tests named `test_sr3_overtemp_cuts_relay`.
- Matrix: `rg -n "SR-[0-9]+" src/ include/ | sort` vs. `rg -n "test_sr[0-9]+" tests/` vs. `docs/safety/SRS.md`. Every SR → ≥ 1 implementation + ≥ 1 test (fault path included). Gaps are findings.
- Coverage: `west twister --coverage -p native_sim/native/64 -T tests` (gcov/lcov) for statement/branch; MC/DC needs a qualified tool (VectorCAST, LDRA, Testwell, gcc 14+ `-fcondition-coverage` for exploration only).

## Guard the bar (constraint-driven)

Write `CONSTRAINTS.md` (from `templates/CONSTRAINTS.md`) with the numbers: required-rule violations = 0, warnings = 0, coverage ≥ target, stack margin ≥ 30 %, flash/RAM headroom. Then watch every diff for a lowered bar and report it as **Must fix**:
- new suppressions without DEV id (`cppcheck-suppress`, `NOLINT`, `#pragma GCC diagnostic ignored`, `-Wno-*`);
- skipped/deleted tests (`ztest_test_skip()`, `TEST_IGNORE()`, removed test files, `platform_exclude` added);
- removed asserts/range checks/watchdog feeds; thresholds or timeouts relaxed; coverage targets edited down;
- stubs that return success (`return 0; /* TODO */`).

## Review (used by `fw-safety` and `review.md`)

1. Coding standard violations in changed lines; undocumented deviations.
2. Safety mechanisms intact and still reachable (no new path that bypasses checks or feeds the watchdog unconditionally).
3. FFI: non-safety code can't corrupt safety data (MPU, ownership), starve safety threads (priorities, time budgets), or block shared resources.
4. Fault paths tested, not only happy paths; reaction time still within budget after the change.
5. Traceability and change impact recorded; independent review recorded at the level the standard requires.
6. AI-generated code flagged in the PR description for the human reviewer/assessor (process transparency).

## Anti-patterns

- Agent claiming certification or compliance.
- Suppressing analyzer findings to get green; "temporary" deviations without records.
- Feeding the watchdog from a timer ISR "to stop resets".
- Safety and non-safety code sharing a thread/stack/buffer without analysis.
- Using ponytail "lean" arguments to remove redundancy that a safety requirement demands.

## Sources
LibreEmbed `safety-critical` (skill + agent, corrected); agent-skills `constraint-driven-development`, `doubt-driven-development`, `security-and-hardening`; IEC 61508-3, ISO 26262-6, DO-178C, IEC 62304, IEC 60730 (summaries — verify against licensed texts).
