# 09 — Decisions, status, limits, backlog

## Decision log

| # | Decision | Why | Alternatives rejected |
|---|---|---|---|
| D1 | Merge 4 toolkits + Pi subagents into **one skill** with on-demand references | 9.3k → 560 always-on tokens; no trigger competition; one reviewer, one testing doctrine | install all side by side; disable selectively per phase |
| D2 | LibreEmbed knowledge **rewritten Zephyr-first**, not copied | upstream leans FreeRTOS/STM32 HAL, knows nothing about DT/Kconfig/west/HWMv2; some facts were wrong (e.g. MISRA 15.5 called "mandatory": it is advisory) | vendoring the 15 plugins |
| D3 | **Profile + generated AGENTS.md block** as the contract | agents stop guessing boards and commands; works for every tool that reads AGENTS.md; Claude via `@AGENTS.md` | per-tool config files |
| D4 | **One curses menu** in Python for Pi/tmux/shell; Claude uses native AskUserQuestion → `embsk set` | single source of truth; Pi can suspend its TUI for a full-terminal program | a TS SettingsList menu in Pi (duplicate logic) |
| D5 | Validate against the **real Zephyr tree** (twister yaml identifiers, `board.yml` SoCs, `board.cmake` runners) | catches non-existent boards, missing qualifiers, MCU/SoC mismatch, wrong probe before any build | static board lists |
| D6 | **Deterministic flash guard** (bash regex hook), shared by Claude, Codex and Pi | irreversible actions must never depend on a model; works offline | LLM/Jev classifier gate |
| D7 | **Evidence ladder L1–L5** in every reply | the agent can't see the LED; claims must carry output | free-form "done" |
| D8 | Tiers T0/T1/T2 | process overhead must scale with risk; safety functions always T2 | one fixed process |
| D9 | graphify **AST mode only** (`graphify update .`) + resolved DTS/Kconfig export | zero LLM cost; DTS/Kconfig/`.conf` aren't parsed by AST mode, so they are exported as greppable text | full semantic extraction by default |
| D10 | Project folder = **west workspace**, `app/` = manifest repo (T2 topology) | `west init -l` puts `.west/` next to the manifest dir; self-contained, deletable, git-ignorable `deps/` | course layout (repo root = manifest → workspace in the parent folder); one shared global workspace |
| D11 | **Module allowlist computed from the board** (SoC vendor HAL + cmsis_6 + features + extras) | 3 projects / 1.7 GB instead of 68 / 9.2 GB; ~40 s to first build | hand-maintained allowlists; full `west update` |
| D12 | Placeholder `none` instead of an empty allowlist | an empty list means "no filter" in west | `[]` |
| D13 | Zephyr template = the training project's blinky `main.cpp` (from Zephyr `samples/basic/blinky`, Apache-2.0 header kept) + `HINTS $ENV{ZEPHYR_BASE}` | the user asked for the course main and the bare minimum; HINTS stops CMake picking another registered Zephyr | rewriting the template in C with tests |
| D14 | `.venv` only when Zephyr Python deps are missing | don't touch system Python; zero overhead when deps exist | always create a venv |
| D15 | **Zephyr SDK is a user prerequisite, found via PATH only**; embsk resolves the SDK root from the first `*zephyr-*-gcc` on PATH, exports it as `ZEPHYR_SDK_INSTALL_DIR` for its west/cmake calls, and never installs anything (exit 3 + one fix line) | the toolchain is machine setup, not part of a skill; one visible choice shared by every terminal and tool; CMake alone would pick an SDK from its registry or default dirs (on the original host: 0.17.4 instead of 1.0.1) | auto-install via `west sdk install` (the earlier `setup --yes`); scanning default dirs / the CMake registry as a silent source |
| D16 | Debug runner fallback for flash-only runners (stm32cubeprogrammer, nrfutil, esp32) | `west debug --runner stm32cubeprogrammer` cannot work (runner caps = flash) | same runner for flash and debug |
| D17 | **One cross-platform installer in Python** (`install.py`; `install.sh` only wraps it) + `INSTALL.md` written for agents, with `--check` smoke tests | Python is already required (embsk, Zephyr), so the same file runs on Linux, macOS and Windows; an agent needs exact steps and a pass/fail check | bash installer + a separate PowerShell port (two copies to keep in sync) |
| D18 | Skill linked **only into `~/.agents/skills`** (+ Claude plugin, + `--agent-dir`); Pi package and Codex plugin no longer carry it; old `~/.codex/skills` link removed | Codex, Cursor, Gemini CLI, Copilot, OpenCode and Pi read `~/.agents/skills`; extra copies caused a Pi name-collision warning and double entries in Codex/Cursor | linking into every agent's own folder |
| D19 | **Hooks pure bash (no jq)**; matcher includes Claude's `PowerShell` tool; Pi gate uses Pi's own `getShellConfig()` bash | Claude Code and Pi run hooks in Git Bash on Windows, which has no jq; the old guard silently *allowed* everything without jq | Python guard (no single interpreter name works on Linux and Windows), PowerShell port (second regex copy) |
| D21 | **`embsk uart`**: one bounded send/expect UART session (serial via pyserial or termios, or a process's stdin/stdout); and the **SIL pattern**: the unchanged app on `native_sim/native/64`, simulated devices behind the same Zephyr APIs, scenario files run by `embsk verify` | an agent can't use picocom (it never exits); unit tests can't reach the hardware shell (LEDs, debounce, fault paths); with no board the agent still needs a running app to talk to | `#ifdef`-ing the hardware shell for tests; Renode for everything (no board model for most parts); pexpect (not on Windows) |
| D20 | Windows links: symlink → junction → copy; `embsk.cmd` + sh launcher; `~/.local/bin` appended to the user PATH via the registry | junctions need no admin/Developer Mode; Git Bash ignores `.cmd`; `setx` truncates PATH at 1024 chars | require Developer Mode; copy always |

## Verified on the original host

Ubuntu 24.04, Zephyr reference tree 4.4.0-rc3 at `~/zephyrproject`, workspaces at v4.4.2, west 1.5.0, Zephyr SDK 1.0.1, Python 3.12, graphify 0.9.64.

| Item | Result |
|---|---|
| Board index | 973 boards in 0.6 s |
| doctor | catches wrong MCU/SoC, unsupported probe, missing qualifiers, typos (with suggestions); `set` rejects invalid values |
| curses menu (pty-driven) | navigation, board search, save, setup prompt |
| `embsk setup` empty folder → f767 build | PASS, 45 s; re-run 4 s; board switch to nRF52840 → only hal_nordic fetched, PASS 19 s |
| module resolution | 7 boards/feature combos correct |
| Zephyr template (old C version and current course version) | target build 0 warnings; host tests (old version) PASS |
| example 01 / 02 from fresh copies | PASS (28 KB; 91 KB / 16 KB, 7/7 tests, 0 warnings) |
| Zephyr SDK from PATH (example 02) | no SDK on PATH → doctor ERR + setup exit 3 with the `export PATH=` line for the SDK on disk, nothing installed; SDK 1.0.1 on PATH with `ZEPHYR_SDK_INSTALL_DIR` unset → CMake "Found toolchain: zephyr 1.0.1", cached in `CMakeCache.txt`; a later plain `west build` without the env reuses it; `embsk verify` 3/3 PASS; different `ZEPHYR_SDK_INSTALL_DIR` → WARN |
| bare-metal template | Unity host tests via ctest PASS |
| `embsk uart` + SIL (example 02) | scenario 21/21 over the UART in 13.4 s, deterministic (3 runs); `embsk verify` gates on it; mutation check: removing the debounce, blue lit in HOT, blue ignoring FAULT each fail a step; board image unchanged (91 376 B); serial path tested on a pty with pyserial and the termios fallback |
| flash guard | 27 cases incl. PowerShell tool, Windows paths and `.exe` names, Codex array form, JSON-escaped reason, deny mode; 2 MB `Write` input in 0.07 s |
| Pi extension | strict tsc clean; loads in RPC mode; `/embsk` registered; status set |
| Pi workflow | validated by the workflow extension's schema code |
| Claude plugin | `claude plugin validate` passed |
| installer (`install.py`) | Linux, throw-away HOME: install with the real `claude` and `pi` CLIs → plugin enabled, Pi lists `/embsk` and `skill:embedded-sys` once; `--check` exit 0; re-run idempotent; `--agent-dir`; moved repo heals links; foreign folders left alone; `--uninstall` removes plugin, package, keybinding, links. Windows branches simulated in quick-check (junction/copy fallback, launchers, registry PATH, Git Bash lookup, `.exe` SDK) |

## Not verified / known limits

- **No on-target run (L4/L5)**: no board attached. Flashing has never been exercised.
- **Pi subagents broken on the original host** (bwrap + AppArmor user namespaces). The skill falls back to sequential roles.
- **Windows was not run on a real host** (none available): the Windows branches of `install.py`, `embsk.py` and the Pi extension are simulated or reviewed, not executed. First real run: `py -3 install.py && py -3 install.py --check`, then a Zephyr build from PowerShell and from Git Bash.
- macOS: same code paths as Linux, not run.
- **Codex** plugin, prompt and hook "ask" support are untested. **tmux** binding untested (tmux not installed).
- Claude `meta+a → command:embsk` not live-tested (needs the plugin installed and a terminal that sends Meta).
- `ensure_python()` venv creation was not exercised: the host already had the deps.
- hal_stm32 working tree is 1.1 GB (all STM32 series).
- Blob-requiring modules are only reported, not fetched automatically.
- Safety reference is orientation, not compliance; MISRA rule texts are licensed separately.
- `menu` requires a TTY; in non-interactive contexts use `embsk set`.

## Backlog (ideas, prioritized)

1. **L4 bench validation** with a NUCLEO-F767ZI: flash example 02, capture `artifacts/uart.txt`, verify LEDs/button/watchdog. Then record evidence in the example docs.
2. Optional **sparse checkout** for big HALs (hal_stm32: keep only `stm32cube/<series>`, `dts/st/<series>` plus common files) behind a profile flag; measure that builds still pass.
3. Shared **west cache** across projects (`west update --path-cache/--name-cache`) to avoid re-downloading Zephyr for every project.
4. Test the Codex plugin and hooks; test the tmux binding; live-test Claude Alt+A.
5. An opt-in flag for `embsk setup` that runs `west blobs fetch <module>` when a module declares blobs and the board needs them.
6. CI: `.github/workflows/check.yml` runs quick-check on Linux (Zephyr checks skipped) and the installer on Windows. Next: cache a shallow Zephyr v4.4.2 tree so the Zephyr checks and `--full` run in CI too.
7. Done: plugin icon `.claude-plugin/icon.png`, rendered from `docs/assets/logo.svg`.

## Original host facts (may not apply elsewhere)

- `west twister` broken (missing `natsort`); 32-bit `native_sim` fails (no gcc-multilib) → use `native_sim/native/64`.
- `west flash --runner openocd` picks STM32CubeIDE's openocd with a bad scripts dir → for Nucleo boards use `debugger=stlink` (STM32CubeProgrammer in `~/STMicroelectronics/...`, found by Zephyr's runner) or pass `--openocd <path>`.
- Host `/usr/bin/python3` lacks `anytree` → `west build -t rom_report` fails; `embsk verify` uses the SDK `size` tool instead.
- `grep` in interactive shells is wrapped by `rtk` (use `/usr/bin/grep` in scripts if output looks odd).
- pip outside a venv needs `--user --break-system-packages`.
