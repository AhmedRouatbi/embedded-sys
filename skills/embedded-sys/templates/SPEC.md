# Spec: <product / feature>

Status: draft | approved (<date>, <who>)   ·   Profile: see `embsk` block in AGENTS.md

## Objective
<What it does for whom. One measurable success sentence.>

## Assumptions
1. <assumption — confirmed? yes/no>

## Hardware
| Item | Part / value | Source |
|---|---|---|
| Board / MCU | <from profile> | |
| <sensor/actuator> | <part number> | <datasheet link, rev> |

| Signal | MCU pin | Peripheral | Direction | Level / pull | Notes |
|---|---|---|---|---|---|
| | | | | | |

## Requirements
| ID | Requirement (testable, with numbers) | Verification (host test / target test / measurement / review) |
|---|---|---|
| REQ-1 | | |

## Budgets
| Resource | Budget | Measured |
|---|---|---|
| Flash | <KB of board flash> | |
| RAM | | |
| CPU load / deadlines | <event → deadline> | |
| Power | <µA sleep, mA active, lifetime> | |

## Interfaces
- External protocol / frames: <format, versioning>
- Shell commands: <cmd → output>
- Log lines (verifier greps these): `boot ok v<ver>`, <...>

## Failure modes
| Fault | Detection | Reaction | Reaction time |
|---|---|---|---|
| Watchdog / hang | | | |
| Brown-out | | | |
| <bus/sensor absent> | | | |

## Safety (only if profile safety ≠ none)
Safety functions, hazards (docs/safety/hazards.md), `SR-n` requirements with integrity level, safe state.

## Boundaries
- Always: <run tests, check returns, ...>
- Ask first: <new dependency, partition/flash layout, pin changes, Kconfig defaults>
- Never: <flash without OK, touch bootloader/option bytes, commit secrets>

## Out of scope
- <explicitly not doing>

## Agent toolbox (navigate, verify, debug this project)
Commands come from the `embsk` block in AGENTS.md; this section maps them to this spec.

| Question | Command |
|---|---|
| Main pieces / where to start | `graphify god-nodes --top 10` (then open `graphify-out/graph.html`) |
| Where is REQ-n implemented | `graphify query "<REQ-n in words>"` → `graphify explain "<function>()"` |
| What breaks if I change X | `graphify affected "<function>()"` |
| Is DT node / Kconfig really enabled | `embsk export build && rg -n "<node>" docs/generated/dt-nodes-and-status.txt` |
| Build + host tests + SIL + size | `embsk verify` |
| Talk to the firmware (board or SIL) | `embsk uart --send "<shell cmd>" --expect "<line>"` |

| Need | Say to the agent / run | Skill part |
|---|---|---|
| Profile, board, probe | Alt+A · `/embsk` · `embsk set ...` | embsk |
| Next task | `task <n> from docs/PLAN.md` | phases 5–6, `coding.md`, `testing-verification.md` |
| Something is wrong | `debug: <symptom>` | `debugging.md` (UART loop) |
| Fresh-context review | `review` | `review.md`, `fw-reviewer` |
| Docs at a milestone | `doc` | `docs-release.md`, `graphify export wiki` |
