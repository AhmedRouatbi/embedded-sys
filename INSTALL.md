# Install embedded-sys: any agent, Linux, macOS or Windows

For humans and AI agents. **Agent asked to install this skill:** do steps 1–4 in order. Each step has a check, so don't skip them. The installer is non-interactive and safe to re-run.

## 1. Requirements

| Need | Check | Notes |
|---|---|---|
| Python 3.9+ | Linux/macOS `python3 --version` · Windows `py -3 --version` or `python --version` | the installer and `embsk` are stdlib-only Python |
| git | `git --version` | Claude Code plugin marketplace; your projects |
| **Windows only: Git for Windows (Git Bash)** | `"%ProgramFiles%\Git\bin\bash.exe" --version` | Claude Code and Pi run this skill's hooks (flash guard) in Git Bash. Without it the installer still installs the skill, but not the Claude plugin (Claude Code would block tool calls on a hook it can't run) |

Not needed to *install*, needed to *build firmware*, and never installed by this skill: the **Zephyr SDK on PATH** ([docs/05](docs/05-zephyr-workspace.md#zephyr-sdk-your-prerequisite-found-on-path)), CMake, Ninja, probe tools. `west` is added to a project `.venv` by `embsk setup` when missing.

## 2. Get the folder, somewhere permanent

```bash
git clone https://github.com/YOUR-USER/embedded-sys.git ~/embedded-sys     # Windows: %USERPROFILE%\embedded-sys
cd ~/embedded-sys
```

The installer creates links and small launchers that point **into this folder**. Put it where it can stay, e.g. `~/embeddedSysSk` or `%USERPROFILE%\embeddedSysSk`, not a temp or download folder. After moving it later, just re-run the installer from the new place.

## 3. Run the installer

| Shell | Command (run inside this folder) |
|---|---|
| Linux / macOS | `python3 install.py` (or `./install.sh`) |
| Windows PowerShell or cmd | `py -3 install.py` (or `python install.py`) |
| Windows Git Bash | `py -3 install.py` |

What it does, for each agent it finds:

| Target | Installed | Linux/macOS | Windows |
|---|---|---|---|
| `embsk` command | `~/.local/bin/embsk` | symlink | `embsk.cmd` + a Git Bash launcher; `~/.local/bin` added to the user PATH |
| The skill, for every Agent Skills tool | `~/.agents/skills/embedded-sys` | symlink | junction (no admin needed) |
| Claude Code (`claude` on PATH) | plugin `embedded-sys@embsk`: skill, `/embsk`, 5 agents, hooks; Alt+A keybinding | ✓ | ✓ with Git Bash; skill only (`~/.claude/skills`) without |
| Pi (`pi` on PATH) | package: Alt+A, `/embsk`, status, flash-guard gate; workflow `embedded` | ✓ | ✓ |
| Codex (`codex` or `~/.codex`) | `/prompts:embsk` (+ plugin with the hooks if your Codex has plugins) | ✓ | ✓ |
| tmux | Alt+A popup for any terminal agent | if tmux is installed | — |
| `embsk menu` on Windows | `windows-curses` via pip (best effort) | — | ✓ |

`~/.agents/skills` is read by **Codex, Cursor, Gemini CLI, GitHub Copilot, OpenCode and Pi** (and Cline, Warp, Zed, Kimi). That is why the skill is linked only there: one copy, no duplicates.

Never touched: toolchains, your projects, other plugins. Superseded toolkits are reported with the command to disable them; nothing is disabled for you.

## 4. Verify

```bash
python3 install.py --check        # Windows: py -3 install.py --check
```

Exit code 0 means the skill is usable. It checks:
- the launcher and the skill link exist;
- the Claude plugin and Pi package, when those CLIs exist;
- your prerequisites (Zephyr SDK on PATH, Git Bash on Windows);
- **smoke tests**: `embsk` runs, and the flash guard asks before `west flash`.

Then:
1. **Open a new terminal**, so PATH changes apply, and run `embsk schema`. It should print JSON.
2. **Restart your agent.** Claude Code: `/embsk` exists. Pi: `/skill:embedded-sys`. Codex, Cursor, Gemini, Copilot, OpenCode: the skill `embedded-sys` is listed in their skills view.
3. Use it: in a firmware project press **Alt+A** (or `/embsk`, or `embsk menu`), then run `embsk doctor`.

## 5. An agent that wasn't detected

If your agent reads skills from its own folder, link the skill there too (repeatable). The installer remembers each folder for `--uninstall`:

```bash
python3 install.py --agent-dir ~/.codeium/windsurf/skills      # Windows: py -3 install.py --agent-dir %USERPROFILE%\.codeium\windsurf\skills
```

| Agent | Skills folder (global) |
|---|---|
| Windsurf | `~/.codeium/windsurf/skills` |
| Amp | `~/.config/agents/skills` |
| Roo Code | `~/.roo/skills` |
| Kiro | `~/.kiro/skills` |
| Goose | `~/.config/goose/skills` |
| Qwen Code | `~/.qwen/skills` |
| Continue | `~/.continue/skills` |
| Augment | `~/.augment/skills` |
| Junie | `~/.junie/skills` |
| Trae | `~/.trae/skills` |
| Factory Droid | `~/.factory/skills` |
| Crush | `~/.config/crush/skills` |
| OpenHands | `~/.openhands/skills` |

The folder list comes from the Agent Skills CLI, which knows ~80 agents. It can install the skill for you instead:

```bash
npx skills add ./skills -g -a <agent> -y
```

That route installs a copy and skips the `embsk` command, so run `install.py` as well.

An agent with no skill support at all: tell it to read `skills/embedded-sys/SKILL.md` at the start of a task. It reads the project's `AGENTS.md` anyway, and `embsk` writes the commands and rules there.

## 6. Update, move, uninstall

| Task | How |
|---|---|
| Update | Replace or pull this folder; links follow it. If the installer reported "copy" (a Windows drive without junctions), re-run it |
| Move | Move the folder, then re-run `install.py` from the new place. Dangling links and launchers are replaced |
| Uninstall | `python3 install.py --uninstall` (Windows: `py -3 install.py --uninstall`). Removes only what the installer made. On Windows, `~/.local/bin` stays on PATH because other tools use it |

## 7. Install problems

| Symptom | Fix |
|---|---|
| `embsk: command not found` right after installing | Open a new terminal. Linux/macOS: add `export PATH="$HOME/.local/bin:$PATH"` to your shell rc |
| Windows: "Claude plugin not installed, no Git Bash" | Install Git for Windows (or set `CLAUDE_CODE_GIT_BASH_PATH`), then re-run |
| `plugin install failed` | Run the two printed `claude plugin ...` commands by hand; `claude plugin validate .` must pass |
| `… exists and wasn't made by this installer` | A real folder or file is in the way. The installer never deletes it. Remove or rename it yourself, then re-run |
| Pi warns about a duplicate `embedded-sys` skill | An older install linked it elsewhere. Run `install.py --uninstall` and then `install.py`. Then check `~/.pi/agent/skills` for a stale copy |
| `embsk menu` on Windows: "needs curses" | `py -3 -m pip install --user windows-curses`, or use `embsk set key=value` / `/embsk` |
| Anything else | [docs/10-troubleshooting.md](docs/10-troubleshooting.md) |
