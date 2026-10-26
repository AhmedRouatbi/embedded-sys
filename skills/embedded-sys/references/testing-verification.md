# Testing & verification — the evidence ladder

> Load when: writing tests, verifying a task, setting up HIL/CI tests, before any "done" claim.
> Profile keys: `tests` (ztest|unity|cmocka), `hil` (none|board|renode|qemu), `log`, `debugger`, `host_board`, `safety`.

The agent cannot see the LED blink. Every verification step must produce **text evidence in a file or command output** that can be grepped. A change is as verified as the highest level it reached — say which.

## The ladder

| Level | Evidence | Zephyr | Bare metal |
|---|---|---|---|
| **L1 build** | target build passes, no new warnings | `west build -b <board>` | `cmake --build build` with `-Wall -Wextra -Werror` |
| **L2 host tests** | unit tests pass on the PC; SIL scenario passes if the app has one | ztest on `native_sim/native/64` (32-bit `native_sim` needs gcc-multilib); `sil` row (below) | Unity/CMocka/Ceedling with host gcc |
| **L3 static** | analyzers clean on changed files | `west build -- -DZEPHYR_SCA_VARIANT=gcc` (also `clang`, `codechecker`, `sparse`, `eclair`, `cpptest`) or direct cppcheck/clang-tidy | `cppcheck --enable=warning,style --addon=misra`; clang-tidy |
| **L4 on target** | flashed (user OK), expected log line in `artifacts/*.txt` | `west flash` + RTT/UART capture | probe flash + capture |
| **L5 automated HIL** | scripted on-target test passes | `west twister --device-testing` / pytest harness | pytest + pyserial/probe scripts; Renode robot tests |

No hardware attached → stop at L3 and write `Verified: L2 (host) — not run on target`. Never imply L4.

## TDD loop for firmware (red → green → refactor)

1. Write the test for the **functional core** (parser, filter, state machine, conversion, CRC, protocol framing) — fails for the right reason.
2. Smallest code that passes (`coding.md`).
3. Refactor only with tests green. Bug fix: first a test that reproduces the bug.
4. Test the *behaviour and error paths*: invalid length, timeout, bus error (`-EIO`), sensor absent, saturation, wrap-around of counters, odd sizes.

What not to unit-test on host: register sequences already covered by vendor/Zephyr drivers, timing — measure those on target (L4).

## Zephyr test app (`tests/` is a Zephyr app)

```
tests/CMakeLists.txt   find_package(Zephyr ...); project(app_tests)
                       target_sources(app PRIVATE src/test_core.c ../src/core.c)
                       target_include_directories(app PRIVATE ../src)
tests/prj.conf         CONFIG_ZTEST=y  (+ CONFIG_ZTEST_SHUFFLE=y optional)
tests/testcase.yaml    tests: app.core: {platform_allow: [native_sim/native/64], tags: [unit]}
```

```c
#include <zephyr/ztest.h>
#include "core.h"
ZTEST_SUITE(core, NULL, NULL, NULL, NULL, NULL);
ZTEST(core, test_frame_rejects_short)
{
	uint8_t buf[2] = {0xAA, 0x01};
	zassert_equal(frame_parse(buf, sizeof(buf), NULL), -EINVAL);
}
```

- Run: `west build -b native_sim/native/64 -p auto -d build-test tests && ./build-test/zephyr/zephyr.exe` (exit code ≠ 0 on failure). Filter: `./build-test/zephyr/zephyr.exe -test=core::test_frame_rejects_short`.
- Fakes: `#include <zephyr/fff.h>` + `DEFINE_FFF_GLOBALS;` `FAKE_VALUE_FUNC(int, i2c_write_dt, ...)` for functions outside the core.
- Bus emulators: `CONFIG_EMUL=y` + `zephyr,i2c-emul-controller` / `zephyr,spi-emul-controller` DT nodes and a device emulator — runs real driver code on `native_sim`.
- Many suites: `west twister -T tests -p native_sim/native/64` (needs twister's Python deps from `scripts/requirements*.txt`). Coverage: `west twister --coverage -p native_sim/native/64 -T tests`.
- Sanitizers on host: `CONFIG_ASAN=y`, `CONFIG_UBSAN=y` in a host-only `.conf`.

## SIL — the real app on native_sim, driven over its UART

Unit tests cover the functional core. The hardware shell (threads, ISRs, LEDs, debounce, fault paths) is only reached by running the app. Without a board, run the **same app** on `native_sim/native/64` with simulated devices **behind the same Zephyr APIs**, and let the agent drive it over the shell.

| Piece | Where | Rule |
|---|---|---|
| Simulated devices | `app/src/sim/*.c` + bindings `app/dts/bindings/vnd,sim-*.yaml` | implement the API the app already uses (sensor, watchdog...); never `#ifdef` the hardware shell |
| Overlay + conf | `app/boards/native_sim_native_64.{overlay,conf}` | exact name: for `native_sim/native/64` Zephyr has **no fallback** to `native_sim.overlay` |
| Same logging as the board | the `.conf` | `CONFIG_LOG_MODE_DEFERRED=y` (native_sim defaults to immediate: lines logged before the shell starts, such as the boot line, never reach it), `CONFIG_LOG_BACKEND_NATIVE_POSIX=n` (else every line twice), `CONFIG_UART_NATIVE_PTY_0_ON_STDINOUT=y` |
| Controls | a `sim` shell command set (`sim temp 50000`, `sim fail 10`, `sim press`, `sim leds`) | compiled only for native_sim: `target_sources_ifdef(CONFIG_BOARD_NATIVE_SIM ...)` |
| Scenario | `app/sil/*.sil`: one `send` / `expect` / `fail-on` step per line, tagged with REQ ids | embsk adds a `sil` row; `embsk verify` runs it |

- Check the scenario by mutation: break one line of the shell (drop a debounce, light the wrong LED) and confirm a step fails. A scenario that passes on broken code is decoration.
- native_sim ticks at 100 Hz: `k_msleep(2)` lasts 10–20 ms. Use `k_busy_wait()` for sub-tick timing in simulated stimuli.
- Before trusting a SIL failure, diff the two configs: `diff <(sort build/zephyr/.config) <(sort build-sim/zephyr/.config)`. Look at the log mode, tick rate and drivers.
- SIL is L2. It doesn't prove ADC calibration, real timing or the watchdog reset: those stay L4.

## Bare metal / FreeRTOS host tests

- Unity + CMock (Ceedling: `ceedling test:all`) or CMocka. CMake option: `option(HOST_TESTS "build host tests" OFF)`, when ON compile the core sources with host gcc and `add_test()` per test binary, run `ctest --test-dir build-host --output-on-failure`.
- Hardware access goes through a thin ops struct or link-time substitution (a `fake_hal.c` linked instead of the vendor HAL in the test build). Don't build a "testable HAL" layer for one driver — fake the 2–3 functions it calls.
- PlatformIO: `pio test -e native`.

## On target (L4) — make the firmware talk, pipe it to a file

Dev-only config (create `app/prj.dev.conf`, build with `--extra-conf prj.dev.conf`; keep it out of release builds):
`CONFIG_LOG=y`, `CONFIG_LOG_MODE_DEFERRED=y`, RTT: `CONFIG_USE_SEGGER_RTT=y` + `CONFIG_LOG_BACKEND_RTT=y`, `CONFIG_SHELL=y`, `CONFIG_THREAD_NAME=y`, `CONFIG_THREAD_ANALYZER=y` + `CONFIG_THREAD_ANALYZER_AUTO=y`, `CONFIG_THREAD_STACK_INFO=y`, `CONFIG_INIT_STACKS=y`, `CONFIG_ASSERT=y`, `CONFIG_EXTRA_EXCEPTION_INFO=y`.

UART logs: use `embsk uart` (the `uart` row), never picocom/miniterm in a tool call (they never exit). One bounded session, transcript appended to `artifacts/uart.txt`; exit 0 only if every expect matched:

```bash
west flash -d build                                   # user OK (flash guard asks)
embsk uart --timeout 15 --fail-on "ASSERT|FATAL|Faulting" --expect "boot ok v" \
           --send "app stats" --expect "rate=100"     # one step per flag, run in order
embsk uart --script app/sil/smoke.sil --port /dev/ttyACM0   # the SIL scenario steps work on the board too
rg -n "<err>|ASSERT|FATAL|stack overflow" artifacts/uart.txt  # must be empty
```

RTT: start the capture from the `log` row in the background, then `rg` the file the same way. `embsk uart` without steps listens for `--timeout` seconds.

- Design log lines for machines: stable prefix, key=value (`imu: rate=100 drop=0`).
- A shell command per feature (`sensor get`, `app stats`) lets the agent query state without reflashing.
- Timing claims need measurement: DWT cycle counter / `k_cycle_get_32()` around the code, GPIO toggle + logic analyzer, or `CONFIG_TRACING`. Reasoned timing is labelled "estimated".

## HIL (L5)

- Zephyr: `testcase.yaml` with `harness: console` + `harness_config: {type: multi_line, regex: [...]}` or `harness: pytest`; run `west twister --device-testing --device-serial /dev/ttyACM0 -p <board> -T tests/hil` (or `--hardware-map map.yaml`).
- pytest-twister-harness: `dut` fixture flashes and reads the console — `dut.readlines_until(regex="accel:", timeout=5)`.
- Renode (`hil=renode`): `west simulate -d build --runner renode` for boards with Renode support, `renode-test` robot files for scripted checks; QEMU boards: `west build -t run`.
- Physical rigs: one owner per probe/serial port; power-cycle via a USB relay/smart hub when tests need a cold boot.

## Static analysis (L3)

- `cppcheck --enable=warning,style,performance --inline-suppr --error-exitcode=1 -I include src/` (+ `--addon=misra` with a rules text file if licensed rule texts exist).
- `clang-tidy -p build src/*.c` with `bugprone-*,cert-*,clang-analyzer-*` (needs `compile_commands.json`; Zephyr writes it to `build/`).
- Compiler: `-Wall -Wextra -Wshadow -Wdouble-promotion -Wconversion` on your sources (not vendor code); Zephyr `CONFIG_COMPILER_WARNINGS_AS_ERRORS=y` in CI.
- Stack: `-fstack-usage` / `west build -d build -t puncover` (needs `pip install puncover`) for static stack estimates.

## Verification report (end of phase 6)

```
Verified: L4
- L1 west build -b nucleo_f401re: PASS (flash 41.2K/512K, RAM 11.0K/96K, +1.3K flash)
- L2 ztest native_sim/native/64: 14/14 PASS
- L3 cppcheck src/: 0 findings
- L4 flashed (user OK 10:42), artifacts/rtt.txt:L88 "imu: rate=100 drop=0"; no <err>
Not verified: 24 h soak, temperature range.
```

## Anti-patterns

- "Should work" / "tests pass" without command output; claiming L4 from a successful flash with no log check.
- Tests that assert nothing or mirror the implementation's arithmetic.
- `#ifdef UNIT_TEST` branches inside production logic.
- Testing on host only for timing-critical behaviour.
- Deleting or skipping a failing test to get green (stop and report instead).

## Sources
agent-skills `test-driven-development`, `ci-cd-and-automation`, `observability-and-instrumentation`; LibreEmbed `embedded-testing`, `debug-trace`; EmbeddedDev-Flow `hil-logging.md`.
