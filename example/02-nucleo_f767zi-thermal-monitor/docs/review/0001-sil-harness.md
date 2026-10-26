# Review 0001: SIL harness (PLAN task 8)

Reviewer role: `fw-reviewer` (`agents/fw-reviewer.md`, format `references/review.md`). Input: the task-8 diff and `docs/SPEC.md`, nothing else.
How it ran: simulated fresh context. On the machine where this example was built, Pi's `spawn_agent` could not start (bwrap: user namespaces blocked by AppArmor), and the Claude Code CLI was logged out. The skill's fallback (`subagents.md`) is to run the role yourself and re-read only the diff and the spec. Every finding was proven by mutation before it was written down.

**What this change does:** builds the unchanged application for `native_sim/native/64` with a simulated die sensor and watchdog that implement the same Zephyr APIs, LEDs and B1 on `gpio_emul`, and a `sim` shell. `app/sil/thermal.sil` drives it over the UART (`embsk uart --exec`) with one block of steps per requirement.

1. **REQ-5 debounce is tested nowhere** (`app/src/sim/sim_shell.c` `cmd_press`, `app/sil/thermal.sil` REQ-5 block)
   - What this is: `sim press` made one clean rising edge, and the scenario only checked `report on`.
   - Problem: with the debounce deleted from `button_work_fn()` (`if (now - last_ms < DEBOUNCE_MS)` → `if (0)`), the scenario still passed 19/19. The unit tests can't see it either, because the debounce lives in the hardware shell.
   - Fix: `sim press` bounces like a contact (3 bounces of 2 ms, then closed 30 ms: 4 rising edges in 12 ms), and the scenario checks `presses=1 report=on`.
   - If we skip it: a debounce regression ships unnoticed; on the bench one press toggles the report 2–4 times.

2. **REQ-4 is not checked in HOT** (`app/sil/thermal.sil` REQ-3 block)
   - What this is: `sim leds` was checked in NORMAL, WARM and FAULT only.
   - Problem: with the blue LED driven by `s != THERMAL_NORMAL` (lit in WARM *and* HOT), the scenario passed 19/19.
   - Fix: after `state=HOT`, `send sim leds` / `expect leds green=0 blue=0 red=[01]` (red blinks at 2 Hz, so either level is valid).
   - If we skip it: two LEDs on in HOT, against "exactly one LED".

3. **Nice to have: the SIL target is `native_sim/native/64` only** (`app/boards/native_sim_native_64.*`)
   - What this is: Zephyr picks board files by exact name and has no fallback from `native_sim/native/64` to `native_sim.overlay`. The first build of this task failed for exactly that reason.
   - Problem (reasoned, not built: 32-bit needs gcc-multilib): `west build -b native_sim app` compiles the sim sources without the overlay, so `__device_dts_ord_DT_N_ALIAS_die_temp0_ORD` is undeclared.
   - Fix: name the supported target in the overlay header (done). Add a 32-bit copy only if someone needs it.
   - If we skip it: a confusing devicetree error for whoever tries 32-bit.

Mutation check after the fixes (each line: break `app/src/monitor.c` in one place, rebuild, run the scenario):

| Mutant | Before the fixes | After the fixes |
|---|---|---|
| debounce removed | 19/19 pass (survives) | fails at step 7 |
| blue LED lit in HOT | 19/19 pass (survives) | fails at step 19 (`leds green=0 blue=0 red=[01]`) |
| blue LED ignores FAULT (the walkthrough's demo bug) | fails | fails at step 27 (`leds green=0 blue=0 red=1`) |
| none (good code) | 19/19 | 21/21, three runs in a row, 13.5 s each |

Also found while fixing finding 1: the first bouncy `sim press` used `k_msleep(2)`. native_sim ticks at 100 Hz, so the "bounce" lasted 80 ms, and the app *correctly* counted two presses. The spacing now uses `k_busy_wait()`. The simulator is code too, and it gets checked the same way.

Verdict: fix 1 and 2 first → fixed and re-verified → **Ship.**
Not checked: REQ-8 reset path (the shell can't stall the sampler; the sim watchdog only reports a stall), REQ-1 jitter (simulated time), ADC calibration, and everything on hardware (L4: no board attached).
