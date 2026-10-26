# 06 — Integrations (Pi, Claude Code, Codex, tmux) and hooks

## Installer (`install.py`; `install.sh` wraps it on Linux/macOS)

One stdlib Python file for Linux, macOS and Windows (`python3 install.py` / `py -3 install.py`). Step-by-step guide with checks: [INSTALL.md](../INSTALL.md).

What it installs is the skill and its adapters only (symlinks, plugin, keybinding). **No toolchain**: the Zephyr SDK, CMake, Ninja, dtc and probe tools are prerequisites you install yourself (only west + Zephyr's Python packages are added to a project `.venv` by `embsk setup`, and only when missing). The Zephyr SDK must be on PATH (see [05](05-zephyr-workspace.md#zephyr-sdk-your-prerequisite-found-on-path)).

| Mode | Does |
|---|---|
| `install.py` | for every tool found: `embsk` launcher in `~/.local/bin` (Linux/macOS symlink; Windows `embsk.cmd` + an sh launcher for Git Bash, `~/.local/bin` appended to the user PATH in the registry, `windows-curses` via pip) · `~/.agents/skills/embedded-sys` (symlink; Windows junction, copy as last resort) · Claude: `claude plugin marketplace add <repo>` + `claude plugin install embedded-sys@embsk` + merge `meta+a → command:embsk` into `~/.claude/keybindings.json` (an existing different `meta+a` binding is kept); Windows without Git Bash → skill only in `~/.claude/skills` · Pi: `pi install <repo>` + `~/.pi/workflows/embedded.yaml` · Codex: `~/.codex/prompts/embsk.md` + optional plugin (removes an old `~/.codex/skills` link) · tmux (Linux/macOS): `~/.config/embsk/embsk.tmux.conf` + `source-file` line · reports prerequisites (Zephyr SDK on PATH, Git Bash on Windows; never installs them) · smoke test · overlap report |
| `install.py --agent-dir DIR` | also links the skill into DIR (agents that don't read `~/.agents/skills`; folders in INSTALL.md §5) |
| `install.py --check` | read-only status + smoke test (`embsk schema` runs, the flash guard asks before `west flash`); exit 1 if the launcher or the skill link is missing or a smoke test fails |
| `install.py --uninstall` | removes everything it created (paths recorded in `~/.config/embsk/install-state.json`, plus the defaults), the Pi package, the Claude plugin, marketplace and keybinding, the Codex plugin and the tmux line. Never deletes a file or folder it didn't create |

**One copy of the skill per agent.** Codex, Cursor, Gemini CLI, GitHub Copilot, OpenCode and Pi all read `~/.agents/skills`, so the skill is linked only there. For the same reason, the Pi package and the Codex plugin no longer carry the skill: Pi would warn about a name collision, and Codex would list it twice. Claude Code reads only its own folders, so it gets the skill through the plugin.

**Links point into the repo folder**: keep it in place; after moving it, re-run `install.py` (dangling links and old launchers are replaced).

Overlap report: it never disables anything; it prints the commands. agent-skills and LibreEmbed are superseded (disable them). ponytail can stay installed (same rules, plus its level switching and statusline).

## Pi

- **Package**: `package.json` → `pi.extensions: ["./pi-extension/index.ts"]` only; Pi loads the skill from `~/.agents/skills`. `pi install <local path>` loads in place (no copy).
- **Extension** (`pi-extension/index.ts`):
  - `pi.registerShortcut("alt+a")` and `/embsk [doctor|commands]` open the menu. It suspends the TUI (`tui.stop()`), runs `<python> embsk.py menu --wait` with inherited stdio so setup output stays visible until Enter, then restarts the TUI. `<python>` is the first of `python3`, `python` (Windows: `python`, `py`, `python3`) that is ≥ 3.9.
  - After a save it notifies the doctor result, sets the status (`⚙ zephyr nucleo_f767zi · stlink`), and queues a hidden `embsk-profile` message (`deliverAs: "nextTurn"`) so the agent re-reads AGENTS.md.
  - `tool_call` gate: for `bash` (command) and `read/write/edit` (path) it runs `hooks/flash-guard.sh`. On "ask" it shows `ctx.ui.select(["Allow once","Block"])`; with no UI it blocks. A guard failure blocks (fail closed).
  - Verified: strict `tsc`; loads in `pi --mode rpc`, registers `/embsk`, sets the status.
- **Workflow**: `pi-workflows/embedded.yaml` → `workflow_run embedded "<task>"`: plan (read-only) → execute (TDD, no flashing; runs `embsk setup --no-build` if the workspace is missing) → verify (structured PASS/FAIL, `embsk verify`, on-target only if the profile has `hil=board` and the task says flashing is approved) ⇄ review (structured PASS/FAIL, review.md format). Validated with the workflow extension's own `discoverWorkflows`.
- **Subagents**: `spawn_agent`/`wait_agent`/`followup_task`, reviewers with `fork_turns: "none"`. On the original host they fail to start: `bwrap: setting up uid map: Permission denied` (fix in [10](10-troubleshooting.md)).

## Claude Code

- **Plugin** (`.claude-plugin/plugin.json`, marketplace `embsk`): auto-discovers `skills/`, `commands/` and `hooks/hooks.json`; agents are listed explicitly (`skills/embedded-sys/agents/fw-*.md`). `claude plugin validate .` passes (only a missing-icon warning).
- **Command** `/embsk` (`commands/embsk.md`):
  - Arguments: `doctor | commands | key=value…`; empty arguments open the menu.
  - Menu = `AskUserQuestion` rounds: platform/probe/log/safety, then target (board resolved through `embsk boards`, qualifiers re-asked), then feature checkboxes, then workflow.
  - Applied with one `embsk set`, then `embsk setup` (Zephyr). Exit 3 = Zephyr SDK not on PATH → show the user the printed fix line, wait, re-run. The agent never installs the SDK.
- **Alt+A**: `~/.claude/keybindings.json` `{"bindings":[{"context":"Chat","bindings":{"meta+a":"command:embsk"}}]}`. If it doesn't fire for the plugin command, use `command:embedded-sys:embsk`. The terminal must send Alt as Meta.
- **Project context**: Claude reads `CLAUDE.md`; embsk creates it as `@AGENTS.md`.
- **Agents**: the 5 role cards (frontmatter `name/description/tools/model`) run via the Task tool and start with isolated context.

## Codex and other agents

- **Skill**: `~/.agents/skills/embedded-sys` (Codex's user skills folder; also read by Cursor, Gemini CLI, Copilot, OpenCode, Pi). Agents with their own folder: `install.py --agent-dir`. All of them read `AGENTS.md` from the project.
- **Prompt**: `~/.codex/prompts/embsk.md` → `/prompts:embsk`. It uses `request_user_input` if present, otherwise asks for tmux Alt+A / `embsk menu` / a chat checklist.
- **Plugin**: `.codex-plugin/plugin.json` (`hooks/hooks.json` only; Codex uses the Claude hook format). After install, trust the hooks via `/hooks` in Codex. **Untested** (Codex not installed on the original host). If Codex ignores `permissionDecision: "ask"`, set `EMBSK_FLASH_GUARD=deny`.
- **No subagent tool**: roles run sequentially; for fresh-context review use `codex exec --sandbox read-only - < prompt.md`.

## tmux (any terminal agent)

`bind -n M-a display-popup -E -w 90% -h 90% -d "#{pane_current_path}" "embsk menu; …; read"` (tmux ≥ 3.2). It captures Alt+A in all panes; Pi and Claude get the same menu through the popup.

## Hooks

### `hooks/flash-guard.sh` (PreToolUse)

Input: hook JSON on stdin. It reads `tool_input.command`, `tool_input.cmd` or a Codex array command, and `tool_input.file_path|path|notebook_path`.

Output: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask"|"deny","permissionDecisionReason":…}}`, or nothing (allow). **Pure bash, no jq or Python**, so it runs wherever the hook runs: Linux, macOS, Git Bash on Windows. It extracts `tool_name`, the command (string or Codex array) and the file path with bash regexes and unescapes JSON. File tools (Read/Write/Edit) get only the secret-file check, so a README mentioning `west flash` is not flagged.

Windows: Claude Code runs shell-form hooks in Git Bash; the matcher includes the **`PowerShell` tool** (Claude routes shell commands through it when enabled), and Pi's gate covers its `powershell` tool. Paths with `\`, `.exe` names (`STM32_Programmer_CLI.exe`, `JLink.exe`, `pyocd.exe`) and PowerShell's `& "C:\…\tool.exe"` form are matched.

Asks for:
- `west flash|debug`;
- OpenOCD `program`/`flash write|erase|protect`/`mass_erase`/`lock|unlock`;
- `st-flash write|erase`;
- `STM32_Programmer_CLI -w|-e|-d|-ob` (and long forms);
- `pyocd flash|load|erase|commander`;
- `probe-rs download|run|erase|flash`;
- `nrfjprog --program|eraseall|erasepage|recover|memwr`;
- `nrfutil device program|erase|recover|x-protection-set`;
- `LinkServer flash`;
- J-Link Commander: `JLinkExe` / `JLink.exe` / `JLink -…` (any use; `JLinkGDBServer`, `JLinkRTTLogger` are allowed);
- `esptool write_flash|erase_flash|erase_region|burn_*`;
- `espefuse`;
- `idf.py flash|app-flash|erase-flash`;
- `dfu-util -D`;
- `avrdude -U …:w:`;
- `picotool load`;
- `pio run -t upload|erase`;
- any `*gdb … -ex load`;
- `make flash`;
- reads/writes of `.env*` (except `.example/.sample/.template`), `*.pem|key|p12|pfx`, paths containing `credentials|secret`.

| Env var | Effect |
|---|---|
| `EMBSK_FLASH_GUARD=deny` | deny instead of ask (tools without "ask" support) |
| `EMBSK_FLASH_OK=1` | allow everything (dedicated HIL runner/CI only) |

Verified cases (`docs/quick-check.sh`): 18 command cases (Bash + PowerShell, Linux and Windows paths), a multi-line command, Codex array form, secret files (POSIX and Windows paths), `Write` content not matched, JSON-escaped reason, deny mode. Each tool name may be preceded by a path or quote (`/usr/bin/west flash`).

### `hooks/session-start.sh`

- With a profile: prints one line, `[embsk] profile: <platform> <board|mcu> · probe · logs · safety · ponytail…`.
- Firmware-looking repo without a profile (`prj.conf`, `west.yml`, `platformio.ini`, `*.ld`, `*.ioc`): suggests Alt+A.
- Matchers: `startup|resume|clear|compact`.
