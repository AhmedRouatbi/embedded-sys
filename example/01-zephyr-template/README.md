# Zephyr project template

Minimal Zephyr app (blinky + log) with a managed west workspace. You pick the board; `embsk setup` downloads Zephyr plus only that board's modules and builds.

```bash
embsk setup            # or press Alt+A, choose "Zephyr board", save, answer Y
west flash -d build    # flash (agents ask first)
```

- Change board: `embsk set board=<board>` (or Alt+A), then `embsk setup` again. `app/west.yml`'s allowlist follows the board.
- Without embsk: `west init -l app && west update --narrow -o=--depth=1 && west build -b nucleo_f767zi -d build app`.
- Generated (git-ignored): `.west/`, `deps/` (Zephyr + modules), `build/`, `.venv/`.
