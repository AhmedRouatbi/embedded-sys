# Bare metal & FreeRTOS — startup, linker, clocks, Cortex-M/RISC-V

> Load when: `platform=baremetal` or `freertos`; startup/linker/clock/vector-table/NVIC/MPU questions on any platform.
> Profile keys: `mcu`, `core`, `toolchain`, `build`, `elf`, `debugger`.

Rule zero: **don't hand-write what the vendor ships.** Startup file, linker script, `system_<dev>.c` and device headers come from the vendor CMSIS device pack / SDK (STM32Cube, nRF MDK, MCUXpresso, Pico SDK, MSDK). You adapt them; you cite the RM for every register you touch beyond them.

## Project skeleton (CMake + arm-none-eabi)

```
cmake/arm-none-eabi.cmake   toolchain file (below)
CMakeLists.txt              add_executable(app.elf src/*.c startup_<dev>.s system_<dev>.c)
                            target_link_options(app.elf PRIVATE -T${CMAKE_SOURCE_DIR}/<dev>.ld
                              -Wl,-Map=app.map,--gc-sections,--print-memory-usage --specs=nano.specs --specs=nosys.specs)
                            option(HOST_TESTS "host unit tests" OFF)   # testing-verification.md
src/  include/  vendor/ (CMSIS + device files, untouched)  tests/
```

```cmake
# cmake/arm-none-eabi.cmake
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_C_COMPILER arm-none-eabi-gcc)
set(CMAKE_ASM_COMPILER arm-none-eabi-gcc)
set(CMAKE_OBJCOPY arm-none-eabi-objcopy)
set(CPU "-mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard")   # match the core table
set(CMAKE_C_FLAGS_INIT "${CPU} -ffunction-sections -fdata-sections -Wall -Wextra")
set(CMAKE_ASM_FLAGS_INIT "${CPU} -x assembler-with-cpp")
set(CMAKE_EXE_LINKER_FLAGS_INIT "${CPU}")
```

`-Werror` on your own sources (not vendor), `-Og -g3` debug / `-Os` or `-O2` release, always keep the `.elf` with symbols for debugging.

## Core table

| Core | `-mcpu` / FPU flags | FPU | DSP/SIMD | Cache | TrustZone | Unaligned | Notes |
|---|---|---|---|---|---|---|---|
| M0/M0+ | `cortex-m0plus` | — | — | — | — | **fault** | no DWT cycle counter, no VTOR on M0 (M0+ optional), 2-bit priorities |
| M3 | `cortex-m3` | — | — | — | — | ok | BASEPRI, bit-banding on many parts |
| M4F | `cortex-m4 -mfpu=fpv4-sp-d16 -mfloat-abi=hard` | SP | yes | rare | — | ok | enable CPACR before first float |
| M7 | `cortex-m7 -mfpu=fpv5-d16 -mfloat-abi=hard` | SP/DP | yes | **I/D cache** | — | ok | DMA ↔ cache coherency, TCM |
| M33 | `cortex-m33 -mfpu=fpv5-sp-d16 -mfloat-abi=hard` | SP | opt | opt | yes | ok | stack limit regs (MSPLIM/PSPLIM), SAU |
| M55 | `cortex-m55 -mfloat-abi=hard` | +MVE | Helium | yes | yes | ok | cache maintenance like M7 |
| RISC-V (rv32imac) | `-march=rv32imac_zicsr -mabi=ilp32` | opt (F) | opt | varies | PMP | varies | `mtvec`, CLINT/PLIC/CLIC interrupt controllers |

## Startup sequence (what the vendor `Reset_Handler` + `SystemInit` must do)

1. Stack pointer from vector entry 0 (Cortex-M hardware does it).
2. `SystemInit()`: FPU enable (`SCB->CPACR |= (0xFU << 20)` + `__DSB(); __ISB();`), VTOR if the image isn't at the boot address, clock setup **or** leave it to `main`.
3. Copy `.data` from flash (LMA) to RAM (VMA); zero `.bss`.
4. `__libc_init_array()` (C++ constructors / newlib init).
5. `main()`; never return (`for (;;)` with WFI or the scheduler).

Clock bring-up order (most "random HardFault right after clock init" bugs): enable regulator/voltage scale → **raise flash wait states** → start oscillator, wait ready **with timeout** → configure PLL, wait lock → switch SYSCLK, wait switch status → set bus prescalers within datasheet limits → update `SystemCoreClock`. Lowering the clock: reverse order (wait states last).

## Linker script essentials

```ld
MEMORY { FLASH (rx) : ORIGIN = 0x08000000, LENGTH = 512K
         RAM  (rwx) : ORIGIN = 0x20000000, LENGTH = 96K }
_estack = ORIGIN(RAM) + LENGTH(RAM);
SECTIONS {
  .isr_vector : { KEEP(*(.isr_vector)) } > FLASH
  .text   : { *(.text*) *(.rodata*) KEEP(*(.init)) KEEP(*(.fini)) } > FLASH
  .data   : { _sdata = .; *(.data*) _edata = .; } > RAM AT > FLASH
  _sidata = LOADADDR(.data);
  .bss (NOLOAD) : { _sbss = .; *(.bss*) *(COMMON) _ebss = .; } > RAM
  ._user_heap_stack (NOLOAD) : { . = ALIGN(8); . += _Min_Heap_Size; . += _Min_Stack_Size; } > RAM
}
```
- Memory origins/lengths from the datasheet memory map (cite it); bootloader present → app `ORIGIN` = slot offset and set VTOR.
- `KEEP()` anything referenced only by hardware (vector table, sections walked by code).
- Inspect: `arm-none-eabi-size -A app.elf`, `--print-memory-usage`, `arm-none-eabi-nm --size-sort -S app.elf | tail -20`, map file "Discarded input sections" for what `--gc-sections` removed.

## Registers, NVIC, critical sections

- Use the device header (`stm32f4xx.h`, `nrf.h`) structs/masks: `USART2->CR1 |= USART_CR1_UE;` — never raw addresses unless the header lacks them (then cite RM section).
- Clock the peripheral (RCC/CMU enable) before touching it; read back once on parts whose errata require a delay after enabling.
- Write-1-to-clear status flags: assign, don't `|=`.
- NVIC: priority number lower = more urgent; only `__NVIC_PRIO_BITS` high bits implemented (`NVIC_SetPriority` handles the shift). Set grouping once (`NVIC_SetPriorityGrouping`), all preempt bits is simplest.
- Critical section: `uint32_t pm = __get_PRIMASK(); __disable_irq(); ... __set_PRIMASK(pm);` (nest-safe). On M3+ prefer `BASEPRI` masking to leave urgent IRQs live. Keep it to a few instructions.
- Peripheral RMW shared with ISRs: critical section or the hardware set/clear registers (GPIO BSRR, OUTSET/OUTCLR).
- Barriers: `__DSB()` after writing a register that disables an interrupt source before returning from the ISR (avoid ISR re-entry on M7 write buffers); `__DSB(); __ISB();` after VTOR, CPACR, MPU changes.

## MPU (cheap safety net)

Guard region at the bottom of each stack (no access, XN) catches overflows as a MemManage fault instead of silent corruption. Region size/alignment rules differ: ARMv7-M = power of two ≥ 32 B, base aligned to size; ARMv8-M (M33/M55) = base/limit 32-B granularity. Enable with `PRIVDEFENA` so privileged code keeps the default map; `__DSB(); __ISB();` after.

## Timebase & low-level timing

- `SysTick_Config(SystemCoreClock / 1000U)` → 1 ms tick; elapsed time with unsigned subtraction (`now - start >= ms`) is wrap-safe.
- Cycle-accurate timing: DWT (`CoreDebug->DEMCR |= TRCENA; DWT->CTRL |= CYCCNTENA`) — not on M0/M0+.
- Busy delays only in init code before the scheduler; never to paper over a timing bug.

## FreeRTOS on bare metal (`platform=freertos`)

- `FreeRTOSConfig.h` essentials: `configASSERT` mapped to a breakpoint/log + safe stop; `configCHECK_FOR_STACK_OVERFLOW 2` + `vApplicationStackOverflowHook`; `configUSE_MALLOC_FAILED_HOOK 1`; static allocation (`configSUPPORT_STATIC_ALLOCATION 1`) for production; `configTICK_RATE_HZ` 1000 or lower for power.
- ISR priorities: ISRs calling `...FromISR()` must have NVIC priority **numerically ≥** `configMAX_SYSCALL_INTERRUPT_PRIORITY` (in shifted form; `configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY` in unshifted). Higher-urgency ISRs must not call any FreeRTOS API.
- Port hooks: `SVC_Handler`/`PendSV_Handler`/`SysTick_Handler` mapped to the port (`vPortSVCHandler`, `xPortPendSVHandler`, `xPortSysTickHandler`) — vendor HALs often also want SysTick: give the HAL a different timer.
- `portYIELD_FROM_ISR(xHigherPriorityTaskWoken)` at the end of ISRs that give semaphores/queues.
- Concurrency patterns: `rtos.md` (mapping table Zephyr ↔ FreeRTOS).

## Anti-patterns

- Hand-writing startup/linker files when the vendor pack has them.
- Raising SYSCLK before flash wait states; waiting on ready flags without timeout.
- `|=` on write-1-to-clear registers; RMW on registers shared with ISRs without protection.
- Floats in ISRs on M4F without lazy stacking configured; enabling the FPU after the first float.
- Long `__disable_irq()` sections; calling FreeRTOS API from an ISR above the syscall priority.

## Sources
LibreEmbed `bare-metal`, `arm-cortex-m`, `memory-management`, `rtos-patterns`; ARM CMSIS-Core docs; FreeRTOS Cortex-M port notes.
