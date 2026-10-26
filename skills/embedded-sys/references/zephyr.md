# Zephyr — workflow, devicetree, Kconfig, drivers, gotchas

> Load when: `platform=zephyr`, or any west/DT/Kconfig/sysbuild question.
> Profile keys: `board`, `host_board`, `app_dir`, `debugger`, `log`, `features`.

Zephyr already has a driver, a subsystem or a sample for most things. Search before writing: `rg -l "compatible = \"<vendor>,<part>\"" $ZEPHYR_BASE/dts/bindings`, `ls $ZEPHYR_BASE/samples/drivers`, `west boards -n <regex>`, `west shields`.

## Board identifiers (HWMv2)

- Full target = `board[@revision][/soc[/cpucluster[/variant]]]`: `nucleo_f401re`, `nrf5340dk/nrf5340/cpuapp/ns`, `max32690evkit/max32690/m4`.
- Valid identifiers are the `identifier:` fields in `boards/<vendor>/<board>/*.yaml`. `embsk boards <mcu|name>` lists them with SoC + runners; `embsk doctor` rejects non-existent ones.
- Board-specific files in an app use the identifier with `/` → `_`: `boards/nrf5340dk_nrf5340_cpuapp.overlay`, `boards/nrf5340dk_nrf5340_cpuapp.conf`.
- Host: `native_sim` (32-bit, needs gcc-multilib) or `native_sim/native/64` (works on any x86-64 Linux).

## Workspace (`embsk setup`)

Layout: the project folder **is** the west workspace; `app/` is the manifest repo + application (west puts `.west/` next to the manifest dir).

```
my-project/
├── app/west.yml      zephyr revision + import name-allowlist (managed by embsk)
├── app/CMakeLists.txt, prj.conf, src/, boards/, tests/
├── .west/  deps/zephyr  deps/modules/hal/<x>   (generated, git-ignored)
└── build/
```

- `import: {path-prefix: deps, name-allowlist: [...]}` imports only the listed modules from Zephyr's manifest; `path-prefix` also moves Zephyr itself to `deps/zephyr` (don't add `path:`).
- **Never write an empty allowlist** — west treats `[]` as "no filter" and fetches all ~60 modules. embsk writes the placeholder `- none` (Zephyr only) when it can't compute the list yet.
- Allowlist rule: SoC vendor HAL (`zephyr/soc/<vendor>` → `hal_stm32`, `hal_nordic`, `hal_nxp`, `hal_espressif`, `hal_rpi_pico`, `hal_adi`, …) + `cmsis_6` for arch arm + feature modules (filesystem→littlefs, bootloader-ota→mcuboot+zcbor, secure-boot→mcuboot+mbedtls, dsp→cmsis-dsp, lora→loramac-node, display→lvgl) + `segger` for RTT logs + `extra_modules` (e.g. `hal_st` for ST MEMS sensor drivers). `embsk modules` prints it.
- Manual equivalent: `west init -l app && west update --narrow -o=--depth=1 && west config zephyr.base deps/zephyr && west build -b <board> -p auto -d build app`.
- Board change: `embsk set board=...` (or Alt+A) → `embsk setup` adds the new HAL and rebuilds; old modules stay on disk (`rm -rf deps/modules/hal/<x>` to reclaim).
- **Zephyr SDK = user prerequisite, from PATH.** The skill never installs it. embsk takes the SDK that owns the first `*zephyr-*-gcc` on PATH (`<sdk>/gnu/<tc>/bin` for SDK 1.x, `<sdk>/<tc>/bin` for 0.x) and passes it to CMake as `ZEPHYR_SDK_INSTALL_DIR` (CMake doesn't search PATH for the SDK). The first configure caches it in `build/CMakeCache.txt`, so later plain `west build -d build` calls keep the same SDK. Missing → doctor `ERR` / setup exit 3 with the exact `export PATH=…` line: ask the user.
- A global `ZEPHYR_BASE` hijacks `west init`/`update` ("already initialized in …"): embsk unsets it for workspace commands and exports the workspace's own Zephyr for builds.
- Blobs: modules with `blobs:` in `zephyr/module.yml` (hal_nordic, hal_espressif, hal_stm32 for WB/WBA radios) may need `west blobs fetch <module>`.
- Typical cost, nucleo_f767zi: ~160 MB downloaded (shallow), 1.7 GB on disk (hal_stm32 checks out every STM32 series), ~40 s from empty folder to a built image.

## west build cheat sheet

| Need | Command |
|---|---|
| Build (incremental, re-configure when board changes) | `west build -b <board> -p auto -d build <app>` |
| Clean rebuild | `west build -p always ...` |
| Extra Kconfig / overlay fragments | `--extra-conf prj.dev.conf --extra-dtc-overlay dev.overlay` (or `-- -DEXTRA_CONF_FILE=... -DEXTRA_DTC_OVERLAY_FILE=...`) |
| Build variant files (`prj_release.conf`, `app_release.overlay`) | `-- -DFILE_SUFFIX=release` |
| Snippet / shield | `-S rtt-console`, `-S cdc-acm-console` · `--shield <name>` |
| Config UI / inspect | `west build -d build -t menuconfig` (`guiconfig`) — then move the change into `prj.conf` |
| Size reports | `-t rom_report`, `-t ram_report` (`-t footprint` for both) |
| Bootloader + app (MCUboot etc.) | `west build --sysbuild -b <board> <app>` + `sysbuild.conf` (`SB_CONFIG_BOOTLOADER_MCUBOOT=y`) |
| Build a scenario from testcase.yaml/sample.yaml | `west build -b <board> -T <scenario> <dir>` or twister |
| Flash / debug | `west flash`, `west debug`, `west debugserver`, `west attach`, `west rtt`, `west reset` — add `--runner <name>`; available runners for the build are in `build/zephyr/runners.yaml` |

## App layout

```
CMakeLists.txt     cmake_minimum_required(VERSION 3.20.0)
                   find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
                   project(app)  ;  target_sources(app PRIVATE src/main.c src/core.c)
prj.conf           Kconfig for all boards (minimal: only what you need)
boards/<id>.overlay / .conf    board-specific DT and Kconfig
Kconfig            optional app symbols; must end with  source "Kconfig.zephyr"
sample.yaml        twister metadata for the app (optional)
tests/             separate Zephyr app with ztest (testing-verification.md)
```

`zephyr_library()` in a subdirectory added **after** `find_package(Zephyr)` is not linked automatically: add `target_link_libraries(app PRIVATE <lib>)` and `add_dependencies(<lib> zephyr_generated_headers)` — or just `target_sources(app ...)` and skip the library.

## Devicetree essentials

- Source of truth after a build: `build/zephyr/zephyr.dts` (exported to `docs/generated/zephyr-dts.txt` by `embsk export`). Source `.dtsi`/overlay fragments don't show the merged result.
- Overlays change existing nodes by label: `&i2c1 { status = "okay"; clock-frequency = <I2C_BITRATE_FAST>; bmi270@68 { compatible = "bosch,bmi270"; reg = <0x68>; }; };`
- Properties allowed on a node = its binding: `$ZEPHYR_BASE/dts/bindings/**/<vendor>,<part>.yaml` (+ inherited `include:`). Never invent properties; an unknown property is a build error at best and silently ignored in custom bindings at worst.
- `aliases { led0 = &green_led; }` and `chosen { zephyr,console = &usart2; zephyr,shell-uart = &usart2; }` decouple code from boards.
- Pins: `pinctrl-0 = <&usart1_tx_pb6 &usart1_rx_pb7>; pinctrl-names = "default";` — pin group names come from the SoC's pinctrl dtsi (`rg usart1_tx $ZEPHYR_BASE/../modules/hal/*/dts`).
- Code side: `DEVICE_DT_GET(DT_NODELABEL(i2c1))`, `DEVICE_DT_GET(DT_ALIAS(x))`, `GPIO_DT_SPEC_GET(DT_ALIAS(led0), gpios)`, `I2C_DT_SPEC_GET(node)`, `SPI_DT_SPEC_GET(node, op, delay)`; check `device_is_ready()` at init. `DT_HAS_COMPAT_STATUS_OKAY(compat)` for conditional code.
- `status = "okay"` on a child does **not** enable its parent bus or required clocks/regulators — enable the parent too.

## Kconfig essentials

- `prj.conf` holds the minimum; inspect the result in `build/zephyr/.config` (`docs/generated/kconfig-resolved.conf`).
- A symbol "doesn't stick": its `depends on` isn't met → check with `menuconfig` (`/` search shows dependencies) or the warning at CMake time. Never ignore Kconfig warnings.
- Driver symbols usually default to `y` when a matching DT node is `okay` (`DT_HAS_<COMPAT>_ENABLED`); you still enable the subsystem (`CONFIG_I2C=y`, `CONFIG_SENSOR=y`).
- Hardening for release builds: `CONFIG_ASSERT=n` only if the safety analysis allows; `CONFIG_HW_STACK_PROTECTION=y` (or `CONFIG_STACK_SENTINEL=y`); a custom `k_sys_fatal_error_handler()` that records the reason and calls `sys_reboot()` in release builds; disable shells/logging backends you don't ship.

## Driver model (when an app-level bus call isn't enough)

```c
#define DT_DRV_COMPAT acme_tmp42
struct tmp42_config { struct i2c_dt_spec bus; };
struct tmp42_data   { int16_t raw; };
static int tmp42_init(const struct device *dev)
{
	const struct tmp42_config *cfg = dev->config;
	return i2c_is_ready_dt(&cfg->bus) ? 0 : -ENODEV;
}
#define TMP42_DEFINE(inst)                                                         \
	static struct tmp42_data data_##inst;                                       \
	static const struct tmp42_config cfg_##inst = { .bus = I2C_DT_SPEC_INST_GET(inst) }; \
	SENSOR_DEVICE_DT_INST_DEFINE(inst, tmp42_init, NULL, &data_##inst, &cfg_##inst,     \
				     POST_KERNEL, CONFIG_SENSOR_INIT_PRIORITY, &tmp42_api);
DT_INST_FOREACH_STATUS_OKAY(TMP42_DEFINE)
```
Plus `dts/bindings/sensor/acme,tmp42.yaml` (`compatible`, `include: [sensor-device.yaml, i2c-device.yaml]`), a Kconfig symbol (`default y`, `depends on DT_HAS_ACME_TMP42_ENABLED`, `select I2C`) and a CMake entry. Init levels: `PRE_KERNEL_1` (no kernel services) → `PRE_KERNEL_2` → `POST_KERNEL` (drivers) → `APPLICATION`.

## Out-of-tree board / module

- Module: `zephyr/module.yml` with `build: { cmake: ., kconfig: Kconfig, settings: { board_root: ., dts_root: ., soc_root: . } }` — `settings` nested **under** `build`.
- Board: `boards/<vendor>/<board>/board.yml` (`name`, **`full_name`**, `vendor`, `socs`), `<board>.dts`, `<board>_defconfig`, `Kconfig.<board>`, `board.cmake` (runners), `<board>.yaml` (twister identifier/ram/flash). Copy the closest in-tree board as a start; `west build -- -DBOARD_ROOT=<path>` if not a module.

## Logging, shell, console

- `LOG_MODULE_REGISTER(app, LOG_LEVEL_INF);` · `LOG_INF/WRN/ERR/DBG`, `LOG_HEXDUMP_DBG`. Deferred mode (`CONFIG_LOG_MODE_DEFERRED=y`) is ISR-safe; immediate mode is for crash debugging only.
- RTT: `CONFIG_USE_SEGGER_RTT=y` + `CONFIG_LOG_BACKEND_RTT=y` (or snippet `-S rtt-console`); UART: `zephyr,console`/`zephyr,shell-uart` chosen nodes.
- Shell: `CONFIG_SHELL=y`, `SHELL_CMD_REGISTER(app, &sub_app, "App commands", NULL);` — gives the agent a query surface (`device list`, `kernel threads`, `kernel stacks`).

## Build errors → cause

| Error | Cause → fix |
|---|---|
| `__device_dts_ord_N undeclared` | `DEVICE_DT_GET` on a node whose driver isn't built: node or **parent bus** `disabled`, or driver Kconfig off. Check `dt-nodes-and-status.txt` + `kconfig-resolved.conf`. |
| `DT_N_..._P_<prop> undeclared` | property absent in DT or not in the binding; check the binding YAML, spelling (`-` → `_`). |
| `Invalid BOARD; see above` / board not found | wrong identifier or missing qualifiers → `embsk boards <name>`; out-of-tree board needs `BOARD_ROOT`/module. |
| `warning: <SYM> was assigned the value y but got the value n` | unmet `depends on` → enable the dependency or the DT node. |
| Undefined reference to a Zephyr API | subsystem Kconfig off (e.g. `CONFIG_I2C`), or library not linked (see CMake note above). |
| `region 'FLASH'/'RAM' overflowed` | `-t rom_report/ram_report`; shrink logging/shell/stacks, `CONFIG_SIZE_OPTIMIZATIONS=y`. |
| `west flash` uses the wrong tool / cfg not found | inspect `build/zephyr/runners.yaml`; pass `--runner`, `--openocd <path>`, `--openocd-search <dir>`, `--dev-id <serial>`. |
| Build used stale config after board change | `-p always` once. |

## Version notes

- Zephyr 4.x: HWMv2 board names only; ztest new API is the only API (`ZTEST_SUITE`/`ZTEST`); `native_posix` is gone → `native_sim`.
- Check the tree version with `cat $ZEPHYR_BASE/VERSION` (shown by `embsk doctor`) before using recent APIs; read the release notes in `doc/releases/` for renamed symbols.

## Anti-patterns

- `#ifdef CONFIG_BOARD_X` in sources instead of overlays/aliases.
- Editing files under `$ZEPHYR_BASE` or `modules/` (use overlays, out-of-tree modules, or upstream patches).
- Keeping `menuconfig` changes only in `build/` (lost on pristine build).
- Hand-written register access for a peripheral with an in-tree driver.
- Copying a sample's whole `prj.conf` (enables things you don't need).

## Sources
Zephyr 4.x tree (`scripts/west_commands`, `cmake/`, `boards/`, `snippets/`); LibreEmbed `rtos-patterns`, `arm-cortex-m`; EmbeddedDev-Flow host notes.
