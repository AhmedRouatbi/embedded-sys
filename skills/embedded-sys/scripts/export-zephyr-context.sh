#!/usr/bin/env bash
# Export the RESOLVED Zephyr build context into small, greppable files under docs/generated/.
#
# WHY: graphify's AST mode (`graphify update .`) indexes .c/.h but not .dts/.dtsi/.overlay,
#      Kconfig, prj.conf, .ld or .S. The devicetree - what agents hallucinate most about -
#      is therefore invisible to the code graph. The exported .h files are indexed; the
#      .txt/.conf files are for `rg` and for graphify's optional LLM pass.
#
#      The *resolved* artifacts are also strictly better than the source fragments:
#      they show what actually got built, which is what diagnoses
#      `__device_dts_ord_N undeclared` and "enabling a child never enables its parent".
#
# Usage:   ./export-zephyr-context.sh [build-dir] [--update]
#          embsk export build --update     # also runs `graphify update .`
#
# Run from your application directory, after a successful `west build`.

set -euo pipefail

BUILD="${1:-build}"
[[ "${1:-}" == "--update" ]] && BUILD="build"
OUT="docs/generated"

say()  { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }

[[ -d "$BUILD/zephyr" ]] || { warn "no $BUILD/zephyr - run 'west build' first"; exit 1; }

mkdir -p "$OUT"
say "Exporting resolved build context -> $OUT/"

copy() {  # src  dest  label
  if [[ -f "$1" ]]; then
    cp "$1" "$2"
    printf '  %-34s %s\n' "$(basename "$2")" "$(wc -l < "$2") lines"
  else
    warn "missing: $1  ($3)"
  fi
}

# --- resolved devicetree: the big one -------------------------------------------
copy "$BUILD/zephyr/zephyr.dts"                                   "$OUT/zephyr-dts.txt"              "resolved devicetree"
copy "$BUILD/zephyr/include/generated/zephyr/devicetree_generated.h" "$OUT/devicetree_generated.h"   "DT macros"

# --- resolved Kconfig ----------------------------------------------------------
copy "$BUILD/zephyr/.config"                                      "$OUT/kconfig-resolved.conf"       "resolved Kconfig"
copy "$BUILD/zephyr/include/generated/zephyr/autoconf.h"          "$OUT/autoconf.h"                  "Kconfig as C macros"

# --- memory / layout evidence --------------------------------------------------
copy "$BUILD/zephyr/zephyr.map"                                   "$OUT/zephyr-map.txt"              "link map"
copy "$BUILD/zephyr/linker.cmd"                                   "$OUT/linker-resolved.txt"         "preprocessed linker script"

# --- size report so the agent can see RAM/ROM cost of its own changes ----------
# Use the toolchain this build used: `size` next to CMAKE_NM in the CMake cache.
SIZE="$(sed -n 's/^CMAKE_NM:FILEPATH=\(.*\)nm\(\.exe\)\{0,1\}$/\1size\2/p' "$BUILD/CMakeCache.txt" 2>/dev/null)"   # Windows: ...nm.exe
[[ -x "$SIZE" ]] || SIZE="$(command -v arm-none-eabi-size || true)"
if [[ -n "$SIZE" && -f "$BUILD/zephyr/zephyr.elf" ]]; then
  "$SIZE" -A "$BUILD/zephyr/zephyr.elf" > "$OUT/size-report.txt" 2>/dev/null \
    && printf '  %-34s %s\n' "size-report.txt" "$(wc -l < "$OUT/size-report.txt") lines"
fi

# --- devicetree node list: a cheap, greppable index ---------------------------
if [[ -f "$OUT/zephyr-dts.txt" ]]; then
  grep -nE '^\s*[a-zA-Z0-9_,@&-]+\s*:\s*[a-zA-Z0-9_,@-]+\s*\{|status\s*=' "$OUT/zephyr-dts.txt" \
    > "$OUT/dt-nodes-and-status.txt" 2>/dev/null || true
  printf '  %-34s %s\n' "dt-nodes-and-status.txt" "$(wc -l < "$OUT/dt-nodes-and-status.txt" 2>/dev/null || echo 0) lines"
fi

# --- runner config: why 'west flash' picked the wrong openocd ------------------
copy "$BUILD/zephyr/runners.yaml"                                 "$OUT/runners.conf"                "flash/debug runner config"

cat > "$OUT/README.md" <<'EOF'
# Generated build context — DO NOT EDIT

Produced by `embsk export` after a successful `west build`.

These are the **resolved** artifacts (what was actually built), as greppable text. graphify's
AST mode indexes the `.h` files; use `rg` on the `.txt`/`.conf` files. Source `.dts`, `.dtsi`,
`.overlay`, `Kconfig`, `.ld` and `.S` files are not in the code graph.

| File | Source | Use it to answer |
|---|---|---|
| `zephyr-dts.txt` | `build/zephyr/zephyr.dts` | which nodes exist, their labels, their real `status` |
| `dt-nodes-and-status.txt` | grep of the above | fast "is this node enabled?" lookup |
| `devicetree_generated.h` | generated | why `DT_*` / `DEVICE_DT_GET` macros resolve or don't |
| `kconfig-resolved.conf` | `build/zephyr/.config` | which drivers/subsystems were actually built |
| `autoconf.h` | generated | Kconfig as seen by the C preprocessor |
| `zephyr-map.txt` | `zephyr.map` | where RAM/ROM went, symbol placement |
| `linker-resolved.txt` | `linker.cmd` | final memory regions and section placement |
| `size-report.txt` | `arm-none-eabi-size -A` | RAM/ROM cost of a change |
| `runners.conf` | `runners.yaml` | which openocd/J-Link binary `west flash` will call |

**Debugging `__device_dts_ord_N undeclared`:** grep `dt-nodes-and-status.txt` for the node
*and its parent bus*. Enabling a child never enables its parent. Then confirm the driver's
`CONFIG_*` is `=y` in `kconfig-resolved.conf`.

Regenerate and re-index:
```bash
embsk export && graphify update .
```
EOF
printf '  %-34s\n' "README.md"

# --- keep logs greppable: graphify reads .txt, not .log ------------------------
if compgen -G "artifacts/*.log" > /dev/null; then
  say "Renaming artifacts/*.log -> *.txt (graphify ignores .log)"
  for f in artifacts/*.log; do mv -- "$f" "${f%.log}.txt"; echo "  $(basename "${f%.log}.txt")"; done
fi

# --- optional re-index ---------------------------------------------------------
if [[ "${1:-}" == "--update" || "${2:-}" == "--update" ]]; then
  if command -v graphify >/dev/null; then
    say "graphify update ."
    graphify update .
  else
    warn "graphify not on PATH"
  fi
else
  say "Done. Now run:  graphify update ."
fi
