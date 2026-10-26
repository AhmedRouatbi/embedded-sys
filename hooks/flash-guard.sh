#!/usr/bin/env bash
# embsk flash guard (PreToolUse) for Claude Code / Codex / Pi. Adapted from LibreEmbed libre-embed-hooks (MIT).
# Asks before: flashing/erasing/locking a target, option-byte/fuse/RDP changes, secret files.
# Input: hook JSON on stdin. Output: permissionDecision JSON, or nothing (allow).
# Pure bash on purpose (no jq/python): it runs wherever the hook runs, incl. Git Bash on Windows.
#   EMBSK_FLASH_GUARD=deny  -> deny instead of ask (tools that don't support "ask")
#   EMBSK_FLASH_OK=1        -> allow (dedicated HIL runner / CI only)
set -uo pipefail
[[ "${EMBSK_FLASH_OK:-0}" == "1" ]] && exit 0
INPUT="$(cat)"

field() {  # raw (still JSON-escaped) value of the first "key": "string" whose key matches $1
  local re="\"($1)\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\""
  [[ "$INPUT" =~ $re ]] && printf '%s' "${BASH_REMATCH[2]}"
}
unjson() {  # minimal JSON unescape; \\ first via a placeholder so C:\\nrf stays C:\nrf
  local s="${1//\\\\/$'\x01'}"
  s="${s//\\\"/\"}"; s="${s//\\n/$'\n'}"; s="${s//\\t/$'\t'}"; s="${s//\\\//\/}"
  printf '%s' "${s//$'\x01'/\\}"
}
decide() {
  local mode="ask" r="${1//\\/\\\\}"; [[ "${EMBSK_FLASH_GUARD:-ask}" == "deny" ]] && mode="deny"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$mode" "${r//\"/\\\"}"
  exit 0
}

shopt -s nocasematch
TOOL="$(field tool_name)"
case "$TOOL" in
  read|write|edit|multiedit|notebookedit)
    FILE="$(unjson "$(field 'file_path|notebook_path|path')")"
    base="${FILE##*[/\\]}"
    if [[ -n "$base" && ! "$base" =~ ^\.env\.(example|sample|template)$ ]] && [[ "$base" =~ ^\.env($|\.) || "$base" =~ \.(pem|key|p12|pfx)$ || "$FILE" =~ (credentials|secret) ]]; then
      decide "embsk: $TOOL touches a file that may hold secrets or signing keys ($base). Confirm first."
    fi
    exit 0 ;;
esac

CMD="$(field 'command|cmd')"
if [[ -z "$CMD" ]]; then  # Codex array form: "command": ["bash", "-lc", "west flash"]
  re_arr='"(command|cmd)"[[:space:]]*:[[:space:]]*\[(.*)\]'
  [[ "$INPUT" =~ $re_arr ]] && CMD="${BASH_REMATCH[2]//\"/ }" && CMD="${CMD//,/ }"
fi
CMD="$(unjson "$CMD")"
[[ -n "$CMD" ]] || exit 0

s='[^;&|]*'                       # stay within one command of a pipeline/list
x='(\.exe)?'                      # Windows binaries
re="(^|[;&|[:space:]/\\\"'(])("   # start of a command, or after a path separator / quote
re+="west${x}[[:space:]]+(flash|debug)"
re+="|openocd${s}(program|flash[[:space:]]+(write|erase|protect)|mass_erase|[[:space:]](un)?lock)"
re+="|st-flash${s}[[:space:]](write|erase)"
re+="|STM32_Programmer_CLI${s}[[:space:]](-w|-e|-d|-ob|--write|--erase|--download|--optionbytes)([[:space:]]|$)"
re+="|pyocd${x}[[:space:]]+(flash|load|erase|commander)"
re+="|probe-rs${x}[[:space:]]+(download|run|erase|flash)"
re+="|nrfjprog${s}--(program|eraseall|erasepage|recover|memwr)"
re+="|nrfutil${s}device[[:space:]]+(program|erase|recover|x-protection-set)"
re+="|LinkServer${x}[[:space:]]+flash"
re+="|JLink(Exe|\.exe)([[:space:]\"']|$)|JLink[[:space:]]+-"
re+="|esptool(\.py)?${s}[[:space:]](write[-_]flash|erase[-_]flash|erase[-_]region|burn[-_])"
re+="|espefuse(\.py)?"
re+="|idf\.py${s}[[:space:]](flash|app-flash|erase[-_]flash)([[:space:]]|$)"
re+="|dfu-util${s}[[:space:]]-D"
re+="|avrdude${s}-U[[:space:]]*[a-z]+:w:"
re+="|picotool${x}[[:space:]]+load"
re+="|(pio|platformio)${x}[[:space:]]+run${s}(-t|--target)[[:space:]]*(upload|erase)"
re+="|[[:alnum:]_-]*gdb${s}-ex[[:space:]]+['\"]?load"
re+="|make${s}[[:space:]]flash([[:space:]]|$)"
re+=")"
if [[ "$CMD" =~ $re ]]; then
  decide "embsk: this flashes, erases or locks a connected target. Confirm the board, the image and that the build + host tests passed. Never approve erase/option-byte/RDP/fuse changes casually."
fi
exit 0
