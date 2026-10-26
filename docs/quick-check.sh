#!/usr/bin/env bash
# Self-test for the embedded-sys repo.
#   bash docs/quick-check.sh          offline checks (~30 s; Zephyr checks need a reference tree:
#                                     $ZEPHYR_BASE or ~/zephyrproject/zephyr, else they are skipped)
#   bash docs/quick-check.sh --full   + real `embsk setup` (download ~160 MB) and `embsk verify` of example 02
#                                     (needs your Zephyr SDK on PATH; skipped otherwise)
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1   # keep the skill dir (linked into agents) free of __pycache__
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SK="$REPO/skills/embedded-sys"
EMBSK=(python3 "$SK/scripts/embsk.py")
FULL=0; [[ "${1:-}" == "--full" ]] && FULL=1
pass=0; fail=0; skip=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
ko()   { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
sk()   { printf '  \033[33mSKIP\033[0m %s\n' "$1"; skip=$((skip + 1)); }
hdr()  { printf '\033[1m== %s\033[0m\n' "$1"; }
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$n"; else ko "$n"; fi; }
refuse() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then ko "$n (should fail)"; else ok "$n"; fi; }
has()  { local n="$1" needle="$2" out; shift 2; out="$("$@" 2>&1)"; if grep -qF -- "$needle" <<<"$out"; then ok "$n"; else ko "$n (missing: $needle)"; fi; }  # exit code ignored (doctor exits 1 on ERR)
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
newproj() { rm -rf "$T/p" && mkdir -p "$T/p/.embsk" && cd "$T/p"; }

hdr "syntax"
pyok() { python3 -c "import sys; compile(open(sys.argv[1], encoding='utf-8').read(), sys.argv[1], 'exec')" "$1"; }  # in memory: no __pycache__
check "embsk.py compiles" pyok "$SK/scripts/embsk.py"
check "install.py compiles" pyok "$REPO/install.py"
for f in "$REPO/install.sh" "$REPO"/hooks/*.sh "$SK/scripts/export-zephyr-context.sh" "$REPO/docs/quick-check.sh"; do
  check "bash -n $(basename "$f")" bash -n "$f"
done
for f in "$REPO/package.json" "$REPO"/.claude-plugin/*.json "$REPO/.codex-plugin/plugin.json" "$REPO/hooks/hooks.json"; do
  check "json $(basename "$(dirname "$f")")/$(basename "$f")" python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f"
done

hdr "skill integrity"
check "SKILL.md frontmatter, references, agents" python3 - "$SK" <<'EOF'
import os, re, sys
sk = sys.argv[1]
t = open(f"{sk}/SKILL.md").read()
fm = re.match(r"---\n(.*?)\n---", t, re.S).group(1)
assert re.fullmatch(r"[a-z0-9-]{1,64}", re.search(r"^name:\s*(\S+)", fm, re.M).group(1))
desc = " ".join(l.strip() for l in re.search(r"description:\s*>\n((?:  .*\n?)+)", fm).group(1).splitlines())
assert len(desc) <= 1024, len(desc)
named = set(re.findall(r"references/([a-z-]+\.md)", t)) | {x for x in re.findall(r"`([a-z-]+\.md)`", t) if x not in ("SPEC.md", "ADR.md", "CONSTRAINTS.md")}
files = set(os.listdir(f"{sk}/references"))
assert not (named - files), f"missing: {named - files}"
assert not (files - named), f"orphaned: {files - named}"
for a in os.listdir(f"{sk}/agents"):
    assert open(f"{sk}/agents/{a}").read().startswith(f"---\nname: {a[:-3]}\n"), a
EOF

hdr "profile validation"
newproj
refuse "set rejects unknown key" "${EMBSK[@]}" set nosuchkey=1
refuse "set rejects invalid probe" "${EMBSK[@]}" set debugger=xlink
refuse "set rejects invalid feature" "${EMBSK[@]}" set features=ble,foo
refuse "set rejects SIL2 for ISO 26262" "${EMBSK[@]}" set safety_level=SIL2 safety=iso26262
check "order-independent validation (ASIL-B)" "${EMBSK[@]}" set safety_level=ASIL-B safety=iso26262
has "safety level stored" '"ASIL-B"' "${EMBSK[@]}" get safety_level
"${EMBSK[@]}" set platform=baremetal toolchain=zephyr-sdk tests=ztest safety=none >/dev/null 2>&1
has "normalize: baremetal toolchain" '"gnu-arm"' "${EMBSK[@]}" get toolchain
has "normalize: baremetal tests" '"unity"' "${EMBSK[@]}" get tests
"${EMBSK[@]}" set platform=zephyr >/dev/null 2>&1
has "platform=zephyr restores ztest" '"ztest"' "${EMBSK[@]}" get tests
check "extra_modules list" bash -c "\"\$@\" set extra_modules=hal_st,segger >/dev/null && \"\$@\" get extra_modules | grep -q hal_st" _ "${EMBSK[@]}"

hdr "zephyr (reference tree)"
ZREF="${ZEPHYR_BASE:-$HOME/zephyrproject/zephyr}"
if [[ -f "$ZREF/VERSION" ]]; then
  newproj
  has "boards finds nucleo_f767zi by MCU" "nucleo_f767zi" "${EMBSK[@]}" boards stm32f767
  "${EMBSK[@]}" set board=nucleo_f40 >/dev/null 2>&1;            refuse "doctor: non-existent board" "${EMBSK[@]}" doctor
  "${EMBSK[@]}" set board=max32690evkit >/dev/null 2>&1;         has "doctor: needs qualifiers" "needs qualifiers" "${EMBSK[@]}" doctor
  "${EMBSK[@]}" set board=nucleo_f767zi mcu=nrf52840 >/dev/null 2>&1; has "doctor: MCU vs SoC" "does not match board SoC" "${EMBSK[@]}" doctor
  "${EMBSK[@]}" set mcu= debugger=pyocd >/dev/null 2>&1;         has "doctor: unsupported probe" "is not a runner" "${EMBSK[@]}" doctor
  "${EMBSK[@]}" set debugger=stlink log=uart extra_modules= features= >/dev/null 2>&1
  has "debug falls back from stm32cubeprogrammer" "--runner openocd" "${EMBSK[@]}" commands
  while read -r board want; do
    "${EMBSK[@]}" set board="$board" >/dev/null 2>&1
    got="$("${EMBSK[@]}" modules 2>/dev/null)"
    [[ "$got" == "$want" ]] && ok "modules $board = $want" || ko "modules $board: got '$got' want '$want'"
  done <<'EOF'
nucleo_f767zi cmsis_6 hal_stm32
nrf52840dk/nrf52840 cmsis_6 hal_nordic
rpi_pico cmsis_6 hal_rpi_pico
max32690evkit/max32690/m4 cmsis_6 hal_adi
frdm_k64f cmsis_6 hal_nxp
EOF
  "${EMBSK[@]}" set board=native_sim/native/64 >/dev/null 2>&1
  [[ -z "$("${EMBSK[@]}" modules 2>/dev/null)" ]] && ok "modules native_sim = (none)" || ko "modules native_sim not empty"
  "${EMBSK[@]}" set board=nucleo_f767zi log=rtt features=filesystem,bootloader-ota >/dev/null 2>&1
  has "modules follow features/log" "cmsis_6 hal_stm32 littlefs mcuboot segger zcbor" "${EMBSK[@]}" modules
else
  sk "no Zephyr reference tree at $ZREF (set ZEPHYR_BASE)"
fi

hdr "manifest"
newproj
check "empty module list -> placeholder 'none', patch keeps content" python3 - "$SK/scripts" <<'EOF'
import sys; sys.path.insert(0, sys.argv[1]); import embsk
p = embsk.load(); embsk.write_manifest(p, [])
t = open("app/west.yml").read(); assert "- none" in t and "name-allowlist: []" not in t
open("app/west.yml", "a").write("# user comment\n")
embsk.write_manifest(p, ["cmsis_6", "hal_nxp"])
t = open("app/west.yml").read()
assert embsk.read_allowlist(p) == ["cmsis_6", "hal_nxp"] and "# user comment" in t and "path:" not in t
EOF

hdr "zephyr sdk (user-installed, from PATH, never installed by the skill)"
newproj
check "SDK from PATH (1.x + 0.x layouts), exported to CMake; not on PATH -> hint" python3 - "$SK/scripts" "$T" <<'EOF'
import os, sys; sys.path.insert(0, sys.argv[1]); import embsk
from pathlib import Path
t = Path(sys.argv[2]) / "sdks"
os.environ.pop("ZEPHYR_SDK_INSTALL_DIR", None)
for ver, rel in (("1.0.1", "gnu/arm-zephyr-eabi/bin"), ("0.17.4", "arm-zephyr-eabi/bin")):
    sdk = t / f"zephyr-sdk-{ver}"; b = sdk / rel; b.mkdir(parents=True)
    (sdk / "sdk_version").write_text(ver + "\n"); (b / "arm-zephyr-eabi-gcc").touch()
    os.environ["PATH"] = str(b)
    assert embsk.find_sdk("arm") == (sdk.resolve(), ver), embsk.find_sdk("arm")
    assert embsk.find_sdk("riscv") == (False, "riscv64-zephyr-elf")  # SDK lacks that toolchain
    assert embsk.find_sdk("posix") == (None, None)                    # native_sim: host gcc
    assert embsk.west_env(embsk.load())["ZEPHYR_SDK_INSTALL_DIR"] == str(sdk.resolve())
os.environ["PATH"] = str(t)                    # SDKs on disk, none on PATH
os.environ["ZEPHYR_SDK_INSTALL_DIR"] = str(t)
assert embsk.find_sdk("arm")[0] is False
assert embsk.west_env(embsk.load())["ZEPHYR_SDK_INSTALL_DIR"] == str(t)  # nothing on PATH: user's env untouched
h = embsk.sdk_hint("arm-zephyr-eabi")
assert "export PATH=" in h and str(t) in h, h
EOF
refuse "embsk never runs an SDK install" grep -qE '"sdk", *"install"|setup\.sh", *"-t' "$SK/scripts/embsk.py"

hdr "embsk uart (bounded UART session for agents)"
cat > "$T/dev.py" <<'EOF'
# fake target on stdin/stdout, drawn like the Zephyr shell: colours, prompt redraw (ESC[8D ESC[J), CRLF
import sys
w = sys.stdout.buffer
w.write(b"boot ok v1\r\n\x1b[1;32muart:~$ \x1b[m"); w.flush()
buf = b""
while True:
    c = sys.stdin.buffer.read(1)
    if not c:
        break
    buf += c
    if c == b"\r":
        cmd, buf = buf.strip().decode(), b""
        reply = {"ping": "pong 42", "boom": "ASSERTION FAIL @ x.c:1"}.get(cmd, "unknown")
        w.write(f"\x1b[8D\x1b[J{cmd}\r\n{reply}\r\n\x1b[1;32muart:~$ \x1b[m".encode()); w.flush()
EOF
U=("${EMBSK[@]}" uart --exec "python3 $T/dev.py" --log "$T/uart.txt" --timeout 2)
check "send/expect over --exec" "${U[@]}" --expect "boot ok" --send ping --expect 'pong \d+'
check "transcript clean (no escape codes, one line per message)" bash -c "grep -qx 'pong 42' '$T/uart.txt' && ! grep -q $'\x1b' '$T/uart.txt'"
refuse "expect timeout -> exit 1" "${U[@]}" --timeout 1 --send ping --expect nope
refuse "expect only sees lines after the last send" "${U[@]}" --send ping --expect pong --send other --expect pong
refuse "fail-on stops the run" "${U[@]}" --fail-on ASSERT --send boom --sleep 1
printf 'send ping\nbogus x\n' > "$T/bad.sil"
check "script with an unknown step -> exit 2" bash -c "\"\$@\" --script '$T/bad.sil'; test \$? -eq 2" _ "${U[@]}"
if python3 -c "import pty, termios" 2>/dev/null; then
  check "serial port path (pty, raw 8N1; pyserial or termios)" python3 - "$SK/scripts" "$T" <<'EOF'
import os, pty, subprocess, sys, threading, tty
sys.path.insert(0, sys.argv[1]); import embsk
m, s = pty.openpty(); tty.setraw(s)  # a real UART doesn't echo; a fresh pty does
def dev():
    buf = b""
    while True:
        try:
            buf += os.read(m, 64)
        except OSError:
            return
        while b"\r" in buf:
            cmd, buf = buf.split(b"\r", 1)
            os.write(m, b"\x1b[8D\x1b[J" + cmd + b"\r\npong 7\r\n")
threading.Thread(target=dev, daemon=True).start()
port = os.ttyname(s)
r = subprocess.run([sys.executable, f"{sys.argv[1]}/embsk.py", "uart", "--port", port, "--log", f"{sys.argv[2]}/pty.txt",
                    "--timeout", "3", "--send", "ping", "--expect", r"pong \d"], capture_output=True, text=True)
assert r.returncode == 0, r.stdout
t = embsk._Termios(port, 115200); term = embsk._Term()   # the no-pyserial backend, directly
t.write(b"ping\r"); lines = []
for _ in range(20):
    lines += term.feed(t.read(0.1))
    if "pong 7" in lines:
        break
t.close()
assert lines[-2:] == ["ping", "pong 7"], lines
EOF
else
  sk "serial port path: no pty/termios (Windows): covered by pyserial"
fi
newproj
mkdir -p app/sil && echo "expect boot" > app/sil/smoke.sil
"${EMBSK[@]}" set platform=zephyr board=nucleo_f767zi log=uart >/dev/null 2>&1
has "sil row when app/sil/*.sil exists" "--script app/sil/smoke.sil" "${EMBSK[@]}" commands
has "uart row for agents when log=uart" "embsk uart --send" "${EMBSK[@]}" commands

hdr "scaffold"
newproj
"${EMBSK[@]}" set platform=zephyr board=nucleo_f767zi >/dev/null 2>&1; "${EMBSK[@]}" scaffold >/dev/null 2>&1
check "zephyr template in app/" test -f app/west.yml -a -f app/src/main.cpp -a -f app/CMakeLists.txt -a -f .gitignore -a -f .graphifyignore
has "AGENTS.md has workspace line" "West workspace" cat AGENTS.md
newproj
"${EMBSK[@]}" set platform=baremetal mcu=STM32F767ZI tests=unity >/dev/null 2>&1; "${EMBSK[@]}" scaffold >/dev/null 2>&1
check "bare-metal template in app/" test -f app/CMakeLists.txt -a -f app/tests/test_build_info.c -a -f app/cmake/arm-none-eabi.cmake
refuse "setup refuses bare metal" "${EMBSK[@]}" setup

hdr "flash guard (pure bash: Linux, macOS, Git Bash on Windows)"
g() {  # -> ask | deny | allow (no output); JSON validity checked with python, the guard itself needs nothing
  local out; out="$(printf '%s' "$1" | bash "$REPO/hooks/flash-guard.sh")"
  [[ -z "$out" ]] && echo allow || python3 -c 'import json,sys; print(json.loads(sys.argv[1])["hookSpecificOutput"]["permissionDecision"])' "$out" 2>/dev/null || echo invalid-json
}
B() { python3 -c 'import json,sys; print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"command": sys.argv[2], "description": "run it"}}))' "$1" "$2"; }
while IFS='|' read -r want tool c; do
  [[ "$(g "$(B "$tool" "$c")")" == "$want" ]] && ok "$want: [$tool] $c" || ko "$want: [$tool] $c"
done <<'EOF'
ask|Bash|west flash -d build
ask|Bash|pyocd erase --chip
ask|Bash|STM32_Programmer_CLI -c port=SWD -ob RDP=0xBB
ask|Bash|probe-rs run --chip X a.elf
ask|Bash|nrfutil device recover
ask|Bash|esptool.py --chip esp32 erase_flash
ask|Bash|arm-none-eabi-gdb -ex "load" a.elf
ask|Bash|openocd -f a.cfg -c program
ask|Bash|/usr/bin/west flash
ask|PowerShell|west flash -d build
ask|PowerShell|& "C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe" -c port=SWD -w a.elf
ask|PowerShell|C:\nrf\nrfjprog.exe --program a.hex
ask|Bash|JLink.exe -device STM32F767ZI -CommandFile f.jlink
allow|Bash|west build -b nucleo_f767zi app
allow|Bash|cat build/zephyr/zephyr.dts
allow|Bash|echo westflash
allow|Bash|arm-none-eabi-gdb -batch -ex bt a.elf
allow|Bash|JLinkGDBServer -device X
EOF
[[ "$(g "$(B Bash $'cd build\nwest flash')")" == ask ]] && ok "multi-line command" || ko "multi-line command"
[[ "$(g '{"tool_name":"shell","tool_input":{"command":["bash","-lc","west flash"]}}')" == ask ]] && ok "Codex array form" || ko "Codex array form"
[[ "$(g '{"tool_name":"Read","tool_input":{"file_path":"/x/.env"}}')" == ask ]] && ok "secret file" || ko "secret file"
[[ "$(g '{"tool_name":"Read","tool_input":{"file_path":"C:\\Users\\me\\p\\.env"}}')" == ask ]] && ok "secret file, Windows path" || ko "secret file, Windows path"
[[ "$(g '{"tool_name":"Write","tool_input":{"file_path":"/x/README.md","content":"west flash -d build"}}')" == allow ]] && ok "docs mentioning west flash" || ko "docs mentioning west flash"
[[ "$(g '{"tool_name":"Read","tool_input":{"file_path":"C:\\x\\a \"q\".pem"}}')" == ask ]] && ok "reason JSON-escaped" || ko "reason JSON-escaped"
[[ "$(EMBSK_FLASH_GUARD=deny g "$(B Bash 'west flash')")" == deny ]] && ok "deny mode" || ko "deny mode"
check "hooks.json gates the PowerShell tool" grep -q '"matcher": "Bash|PowerShell|' "$REPO/hooks/hooks.json"
has "session-start without jq" "profile: zephyr nucleo_f767zi" bash -c "echo '{\"cwd\":\"$REPO/example/02-nucleo_f767zi-thermal-monitor\"}' | bash '$REPO/hooks/session-start.sh'"

hdr "installer (install.py, throw-away HOME, no agent CLIs on PATH)"
FH="$T/home"; mkdir -p "$FH/other-agent"
inst() { HOME="$FH" PATH="/usr/bin:/bin" python3 "$REPO/install.py" "$@"; }
check "install" inst --agent-dir "$FH/other-agent"
check "embsk launcher + Agent Skills link" test -L "$FH/.local/bin/embsk" -a -L "$FH/.agents/skills/embedded-sys" -a -L "$FH/other-agent/embedded-sys"
check "launcher runs" bash -c "HOME='$FH' '$FH/.local/bin/embsk' schema | grep -q '\"options\"'"
check "re-run is idempotent" inst
check "--check passes" inst --check
mkdir -p "$FH/.agents/skills/mine"; echo x > "$FH/.agents/skills/mine/SKILL.md"
check "uninstall" inst --uninstall
check "uninstall removed links, kept foreign files" test ! -e "$FH/.local/bin/embsk" -a ! -e "$FH/.agents/skills/embedded-sys" -a ! -e "$FH/other-agent/embedded-sys" -a -f "$FH/.agents/skills/mine/SKILL.md"
refuse "--check fails when not installed" inst --check
check "install.sh wrapper forwards" bash -c "HOME='$FH' PATH=/usr/bin:/bin sh '$REPO/install.sh' --check >/dev/null; test \$? -eq 1"

hdr "Windows code paths (simulated: WIN=True, no symlink privilege, fake winreg)"
check "embsk + install.py Windows branches" python3 - "$REPO" "$T" <<'EOF'
import os, sys, types, shutil
from pathlib import Path
repo, t = Path(sys.argv[1]), Path(sys.argv[2]) / "win"
sys.path.insert(0, str(repo)); sys.path.insert(0, str(repo / "skills/embedded-sys/scripts"))
import embsk
embsk.WIN = True
assert embsk.venv_exe(Path("v"), "python") == Path("v/Scripts/python.exe")
pf = t / "pf"; (pf / "Git/bin").mkdir(parents=True); (pf / "Git/bin/bash.exe").touch()
os.environ["ProgramFiles"] = str(pf)
assert embsk.bash_exe() == str(pf / "Git/bin/bash.exe")                       # Git Bash, not System32 WSL
sdk = t / "zephyr-sdk-1.0.1"; b = sdk / "gnu/arm-zephyr-eabi/bin"; b.mkdir(parents=True)
(sdk / "sdk_version").write_text("1.0.1"); (b / "arm-zephyr-eabi-gcc.exe").touch()
os.environ["PATH"] = str(b)
assert embsk.find_sdk("arm") == (sdk.resolve(), "1.0.1")                       # SDK from PATH via gcc.exe
assert "SetEnvironmentVariable('Path'" in embsk.path_fix(b)                    # PowerShell fix, not export
import re
m = re.search(r"^CMAKE_NM:FILEPATH=(.*)nm(\.exe)?\s*$", "CMAKE_NM:FILEPATH=C:/sdk/gnu/arm-zephyr-eabi/bin/arm-zephyr-eabi-nm.exe\r", re.M)
assert m and m.group(1).endswith("arm-zephyr-eabi-") and m.group(2) == ".exe"
import install
install.WIN, install.HOME, install.BIN = True, t / "home", t / "home/.local/bin"
install.STATE = t / "home/.config/embsk/install-state.json"
s = install.shims(Path("C:/Python312/python.exe"))
assert s[install.BIN / "embsk.cmd"].startswith('@"C:') and s[install.BIN / "embsk.cmd"].endswith("%*\r\n")
assert s[install.BIN / "embsk"].startswith("#!/bin/sh\nexec \"C:/Python312/python.exe\" -X utf8")
real_symlink = os.symlink
def no_priv(*a, **k): raise OSError(1314, "A required privilege is not held by the client")
os.symlink = no_priv
sys.modules["_winapi"] = types.SimpleNamespace(CreateJunction=lambda s, d: real_symlink(s, d))   # junction stand-in
dst = t / "home/.agents/skills/embedded-sys"
install.link(install.SKILL, dst); assert install.same(dst, install.SKILL) and install.ours(dst)
f = t / "home/.pi/workflows/embedded.yaml"
install.link(repo / "pi-workflows/embedded.yaml", f); assert f.is_file() and not f.is_symlink() and install.ours(f, repo / "pi-workflows/embedded.yaml")
sys.modules["_winapi"] = types.SimpleNamespace(CreateJunction=no_priv)                           # FAT/network drive
d2 = t / "home/x/embedded-sys"; install.link(install.SKILL, d2); assert (d2 / ".embsk-copy").exists() and install.ours(d2)
for p in (dst, f, d2): install.unlink(p); assert not os.path.lexists(p)
assert install.SKILL.is_dir() and (repo / "pi-workflows/embedded.yaml").is_file()               # targets untouched
reg = {"Path": ("C:\\Windows;%USERPROFILE%\\bin", 2)}
class Key:
    def __enter__(self): return self
    def __exit__(self, *a): pass
sys.modules["winreg"] = types.SimpleNamespace(HKEY_CURRENT_USER=0, KEY_READ=1, KEY_WRITE=2, REG_SZ=1, REG_EXPAND_SZ=2,
    OpenKey=lambda *a: Key(), QueryValueEx=lambda k, n: reg[n], SetValueEx=lambda k, n, _, typ, v: reg.__setitem__(n, (v, typ)))
import ctypes; ctypes.windll = types.SimpleNamespace(user32=types.SimpleNamespace(SendMessageTimeoutW=lambda *a: 1))
assert install.win_user_path_add(Path("C:/Users/me/.local/bin")) and reg["Path"][0].endswith(";" + str(Path("C:/Users/me/.local/bin")))
assert not install.win_user_path_add(Path("C:/Users/me/.local/bin"))                             # no duplicate entry
EOF

hdr "plugins"
if command -v claude >/dev/null; then has "claude plugin validate" "Validation passed" timeout 90 claude plugin validate "$REPO"; else sk "claude CLI not installed"; fi

if [[ $FULL -eq 1 ]] && ! python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import embsk; sys.exit(not embsk.sdk_from_path())' "$SK/scripts"; then
  sk "full: no Zephyr SDK on PATH (yours to install; see docs/05)"
elif [[ $FULL -eq 1 ]]; then
  hdr "full: example 02 setup + verify (network)"
  cp -r "$REPO/example/02-nucleo_f767zi-thermal-monitor" "$T/ex2" && cd "$T/ex2"
  check "embsk setup (west init/update/build)" "${EMBSK[@]}" setup
  check "only 3 projects fetched" test "$(ls deps/modules/hal | tr '\n' ' ')" = "cmsis_6 stm32 "
  check "embsk verify (build + 7 host tests + SIL scenario over UART + size)" "${EMBSK[@]}" verify
fi

printf '\n\033[1m%d passed, %d failed, %d skipped\033[0m\n' "$pass" "$fail" "$skip"
[[ $fail -eq 0 ]]
