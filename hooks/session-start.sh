#!/usr/bin/env bash
# embsk SessionStart: one context line. Profile present -> summary; firmware-looking repo -> suggest Alt+A.
# Pure bash (no jq): runs on Linux, macOS and Git Bash on Windows.
set -uo pipefail
J=""; [[ -t 0 ]] || J="$(cat)"
DIR="$PWD"
re='"cwd"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
if [[ "$J" =~ $re ]]; then d="${BASH_REMATCH[1]//\\\\/\\}"; [[ -d "$d" ]] && DIR="$d"; fi
P="$DIR/.embsk/profile.json"
val() { local r="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""; [[ "$PJ" =~ $r ]] && printf '%s' "${BASH_REMATCH[1]}"; }
if [[ -f "$P" ]]; then
  PJ="$(cat "$P")"
  if [[ "$(val platform)" == zephyr ]]; then tgt="$(val board)"; else tgt="$(val mcu)"; fi
  echo "[embsk] profile: $(val platform) $tgt · probe $(val debugger) · logs $(val log) · safety $(val safety) $(val safety_level) · ponytail $(val ponytail). Use the embedded-sys skill; commands are in the embsk block of AGENTS.md; run \`embsk doctor\` before hardware work."
elif [[ -f "$DIR/prj.conf" || -f "$DIR/west.yml" || -f "$DIR/platformio.ini" ]] || ls "$DIR"/*.ld "$DIR"/*.ioc >/dev/null 2>&1; then
  echo "[embsk] Firmware project without an embsk profile. Ask the user to press Alt+A (or run /embsk) to choose platform, board/MCU, probe and safety level before hardware-specific work."
fi
exit 0
