# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) · versions: [SemVer](https://semver.org/).

## [1.0.0] - 2026-10-26

First public release.

### Added
- **Skill `embedded-sys`** (`skills/embedded-sys/`):
  - `SKILL.md` router: profile → tiers T0/T1/T2 → 9 phases with gates;
  - 16 on-demand references (Zephyr-first);
  - 5 firmware role cards (`fw-scout`, `fw-builder`, `fw-verifier`, `fw-reviewer`, `fw-safety`);
  - templates for Zephyr, bare metal, SPEC, ADR and CONSTRAINTS.
- **`embsk` CLI** (one stdlib Python file):
  - project profile with the Alt+A checkbox menu, `set`, `doctor` (validated against the real Zephyr tree: board, MCU ↔ SoC, probe ↔ runner), and the AGENTS.md block with the exact commands;
  - `setup`: the project becomes a west workspace that fetches only the modules the board needs;
  - `verify`: build + host tests + SIL scenario + size;
  - `export`: resolved DTS/Kconfig/map;
  - `uart`: a bounded send/expect session, so an agent can talk to the firmware.
- **SIL pattern:** the unchanged app on `native_sim`, with simulated devices behind the same Zephyr APIs, driven over its UART by scenario files.
- **Zephyr SDK from PATH only.** The skill never installs a toolchain.
- **Adapters:**
  - Claude Code plugin + marketplace (`/embsk`, agents, hooks, Alt+A);
  - Pi package (Alt+A, status, flash-guard gate) + `embedded` workflow;
  - Codex prompt + plugin;
  - tmux popup for any terminal agent.
- **Flash guard** (pure bash hook): asks before flash, erase, option bytes, RDP and fuses, in Bash, PowerShell and Codex tool calls.
- **Installer** `install.py` for Linux, macOS and Windows (junctions, launchers, user PATH); `--check` runs smoke tests; [INSTALL.md](INSTALL.md) is written for agents.
- **Examples:**
  - `01-zephyr-template`;
  - `02-nucleo_f767zi-thermal-monitor`, with spec, plan, ADR, review, SIL scenario, code graph and a [step-by-step walkthrough](example/02-nucleo_f767zi-thermal-monitor/docs/WALKTHROUGH.md).
- **Docs and tests:** handoff documentation in `docs/`, `docs/quick-check.sh` (offline self-test, `--full` with a real build), CI for Linux and Windows.

### Known limits
- No on-target (L4) run yet: the examples are verified up to L2, including the SIL.
- Windows code paths are unit-simulated; the Windows CI job is their first real run.
- Codex plugin hooks and the tmux binding are untested.
