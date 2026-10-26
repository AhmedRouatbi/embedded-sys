# Context & tokens — graphify-first navigation

> Load when: first session in a repo, before any "where/how does X" exploration, when context gets large, when generating docs.
> Profile keys: `graphify` (on/off), `platform`.

Goal: answer code questions from a pre-built graph and small targeted reads, not by reading the tree. Typical saving is an order of magnitude fewer tokens per question; context stays free for the actual change.

## Setup (once per repo, zero LLM cost)

```bash
uv tool install graphifyy          # package "graphifyy", command "graphify"
graphify update .                  # AST-only extraction of code (C/C++/Python/shell...), no API key
graphify hook install              # rebuild on commit/checkout (no daemon)
echo "graphify-out/cache/" >> .gitignore
```

Add a `.graphifyignore` (gitignore syntax) for `build*/`, `twister-out*/`, vendored HALs you never edit (`modules/hal/**`), generated code. Index **your app**, not the whole Zephyr tree — for Zephyr internals use the Zephyr docs or targeted `rg` in `$ZEPHYR_BASE`.

## Daily use

| Need | Command |
|---|---|
| Where is X / how does A reach B | `graphify query "how does the ADC sample reach the BLE notify?" --budget 1500` |
| What is this symbol + neighbours | `graphify explain "sensor_thread"` |
| Call/dependency chain | `graphify path "uart_isr" "frame_parse"` |
| Blast radius before changing a function | `graphify affected "ring_put" --depth 2` |
| Architectural hubs (start here in a new repo) | `graphify god-nodes --top 15` |
| After edits | `graphify update .` (hook does it on commit) |
| Docs snapshot (milestones) | `graphify export wiki` → `graphify-out/wiki/`; `graphify export callflow-html` for a diagram |
| Remember a useful answer | `graphify save-result --question "..." --answer "..." --outcome useful` |

Rules:
1. Query the graph **before** opening files. Open only the files the answer names, and only the line ranges you need.
2. Never `cat` whole directories, never read `build/`, `twister-out/`, `graphify-out/graph.json`.
3. graphify missing or `graphify off` → `rg -n --type c "symbol" src/ include/` with tight globs; `rg -l` first, then read hits.
4. Large tool output → save to `artifacts/<name>.txt` and grep it instead of pasting it into context.

## Zephyr: what the graph cannot see, and the fix

AST mode indexes `.c/.h` but **not** `.dts/.dtsi/.overlay`, `Kconfig`, `prj.conf`, `.ld`, `.S`. Those source fragments also don't tell you what was actually built. After every build that touches DT or Kconfig:

```bash
embsk export build        # copies resolved artifacts to docs/generated/
```

| File in `docs/generated/` | Answers |
|---|---|
| `zephyr-dts.txt` | final devicetree: node labels, addresses, real `status` |
| `dt-nodes-and-status.txt` | one-line-per-node index — grep this first |
| `devicetree_generated.h` (indexed by graphify) | why a `DT_*`/`DEVICE_DT_GET` macro resolves or not |
| `kconfig-resolved.conf`, `autoconf.h` | which drivers/subsystems are really enabled |
| `zephyr-map.txt`, `size-report.txt`, `linker-resolved.txt` | where flash/RAM went |
| `runners.conf` | which flash/debug tool `west flash` will call, with which args |

`__device_dts_ord_N undeclared` → `rg -n "<node>|<parent-bus>" docs/generated/dt-nodes-and-status.txt` then `rg CONFIG_<DRIVER> docs/generated/kconfig-resolved.conf`. Enabling a child node never enables its parent bus.

RTOS entry points are invisible as callers: a thread started by `k_thread_create`/`K_THREAD_DEFINE`, an ISR registered with `gpio_init_callback`/`IRQ_CONNECT`, a `K_WORK_DEFINE` handler or a `SHELL_CMD` handler shows up as a root. `graphify path "main()" "leds_show()"` then finds no directed path. Ask from the entry instead (`graphify explain "sampler()"`, `graphify affected "leds_show()"`), and list entries with `rg -n "k_thread_create|K_THREAD_DEFINE|K_WORK_DEFINE|gpio_init_callback|SHELL_CMD"`.

Logs: keep captures as `.txt` (`artifacts/rtt.txt`), so they're greppable and LLM graph passes can ingest them.

## Context hygiene (from context-engineering)

- Project rules live in `AGENTS.md` (Claude Code reads it through `CLAUDE.md` → `@AGENTS.md`). The `embsk` block there is the single source for target + commands; don't restate it in chat.
- Load references from this skill on demand (see SKILL.md §6); never all at once.
- Long session: summarize decisions into `docs/SPEC.md`/ADRs, then compact. State lives in files, not in the conversation.
- Delegate wide searches to a `fw-scout` subagent that returns paths + facts, not file dumps.

## Optional semantic layer

`graphify extract . --backend <gemini|claude|openai|ollama>` adds doc/spec/datasheet-notes nodes (INFERRED edges) using an LLM. Worth it once docs/specs exist; not needed for code navigation. Datasheets: keep extracted notes as markdown in `docs/hw/` rather than PDFs in the repo.

## Anti-patterns

- Reading 30 files "to understand the codebase" before a 5-line change.
- Indexing all of `zephyrproject/` (huge graph, slow, noisy).
- Trusting source `.overlay` fragments over the resolved `zephyr-dts.txt`.
- Pasting full build logs into the conversation instead of grepping the saved file.

## Sources
graphify (Graphify-Labs, CLI 0.9.x); agent-skills `context-engineering`; the author's EmbeddedDev-Flow analysis (resolved DTS export).
