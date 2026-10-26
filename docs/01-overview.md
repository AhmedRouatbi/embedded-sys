# 01 — Overview

## What it is

`embedded-sys` is a single, portable **Agent Skill** (agentskills.io format: `SKILL.md` + `references/` + `scripts/` + `templates/` + `agents/`) that turns a coding agent into a disciplined firmware engineer for **MCU projects on Zephyr RTOS, bare metal and FreeRTOS**. Around the skill sit small adapters so it behaves the same in **Pi, Claude Code, Codex** and any terminal agent:

- the `embsk` CLI (project profile, validation, Zephyr workspace automation),
- an **Alt+A** checkbox menu,
- a deterministic **flash guard** hook,
- 5 firmware **subagent role cards**,
- a Pi multi-phase **workflow**.

Core idea: the bench is the source of truth. Generated C is a hypothesis until a build, a test and (with hardware attached) a log line prove it.

## Why it exists — the merge

The user wanted an automated embedded workflow from four toolkits plus their Pi subagents. Installed side by side they cost ~9,300 always-on tokens, put 50+ skills in competition for triggers, and duplicated each other inside each axis (4 code reviewers, 2 testing doctrines, 15 domain personas). This skill merges them into one router + on-demand references (~560 always-on tokens).

| Source (MIT; graphify Apache-2.0, see THIRD-PARTY-NOTICES.md) | Axis | Kept (where it lives now) | Dropped |
|---|---|---|---|
| [LibreEmbed-Claude-Code](https://github.com/Ormus-Solutions/LibreEmbed-Claude-Code) — 15 plugins (agent + command + skill each) + hooks | domain knowledge | rewritten Zephyr-first into `references/` (zephyr, baremetal, rtos, debugging, peripherals, power-memory, boot-ota-security, connectivity, safety, testing); its flash-confirm hook → `hooks/flash-guard.sh` (extended) | embedded-linux, fpga-integration (out of MCU scope); 15 personas → 5 role cards; 15 slash commands → `/embsk` |
| [ponytail](https://github.com/DietrichGebert/ponytail) — 6 skills | how much code / review | the "smallest complete change" ladder → `references/coding.md`; ponytail-review format → `references/review.md`; `shortcut:` comment convention | audit, debt, gain, help skills |
| [agent-skills](https://github.com/addyosmani/agent-skills) (addyosmani) — 25 skills | process | spec, plan, incremental, interview, TDD, debugging, docs/ADR, git, CI, shipping, constraint-driven, doubt-driven, context-engineering, source-driven → phases in `SKILL.md` + `spec-plan.md`, `testing-verification.md`, `debugging.md`, `review.md`, `safety.md`, `docs-release.md`, `context-graphify.md` | frontend-ui, browser-testing, api-design, web performance, idea-refine, using-agent-skills, deprecation (web/meta) |
| [graphify](https://github.com/Graphify-Labs/graphify) — CLI + 713-line skill | cheap context | the CLI stays a tool (`graphify update .` AST mode, `query/explain/path/affected`); usage condensed to `context-graphify.md`; resolved-DTS export (`embsk export`) | the long extraction procedure (not needed for AST mode) |
| Pi subagents + workflow extensions (user's Pi setup) | parallelism / fresh context | `references/subagents.md`, `agents/fw-*.md`, `pi-workflows/embedded.yaml` | — |

Resolved collisions:
- One reviewer: ponytail format + firmware axes + a doubt loop for critical changes.
- TDD and embedded testing merged into one evidence ladder.
- "source-driven" became the **datasheet-driven** rule: every register or timing claim cites its source.
- constraint-driven and doubt-driven are folded into safety and review.

## Design principles

1. **Profile = contract.** Board, probe, safety level and commands are decided once and validated against the real Zephyr tree. The agent never guesses or re-derives them.
2. **Evidence ladder:** L1 build · L2 host tests · L3 static analysis · L4 on-target log line · L5 automated HIL. Every reply states the level reached.
3. **Close the hardware loop.** Logs go to `artifacts/*.txt` (RTT/UART), a shell gives the agent a query surface, and stack high-water marks are measured.
4. **Functional core / hardware shell.** Logic lives in plain C that runs in host tests; drivers stay thin.
5. **Deterministic gates for irreversible actions.** Flash, erase, option bytes, RDP and fuses always ask, via a hook rather than a model decision.
6. **Fresh-context adversarial review**, plus an independent safety audit when a standard applies.
7. **Ceremony scales with stakes:** T0 trivial / T1 standard / T2 critical (safety functions are always T2).
8. **Query, don't crawl.** Use the graph and targeted reads; state lives in files (SPEC, ADRs, AGENTS.md), not chat.
9. **Only what is needed.** Zephyr workspaces fetch only the board's modules (allowlist). References load on demand.

## Scope

- In: Cortex-M / RISC-V / Xtensa MCUs; Zephyr 4.x (HWMv2 board names); bare metal with vendor CMSIS packs; FreeRTOS; probes OpenOCD, J-Link, pyOCD, ST-Link/STM32CubeProgrammer, probe-rs, LinkServer, nrfutil/nrfjprog, esptool, Black Magic; functional safety orientation (IEC 61508, ISO 26262, IEC 62304, DO-178C, IEC 60730, EN 50128).
- Out: embedded Linux (Yocto/Buildroot), FPGA/HDL, certification claims (the skill produces evidence; humans decide compliance).

## Status (at handoff)

- Version 1.0.0. All components built and tested on the original host (see [09](09-decisions-and-status.md)).
- No on-target (L4) hardware run yet. Codex and tmux paths are untested (tools not installed on the original host).
- Installer: `install.py` (Linux, macOS, Windows), verified end to end on Linux with the real Claude Code and Pi CLIs in a throw-away HOME. Windows code paths are covered by a simulation in quick-check but were not run on a Windows host. Check with `python3 install.py --check` (Windows: `py -3 install.py --check`).
