# 04 — `embsk` CLI reference

File: `skills/embedded-sys/scripts/embsk.py` (Python ≥ 3.9, stdlib only; PyYAML used if present). `install.py` installs it as `~/.local/bin/embsk` (Linux/macOS symlink; Windows `embsk.cmd` + a Git Bash launcher). Without it: `python3 <skill>/scripts/embsk.py` (Windows `py -3 …`).

Windows: runs natively (cmd, PowerShell, Git Bash). It re-runs itself in Python's UTF-8 mode, uses `.venv\Scripts`, finds `*.exe` toolchains on PATH, and prints PowerShell PATH fixes. Two parts need more: `embsk export` needs Git Bash, and `embsk menu` needs `windows-curses` (installed by `install.py`). Host tests on `native_sim` need Linux, so doctor warns on Windows: use WSL or a QEMU `host_board`.

## Project root

All commands act on the **project root**: the nearest directory (cwd or a parent) that contains `.embsk/`; otherwise the git top-level; otherwise cwd. Create `.embsk/` first (or run `embsk set …`, which creates it) when the folder sits inside an unrelated git repo.

## Commands

| Command | Does | Writes | Exit |
|---|---|---|---|
| `embsk menu [--wait]` (default) | curses checkbox menu (`--wait`: "Press Enter" at the end, used by the Pi popup); `s` saves (asks if doctor has ERR); Zephyr: then offers **setup + build now? [Y/n]** | profile, AGENTS.md, CLAUDE.md, `artifacts/` | setup's code, or 0 |
| `embsk set k=v [k=v…]` | non-interactive update; lists comma-separated (`features=ble,can`, empty: `features=`); validates *after* all assignments | profile, AGENTS.md | 1 on invalid key/value |
| `embsk get [key]` | profile JSON or one value (JSON) | — | 0 |
| `embsk schema` | options + levels as JSON (for front-ends) | — | 0 |
| `embsk boards <query>` | search boards by identifier, full name or MCU/SoC (≤ 40 results with SoC, arch, runners) | — | 0 |
| `embsk doctor` | validate profile vs Zephyr tree and tools (table below) | — | 1 if any ERR |
| `embsk render` | rewrite the managed block in AGENTS.md | AGENTS.md, CLAUDE.md | 0 |
| `embsk commands` | print the generated command table | — | 0 |
| `embsk scaffold` | copy the platform template into the project (never overwrites); Zephyr: re-render | template files, `docs/SPEC.md` | 0 |
| `embsk setup [--no-build]` | Zephyr workspace automation (see [05](05-zephyr-workspace.md)); uses the Zephyr SDK from PATH, never installs it | `app/west.yml`, `.west/`, `deps/`, maybe `.venv/`, `build/` | 0 ok · 1 board not found · 2 not Zephyr / app_dir "." · 3 Zephyr SDK not on PATH (prints the fix line) · build's exit code · `SystemExit` message if a west/pip command fails |
| `embsk modules` | print the west modules the board + features need; notes on stderr | — | 1 if board unknown / no tree |
| `embsk export [build-dir]` | run `export-zephyr-context.sh`: resolved `zephyr.dts`, DT macros, `.config`, `autoconf.h`, map, linker script, size report, node/status index, `runners.yaml` → `docs/generated/` | `docs/generated/*` | script's code |
| `embsk verify` | run `build`, `test_host`, `sil`, `size` from the command table; stops at the first gating failure; size is informational (WARN) | `artifacts/verify.txt` | 1 if build/test/SIL failed |
| `embsk uart [--port P] [--baud N] [--exec "CMD"] [--log F] [--timeout S] STEPS` | one bounded UART session for agents: steps `--send TEXT`, `--expect REGEX` (a line received after the last send), `--sleep S`, `--fail-on REGEX`, `--script FILE` run in order; CR after each send; colours and the shell's prompt redraws removed; no steps = listen for `--timeout` s. Serial: pyserial, else POSIX termios (Windows needs pyserial; `install.py` adds it). `--exec`: a process's stdin/stdout, e.g. a native_sim SIL build | appends to `artifacts/uart.txt` | 0 all expects matched · 1 timeout / fail-on / target gone · 2 usage or port |

## Profile schema (`.embsk/profile.json`)

| Key | Type | Default | Values / notes | Menu shows when |
|---|---|---|---|---|
| `platform` | choice | `zephyr` | zephyr, baremetal, freertos | always |
| `board` | board | `""` | Zephyr identifier, e.g. `nucleo_f767zi`, `nrf5340dk/nrf5340/cpuapp`; menu has a search screen | zephyr |
| `mcu` | text | `""` | free text (`STM32F767ZI`); Zephyr: auto-filled from the board's SoC if empty/mismatching | always |
| `app_dir` | text | `app` | app + (Zephyr) manifest repo folder; must not be `.` for `setup` | always |
| `zephyr_rev` | text | `v4.4.2` | written into `app/west.yml` by setup | zephyr |
| `extra_modules` | list | `[]` | extra west modules for the allowlist, e.g. `hal_st` | zephyr |
| `host_board` | text | `native_sim/native/64` | host test board | zephyr |
| `core` | choice | `auto` | auto, cortex-m0+, -m3, -m4f, -m7, -m33, -m55, riscv32, xtensa | always |
| `toolchain` | choice | `zephyr-sdk` | zephyr-sdk, gnu-arm, llvm, iar, keil | always |
| `build` | choice | `cmake` | cmake, make, platformio, vendor-ide | baremetal/freertos |
| `elf` | text | `build/app.elf` | bare-metal image path | baremetal/freertos |
| `debugger` | choice | `openocd` | openocd, jlink, pyocd, stlink, probe-rs, linkserver, nrfutil, esptool, blackmagic, none | always |
| `log` | choice | `rtt` | rtt, uart, swo, usb-cdc, semihosting, none | always |
| `serial_port` | text | `/dev/ttyACM0` | | log ∈ uart, usb-cdc |
| `tests` | choice | `ztest` | ztest, unity, cmocka, none | always |
| `hil` | choice | `none` | none, board, renode, qemu | always |
| `safety` | choice | `none` | none, iec61508, iso26262, iec62304, do178c, iec60730, en50128 | always |
| `safety_level` | level | `-` | per standard: SIL1–4 · QM, ASIL-A–D · class-A–C · DAL-E…A · class-A–C · SIL0–4 | safety ≠ none |
| `coding_standard` | choice | `none` | none, misra-c-2012, misra-c-2023, cert-c, barr-c | always |
| `features` | multi | `[]` | low-power, ble, wifi, ethernet, can, usb, lora, sensors, dsp, display, filesystem, bootloader-ota, secure-boot | always (checkbox rows) |
| `ponytail` | choice | `full` | full, lite, ultra | always |
| `graphify` | bool | `true` | | always |
| `subagents` | bool | `true` | | always |
| `autocommit` | bool | `false` | | always |
| `zephyr_base` | text (hidden) | — | force a Zephyr tree; `set` only | — |
| `board_root` | list (hidden) | — | extra board roots (out-of-tree boards) for the index | — |

**Validation (`set`)**: unknown keys are rejected. Choice/multi values must be in the schema. `safety_level` must belong to the chosen standard. Validation runs after all assignments, so argument order doesn't matter. If `platform` changes to zephyr without `tests` being given, tests becomes `ztest`.

**Normalization (set/menu save)**:
- Zephyr forces `toolchain=zephyr-sdk` unless it is llvm.
- Non-Zephyr turns `zephyr-sdk` into `gnu-arm` and `ztest` into `unity`.
- `safety=none` sets the level to `-`.
- An invalid level falls back to the standard's second (or only) level.

## Zephyr tree resolution (`zephyr_base`)

Profile `zephyr_base` → the project's own west workspace (`.west/config` → `zephyr.base`, else `deps/zephyr` or `zephyr` if it has `VERSION`) → `$ZEPHYR_BASE` → `~/zephyrproject/zephyr`. Before the workspace exists, the last two act as a **reference tree** for board validation and module computation.

Board index (`board_index`, cached per tree):
- walks `boards/**/board.yml`;
- per board: the identifiers from twister `*.yaml` (`identifier`, `arch`, `ram`, `flash`), the SoCs from `board.yml`, and the runners parsed from `board.cmake` (`boards/common/<runner>.board.cmake`, `board_runner_args(<runner> …)`, `board_set_*_ifnset`).

`soc_match`: case-insensitive. An `x` in the SoC name is a wildcard, so `stm32f401ret6` ~ `stm32f401xe`. A prefix query also matches (`stm32f401`).

## Doctor checks

| Level | Check |
|---|---|
| ERR | Zephyr tree not found · no board · board not in tree (+ closest names) · board needs qualifiers (lists identifiers) · MCU ≠ board SoC · probe not a runner for the board · **Zephyr SDK for the board's arch not on PATH** (prints `export PATH=…` for an SDK already on disk, else the install link) · `west` not on PATH · bare metal without MCU · invalid safety level |
| WARN | `ZEPHYR_SDK_INSTALL_DIR` points at a different SDK than the one on PATH · Windows + `native_sim` host board (Linux only) · toolchain zephyr-sdk on non-Zephyr · compiler not on PATH · OpenOCD target cfg missing · probe tool not on PATH (also checks `~/STMicroelectronics/.../STM32_Programmer_CLI`, `/opt/SEGGER/JLink/JLinkExe`) · RTT with stlink/esptool/blackmagic · safety without coding standard · ponytail ultra on safety · graphify missing |
| OK | Zephyr version + path · board summary (SoC, arch, RAM/flash) · probe supported · Zephyr SDK version + path (from PATH) · OpenOCD target cfg |

## Generated commands (`embsk commands`, AGENTS.md table)

| Row | Zephyr | Bare metal / FreeRTOS |
|---|---|---|
| setup | `embsk setup` | — |
| build | `west build -b <board> -p auto -d build <app>` | cmake: `cmake -S <app> -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=<app>/cmake/arm-none-eabi.cmake && cmake --build build` · make: `make -C <app> -j` · pio: `pio run -d <app>` |
| test_host | only if `<app>/tests/` exists and tests=ztest: `west build -b <host_board> -p auto -d build-test <app>/tests && ./build-test/zephyr/zephyr.exe` (+ `test_suite` twister row) | unity/cmocka: `cmake -S <app> -B build-host -DHOST_TESTS=ON && … && ctest --test-dir build-host` (pio: `pio test -d <app> -e native`) |
| sil | only if `<app>/sil/*.sil` exists: `west build -b <host_board> -p auto -d build-sim <app> && embsk uart --exec build-sim/zephyr/zephyr.exe --script <app>/sil/<f>.sil` (the app on native_sim with simulated devices, see `testing-verification.md` §SIL) | — |
| size | `rom_report` + `ram_report` (verify uses the SDK `size` from `CMakeCache.txt` instead) | `arm-none-eabi-size -A` + `nm --size-sort` |
| context | `embsk export build && graphify update .` | — |
| flash | `west flash -d build --runner <r>`; stlink → `stm32cubeprogrammer`, nrfutil → `nrfutil`, esptool → `esp32`, blackmagic → `blackmagicprobe` | per probe (OpenOCD `program … verify reset exit` with `interface/stlink.cfg` for STM32 else `cmsis-dap.cfg` and `target/<family>.cfg`; JLinkExe; pyocd; STM32_Programmer_CLI; probe-rs; LinkServer; nrfjprog; esptool; BMP gdb) |
| debug | `west debug -d build --runner <r>`; flash-only runners (stm32cubeprogrammer/nrfutil/esp32) switch to the first of stlink_gdbserver, openocd, jlink, pyocd the board supports | gdbserver per probe |
| log | rtt: jlink → `JLinkRTTLogger -Device <dev>` (Zephyr: device string from `board.cmake --device=`, matched to the CPU cluster), pyocd/probe-rs → their rtt; else `west rtt`. uart/usb-cdc → `picocom … --logfile artifacts/uart.txt` (humans: it never exits). swo → SWO viewer | same |
| uart | log ∈ uart/usb-cdc: `embsk uart --send "<shell command>" --expect "<reply regex>"` (agents) | same |

## AGENTS.md block

Between `<!-- embsk:begin (generated by \`embsk render\`, …) -->` and `<!-- embsk:end -->`:
1. Profile bullets: platform/target, probe/logs/tests/HIL, safety, features, toolchain (Zephyr: "SDK from PATH, user-installed, never install it"), west workspace (manifest, Zephyr revision, current allowlist), workflow toggles.
2. The commands table.
3. Six hard rules:
   - flash needs OK;
   - evidence definition (adds host tests / target log when applicable);
   - query before reading;
   - ponytail + never-cut list;
   - datasheet citations;
   - which references to load.

**Reference selection (`refs_for`)**:
- always: `coding`, `review`, `testing-verification`, `debugging`, plus `zephyr` or `baremetal`;
- `rtos` for zephyr/freertos or any feature;
- feature refs (low-power/filesystem → power-memory; ble/wifi/ethernet/lora → connectivity; can/usb/sensors/display → peripherals; dsp → rtos; bootloader-ota/secure-boot → boot-ota-security);
- `safety` if a safety or coding standard is set.

## Menu keys

↑/↓ move · ←/→/Space cycle a choice or toggle a checkbox · Enter edits text or opens the board search (type to filter, ↑/↓, Enter selects, Esc cancels) · `s` save · `q`/Esc quit without saving. Arrow keys work in both SS3 and CSI form (terminals and multiplexers differ).
