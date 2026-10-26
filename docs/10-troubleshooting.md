# 10 — Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `west init -l app` → `FATAL ERROR: already initialized in /…/zephyrproject` | a global `ZEPHYR_BASE` points at another workspace | use `embsk setup` (it unsets it); manually: `env -u ZEPHYR_BASE west init -l app` |
| Zephyr checked out to `deps/deps/zephyr` | `path: deps/zephyr` combined with `path-prefix: deps` | remove `path:` from the zephyr project in `app/west.yml`; `rm -rf .west deps` and re-run setup |
| `west update` downloads every module | `name-allowlist` is empty (`[]`) | let embsk write it (placeholder `none`), or list modules explicitly |
| `board '<x>' not found` / `needs qualifiers` | wrong identifier or missing `/soc/cluster` | `embsk boards <mcu or name>` and pick a listed identifier (e.g. `max32690evkit/max32690/m4`) |
| `MCU '<x>' does not match board SoC` | profile MCU from another part | clear it (`embsk set mcu=`) or pick the matching board |
| `Probe '<x>' is not a runner for <board>` | the board's `board.cmake` doesn't include that runner | choose one of the listed runners |
| setup exits 3 / doctor ERR: `Zephyr SDK not on PATH` | the SDK's toolchain `bin/` isn't on PATH (the skill never installs the SDK) | run the printed `export PATH="<sdk>/gnu/<tc>/bin:$PATH"` and add it to your shell rc; no SDK on disk: install it yourself (Zephyr docs → Zephyr SDK), then the same export |
| doctor ERR: `Zephyr SDK <dir> (from PATH) has no <tc> toolchain` | the board's arch needs a toolchain that SDK lacks (e.g. riscv) | `<sdk>/setup.sh -t <tc>` (yourself) |
| doctor WARN: `ZEPHYR_SDK_INSTALL_DIR=… is not the SDK on PATH` | shell rc sets another SDK | unset it or point it at the PATH SDK; embsk's own builds already use the PATH SDK |
| build uses another SDK version than expected | build dir configured before / outside embsk; CMake picked one from its registry or `~`, `/opt` | `rm -rf build && embsk setup` (configures with the PATH SDK and caches it) |
| `ModuleNotFoundError: elftools/yaml/pykwalify` during build | west's Python lacks Zephyr requirements | `embsk setup` creates `.venv` automatically; manually `pip install -r deps/zephyr/scripts/requirements-base.txt` in a venv |
| `west build -t rom_report` → `No module named 'anytree'` | Zephyr Python requirements incomplete | install requirements, or rely on `embsk verify` (uses the SDK `size` tool) |
| Build asks for binary blobs | module ships blobs (hal_nordic, hal_espressif, STM32WB radio) | `west blobs fetch <module>` |
| `__device_dts_ord_N undeclared` | `DEVICE_DT_GET` on a node whose driver isn't built (node or parent bus disabled, Kconfig off) | `embsk export build`, then `rg` the node and its parent in `docs/generated/dt-nodes-and-status.txt` and the driver symbol in `kconfig-resolved.conf` |
| `west: unknown command "build"` outside a workspace | no west workspace found | run inside the project (after setup), or export `ZEPHYR_BASE` of a reference tree |
| `west flash` uses the wrong openocd / "Can't find board/<x>.cfg" | runner picks another openocd install | `debugger=stlink` on Nucleo (STM32CubeProgrammer), or `west flash --openocd <path>` |
| `west debug --runner stm32cubeprogrammer` fails | that runner only flashes | use the `debug` row from AGENTS.md (embsk picks openocd/stlink_gdbserver/jlink/pyocd) |
| Pi: `spawn_agent` → `bwrap: setting up uid map: Permission denied` | Ubuntu 24.04 `kernel.apparmor_restrict_unprivileged_userns=1` | sudo: create `/etc/apparmor.d/bwrap` with `abi <abi/4.0>, include <tunables/global> profile bwrap /usr/bin/bwrap flags=(unconfined) { userns, include if exists <local/bwrap> }` then `sudo apparmor_parser -r /etc/apparmor.d/bwrap`; meanwhile work sequentially (don't fall back to delegate) |
| Windows: Claude Code blocks every tool call, "Git Bash wasn't found" | plugin hooks are bash scripts | install Git for Windows (or set `CLAUDE_CODE_GIT_BASH_PATH`); `install.py` installs only the skill when Git Bash is missing |
| Windows: `embsk` not found in Git Bash but works in PowerShell | old install (only `embsk.cmd`) or terminal opened before install | re-run `py -3 install.py` (adds the sh launcher), open a new terminal |
| Windows: `UnicodeEncodeError` / garbled `·` `→` | Python not in UTF-8 mode | use the `embsk` launcher (passes `-X utf8`); `embsk.py` also re-runs itself in UTF-8 mode |
| Windows: `embsk export` → "needs bash" | no Git Bash | install Git for Windows |
| Windows: host tests (`native_sim`) don't build | `native_sim` is Linux-only (POSIX arch) | run `test_host` in WSL, or set `host_board` to a QEMU board |
| Pi on Windows: every bash call blocked "flash guard needs bash" | Pi can't find Git Bash | install Git for Windows or set `shellPath` in `~/.pi/agent/settings.json` |
| agent tool call hangs on `picocom`/`minicom` | interactive terminals never exit | use the `uart` row: `embsk uart --send … --expect …` (bounded) |
| `embsk uart` exit 2 "cannot open /dev/ttyACM0" | board not connected, wrong port, port held by picocom, or no permission | `ls /dev/ttyACM*`, close other terminals, `sudo usermod -aG dialout $USER` (log in again); Windows: `COMx` + pyserial |
| `embsk uart` expect times out although the line is in the transcript | the line came **before** the last `--send` (expects only see later output), or the regex needs escaping (`\.`) | reorder the steps; escape regex characters |
| SIL: the boot line or early logs are missing, or every line is printed twice | native_sim defaults: immediate log mode + an extra stdout backend | in `boards/native_sim_native_64.conf`: `CONFIG_LOG_MODE_DEFERRED=y`, `CONFIG_LOG_BACKEND_NATIVE_POSIX=n` |
| SIL build: `__device_dts_ord_…ALIAS_die_temp0` undeclared | overlay not applied: for `native_sim/native/64` the file must be `native_sim_native_64.overlay` (no fallback to `native_sim.overlay`) | rename the board files |
| Claude Code: Alt+A does nothing | terminal doesn't send Meta, or the plugin command is namespaced | enable "Alt as Meta" in the terminal; bind `command:embedded-sys:embsk`; or type `/embsk` |
| Claude doesn't see the profile | `CLAUDE.md` existed without `@AGENTS.md` | add the line `@AGENTS.md` to `CLAUDE.md` |
| Codex ignores the flash confirmation | hook "ask" not supported | `export EMBSK_FLASH_GUARD=deny` (agent must hand flash commands to the user) |
| Menu arrows print `^[[B` or quit | terminal sends unexpected sequences | embsk decodes CSI and SS3; if it persists, use `embsk set` |
| `embsk menu` in an agent tool call hangs/fails | no TTY | agents use `embsk set k=v …`; the menu is for humans |
| Profile written to the wrong folder | the folder sits inside another git repo and has no `.embsk/` | `mkdir .embsk` in the project folder first |
| graphify misses devicetree/Kconfig facts | AST mode doesn't parse `.dts/.overlay/Kconfig/.conf` | `embsk export build` and `rg` in `docs/generated/` |
| `twister` fails with `natsort` missing (original host) | broken twister deps | build the tests app directly (the `test_host` row) |
