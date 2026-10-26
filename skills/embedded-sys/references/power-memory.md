# Power & memory — low-power design, RAM/flash budget, persistent storage

> Load when: battery/low-power work, sleep modes, memory budget/overflow, stack/heap questions, map file, NVS/settings/filesystem/flash wear.
> Profile keys: `features` (low-power, filesystem), `platform`, `safety`.

## Part A — Power

### Budget first (put it in SPEC.md)

```
Component       | Active mA | Active ms per cycle | Sleep µA | Cycle s
MCU             | 6.0       | 20                  | 1.8      | 60
Radio TX        | 9.0       | 8                   | 0.4      | 60
Sensor          | 0.7       | 15                  | 0.1      | 60
Regulator Iq    | —         | —                   | 0.5      | —
I_avg = Σ(I_active·t_active)/T + Σ I_sleep   →  lifetime_h = C_mAh · derating(0.7–0.8) / I_avg_mA
```
Measure, don't trust the spreadsheet: Nordic PPK2, Joulescope, Otii, or a µCurrent + scope. Record measured µA per mode in the spec. Sleep current dominates long-life designs.

### Zephyr power management

| Mechanism | Config | What you do |
|---|---|---|
| System PM (idle → SoC low-power states) | `CONFIG_PM=y`; states from DT `cpu-power-states` | keep threads blocked (no polling); the kernel enters states when idle long enough (`min-residency-us`) |
| Device runtime PM | `CONFIG_PM_DEVICE=y`, `CONFIG_PM_DEVICE_RUNTIME=y` | `pm_device_runtime_get(dev)` before use, `_put(dev)` after; drivers suspend peripherals |
| Tickless kernel | default on most SoCs (`CONFIG_TICKLESS_KERNEL`) | avoid periodic `k_timer`s at high rate; batch work |
| Locks | `pm_policy_state_lock_get()` | hold off deep sleep during DMA/radio activity |
| Wake sources | DT `wakeup-source`, GPIO interrupts, RTC/counter alarms | verify each wake source actually wakes from the chosen state |

Bare metal / FreeRTOS: explicit sleep entry (`__WFI()` in idle / `configUSE_TICKLESS_IDLE` with an LPTIM/RTC tick), clocks gated per peripheral.

### Sleep entry checklist
1. Finish or abort DMA; drain UART TX (TC flag) and log buffers.
2. Peripherals into low-power state / clocks gated; external parts into shutdown (sensor power-down register, radio off).
3. Unused and floating pins → analog/disconnected (lowest leakage); no pull resistors fighting external circuits.
4. Wake sources configured and pending flags cleared *before* sleeping (else immediate wake).
5. After wake: restore clocks (deep stop modes often fall back to the internal oscillator) and re-init what lost state.
6. Debug: disconnect the probe (or disable DBGMCU low-power debug bits) when measuring — debug keeps domains powered.

### Design rules
- Event-driven, never polling; one wake → do everything → sleep (batching radio/sensor work).
- Lowest clock that meets deadlines; run fast and sleep beats run slow for compute-bound bursts.
- Logging/RTT/shell off in low-power release builds (UART RX keeps clocks alive).
- Brown-out: set BOR level; on low battery degrade gracefully (stop radio, save state, safe shutdown).

## Part B — Memory

### Budget & inspection

| Question | Zephyr | Bare metal |
|---|---|---|
| Totals | build prints `Memory region Used Size`; `west build -t rom_report` / `ram_report` (tree by symbol/file) | `--print-memory-usage`, `arm-none-eabi-size -A app.elf` |
| Biggest symbols | `rom_report`/`ram_report`; `arm-none-eabi-nm --size-sort -S build/zephyr/zephyr.elf \| tail -30` | same `nm` |
| Where did it go | `docs/generated/zephyr-map.txt` (map file) | `app.map` |
| Delta of a change | compare `size-report.txt` before/after (`embsk export`) | `size` before/after |

Report flash/RAM deltas for every non-trivial change. Keep ≥ 10–20 % headroom (OTA slots need much more flash — see `boot-ota-security.md`).

### Allocation policy
- Static allocation by default: `K_THREAD_STACK_DEFINE`, `K_MSGQ_DEFINE`, `K_MEM_SLAB_DEFINE`, static buffers; FreeRTOS `*Static` APIs.
- Heap only for genuinely variable-size data, sized explicitly (`CONFIG_HEAP_MEM_POOL_SIZE`, `K_HEAP_DEFINE`), monitored (`CONFIG_SYS_HEAP_RUNTIME_STATS=y`, `sys_heap_runtime_stats_get`), never from ISRs; safety projects: no allocation after init.
- Fixed-size blocks (`k_mem_slab`) instead of a general heap for messages → no fragmentation, O(1).
- Big constant tables `const` (stay in flash); big buffers in specific RAM banks when the SoC has them (DTCM for hot data, non-cacheable for DMA): Zephyr `Z_GENERIC_SECTION()` / DT `zephyr,memory-region` + linker region, bare metal `__attribute__((section(".ram2")))`.

### Shrinking (in this order)
1. Logging level/backends and shell in release (`CONFIG_LOG_DEFAULT_LEVEL`, `CONFIG_SHELL=n`), `CONFIG_ASSERT` per safety analysis.
2. Stack sizes after measuring (`rtos.md`), not before.
3. `CONFIG_SIZE_OPTIMIZATIONS=y` (`-Os`), LTO (`CONFIG_LTO=y` where supported), newlib-nano/picolibc, no float `printf` (`CONFIG_CBPRINTF_NANO=y`).
4. Remove unused subsystems the sample `prj.conf` dragged in.
5. Only then: algorithmic/data-structure changes.

## Part C — Persistent storage & flash

| Need | Zephyr | Notes |
|---|---|---|
| Key-value settings (config, calibration) | `settings` subsystem over NVS/ZMS (`CONFIG_SETTINGS=y`, `CONFIG_NVS=y` or `CONFIG_ZMS=y`) | wear-levelled, power-fail safe; ZMS for newer RRAM/MRAM-like parts |
| Files / logs | LittleFS (`CONFIG_FILE_SYSTEM_LITTLEFS=y`) | power-loss resilient; FAT only for PC-exchanged SD cards |
| Raw partitions | `flash_map` / `fixed-partitions` in DT (`storage_partition`) | partitions must not overlap MCUboot slots |

- Flash wear: count erase cycles per sector from datasheet endurance (10k–100k); write rate × lifetime must fit with margin — batch writes, write on change only.
- Power-fail: never erase-then-write the only copy; use a journaled store (NVS/LittleFS) or A/B records with sequence number + CRC.
- Flash erase/write stalls the bus on single-bank parts (interrupt latency spikes); schedule it away from real-time work or run from RAM.
- Persisted struct layout = an interface: version field, explicit sizes, migration on upgrade.

## Anti-patterns

- Polling loops in a "low-power" device; measuring sleep current with the debugger attached.
- `malloc` in steady state; heap with no size/fragmentation monitoring.
- Writing calibration to flash on every boot; raw flash writes without wear/power-fail strategy.
- Shrinking stacks before measuring; ignoring a 95 %-full RAM report until the next feature.

## Sources
LibreEmbed `power-management`, `memory-management`, `firmware-update` (partitions); Zephyr `subsys/pm`, `subsys/settings`, `subsys/kvss`, `subsys/fs`.
