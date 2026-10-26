#!/usr/bin/env python3
"""embedded-sys installer for Linux, macOS and Windows (stdlib only, Python 3.9+).

  Linux / macOS:  python3 install.py [--check | --uninstall] [--agent-dir DIR ...]    (or ./install.sh)
  Windows:        py -3 install.py ...     (or: python install.py ...)

  (no option)       install for every agent found on this machine; safe to re-run
  --check           read-only status + smoke tests; exit 1 if the skill isn't usable yet
  --uninstall       remove everything this script added
  --agent-dir DIR   also link the skill into DIR, the skills folder of any other agent (repeatable)

Everything it adds is a link or a small launcher pointing into THIS folder: keep the folder where it is
(after moving it, re-run). It never installs toolchains (Zephyr SDK, west, CMake, ...), never edits your
projects and never disables other plugins (it prints the commands instead).
"""
import json, os, shutil, subprocess, sys
from pathlib import Path

if sys.version_info < (3, 9):
    sys.exit("embedded-sys needs Python 3.9+")

ROOT = Path(__file__).resolve().parent
SKILL = ROOT / "skills" / "embedded-sys"
EMBSK_PY = SKILL / "scripts" / "embsk.py"
WIN = os.name == "nt"
HOME = Path.home()
BIN = HOME / ".local" / "bin"
SKILL_LINK = HOME / ".agents" / "skills" / "embedded-sys"  # Agent Skills location: Codex, Cursor, Gemini CLI, Copilot, OpenCode, Pi, ...
CLAUDE_SKILL = HOME / ".claude" / "skills" / "embedded-sys"  # only when the Claude plugin can't be used
CODEX = Path(os.environ.get("CODEX_HOME") or HOME / ".codex")
STATE = HOME / ".config" / "embsk" / "install-state.json"  # every path we created, for --uninstall
sys.path.insert(0, str(EMBSK_PY.parent))
sys.dont_write_bytecode = True  # no __pycache__ inside the skill folder that agents load
import embsk  # noqa: E402  same SDK / Git Bash lookups as the CLI

for _s in (sys.stdout, sys.stderr):  # never die on a console code page
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(errors="backslashreplace")
COLOR = sys.stdout.isatty() and (not WIN or "WT_SESSION" in os.environ or "TERM" in os.environ)


def _c(code, s):
    return f"\033[{code}m{s}\033[0m" if COLOR else s


def say(m): print(_c("1;36", "==>"), m)
def ok(m): print(" ", _c("32", "ok"), "", m)
def warn(m): print(" ", _c("33", "!!"), "", m)
def have(cmd): return shutil.which(cmd)


def run(cmd, timeout=180):
    """Run a CLI (claude.cmd/.exe resolved via PATH on Windows too); None if it can't start."""
    try:
        return subprocess.run([shutil.which(cmd[0]) or cmd[0], *cmd[1:]], capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None


# ---------------------------------------------------------------- links (symlink; Windows: junction / copy)
def created(p):
    st = json.loads(STATE.read_text()) if STATE.exists() else []
    if str(p) not in st:
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text(json.dumps(st + [str(p)], indent=1))


def same(a, b):
    return os.path.realpath(a) == os.path.realpath(b)


def ours(dst, src=None):
    """dst was made by this installer: resolves into this repo, is a marked copy, or is one of our launchers."""
    p = Path(dst)
    if not (p.is_symlink() or p.exists()):
        return False
    if p.is_symlink() and not p.exists():  # dangling, e.g. the repo was moved: safe to replace
        return True
    real = os.path.realpath(p)
    if real == str(ROOT) or real.startswith(str(ROOT) + os.sep) or (p / ".embsk-copy").exists():
        return True
    if p.is_file():
        data = p.read_bytes()
        if p.parent == BIN and p.name in ("embsk", "embsk.cmd") and b"embsk.py" in data:  # our launcher, maybe an old repo path
            return True
        return (src is not None and Path(src).is_file() and data == Path(src).read_bytes()) or str(EMBSK_PY).encode() in data \
            or EMBSK_PY.as_posix().encode() in data
    return False


def unlink(p):
    p = Path(p)
    if (p / ".embsk-copy").exists():
        shutil.rmtree(p)
    elif p.is_symlink() or p.is_file():
        try:
            p.unlink()
        except OSError:  # Windows directory symlink
            os.rmdir(p)
    else:
        os.rmdir(p)  # Windows junction: removes the link, never the target


def link(src, dst):
    src, dst = Path(src), Path(dst)
    if same(dst, src):
        ok(f"{dst} -> {src}")
        return created(dst)
    if dst.is_symlink() or dst.exists():
        if not ours(dst, src):
            warn(f"{dst} exists and wasn't made by this installer: left unchanged")
            return
        unlink(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    how = ""
    try:
        os.symlink(src, dst, target_is_directory=src.is_dir())
    except OSError:
        if not WIN:
            raise
        if src.is_dir():  # symlinks need Developer Mode/admin on Windows; junctions don't
            try:
                import _winapi
                _winapi.CreateJunction(str(src), str(dst))
                how = " (junction)"
            except OSError:
                shutil.copytree(src, dst)
                (dst / ".embsk-copy").write_text("copied by install.py: re-run it after updating the repo\n")
                how = " (copy: re-run install.py after updating the repo)"
        else:
            shutil.copy2(src, dst)
            how = " (copy: re-run install.py after updating the repo)"
    ok(f"{dst} -> {src}{how}")
    created(dst)


def drop(p, why):
    if ours(p):
        unlink(p)
        ok(f"removed {p} ({why})")


# ---------------------------------------------------------------- embsk command
def shims(py):
    """Windows launchers: embsk.cmd for cmd/PowerShell, an sh script for Git Bash (it ignores .cmd)."""
    return {BIN / "embsk.cmd": f'@"{py}" -X utf8 "{EMBSK_PY}" %*\r\n',
            BIN / "embsk": f'#!/bin/sh\nexec "{Path(py).as_posix()}" -X utf8 "{EMBSK_PY.as_posix()}" "$@"\n'}


def on_path(d):
    return any(Path(x) == d for x in os.environ.get("PATH", "").split(os.pathsep) if x)


def win_user_path_add(d):
    """Append d to the user PATH in the registry (like uv/rustup); setx would truncate PATH at 1024 chars."""
    import winreg, ctypes
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment", 0, winreg.KEY_READ | winreg.KEY_WRITE) as k:
        try:
            cur, typ = winreg.QueryValueEx(k, "Path")
        except FileNotFoundError:
            cur, typ = "", winreg.REG_EXPAND_SZ
        parts = [x for x in cur.split(";") if x]
        if any(os.path.normcase(os.path.expandvars(x)).rstrip("\\") == os.path.normcase(str(d)) for x in parts):
            return False
        winreg.SetValueEx(k, "Path", 0, typ if typ in (winreg.REG_SZ, winreg.REG_EXPAND_SZ) else winreg.REG_EXPAND_SZ, ";".join(parts + [str(d)]))
    ctypes.windll.user32.SendMessageTimeoutW(0xFFFF, 0x001A, 0, "Environment", 0x0002, 5000, None)  # tell Explorer
    return True


def install_cli():
    say("embsk command")
    if WIN:
        py = Path(getattr(sys, "_base_executable", "") or sys.executable)  # not a venv that may be deleted later
        BIN.mkdir(parents=True, exist_ok=True)
        for f, text in shims(py).items():
            with open(f, "w", encoding="utf-8", newline="") as fh:  # keep \r\n for .cmd and \n for sh
                fh.write(text)
            ok(f"{f} (runs {py})")
            created(f)
        if not on_path(BIN) and win_user_path_add(BIN):
            ok(f"added {BIN} to your user PATH: open a NEW terminal / restart the agent")
        for mod, pkg, why in (("curses", "windows-curses", "`embsk menu` (embsk set works without it)"),
                              ("serial", "pyserial", "`embsk uart --port COMx` (no termios on Windows)")):
            have_it = run([str(py), "-c", f"import {mod}"])
            if have_it and have_it.returncode == 0:
                continue
            r = run([str(py), "-m", "pip", "install", "--user", "-q", pkg])
            (ok if r and r.returncode == 0 else warn)(f"{pkg} for {why}" + ("" if r and r.returncode == 0 else
                                                      f" failed: {py} -m pip install --user {pkg}"))
    else:
        for f in (EMBSK_PY, EMBSK_PY.parent / "export-zephyr-context.sh", *ROOT.glob("hooks/*.sh")):
            f.chmod(f.stat().st_mode | 0o111)
        link(EMBSK_PY, BIN / "embsk")
        if not on_path(BIN):
            warn(f"{BIN} is not on PATH: add  export PATH=\"$HOME/.local/bin:$PATH\"  to your shell rc")


# ---------------------------------------------------------------- agents
def claude_keybinding(action):
    """Merge/remove meta+a -> /embsk in ~/.claude/keybindings.json without clobbering other bindings."""
    f = HOME / ".claude" / "keybindings.json"
    data = json.loads(f.read_text(encoding="utf-8")) if f.exists() else {"bindings": []}
    chat = next((b for b in data.setdefault("bindings", []) if b.get("context") == "Chat"), None)
    if action == "add":
        if chat is None:
            chat = {"context": "Chat", "bindings": {}}
            data["bindings"].append(chat)
        cur = chat["bindings"].get("meta+a")
        if cur and cur != "command:embsk":
            return warn(f"Claude: meta+a already bound to {cur!r}; left unchanged")
        chat["bindings"]["meta+a"] = "command:embsk"
    elif chat and chat["bindings"].get("meta+a") == "command:embsk":
        del chat["bindings"]["meta+a"]
    else:
        return
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    ok(f"{f}: meta+a {'-> /embsk (Alt+A)' if action == 'add' else 'removed'}")


def install_claude():
    if not have("claude"):
        if (HOME / ".claude").is_dir():
            say("Claude Code (no `claude` CLI on PATH): skill only")
            link(SKILL, CLAUDE_SKILL)
        return
    say("Claude Code: plugin (skill, /embsk, agents, hooks) + Alt+A")
    if WIN and not embsk.bash_exe():
        warn("no Git Bash: the plugin's hooks are bash scripts and Claude Code would block tool calls on them. "
             "Installed the skill only; install Git for Windows, then re-run for /embsk, agents and the flash guard")
        return link(SKILL, CLAUDE_SKILL)
    run(["claude", "plugin", "marketplace", "add", str(ROOT)])
    r = run(["claude", "plugin", "install", "embedded-sys@embsk"])
    if r and (r.returncode == 0 or "already" in (r.stdout + r.stderr).lower()):
        ok("claude plugin embedded-sys@embsk (restart Claude Code)")
        drop(CLAUDE_SKILL, "the plugin provides the skill")
    else:
        warn(f"plugin install failed: claude plugin marketplace add \"{ROOT}\" && claude plugin install embedded-sys@embsk"
             + (f"\n      {(r.stderr or r.stdout).strip()[:300]}" if r else ""))
    claude_keybinding("add")


def install_pi():
    if not have("pi"):
        return
    say("Pi: package (Alt+A, /embsk, status, flash-guard gate) + workflow")
    for old in stale_pi_packages():  # repo moved or another copy: two extensions would both bind Alt+A
        run(["pi", "remove", str(old)])
        ok(f"pi remove {old} (old location of this package)")
    r = run(["pi", "install", str(ROOT)])
    (ok if r and r.returncode == 0 else warn)(f"pi install {ROOT}" + ("" if r and r.returncode == 0 else " failed: run it by hand"))
    link(ROOT / "pi-workflows" / "embedded.yaml", HOME / ".pi" / "workflows" / "embedded.yaml")


def stale_pi_packages():
    """Local Pi packages that are this repo at another path (moved or copied), or that no longer exist."""
    agent = HOME / ".pi" / "agent"
    try:
        pkgs = json.loads((agent / "settings.json").read_text(encoding="utf-8")).get("packages", [])
    except (OSError, ValueError):
        return []
    out = []
    for s in (x if isinstance(x, str) else x.get("source", "") for x in pkgs):
        if not s or ":" in s.split("/")[0] and not Path(s).drive:  # npm:, git:, https: sources
            continue
        p = Path(os.path.normpath(agent / Path(s).expanduser()))
        looks_ours = (p / "pi-extension" / "index.ts").exists() and (p / "skills" / "embedded-sys").is_dir()
        if not same(p, ROOT) and (looks_ours or (not p.exists() and p.name == ROOT.name)):
            out.append(p)
    return out


def install_codex():
    if not (have("codex") or CODEX.is_dir()):
        return
    say("Codex: /prompts:embsk (+ plugin with the flash-guard hooks)")
    link(ROOT / "commands" / "embsk.md", CODEX / "prompts" / "embsk.md")
    drop(CODEX / "skills" / "embedded-sys", "Codex reads ~/.agents/skills; Cursor would list it twice")
    if have("codex") and (not WIN or embsk.bash_exe()):
        run(["codex", "plugin", "marketplace", "add", str(ROOT)])
        r = run(["codex", "plugin", "add", "embedded-sys@embsk"])
        (ok if r and r.returncode == 0 else warn)("codex plugin embedded-sys (trust its hooks with /hooks in Codex)" if r and r.returncode == 0
                                                  else "codex plugin not installed (needs a Codex with plugins); skill + /prompts:embsk still work")


def install_tmux():
    if WIN:
        return
    say("tmux: Alt+A popup for any terminal agent")
    conf, rc = HOME / ".config" / "embsk" / "embsk.tmux.conf", HOME / ".tmux.conf"
    link(ROOT / "tmux" / "embsk.tmux.conf", conf)
    if not have("tmux"):
        return warn("tmux not installed (Pi and Claude Code have their own Alt+A)")
    if "embsk.tmux.conf" not in (rc.read_text() if rc.exists() else ""):
        with rc.open("a") as f:
            f.write("source-file ~/.config/embsk/embsk.tmux.conf\n")
        ok(f"added to {rc}")
    run(["tmux", "source-file", str(rc)])


# ---------------------------------------------------------------- reports
def prereqs():
    say("Prerequisites you provide (reported here, never installed)")
    ok(f"Python {sys.version.split()[0]} ({sys.executable})")
    for tool, why in (("git", "projects, Claude plugin marketplace"), ("cmake", "builds"), ("ninja", "builds"),
                      ("west", "Zephyr; `embsk setup` adds it to a project .venv when missing")):
        (ok if have(tool) else warn)(f"{tool}: {have(tool) or 'not on PATH'}  ({why})")
    if WIN:
        b = embsk.bash_exe()
        (ok if b else warn)(f"Git Bash: {b or 'not found'}  (Claude Code/Pi hooks, `embsk export`; install Git for Windows)")
    sdk = embsk.sdk_from_path()
    (ok if sdk else warn)(f"Zephyr SDK on PATH: {sdk}" if sdk else
                          "Zephyr SDK not on PATH: needed for Zephyr builds, never installed by this script (see docs/05)")
    (ok if have("graphify") else warn)("graphify (optional): " + (have("graphify") or "uv tool install graphifyy"))


def overlaps():
    say("Overlap check (superseded toolkits; nothing is changed automatically)")
    found = 0
    if have("claude"):
        r = run(["claude", "plugin", "list"])
        out = r.stdout if r else ""
        if "agent-skills" in out:
            found = warn("Claude: agent-skills installed (~3.6k always-on tokens). Superseded -> claude plugin disable agent-skills") or 1
        if "@libre-embed" in out:
            found = warn("Claude: LibreEmbed plugins installed. Superseded -> claude plugin disable <name>@libre-embed") or 1
        if "ponytail" in out:
            ok("Claude: ponytail can stay (same rules; adds /ponytail level switching + statusline)")
    if (HOME / ".pi" / "agent" / "skills" / "test-driven-development").is_dir():
        found = warn("Pi: agent-skills copies in ~/.pi/agent/skills compete for triggers. Superseded -> move them out") or 1
    libre = {"rtos-patterns", "bare-metal-patterns", "cortex-m-patterns", "communication-buses", "debug-trace-patterns", "embedded-testing-patterns"}
    if (HOME / ".pi" / "skills").is_dir() and libre & {p.name for p in (HOME / ".pi" / "skills").iterdir()}:
        found = warn("Pi: LibreEmbed symlinks in ~/.pi/skills. Superseded -> remove them") or 1
    if not found:
        ok("no superseded toolkits detected")


def smoke():
    """-> number of failures: the CLI runs and the flash guard asks before `west flash`."""
    bad = 0
    r = run([sys.executable, str(EMBSK_PY), "schema"])
    try:
        n = len(json.loads(r.stdout)["options"])
        ok(f"embsk runs ({n} profile options)")
    except (AttributeError, ValueError, KeyError, TypeError):
        bad = warn(f"embsk.py failed: {(r.stderr if r else 'could not start')[:300]}") or 1
    bash = embsk.bash_exe()
    if bash:
        g = subprocess.run([bash, str(ROOT / "hooks" / "flash-guard.sh")], input='{"tool_name":"Bash","tool_input":{"command":"west flash"}}',
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        (ok if '"ask"' in g.stdout else warn)("flash guard asks before `west flash`" if '"ask"' in g.stdout else f"flash guard broken: {g.stderr[:200]}")
        bad += '"ask"' not in g.stdout
    else:
        warn("no bash: the flash guard can't run (Windows: install Git for Windows)")
    return bad


# ---------------------------------------------------------------- modes
def install(extra_dirs):
    install_cli()
    say("Skill (Agent Skills location, read by Codex, Cursor, Gemini CLI, GitHub Copilot, OpenCode, Pi, ...)")
    link(SKILL, SKILL_LINK)
    for d in extra_dirs:
        link(SKILL, Path(d).expanduser() / "embedded-sys")
    install_claude()
    install_pi()
    install_codex()
    install_tmux()
    prereqs()
    say("Smoke test")
    smoke()
    overlaps()
    say("Done. Restart your agent. In a firmware project: Alt+A (or /embsk, or `embsk menu`), then `embsk doctor`.")
    py = "py -3" if WIN else "python3"
    say(f"Other agents: {py} install.py --agent-dir <their skills folder> (see INSTALL.md).  Verify: {py} install.py --check")
    return 0


def check():
    say("Status")
    bad = 0
    launcher = BIN / ("embsk.cmd" if WIN else "embsk")
    if ours(launcher):
        ok(f"embsk launcher: {launcher}" + ("" if have("embsk") else "  (not on PATH in this shell yet: open a new terminal)"))
    else:
        bad = warn(f"embsk launcher missing ({launcher})") or 1
    if same(SKILL_LINK, SKILL):
        ok(f"skill: {SKILL_LINK}")
    else:
        bad = warn(f"skill not linked at {SKILL_LINK}") or 1
    if have("claude"):
        r = run(["claude", "plugin", "list"])
        (ok if r and "embedded-sys" in r.stdout else warn)("claude plugin embedded-sys" + ("" if r and "embedded-sys" in r.stdout else " not installed"))
    if have("pi"):
        r = run(["pi", "list"])
        (ok if r and ROOT.name in r.stdout else warn)("pi package" + ("" if r and ROOT.name in r.stdout else " not installed"))
    for p in (HOME / ".pi" / "workflows" / "embedded.yaml", CODEX / "prompts" / "embsk.md", CLAUDE_SKILL):
        if ours(p):
            ok(str(p))
    prereqs()
    say("Smoke test")
    bad += smoke()
    overlaps()
    return 1 if bad else 0


def uninstall():
    say("Removing embedded-sys")
    st = json.loads(STATE.read_text()) if STATE.exists() else []
    defaults = [BIN / "embsk", BIN / "embsk.cmd", SKILL_LINK, CLAUDE_SKILL, CODEX / "skills" / "embedded-sys", CODEX / "prompts" / "embsk.md",
                HOME / ".pi" / "workflows" / "embedded.yaml", HOME / ".config" / "embsk" / "embsk.tmux.conf"]
    for p in dict.fromkeys([*defaults, *map(Path, st)]):
        if ours(p):
            unlink(p)
            ok(f"removed {p}")
    if have("pi"):
        run(["pi", "remove", str(ROOT)])
        ok("pi package removed")
    if have("claude"):
        run(["claude", "plugin", "uninstall", "embedded-sys@embsk"])
        run(["claude", "plugin", "marketplace", "remove", "embsk"])
        ok("claude plugin + marketplace removed")
        claude_keybinding("remove")
    if have("codex"):
        run(["codex", "plugin", "remove", "embedded-sys"])
    rc = HOME / ".tmux.conf"
    if rc.exists() and "embsk.tmux.conf" in rc.read_text():
        rc.write_text("".join(l for l in rc.read_text().splitlines(True) if "embsk.tmux.conf" not in l))
        ok(f"{rc} cleaned")
    STATE.unlink(missing_ok=True)
    if WIN:
        ok(f"{BIN} stays on your user PATH (other tools use it too)")
    return 0


def main(argv):
    mode, dirs, it = "install", [], iter(argv)
    for a in it:
        if a in ("--check", "check"):
            mode = "check"
        elif a in ("--uninstall", "uninstall"):
            mode = "uninstall"
        elif a in ("--install", "install"):
            mode = "install"
        elif a == "--agent-dir":
            dirs.append(next(it, None) or sys.exit("--agent-dir needs a folder"))
        else:
            print(__doc__)
            return 0 if a in ("-h", "--help") else 2
    return {"install": lambda: install(dirs), "check": check, "uninstall": uninstall}[mode]()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
