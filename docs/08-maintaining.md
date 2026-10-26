# 08 — Maintaining and extending

Run `bash docs/quick-check.sh` before and after every change (offline, ≈ 30 s). Before a release, also run `bash docs/quick-check.sh --full` (network: real `embsk setup` + build + host tests of example 02).

## Repo conventions

- **Cross-platform** (Linux, macOS, Windows): `embsk.py` and `install.py` stay stdlib-only; use `venv_exe()`, `resolve()`, `bash_exe()`, `path_fix()` instead of hard-coding `bin/`, `python3`, `bash` or `export PATH`. Hooks stay pure bash (no jq/python): they run in Git Bash on Windows. Add a Windows case to quick-check's simulation for any new OS branch.
- `embsk.py`: one file, stdlib only, Python ≥ 3.9. Keep functions small and in the section order of [02](02-architecture.md). Comments explain *why* (west quirks, hardware facts).
- No absolute paths in templates, profiles or generated AGENTS.md.
- The skill dir is self-contained; adapters (Pi, Claude, Codex, tmux, hooks) live at the repo root.
- Commands written into references and the AGENTS block must be real for Zephyr 4.x. Verify them against a tree (`~/zephyrproject/zephyr` on the original host) — `rg` the Kconfig symbol, API or west command before writing it.
- Docs: when you change behaviour, update the matching page in `docs/` and, if user-facing, `README.md`.

## How to…

### Add a profile option
1. Add a tuple to `OPTIONS`: `(label, key, type, values|default, visible_when)`. Types: `choice` (list, first = default), `multi` (checkbox rows), `list` (comma text), `text`, `bool`, `board`, `level`.
2. Use it where it matters: `doctor()`, `commands()`, `block()`, `refs_for()`, `required_modules()`.
3. Front-ends pick it up automatically (menu rows, `embsk schema`). Update the `AskUserQuestion` rounds in `commands/embsk.md` if it belongs in the Claude menu.
4. Document it in [04](04-embsk-cli.md) (schema table).

### Add a debug probe
1. Add it to `debugger` values in `OPTIONS`.
2. Add `RUNNERS[probe]` (Zephyr runner names that satisfy it) and `TOOLS[probe]` (host binaries; `TOOL_FALLBACK` for default install paths).
3. In `commands()`: the Zephyr runner name mapping (if it differs from the probe name), the bare-metal flash/debug strings, and the log command if it supports RTT.
4. Add its flash/erase command patterns to `hooks/flash-guard.sh` and a test case to `quick-check.sh`.
5. Add a row to the probe table in `references/debugging.md`.

### Add or fix a board → module rule
- Irregular vendor → HAL name: add it to `HAL` (`zephyr/soc/<vendor>` dir name → module name in Zephyr's `west.yml`).
- Arch-wide module: `ARCH_MODULES`. Feature-driven: `FEATURE_MODULES`. Log-driven: `LOG_MODULES`.
- Verify: `embsk set board=<id> … && embsk modules`, then a real `embsk setup` in a temp folder (`quick-check.sh --full` covers f767).
- Never allow an empty allowlist (west fetches everything). `write_manifest()` already guards this; keep the guard.

### Add a feature checkbox
Add it to the `features` values. Map it in `FEATURE_REFS` (reference to load) and, if it needs west modules, in `FEATURE_MODULES`. Document it in [04](04-embsk-cli.md) and [05](05-zephyr-workspace.md).

### Add a reference file
Create `references/<name>.md` following the style contract below. Add it to the routing tables in `SKILL.md` §6 and [03](03-agent-workflow.md). If the profile should trigger it, update `refs_for()`. `quick-check.sh` verifies every reference named in SKILL.md exists and every file is referenced.

### Change the default Zephyr version
Edit the `zephyr_rev` default in `OPTIONS`, `revision:` in `templates/zephyr-app/app/west.yml`, the `"v4.4.2"` fallback in `write_manifest()`, and the docs/examples that mention it. Then run `quick-check.sh --full`.

### Change a template
Templates are in `skills/embedded-sys/templates/<platform>/`. Root files (`gitignore`, `graphifyignore`) are stored without the dot. Everything for the application lives under `app/`. Rebuild the examples if the template changes: in `example/01-zephyr-template`, re-run `embsk scaffold` on a copy and diff.

### Change the Pi extension
Edit `pi-extension/index.ts`, then type-check. On the original host this needed a scratch dir with symlinks to Pi's package and `@types/node`, plus the typescript compiler found under `~/.cache/opencode/.../typescript/bin/tsc`. Smoke-test: `(echo '{"type":"get_commands","id":"1"}'; sleep 6) | pi --mode rpc --no-session -e pi-extension/index.ts | grep '"name":"embsk"'`.

## Reference-file style contract

1. First line `# Title`. Then `> Load when: …` and `> Profile keys: …`.
2. Dense, imperative, checklist-first; tables over prose; no history or marketing.
3. 80–150 lines (hard cap 300).
4. Zephyr first, bare metal second, FreeRTOS third. Use a 3-column table when the rule differs per platform.
5. Code snippets only when they encode something agents get wrong (≤ 25 lines). C99/C11, `<stdint.h>`, negative errno in Zephyr.
6. Every command must be real and current (Zephyr 4.x, HWMv2 names).
7. Ponytail applies to the guidance: recommend the smallest thing that works; never cut validation, error handling, calibration or safety.
8. End with `## Anti-patterns` and `## Sources`.
9. No placeholders, no TODOs.

## Regression checklist (what quick-check.sh covers)

| Area | Check |
|---|---|
| syntax | in-memory `compile()` of embsk.py + install.py (no `__pycache__` in the linked skill dir), `bash -n` on all shell scripts, JSON manifests parse |
| skill integrity | SKILL.md frontmatter (name format, description ≤ 1024 chars); every referenced `references/*.md` exists, none orphaned; agent cards have `name:` frontmatter |
| profile | `set` rejects unknown keys / invalid values / wrong safety level; order-independent validation; normalization |
| Zephyr (if a reference tree exists) | `boards` search; doctor catches non-existent board, missing qualifiers, MCU ≠ SoC, unsupported probe; `modules` for 6 boards; debug runner fallback for stlink |
| manifest | `write_manifest([])` writes the `none` placeholder; patching keeps other content |
| scaffold | Zephyr and bare-metal templates land in `app/`; dotfiles renamed; AGENTS.md gets the workspace line |
| hooks | flash-guard (no jq): 13 ask / 5 allow commands incl. PowerShell + Windows paths, multi-line, Codex array, secret files (POSIX + Windows), `Write` content ignored, escaped reason, deny mode; PowerShell in the matcher; session-start without jq |
| uart | `embsk uart` against a fake shell target: send/expect, clean transcript, timeout exit 1, expects only after the last send, fail-on, bad script exit 2; serial path on a pty (pyserial or termios); `sil`/`uart` rows generated |
| installer | `install.py` in a throw-away HOME: install + `--agent-dir`, launcher runs, idempotent, `--check` 0, uninstall keeps foreign files, `--check` 1 after, `install.sh` forwards |
| Windows (simulated) | Git Bash lookup, `.exe` SDK from PATH, PowerShell PATH fix, `CMAKE_NM …nm.exe`, launchers, junction and copy fallbacks, registry PATH append without duplicates |
| plugin | `claude plugin validate` (if `claude` exists) |
| `--full` | example 02: `embsk setup` (download + build) and `embsk verify` (7/7 tests + SIL scenario 21/21) |
