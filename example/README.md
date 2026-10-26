# Examples — embedded-sys skill on Zephyr (NUCLEO-F767ZI)

| Folder | Level | What it shows |
|---|---|---|
| [`01-zephyr-template/`](01-zephyr-template/) | base | **The Zephyr project template** the skill scaffolds: a blinky (`main.cpp` + `prj.conf`, from a Zephyr training project) + a minimal `west.yml` whose module allowlist is managed for you. Choose a board, run one command, it downloads only what that board needs and builds. |
| [`02-nucleo_f767zi-thermal-monitor/`](02-nucleo_f767zi-thermal-monitor/) | medium | A real feature built with the skill's workflow: die-temperature sensor at 10 Hz, moving average + hysteresis (host-tested), 3 status LEDs, button via ISR → work queue, IWDG watchdog, reset cause, shell commands. With spec, plan, ADR, review, a SIL target driven over the UART, a code graph, and a [step-by-step walkthrough](02-nucleo_f767zi-thermal-monitor/docs/WALKTHROUGH.md) of the session. |

Both are complete project folders: copy one anywhere and run `embsk setup`.

---

## How the skill manages west for you

You choose **only the board** (Alt+A menu, `/embsk`, or `embsk set board=...`). `embsk setup` does the rest:

```
board = nucleo_f767zi
   │
   ├─1 scaffold app/ if missing (template: west.yml, CMakeLists.txt, prj.conf, src/main.cpp)
   ├─2 compute modules:  SoC stm32f767xx → zephyr/soc/st → hal_stm32 ; arch arm → cmsis_6
   │     write app/west.yml:  revision v4.4.2 + name-allowlist [cmsis_6, hal_stm32]
   ├─3 west init -l app                       (only the first time)
   │   west update --narrow -o=--depth=1       (shallow; only Zephyr + the 2 modules)
   │   west config zephyr.base deps/zephyr
   ├─4 Python deps: west's interpreter has Zephyr's requirements? else create .venv and install them
   ├─5 toolchain: Zephyr SDK with arm-zephyr-eabi on PATH? (yours; embsk never installs it)
   │     yes → builds with it (ZEPHYR_SDK_INSTALL_DIR) · no → print the `export PATH=…` fix, exit 3
   └─6 west build -b nucleo_f767zi -p auto -d build app
```

Generated layout (everything except `app/`, `docs/`, `.embsk/`, `AGENTS.md` is git-ignored and re-creatable):

```
my-project/              ← the west workspace (topdir)
├── app/                 ← manifest repo + application: commit this
│   └── west.yml
├── deps/zephyr/         ← Zephyr v4.4.2 (shallow)
├── deps/modules/hal/    ← cmsis_6, stm32 — nothing else
├── .west/config         ← manifest.path = app, zephyr.base = deps/zephyr
└── build/
```

**Why the allowlist matters** — Zephyr's manifest lists ~60 modules (all vendor HALs, mbedTLS, TF-M, LVGL, OpenThread, babblesim, …). The allowlist picks the 2 this board needs:

| | Full workspace (`~/zephyrproject` on this machine) | This template (allowlist) |
|---|---|---|
| Projects | 68 (Zephyr + all modules) | **3** (Zephyr + cmsis_6 + hal_stm32) |
| Download | full git history | **~160 MB** (shallow, `--narrow -o=--depth=1`) |
| Disk | **9.2 GB** (Zephyr 1.4 GB + modules 7.0 GB) | **1.7 GB** (hal_stm32 checks out every STM32 series) |
| Empty folder → built image | — | **~40 s** (measured here) |

Two west details the skill handles:
- `path-prefix: deps` also relocates Zephyr itself (→ `deps/zephyr`): adding `path: deps/zephyr` gives `deps/deps/zephyr`.
- An **empty** `name-allowlist` means "no filter" to west and downloads everything. embsk never writes one; it uses the placeholder `- none` (Zephyr only) until it can compute the list.

Change the board and run setup again: the allowlist follows. Measured here: `embsk set board=nrf52840dk/nrf52840 && embsk setup` → `[cmsis_6, hal_nordic]`, fetched hal_nordic only, built the same `main.cpp` in 19 s.

Prerequisites: `git`, `cmake` ≥ 3.20, `ninja`, `dtc`, Python ≥ 3.10, the skill installed (`python3 install.py`, Windows `py -3 install.py`, puts `embsk` on PATH), and **the Zephyr SDK installed by you with its toolchain on PATH** (e.g. `export PATH="$HOME/zephyr-sdk-1.0.1/gnu/arm-zephyr-eabi/bin:$PATH"`). Neither the skill nor `embsk setup` installs the SDK. Flashing the Nucleo needs STM32CubeProgrammer (the Zephyr runner also finds it in `~/STMicroelectronics/...` when it isn't on PATH) or OpenOCD.

---

## 01 — the template

```bash
cp -r example/01-zephyr-template ~/work/blinky && cd ~/work/blinky
embsk setup                       # or: Alt+A → Zephyr board → s → "Set up ... now? [Y/n]" → Enter
west flash -d build               # flash (the agent always asks first)
picocom -b 115200 /dev/ttyACM0    # <inf> main: LED state: ON / OFF every second
```

Files:

| File | From | Notes |
|---|---|---|
| `app/src/main.cpp` | a Zephyr training project's blinky (from Zephyr `samples/basic/blinky`, Apache-2.0 header kept) | blinks `led0`, logs state; builds as C++ without `CONFIG_CPP` (no C++ library features used) |
| `app/prj.conf` | zephyr-course, unchanged | `CONFIG_GPIO=y`, `CONFIG_LOG=y` |
| `app/CMakeLists.txt` | zephyr-course + `HINTS $ENV{ZEPHYR_BASE}` | so CMake uses this workspace's Zephyr, not another tree registered on the machine |
| `app/west.yml` | zephyr-course manifest, Zephyr pinned to v4.4.2 | allowlist owned by `embsk setup` |
| `.gitignore` | course entries + `.venv`, artifacts, secrets | |
| `.embsk/profile.json`, `AGENTS.md`, `CLAUDE.md` | generated by embsk | board, probe, commands for the agent |

The course's `modules/` and `tests/` are left out on purpose (minimum). Example 02 shows how to add host tests.

Start a new project from it the skill way: empty folder → Alt+A → choose board → save → `Y`. `embsk setup` scaffolds this template itself.

---

## 02 — thermal monitor (medium)

### What it does
| Feature | Zephyr pieces | Requirement |
|---|---|---|
| Die temperature at 10 Hz, drift-free | sensor API, `st,stm32-temp-cal` (enabled in `app/boards/nucleo_f767zi.overlay`), `K_TIMEOUT_ABS_MS` | REQ-1 |
| 8-sample average, NORMAL/WARM/HOT with 2 °C hysteresis, plausibility check | pure C core `thermal.c` (host-tested) | REQ-2, 3, 7 |
| LD1 green / LD2 blue / LD3 red blinking, red steady on FAULT | `gpio_dt_spec` from board aliases | REQ-4 |
| B1 toggles a 1 Hz report line | GPIO interrupt → `k_work` (debounce 50 ms) | REQ-5 |
| `thermal status`, `thermal thresholds <warm_mC> <hot_mC>` | shell subcommands | REQ-6 |
| IWDG 1 s, fed only by the sampler, paused under the debugger | watchdog API | REQ-8 |
| `boot ok v0.1.0 reset=<cause>` | `app_version.h`, hwinfo | REQ-9 |

Structure: **functional core** (`thermal.c`, no Zephyr headers, 7 ztest cases on `native_sim/native/64`) + **hardware shell** (`monitor.c`, `shell_cmds.c`, `main.c`). Modules: still only `cmsis_6` + `hal_stm32`. The sensor, ADC, IWDG and shell all come from Zephyr itself, so nothing is added to the allowlist.

### How it was built with the skill (the session)

Full replay with real outputs: **[docs/WALKTHROUGH.md](02-nucleo_f767zi-thermal-monitor/docs/WALKTHROUGH.md)**. Summary:

| Phase | You say / the agent does | Artifact |
|---|---|---|
| 0 Profile | Alt+A: Zephyr, `nucleo_f767zi`, probe stlink, logs uart, tests ztest, HIL board, feature `sensors` → `embsk setup` | `.embsk/profile.json`, `AGENTS.md`, `app/west.yml` |
| 1 Map | new project → nothing to map; later `graphify update .` | — |
| 2 Specify | *"new: thermal monitor on the F767 Nucleo — LEDs show normal/warm/hot, button toggles reports, shell to tune thresholds"* → 3 assumptions confirmed, 9 numbered REQs, budgets, failure modes | `docs/SPEC.md` |
| 3 Design | float vs fixed point, EMA vs moving average → ADR; DT plan (enable `die_temp`, aliases exist); threads: 1 sampler + system work queue + shell | `docs/adr/0001-…md`, overlay |
| 4 Plan | 9 tasks in 3 lanes (core, hardware shell, SIL harness); two lanes go to `fw-builder` subagents | `docs/PLAN.md` |
| 5 Build | ponytail ladder: in-tree sensor driver instead of ADC code, board aliases instead of pin numbers, no HAL wrapper; test-first core | `app/src/*`, `app/tests/*` |
| 6 Verify | `embsk verify` → L1 build, L2 host tests + SIL scenario over the UART (`embsk uart`); L4 after you approve flashing | `artifacts/verify.txt`, `artifacts/uart.txt` |
| 7 Review | fresh-context `fw-reviewer`: 2 findings on the SIL harness, proven by mutation, fixed | `docs/review/0001-sil-harness.md`, notes below |
| 8 Document | `graphify update .` → the code graph; `embsk export build` → resolved DTS/Kconfig | `graphify-out/graph.html` |

### Run it
```bash
cp -r example/02-nucleo_f767zi-thermal-monitor ~/work/thermal && cd ~/work/thermal
embsk setup          # init/update (cmsis_6 + hal_stm32) + build
embsk verify         # L1 build + L2 7/7 host tests + SIL 21/21 over the UART + size → artifacts/verify.txt
west flash -d build  # L4, after your OK
embsk uart --timeout 15 --expect "boot ok v" --send "thermal status" --expect "state="   # agent: bounded, → artifacts/uart.txt
picocom -b 115200 --logfile artifacts/uart.txt /dev/ttyACM0                               # you: interactive
```

Expected console (illustrative; values depend on your chip and room):
```
*** Booting Zephyr OS build v4.4.2 ***
<inf> app: boot ok v0.1.0 reset=power-on
<inf> app: monitor running: 10 Hz, B1 toggles report, shell: thermal status
<inf> thermal: report on                                  ← press B1
<inf> thermal: t=36.512C avg=36.402C state=NORMAL         ← once per second
uart:~$ thermal status
t=36.512C avg=36.402C min=35.880C max=37.020C state=NORMAL
warm=45000 hot=60000 mC samples=61 errors=0 presses=1 report=on
uart:~$ thermal thresholds 30000 40000                    ← blue LED on a desk-warm chip
ok
```
L4 evidence for the agent: `rg -n "boot ok|thermal: t=" artifacts/uart.txt` and `rg -n "<err>|FAULT" artifacts/uart.txt` (should be empty).

### Verified on this machine (no board attached)
- `embsk setup` from a fresh copy: west init + update fetched only zephyr, cmsis_6, hal_stm32 → build **PASS**, 0 warnings, **91 KB flash / 16 KB RAM** (budget 128 / 32 KB), 41 s.
- `embsk verify`: build PASS · host tests **7/7 PASS** (`native_sim/native/64`, 0 warnings) · SIL scenario **21/21** over the UART · size PASS.
- Resolved devicetree (`embsk export`): `die_temp` okay from `app/boards/nucleo_f767zi.overlay:13`, `iwdg` okay; Kconfig `CONFIG_STM32_TEMP=y`, `CONFIG_IWDG_STM32=y`, `CONFIG_HWINFO_STM32=y`, `CONFIG_SHELL=y`.
- Not verified: L4/L5 on hardware (no board connected here). LED behaviour and debounce are checked in the SIL (simulated GPIO); real LEDs, contact bounce and the watchdog reset still need a bench run.

### Review notes (phase 7)
- ISR does only `k_work_submit`; debouncing and logging run on the system work queue. ✔
- Every mutex take has a 50 ms timeout with a handled failure path (skip sample / `-EBUSY` to the shell). ✔
- Watchdog fed in one place, after a full sampler iteration; started last in `monitor_start()` because the IWDG cannot be stopped. ✔
- Reset cause checks watchdog/brown-out/POR before PIN (STM32 sets PIN on most resets). ✔
- Known limit: the die sensor measures junction temperature (5–15 °C above ambient). Thresholds are adjustable from the shell and are not persisted (out of scope; adding them would need `settings` + NVS).
