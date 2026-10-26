# embedded-sys — documentation (agent handoff pack)

Everything another AI agent (or human) needs to **use**, **maintain** or **extend** the `embedded-sys` skill without the original conversation.

Repository root: the folder that holds this `docs/` (clone it anywhere). Version 1.0.0.

## Start here

| You are… | Read in this order |
|---|---|
| An agent asked to **install** the skill | [`../INSTALL.md`](../INSTALL.md) (or paste prompt D of [`HANDOFF-PROMPT.md`](HANDOFF-PROMPT.md)) |
| An agent starting a new session | [`HANDOFF-PROMPT.md`](HANDOFF-PROMPT.md) (paste it) → this page |
| A human who wants the picture first | [11](11-flow.md) (graphs) → [the example walkthrough](../example/02-nucleo_f767zi-thermal-monitor/docs/WALKTHROUGH.md) → [01](01-overview.md) |
| An agent **using** the skill on a firmware project | [01](01-overview.md) → [11](11-flow.md) → [03](03-agent-workflow.md) → [04](04-embsk-cli.md) → [05](05-zephyr-workspace.md) |
| An agent **maintaining/extending** the skill | [01](01-overview.md) → [02](02-architecture.md) → [04](04-embsk-cli.md) → [08](08-maintaining.md) → [09](09-decisions-and-status.md), then run `docs/quick-check.sh` |
| Debugging a failure | [10](10-troubleshooting.md) |

## Contents

| File | What it covers |
|---|---|
| [`../INSTALL.md`](../INSTALL.md) | Install for any agent on Linux, macOS or Windows, with checks |
| [`HANDOFF-PROMPT.md`](HANDOFF-PROMPT.md) | Copy-paste prompts for a new agent session (use the skill / continue developing it) |
| [`01-overview.md`](01-overview.md) | What the skill is, the 5 sources merged and what was kept/dropped, principles, scope |
| [`02-architecture.md`](02-architecture.md) | Components, data flow, state files, full repository file map |
| [`03-agent-workflow.md`](03-agent-workflow.md) | How an agent works on a firmware project: profile, tiers, 9 phases + gates, rules, evidence ladder, subagents |
| [`04-embsk-cli.md`](04-embsk-cli.md) | `embsk` CLI reference: commands, exit codes, profile schema, validation, doctor checks, generated commands |
| [`05-zephyr-workspace.md`](05-zephyr-workspace.md) | `embsk setup`: west workspace automation, module allowlist algorithm, west gotchas, numbers |
| [`06-integrations.md`](06-integrations.md) | Pi, Claude Code, Codex, tmux, generic agents; installer; hooks (flash guard) |
| [`07-examples.md`](07-examples.md) | The two worked examples (template + medium NUCLEO-F767ZI project) and how to reproduce them; example 02 has a [step-by-step walkthrough](../example/02-nucleo_f767zi-thermal-monitor/docs/WALKTHROUGH.md) |
| [`08-maintaining.md`](08-maintaining.md) | How to add options, probes, HAL rules, references, templates; style contract; regression checklist |
| [`09-decisions-and-status.md`](09-decisions-and-status.md) | Decision log, what was verified, known limits, backlog, facts about the original host |
| [`10-troubleshooting.md`](10-troubleshooting.md) | Symptom → cause → fix |
| [`11-flow.md`](11-flow.md) | How it works as graphs: machine → project → agent; the spec → doc work graph (phases, gates, loops); artifacts per node; one requirement traced end to end |
| [`quick-check.sh`](quick-check.sh) | Offline self-test of the repo (≈ 30 s); `--full` adds a real `embsk setup` with download + build |

## The skill in 10 lines

1. One portable Agent Skill (`skills/embedded-sys/`) for MCU firmware: **Zephyr**, **bare metal**, **FreeRTOS**.
2. A **project profile** (`.embsk/profile.json`), chosen once via an **Alt+A checkbox menu**, fixes board/MCU, probe, logs, safety level and features.
3. `embsk` (one stdlib Python file) validates the profile against the real Zephyr tree and writes an **`embsk` block into `AGENTS.md`** with the exact build/test/flash/log commands.
4. For Zephyr, **`embsk setup`** makes the project folder a west workspace and fetches **only the modules the board needs** (west `name-allowlist`), then builds with the **Zephyr SDK you put on PATH**. The skill never installs a toolchain.
5. The agent follows **SKILL.md**: tiered ceremony (T0/T1/T2), 9 phases with gates, references loaded on demand.
6. Code = **ponytail** rules (smallest complete change, never cut safety/error paths); review = one firmware reviewer with fresh context.
7. Navigation = **graphify** (AST graph, no LLM cost) + resolved devicetree/Kconfig export.
8. Verification = **evidence ladder** L1 build → L5 HIL; never "done" without output. The agent talks to the firmware with `embsk uart` (board, or the same app on native_sim with simulated devices).
9. Flashing/erasing/option bytes always require explicit user OK (deterministic hook).
10. Works with Pi, Claude Code, Codex, Cursor, Gemini CLI, Copilot, OpenCode and any terminal agent, on Linux, macOS and Windows (`install.py`); ~560 tokens always-on.
