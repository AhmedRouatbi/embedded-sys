# Review — embedded code review (ponytail-review + firmware axes + doubt loop)

> Load when: reviewing a diff/PR/commit, or your own work before claiming done (phase 7).
> Profile keys: `safety`, `safety_level`, `coding_standard`, `hil`, `features`.

Review like the firmware engineer who gets the call when 10 000 units brick in the field.
Order: **correct → safe for hardware → holds under real timing/load → tested → fast/small enough → lean.**
This is one reviewer, not four: it replaces ponytail-review, ponytail-audit (per change), agent-skills code-review-and-quality and code-simplification.

## 1. Understand first

- Scope: what the user names (staged/uncommitted changes, branch, PR, files). Nothing named → uncommitted changes, else the last commit.
- Read the diff, then the connected code: callers of every changed function (`graphify affected <symbol>` or `rg`), the ISR/thread contexts that call it, the DT overlay and Kconfig it relies on, the tests.
- Trace the real flow: interrupt/peripheral → buffer → thread → output. Note which context (ISR, thread priority, work-queue) each line runs in.
- Find the expected load/timing in the spec (`docs/SPEC.md`): sample rates, bus speeds, worst-case burst, power budget. Judge against that and say which you assumed.
- Fresh context is the point: review from the **diff + spec**, not from the author's reasoning. In Pi spawn `fw-reviewer` with `fork_turns: "none"`; elsewhere see `subagents.md`.

## 2. Look for (in this order)

1. **Bug** — wrong result, missed edge (0, max, wrap-around of tick counters, last buffer slot, odd length, endianness, unaligned access, signed/unsigned mix, integer promotion), broken caller, fix in one caller while the shared function stays wrong.
2. **Hardware risk** — writes to option bytes/flash/OTP/fuses/RDP; bootloader or partition-table changes; pin used as output that the schematic drives; clock/voltage config outside datasheet limits; missing errata workaround; peripheral used before clock enable/ready flag; DMA buffer in cache-able RAM on M7/M55 without maintenance.
3. **Concurrency & timing** — data shared between ISR and thread without protection; read-modify-write races on registers; blocking/sleeping/`LOG_*` heavy work in ISRs; unbounded waits; priority inversion (mutex held across slow I/O); deadlock order; watchdog fed from an ISR or from a loop that still runs when the system is stuck; latency budget broken by a new critical section.
4. **Resource** — stack growth (new large locals, recursion, `printf` with floats) without stack re-measurement; heap use after init; buffers that only grow; flash/RAM delta vs. budget (`size` target output); power: peripheral clocks left on, busy-wait instead of sleep, wake source not re-armed.
5. **Robustness / security** — unchecked length from a bus/radio/USB/UART; missing return-value check; error path that leaks a lock or leaves a peripheral half-configured; secrets/keys in source or logs; debug interfaces left open in release config; update images accepted without signature/version check.
6. **Missing test** — new branch, parser, state machine, conversion math or bug fix without a test that fails when it breaks (host test preferred). One good test, not coverage.
7. **Speed/size** — real slowdowns in hot paths/ISRs are findings; micro-wins are "nice to have".
8. **Lean** — delete (dead code, unused Kconfig/option), reuse (name the existing helper/driver path), platform (Zephyr subsystem or CMSIS already does it), yagni (abstraction with one user, wrapper over one register), merge (near-copies), split (one function doing unrelated jobs — split by job, never by line count).

With `coding_standard ≠ none` or `safety ≠ none`, also run the checklist in `safety.md` §Review.

## 3. Check before reporting

- Every finding needs a concrete case: *"when X happens (input/timing/state), Y goes wrong"*. No case → no finding.
- Re-read the lines: the caller exists, the value can really be 0, the ISR really shares that variable.
- A `/* shortcut: <limit>, <upgrade> */` comment is a decision, not a finding — unless the spec's load already crosses the limit.
- Propose the smallest fix; prefer fixes that delete code. No style taste, no "consider", no vague worry.

## 4. Output (plain English, short sentences)

Start with `What this change does:` (2–3 sentences). Then number findings across groups (skip empty groups):

- **Must fix** — bug, hardware risk, race, data loss, security, breaks the timing/load in the spec, violates a mandatory coding-standard rule.
- **Should fix** — risky code without a test, real slowness/size cost, duplication, mixed-job function, code that shouldn't exist.
- **Nice to have** — small speed/size wins, shorter forms.

Each finding has four parts, one or two sentences each:

```
3. **UART RX overflow drops bytes at 921600 baud** (`src/uart_rx.c:L58-71`)
   - What this is: the RX ISR copies each byte into a 64-byte ring buffer read by the parser thread.
   - Problem: at 921600 baud a 512-byte burst arrives in 5.5 ms but the parser thread (prio 7) can be
     preempted for 10 ms by the sensor thread, so the buffer overflows and bytes are dropped silently.
   - Fix: use the async UART API with DMA double-buffering (`uart_rx_enable`, 2×256 B), count
     overruns in a stat. ~20 lines, removes the per-byte ISR.
   - If we skip it: corrupted frames under burst traffic; looks like a protocol bug in the field.
```

End with:
- `Verdict: Ship.` or `Verdict: fix 1 and 3 first.`
- `Lean: -<N> lines possible.` when lean findings exist.
- `Not checked:` one line (e.g. "no hardware attached; timing reasoned from the spec, not measured").

Nothing found: `What this change does:` + `Looks good. Ship.` + one line on what you checked.
The review lists findings; it changes no code unless the user asks.

## 5. T2: doubt loop (critical changes, safety functions)

1. **CLAIM** (for yourself): the decision in 2–3 lines and why it matters.
2. **EXTRACT**: the smallest unit — the diff/function + the contract (REQ-n, timing, safety requirement). Strip your reasoning.
3. **DOUBT**: fresh-context reviewer (`fw-reviewer`, plus `fw-safety` if `safety ≠ none`) with this prompt; pass ARTIFACT + CONTRACT only, never the CLAIM:
   ```
   Adversarial review. Assume the author is overconfident. Find what is wrong:
   unstated assumptions, unhandled edges, ISR/thread races, timing violations, hardware
   misuse vs. the datasheet, failure modes under unexpected input or power loss.
   Do NOT validate or summarize. Find issues or state that you found none after thorough
   examination. ARTIFACT: <...>  CONTRACT: <...>
   ```
   Interactive session: offer a cross-model second opinion (another CLI, read-only sandbox, prompt via stdin file); never invoke one without the user's OK.
4. **RECONCILE**, first match wins: contract misread (fix the contract) → valid + actionable (change, re-loop) → valid trade-off (document it for the user) → noise (note what context would have prevented it).
5. **STOP** after a clean pass, 3 cycles (escalate to the user), or "ship it". Too big for 3 cycles → decompose.

## Anti-patterns

- Reviewing the author's explanation instead of the code.
- Approving because tests pass when the tests don't exercise the risky path.
- Style nits while a race or a missing timeout goes unmentioned.
- "LGTM" without stating what was checked and what wasn't (hardware, timing).

## Sources
ponytail `ponytail-review` (MIT); agent-skills `code-review-and-quality`, `doubt-driven-development`, `code-simplification`; LibreEmbed `safety-critical`, `rtos-patterns`, `memory-management`.
