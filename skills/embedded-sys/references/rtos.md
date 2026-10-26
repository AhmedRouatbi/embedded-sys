# RTOS & concurrency — threads, ISRs, priorities, stacks, watchdog

> Load when: designing/changing threads, ISRs, queues, locks, timers, work-queues, priorities, stack sizes, watchdog, timing/latency; DSP pipelines.
> Profile keys: `platform` (zephyr|freertos|baremetal), `safety`, `features` (dsp, low-power).

## Primitive mapping

| Need | Zephyr | FreeRTOS | Bare metal |
|---|---|---|---|
| Thread | `K_THREAD_DEFINE` (static) / `k_thread_create` | `xTaskCreateStatic` | superloop + state machines |
| Protect shared state | `k_mutex` (priority inheritance, threads only) | mutex (`xSemaphoreCreateMutexStatic`) | critical section |
| ISR → thread signal | `k_sem_give` from ISR | `vTaskNotifyGiveFromISR` / binary semaphore | volatile flag + WFI loop |
| Data from producer to consumer | `k_msgq` (fixed-size items), `k_pipe`, `ring_buffer` | queue / stream / message buffer | ring buffer, single producer single consumer |
| Wait for one of N events | `k_event`, `k_poll` | event groups | flag bits |
| Defer work out of ISR | `k_work_submit` (system work-queue) / own `k_work_q` | deferred task, `xTimerPendFunctionCallFromISR` | flag polled in main loop |
| Delayed / periodic action | `k_work_delayable`, `k_timer` (expiry fn runs in ISR context) | software timer (runs in timer task) | SysTick/timer ISR sets flag |
| Pub/sub between modules | `zbus` | queue set / custom | — |
| ISR ↔ thread lock (short) | `irq_lock()`/`irq_unlock()`, `k_spinlock` | `taskENTER_CRITICAL[_FROM_ISR]` | PRIMASK/BASEPRI |
| Single word shared | `atomic_t` + `atomic_*` | `__atomic` builtins / critical section | `__atomic`/LDREX-STREX (M3+) |
| Fixed-size block pool | `k_mem_slab` | static pool + queue of pointers | static array + free list |

Never use a counting semaphore as a mutex (no priority inheritance). Never take a mutex in an ISR.

## ISR rules

1. Clear the interrupt source first, read what's volatile, hand off, return. Target: a few µs.
2. No blocking calls (`K_FOREVER`, `k_sleep`, mutexes), no heavy logging (deferred log mode only), no `printf`, no malloc.
3. Only ISR-safe APIs: Zephyr `k_sem_give`, `k_msgq_put(..., K_NO_WAIT)`, `k_work_submit`, `k_event_post`, `k_timer_start`, `atomic_*`; FreeRTOS `*FromISR` + `portYIELD_FROM_ISR`.
4. Floats in ISRs only if lazy FP context stacking is configured (Zephyr `CONFIG_FPU_SHARING`), else avoid.
5. Zephyr: `IRQ_CONNECT`/`IRQ_DIRECT_CONNECT` for custom ISRs; driver callbacks (GPIO, UART async, counter) already run in ISR context — treat them as ISRs.

Deferred interrupt processing:

```c
static K_SEM_DEFINE(data_ready, 0, 1);
static void drdy_cb(const struct device *d, struct gpio_callback *cb, uint32_t pins)
{
	k_sem_give(&data_ready);                      /* ISR context: signal only */
}
static void sensor_thread(void *a, void *b, void *c)
{
	for (;;) {
		if (k_sem_take(&data_ready, K_MSEC(50)) != 0) {
			LOG_WRN("drdy timeout");               /* handled timeout path */
			continue;
		}
		read_and_process();                        /* thread context: bus I/O, logging ok */
	}
}
K_THREAD_DEFINE(sensor_tid, 1024, sensor_thread, NULL, NULL, NULL, 5, 0, 0);
```

## Priorities

- Zephyr: lower number = higher priority. Negative = cooperative (not preempted by other threads; use for short critical chains only). `CONFIG_NUM_PREEMPT_PRIORITIES`, `CONFIG_MAIN_THREAD_PRIORITY`, system work-queue priority (`CONFIG_SYSTEM_WORKQUEUE_PRIORITY`).
- FreeRTOS: higher number = higher priority; 0 = idle.
- Assign by deadline (rate-monotonic: shorter period → higher priority). Order: hard-real-time ISR follower > control loop > data path > comms > housekeeping/health. Few levels, documented in the design table.
- One thread per truly concurrent activity (different rate/deadline/blocking), not per concept. "Read sensor" and "process sample" are usually one thread.
- Don't block the system work-queue with slow I/O; give slow jobs their own `k_work_q`.

## Priority inversion

| Form | Fix |
|---|---|
| Unbounded (H waits on L, M preempts L) | mutex with priority inheritance (Zephyr `k_mutex`, FreeRTOS mutex) or priority ceiling |
| Bounded (long critical section) | shorten it: no I/O, no sleep, no logging while holding a lock |
| Chain blocking (H→R1→L1→R2→L2) | one lock, fixed lock order, or message passing instead of shared state |

Deadlock prevention: global lock order, never hold two locks across a blocking call, timeouts on lock acquisition in production code with a logged failure.

## Stack sizing

1. Static estimate: compile with `-fstack-usage` (`.su` files) or `west build -t puncover`; walk each thread's deepest call path.
2. Add worst-case ISR nesting on the same stack (Cortex-M ISRs use MSP in Zephyr/FreeRTOS — size the ISR stack `CONFIG_ISR_STACK_SIZE` separately) and FP context (~136 B on M4F with lazy stacking).
3. Margin ×1.3 (×1.5 if unsure), round to 64/128 B.
4. **Measure** on target: Zephyr `CONFIG_THREAD_ANALYZER=y` + `CONFIG_THREAD_ANALYZER_AUTO=y` or `k_thread_stack_space_get()` with `CONFIG_THREAD_STACK_INFO=y` + `CONFIG_INIT_STACKS=y`; FreeRTOS `uxTaskGetStackHighWaterMark`. Report numbers, not guesses.
5. Protection: `CONFIG_HW_STACK_PROTECTION=y` (MPU guard / PSPLIM on v8-M); FreeRTOS `configCHECK_FOR_STACK_OVERFLOW 2`.
Stack killers: large local buffers, `snprintf` with floats, recursion, deep logging calls — move buffers to static or the thread's object.

## Watchdog strategy

| Pattern | Catches | Misses |
|---|---|---|
| Low-priority thread kicks | total hang | one stuck thread |
| **Heartbeat aggregator** (each thread checks in within its window; supervisor kicks only if all did) | any stuck thread | live-lock with heartbeats but no progress → add progress counters |
| Window watchdog | runaway loops kicking too fast | — |

- Zephyr: `task_wdt` (`CONFIG_TASK_WDT=y`): `task_wdt_add(period_ms, cb, NULL)` per thread, `task_wdt_feed(id)` in its loop, hardware watchdog as fallback (`task_wdt_init(hw_wdt_dev)`).
- Never kick from an ISR or timer callback (they keep running while threads are dead).
- Disable/pause watchdog in debug sessions only via the debug-freeze bit (DBGMCU), never by commenting out init.
- Log the reset cause at boot (`hwinfo_get_reset_cause()` in Zephyr, RCC CSR flags bare metal) and clear it.

## Timing & latency

- Write the budget table: event → deadline → measured worst case. Measure with DWT cycles/`k_cycle_get_32()`, GPIO toggle + logic analyzer, or `CONFIG_TRACING` (SEGGER SystemView / Percepio, `-S rtt-tracing`).
- Worst-case latency of a thread = its own WCET + higher-priority interference + longest critical section/IRQ lock + blocking on locks.
- DSP / sample pipelines: DMA double-buffering (ping-pong) into a block-processing thread; process blocks, not samples; CMSIS-DSP for filters/FFT on M4F/M7/M33 (Zephyr: `CONFIG_CMSIS_DSP=y`).

## Common bugs → first check

| Symptom | Check |
|---|---|
| Thread never runs | scheduler started; higher-priority thread busy-looping; blocked on a never-signalled object; `K_THREAD_DEFINE` start delay |
| Random resets | watchdog (reset cause), stack overflow (analyzer, guard), brown-out (power), fault handler rebooting |
| Works alone, fails with others | shared data race, priority starvation, stack overflow from extra ISR nesting, timing budget |
| ISR latency too long | long `irq_lock`/critical sections, logging in ISR, flash erase stalling the bus, lower-priority ISR masking |
| Corrupted shared global | missing lock / volatile-as-lock / non-atomic 64-bit access / DMA writing into it |

## Anti-patterns

- `k_sleep()`/`vTaskDelay()` to "wait for" another thread instead of a semaphore/queue.
- Polling loops at top priority; doing bus I/O inside `k_timer` expiry functions (ISR context).
- Mutex held across logging, flash writes or bus transactions with slow peripherals.
- One thread per feature "for cleanliness"; magic priority numbers without a table.

## Sources
LibreEmbed `rtos-patterns`, `power-management`; Zephyr kernel docs (`k_*`, `task_wdt`, `zbus`); FreeRTOS reference manual.
