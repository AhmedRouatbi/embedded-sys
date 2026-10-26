---
description: Embedded project profile menu — platform, Zephyr board / MCU, debug probe, logs, safety level, features. Writes .embsk/profile.json and the embsk block in AGENTS.md.
argument-hint: "[doctor | commands | key=value ...]"
allowed-tools: Bash(embsk:*), Bash(python3:*), AskUserQuestion, Read
---

Configure the embedded project profile for the `embedded-sys` skill.

`EMBSK` = `embsk` if it is on PATH, else `python3 <embedded-sys skill dir>/scripts/embsk.py` (Windows: `py -3 …` or `python …`).

Arguments: `$ARGUMENTS`
- `doctor` or `commands` → run `EMBSK <arg>`, show the output, stop.
- `key=value ...` → run `EMBSK set $ARGUMENTS`, show the doctor lines it prints, stop.
- empty → run the menu below.

## Menu (checkbox UI)

1. Run `EMBSK get` (current values) and `EMBSK schema` (allowed values). Pre-select current values; never invent values outside the schema.
2. If you have a structured question tool (Claude Code `AskUserQuestion`; Codex `request_user_input`), ask in these rounds. Each question: max 4 options, the user can always type "Other". Put the current value first, marked "(current)".
   - **Round 1** (single-select each): Platform (zephyr / baremetal / freertos) · Debug probe (current + openocd / jlink / pyocd / stlink; Other for probe-rs, linkserver, nrfutil, esptool, blackmagic, none) · Log transport (rtt / uart / swo / none) · Safety standard (none / iec61508 / iso26262; Other for iec62304, do178c, iec60730, en50128).
   - **Round 2 — target**:
     - zephyr: ask "Board or MCU?" with up to 4 suggestions from `EMBSK boards <current mcu or board>`; the user may type a board name, identifier or MCU (e.g. `stm32f401re`). Resolve with `EMBSK boards <text>`. One match → use it. Several identifiers (qualifiers like `/max32690/m4`) → ask again with those as options. None → show the closest names and ask again. Never set a board that `EMBSK boards` didn't list.
     - baremetal/freertos: MCU (free text via Other, suggest current), CPU core (cortex-m0+ / cortex-m4f / cortex-m33 / Other), Build system (cmake / make / platformio / vendor-ide).
     - If safety ≠ none: Integrity level from `levels[<standard>]` in the schema, and Coding standard (misra-c-2012 / misra-c-2023 / cert-c / none).
   - **Round 3 — features** (multiSelect: true, four questions): Connectivity (ble, wifi, ethernet, lora) · Peripherals (can, usb, sensors, display) · System (low-power, filesystem, dsp, bootloader-ota) · Security (secure-boot, none).
   - **Round 4 — workflow**: Tests (ztest / unity / cmocka / none) · Hardware in loop (none / board / renode / qemu) · Code discipline (full / lite / ultra) · Options (multiSelect: graphify, subagents, autocommit).
   No structured question tool: ask the user to press **Alt+A** in tmux or run `embsk menu` in a terminal; or, if they prefer chat, list the options as a compact numbered checklist and parse their reply.
3. Apply everything in one call: `EMBSK set platform=... board=... mcu=... debugger=... log=... safety=... safety_level=... coding_standard=... features=a,b,c tests=... hil=... ponytail=... graphify=true|false subagents=true|false autocommit=true|false` (lists comma-separated, no spaces; empty list = `features=`).
4. Show the doctor lines it prints. For every `ERR` (board doesn't exist, MCU ≠ board SoC, probe not a runner for this board, invalid level), explain the fix in one line and offer to re-ask just that question. `WARN` lines: show, don't block.
5. Zephyr: run `EMBSK setup` — it scaffolds the app if missing, writes `app/west.yml` with only the modules this board needs (name-allowlist), runs `west init -l app` + shallow `west update`, checks Python deps and the Zephyr SDK, then builds. The SDK is the user's: it must already be installed and on PATH; the skill never installs it. Exit 3 = SDK not on PATH: show the user the printed `export PATH=…` / install line, wait for them to fix it, then re-run `EMBSK setup`. Bare metal: `EMBSK scaffold`.
6. Finish with the target, the build result, the commands table location (embsk block in `AGENTS.md`), and the next step: "describe the feature".
