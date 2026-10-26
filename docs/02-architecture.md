# 02 — Architecture

## Component diagram

```
             ┌───────────────────── front-ends (Alt+A) ─────────────────────┐
             │ Pi extension        Claude Code /embsk      tmux popup  shell │
             │ (suspends TUI,      (AskUserQuestion        (Codex, any  embsk│
             │  runs embsk menu)    → embsk set ...)        CLI)         menu │
             └───────────────┬───────────────┬────────────────┬────────────┘
                             ▼               ▼                ▼
                ┌──────────────────────────────────────────────────────┐
                │ skills/embedded-sys/scripts/embsk.py  (stdlib Python) │
                │ profile · board index · doctor · render · setup · ... │
                └───┬───────────────┬──────────────────┬───────────────┘
                    │ writes        │ writes           │ writes / runs (Zephyr)
                    ▼               ▼                  ▼
        .embsk/profile.json   AGENTS.md "embsk"   app/west.yml (allowlist)
                              block (+CLAUDE.md   west init -l app / west update
                              → @AGENTS.md)       / west build
                                    │ read every session
                                    ▼
                ┌──────────────────────────────────────────────────────┐
                │ Agent + skills/embedded-sys/SKILL.md (router)         │
                │  → references/*.md (on demand, chosen by profile)     │
                │  → agents/fw-*.md (subagent roles)                    │
                └───┬──────────────────────────────────────────────────┘
                    │ tool calls
                    ▼
        hooks/flash-guard.sh  (PreToolUse: Claude/Codex; Pi via extension tool_call)
        hooks/session-start.sh (one context line)
        pi-workflows/embedded.yaml (plan → execute → verify → review loop)
```

## State files in a user project

| File | Written by | Read by | Notes |
|---|---|---|---|
| `.embsk/profile.json` | `embsk menu` / `embsk set` | embsk, Pi status, session hook | the contract; marks the project root |
| `AGENTS.md` (block between `<!-- embsk:begin … -->` and `<!-- embsk:end -->`) | `embsk render` (called by set/menu/scaffold) | every agent | content outside the markers is preserved |
| `CLAUDE.md` | created as `@AGENTS.md` if missing | Claude Code | if it exists without the import, embsk prints a note |
| `app/west.yml` | template, then `embsk setup` patches `revision` + `name-allowlist` | west | other manifest content is preserved |
| `.west/config`, `deps/zephyr`, `deps/modules/...` | west via `embsk setup` | west, embsk | git-ignored, re-creatable |
| `.venv/` | `embsk setup` only if Zephyr Python deps are missing | embsk/west | git-ignored |
| `build/CMakeCache.txt` → `ZEPHYR_SDK_INSTALL_DIR` | first configure by `embsk setup` (SDK from PATH) | CMake on every later `west build -d build` | keeps the agent's plain builds on the same SDK |
| `build/`, `build-test/` | west/cmake | embsk verify/export | git-ignored |
| `artifacts/*.txt` | log captures, `embsk verify` | agent (grep) | `.txt`, not `.log` |
| `docs/generated/*` | `embsk export` | agent, graphify | resolved DTS/Kconfig/map |
| `docs/SPEC.md`, `docs/PLAN.md`, `docs/adr/` | agent (from templates) | agent, humans | process artifacts |

## Repository file map

```
embeddedSysSk/
├── README.md                       user-facing overview (answers "why merge", install, verified)
├── INSTALL.md                      install guide for humans and agents (Linux, macOS, Windows)
├── LICENSE · THIRD-PARTY-NOTICES.md · CHANGELOG.md · CONTRIBUTING.md
├── .gitattributes                  LF for shell scripts (Git Bash on Windows breaks on CRLF)
├── .github/workflows/check.yml     CI: quick-check on Linux, install.py + --check on Windows
├── AGENTS.md, CLAUDE.md            orientation for an agent handed this repo
├── install.py                      cross-platform installer: install | --check | --uninstall | --agent-dir (see 06)
├── install.sh                      Linux/macOS wrapper for install.py
├── package.json                    Pi package manifest: pi.extensions only (skill via ~/.agents/skills)
├── .claude-plugin/plugin.json      Claude plugin "embedded-sys" (agents listed explicitly)
├── .claude-plugin/marketplace.json local marketplace "embsk"
├── .claude-plugin/icon.png         plugin icon (512×512, rendered from docs/assets/logo.svg)
├── .codex-plugin/plugin.json       Codex plugin (hooks; skill via ~/.agents/skills)
├── commands/embsk.md               /embsk command (Claude) = Codex prompt; AskUserQuestion rounds → embsk set → embsk setup
├── hooks/
│   ├── hooks.json                  SessionStart + PreToolUse for Claude/Codex (${CLAUDE_PLUGIN_ROOT})
│   ├── flash-guard.sh              asks before flash/erase/lock/option bytes/eFuse + secret files
│   └── session-start.sh            "[embsk] profile: ..." or "press Alt+A"
├── pi-extension/index.ts           Pi: registerShortcut("alt+a"), /embsk, status bar, tool_call gate
├── pi-workflows/embedded.yaml      Pi workflow_run "embedded": plan → execute → verify ⇄ review
├── tmux/embsk.tmux.conf            bind -n M-a display-popup … embsk menu
├── example/                        01-zephyr-template, 02-nucleo_f767zi-thermal-monitor (see 07)
├── docs/                           this documentation + quick-check.sh; docs/assets/ = logo, banner, workflow graphic, social preview
└── skills/embedded-sys/            ← THE SKILL (self-contained, portable)
    ├── SKILL.md                    router: profile → tiers → phases/gates → rules → subagents → reference map → reply format
    ├── references/                 16 on-demand files (see 03 for the routing table)
    ├── agents/                     fw-scout, fw-builder, fw-verifier, fw-reviewer, fw-safety (Claude agent frontmatter)
    ├── scripts/embsk.py            the engine (~950 lines, stdlib only; PyYAML optional)
    ├── scripts/export-zephyr-context.sh   resolved DTS/Kconfig/map/size → docs/generated/
    └── templates/
        ├── zephyr-app/             gitignore, graphifyignore, app/{west.yml, CMakeLists.txt, prj.conf, src/main.cpp}
        ├── baremetal/              gitignore, graphifyignore, app/{CMakeLists.txt, cmake/arm-none-eabi.cmake, src/, tests/}
        ├── SPEC.md, ADR.md, CONSTRAINTS.md
```

Templates store `gitignore` and `graphifyignore` without the leading dot so they don't affect the skill repo. `embsk scaffold` renames them to `.gitignore`/`.graphifyignore`, and maps the template's `app/` to the profile's `app_dir`.

## embsk.py internal layout (top to bottom)

| Section | Key symbols |
|---|---|
| constants | `LEVELS`, `OPTIONS` (schema), `DEFAULTS`, `RUNNERS`, `TOOLS`, `CC`, `HAL`, `ARCH_MODULES`, `FEATURE_MODULES`, `LOG_MODULES`, `SDK_TOOLCHAIN`, `FEATURE_REFS` |
| profile | `root()`, `load()`, `save()`, `normalize()`, `visible()`, `coerce()` |
| Zephyr tree | `west_ws()`, `zephyr_base()`, `_runners()`, `_board_entries()`, `board_index()` (cached in `_INDEX`), `soc_match()`, `search()`, `find_board()` |
| validation | `TOOL_FALLBACK`, `which_any()`, `openocd_target_dir()`, `openocd_target()`, `doctor()` |
| west workspace | `MANIFEST_TEMPLATE`, `manifest_projects()`, `soc_vendor()`, `required_modules()`, `manifest_file()`, `read_allowlist()`, `write_manifest()`, `west_env()`, `sh()`, `west_python()`, `ensure_python()`, `sdk_from_path()`, `find_sdk()`, `sdk_hint()`, `setup()` |
| commands/render | `jlink_device()`, `commands()`, `refs_for()`, `block()`, `render()` |
| UI | `menu()` (curses: rows, cycle, readkey, prompt, pick_board, main loop; offers `setup` after save) |
| CLI | `main(argv)` dispatch |

## Design constraints (keep them)

1. **One menu implementation.** The curses UI in `embsk.py` serves Pi (the TUI is suspended), tmux and the shell. Claude Code uses its native `AskUserQuestion` but writes through `embsk set`, which applies the same validation.
2. **One flash regex.** `hooks/flash-guard.sh` is called by Claude/Codex hooks *and* by the Pi extension (bash from Pi's `getShellConfig()`: Git Bash on Windows).
3. **Self-contained skill dir.** Installers link `skills/embedded-sys` into agent skill folders (symlink; junction on Windows), so nothing in it may depend on files outside it. Commands use the `embsk` CLI on PATH (fallback: `python3 <skill>/scripts/embsk.py`, Windows `py -3 …`).
4. **Portable project files.** `profile.json` and `AGENTS.md` contain no absolute paths; projects can be committed and shared.
5. **Stdlib only.** No dependency in `embsk.py` beyond Python 3.9+; PyYAML (always present in a Zephyr venv) is used opportunistically for `board.yml`.
6. **No bundled toolchains.** The Zephyr SDK is installed by the user and found through PATH (`sdk_from_path()`); embsk passes it to CMake as `ZEPHYR_SDK_INSTALL_DIR` and never downloads or installs it. Neither does `install.py` (it only reports). See [05](05-zephyr-workspace.md#zephyr-sdk-your-prerequisite-found-on-path).
7. **Cross-platform.** `embsk.py` and `install.py` run on Linux, macOS and Windows (stdlib only; `.venv\Scripts`, `.exe` names, UTF-8 mode, Git Bash lookup). Hooks are pure bash (no jq) because every supported agent runs hooks in bash, Git Bash on Windows.

## What comes from where

| Provided by | What | Where it lives |
|---|---|---|
| the skill install (`install.py`) | SKILL.md, references, agents, templates, `embsk`, hooks, Pi/Claude/Codex/tmux adapters | links/launchers pointing into this repo |
| **you, once per machine (on PATH)** | **Zephyr SDK**, CMake, Ninja, dtc, git, Python 3.9+, probe tools (STM32CubeProgrammer, J-Link, OpenOCD, …), Windows: Git for Windows (Git Bash), optional graphify | your system |
| `embsk setup`, per project | Zephyr + only the board's west modules; west + Zephyr Python packages in `.venv` only if missing | `deps/`, `.venv/` (git-ignored) |
