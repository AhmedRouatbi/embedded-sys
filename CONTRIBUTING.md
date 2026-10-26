# Contributing

Issues and pull requests are welcome: wrong Zephyr facts, broken commands, board/probe support, Windows or macOS reports, new references.

## Before you open a PR

1. Read [docs/08-maintaining.md](docs/08-maintaining.md). It has the conventions and the "how to add a probe / option / reference / board rule" recipes.
2. Run the self-test before and after your change:
   ```bash
   bash docs/quick-check.sh          # offline, ~30 s (Windows: from Git Bash)
   bash docs/quick-check.sh --full   # + a real `embsk setup` + build + host tests + SIL (needs the Zephyr SDK on PATH)
   ```
3. Update the `docs/` page that describes what you changed, and `README.md` if users see it. Add a line to [CHANGELOG.md](CHANGELOG.md).

## Rules that keep the skill portable

- `skills/embedded-sys/scripts/embsk.py` and `install.py` stay **stdlib-only** and run on Linux, macOS and Windows.
- `hooks/*.sh` stay **pure bash**, with no jq or Python, because they run in Git Bash on Windows.
- The skill folder is self-contained: it gets linked into agents, so nothing in it may reference files outside it.
- No absolute paths in templates, profiles or the generated AGENTS.md.
- Every Zephyr command or Kconfig symbol you write must exist in a Zephyr 4.x tree: `rg` it first.
- Reference files follow the style contract in `docs/08-maintaining.md`: 80–150 lines, they end with `## Anti-patterns` and `## Sources`, and they contain no placeholders.
- Never install toolchains from the skill. The Zephyr SDK is the user's, found via PATH.

## Commit messages

`<area>: <what>`. For example: `embsk: add probe-rs RTT log row`, `references/zephyr: fix sysbuild flag`.
