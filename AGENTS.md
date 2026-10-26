# embeddedSysSk: guide for agents

This folder **is** the `embedded-sys` agent skill (`skills/embedded-sys/`), plus its installer and the adapters for Claude Code, Pi, Codex and tmux.

- **Asked to install it?** Follow [INSTALL.md](INSTALL.md):
  - Linux/macOS: `python3 install.py`; Windows: `py -3 install.py`;
  - then `install.py --check` must exit 0.
  - Report what `--check` printed, including any `!!` lines (for example: Zephyr SDK not on PATH).
- **Asked to use it on a firmware project?** Install it first. Then work in the project folder: the skill's `SKILL.md` and the project's `AGENTS.md` `embsk` block drive you.
- **Asked to change the skill?**
  - Read [docs/README.md](docs/README.md).
  - Run `bash docs/quick-check.sh` before and after the change (Windows: from Git Bash).
  - Keep `embsk.py` and `install.py` stdlib-only and cross-platform (Linux, macOS, Windows).
  - Keep `hooks/*.sh` pure bash (no jq).

Don't run `embsk setup` or `west` in this folder. The examples in `example/` are meant to be copied elsewhere first.
