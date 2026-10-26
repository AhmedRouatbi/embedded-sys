/**
 * embsk for Pi: Alt+A (and /embsk) opens the embedded-project checkbox menu,
 * a status-bar profile summary, and a confirmation gate for flash/erase/lock commands.
 *
 * The menu itself is the shared curses UI in skills/embedded-sys/scripts/embsk.py
 * (same one tmux/Codex/shell users get); Pi suspends its TUI while it runs.
 */
import { spawnSync } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { getShellConfig } from "@earendil-works/pi-coding-agent";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const EMBSK = fileURLToPath(new URL("../skills/embedded-sys/scripts/embsk.py", import.meta.url));
const GUARD = fileURLToPath(new URL("../hooks/flash-guard.sh", import.meta.url));

type Profile = Record<string, unknown>;

// Linux/macOS ship python3; Windows has python.exe and/or the py launcher (python3 may be a Store stub).
let PY: string | undefined;
function python(): string {
	const cands = process.platform === "win32" ? ["python", "py", "python3"] : ["python3", "python"];
	PY ??= cands.find((c) => spawnSync(c, ["-c", "import sys; sys.exit(sys.version_info < (3, 9))"], { timeout: 10000 }).status === 0) ?? cands[0];
	return PY;
}

// The guard is a bash script: Git Bash on Windows, resolved the way Pi resolves its own bash tool.
function bash(): string | undefined {
	try {
		return getShellConfig().shell;
	} catch {
		return undefined;
	}
}

function run(args: string[], cwd: string, input?: string) {
	return spawnSync(python(), [EMBSK, ...args], { cwd, input, encoding: "utf8", timeout: 20000 });
}

function profilePath(cwd: string): string | undefined {
	const r = spawnSync("git", ["rev-parse", "--show-toplevel"], { cwd, encoding: "utf8" });
	for (const dir of [cwd, r.status === 0 ? r.stdout.trim() : cwd]) {
		const p = join(dir, ".embsk", "profile.json");
		if (existsSync(p)) return p;
	}
	return undefined;
}

function readProfile(cwd: string): Profile | undefined {
	if (!profilePath(cwd)) return undefined;
	const r = run(["get"], cwd);
	try {
		return r.status === 0 ? (JSON.parse(r.stdout) as Profile) : undefined;
	} catch {
		return undefined;
	}
}

function summary(p: Profile): string {
	const target = p.platform === "zephyr" ? p.board || "<board?>" : p.mcu || "<mcu?>";
	const safety = p.safety && p.safety !== "none" ? ` · ${String(p.safety).toUpperCase()} ${p.safety_level}` : "";
	return `${p.platform} ${target} · ${p.debugger}${safety}`;
}

export default function embsk(pi: ExtensionAPI) {
	const syncStatus = (ctx: ExtensionContext) => {
		if (!ctx.hasUI) return;
		const p = readProfile(ctx.cwd);
		ctx.ui.setStatus("embsk", p ? `⚙ ${summary(p)}` : undefined);
	};

	const openMenu = async (ctx: ExtensionContext) => {
		if (ctx.mode !== "tui") {
			ctx.ui.notify("embsk menu needs the interactive TUI; use `embsk set key=value` instead", "error");
			return;
		}
		const before = profilePath(ctx.cwd);
		const mtime = before ? statSync(before).mtimeMs : 0;

		await ctx.ui.custom<number | null>((tui, _theme, _kb, done) => {
			tui.stop();
			process.stdout.write("\x1b[2J\x1b[H");
			// The menu may go on to `embsk setup` (west init/update/build): --wait keeps its output until Enter.
			const r = spawnSync(python(), [EMBSK, "menu", "--wait"], {
				cwd: ctx.cwd,
				stdio: "inherit",
				env: process.env,
			});
			tui.start();
			tui.requestRender(true);
			done(r.status);
			return { render: () => [], invalidate: () => {} };
		});

		const after = profilePath(ctx.cwd);
		if (!after || statSync(after).mtimeMs === mtime) {
			ctx.ui.notify("embsk: profile unchanged", "info");
			return;
		}
		syncStatus(ctx);
		const doctor = run(["doctor"], ctx.cwd);
		const errors = doctor.stdout.split("\n").filter((l) => l.startsWith("ERR")).length;
		ctx.ui.notify(errors ? `embsk: profile saved with ${errors} error(s) — see embsk doctor` : "embsk: profile saved, AGENTS.md updated", errors ? "warning" : "info");
		// Tell the agent without starting a turn: the next prompt sees the new profile.
		pi.sendMessage(
			{
				customType: "embsk-profile",
				content: `[embsk] Project profile changed (AGENTS.md embsk block regenerated). Re-read it before hardware work.\n\nembsk doctor:\n${doctor.stdout.trim()}`,
				display: false,
			},
			{ deliverAs: "nextTurn" },
		);
	};

	pi.registerShortcut("alt+a", { description: "embsk: embedded project profile menu", handler: openMenu });
	pi.registerCommand("embsk", {
		description: "Embedded project profile menu (platform, board/MCU, probe, safety...). Args: doctor | commands",
		handler: async (args, ctx) => {
			const sub = String(args || "").trim();
			if (sub === "doctor" || sub === "commands") {
				const r = run([sub], ctx.cwd);
				ctx.ui.notify((r.stdout || r.stderr).trim() || "(no output)", r.status === 0 ? "info" : "warning");
				return;
			}
			await openMenu(ctx);
		},
	});

	// Flash/erase/lock gate: one source of truth with the Claude/Codex hook (hooks/flash-guard.sh).
	pi.on("tool_call", async (event, ctx) => {
		const name = event.toolName;
		const input = (event.input ?? {}) as Record<string, unknown>;
		let payload: string;
		if (name === "bash" || name === "powershell") payload = JSON.stringify({ tool_name: name === "bash" ? "Bash" : "PowerShell", tool_input: { command: input.command } });
		else if (name === "read" || name === "write" || name === "edit") payload = JSON.stringify({ tool_name: name, tool_input: { file_path: input.path ?? input.file_path } });
		else return undefined;

		const sh = bash();
		if (!sh) return { block: true, reason: "embsk flash guard needs bash (Windows: install Git for Windows); blocked to be safe" };
		const r = spawnSync(sh, [GUARD], { input: payload, encoding: "utf8", timeout: 5000, env: { ...process.env, EMBSK_FLASH_GUARD: "ask" } });
		if (r.status !== 0) return { block: true, reason: "embsk flash guard failed to run; blocked to be safe" };
		if (!r.stdout.trim()) return undefined;
		let reason = "embsk: hardware or secret operation";
		try {
			reason = JSON.parse(r.stdout).hookSpecificOutput.permissionDecisionReason ?? reason;
		} catch {
			/* keep default reason */
		}
		if (!ctx.hasUI) return { block: true, reason: `${reason} (no UI to confirm)` };
		const shown = name === "bash" || name === "powershell" ? String(input.command) : String(input.path ?? input.file_path);
		const choice = await ctx.ui.select(`⚠ ${reason}\n\n  ${shown}\n\nAllow?`, ["Allow once", "Block"]);
		return choice === "Allow once" ? undefined : { block: true, reason: "Blocked by user (embsk flash guard)" };
	});

	pi.on("session_start", async (_event, ctx) => syncStatus(ctx));
}
