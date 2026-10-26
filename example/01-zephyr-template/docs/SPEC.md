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
