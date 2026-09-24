import { afterEach, beforeEach, expect, test } from "bun:test";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import * as path from "node:path";
import { pathToFileURL } from "node:url";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import { createClaudeHooks, type HookConfig, type HookEntry } from "../claude-hooks";

type Event = { toolName: string; toolCallId: string; input: Record<string, unknown> };
type Handler = (event: Event, ctx: ExtensionContext) => Promise<unknown>;

let root: string;
let cwd: string;
let ctx: ExtensionContext;
let confirmCalls: [string, string][];
let confirmAnswer: boolean;

beforeEach(() => {
	root = realpathSync(mkdtempSync(path.join(tmpdir(), "claude-hooks-")));
	cwd = path.join(root, "work");
	mkdirSync(cwd);
	writeFileSync(path.join(root, "package.json"), JSON.stringify({ name: "sample" }));
	confirmCalls = [];
	confirmAnswer = true;
	ctx = {
		cwd,
		hasUI: true,
		sessionManager: { getSessionId: () => "session-42" },
		ui: { confirm: async (title: string, message: string) => {
			confirmCalls.push([title, message]);
			return confirmAnswer;
		} },
	} as unknown as ExtensionContext;
});

afterEach(() => rmSync(root, { recursive: true, force: true }));

function script(name: string, body: string): HookEntry {
	writeFileSync(path.join(root, name), `#!/bin/bash\n${body}\n`);
	return { tool: "bash", claudeTool: "Bash", command: name };
}

function decision(kind: string, reason?: string): string {
	return `printf '%s\\n' '${JSON.stringify({ hookSpecificOutput: { permissionDecision: kind, ...(reason === undefined ? {} : { permissionDecisionReason: reason }) } })}'`;
}

function handler(config: HookConfig, options?: { timeoutMs?: number }, register = createClaudeHooks(root, config, options)): Handler {
	let captured: Handler | undefined;
	register({ on: (event: string, callback: Handler) => {
		if (event === "tool_call") captured = callback;
	} } as unknown as ExtensionAPI);
	if (!captured) throw new Error("tool_call handler not registered");
	return captured;
}

function call(hook: Handler, input: Record<string, unknown> = { command: "echo hello" }, toolName = "bash") {
	return hook({ toolName, toolCallId: "call-7", input }, ctx);
}

test("unmatched tools never spawn hooks", async () => {
	const entry = script("marker.sh", 'touch "$CLAUDE_PLUGIN_ROOT/marker"');
	const hook = handler({ PreToolUse: [{ ...entry, tool: "read" }] });
	expect(await call(hook)).toBeUndefined();
	expect(existsSync(path.join(root, "marker"))).toBe(false);
});

test("empty output allows, passing Claude stdin, env, and resolved cwd", async () => {
	const entry = script("capture.sh", 'cat > "$CLAUDE_PLUGIN_ROOT/stdin.json"\nprintf "%s\\n%s\\n" "$CLAUDE_PLUGIN_ROOT" "$CLAUDE_PROJECT_DIR" > "$CLAUDE_PLUGIN_ROOT/env.txt"');
	const hook = handler({ PreToolUse: [entry] });
	mkdirSync(path.join(cwd, "sub"));
	const absolute = path.join(root, "absolute");
	mkdirSync(absolute);
	for (const [inputCwd, resolved] of [["sub", path.join(cwd, "sub")], [absolute, absolute], ["/", cwd], ["~", homedir()]]) {
		const input = { command: "echo hello", cwd: inputCwd };
		expect(await call(hook, input)).toBeUndefined();
		expect(JSON.parse(readFileSync(path.join(root, "stdin.json"), "utf8"))).toEqual({
			session_id: "session-42", hook_event_name: "PreToolUse", tool_name: "Bash",
			tool_input: input, tool_use_id: "call-7", cwd: resolved,
		});
		expect(readFileSync(path.join(root, "env.txt"), "utf8")).toBe(`${root}\n${cwd}\n`);
	}
});

test("nonexistent cwd blocks before running hooks", async () => {
	const hook = handler({ PreToolUse: [script("marker.sh", 'touch "$CLAUDE_PLUGIN_ROOT/marker"')] });
	expect(await call(hook, { command: "pwd", cwd: "not-here" })).toEqual({
		block: true, reason: "sample: cannot resolve the bash cwd (not-here); use a plain absolute or relative path.",
	});
	expect(existsSync(path.join(root, "marker"))).toBe(false);
});

test("JSON allow allows; JSON deny stops before later hooks, with a fallback reason", async () => {
	const allow = script("allow.sh", decision("allow"));
	const deny = script("deny.sh", decision("deny", "policy says no"));
	const later = script("later.sh", 'touch "$CLAUDE_PLUGIN_ROOT/marker"');
	expect(await call(handler({ PreToolUse: [allow] }))).toBeUndefined();
	expect(await call(handler({ PreToolUse: [allow, deny, later] }))).toEqual({ block: true, reason: "policy says no" });
	expect(existsSync(path.join(root, "marker"))).toBe(false);
	expect(await call(handler({ PreToolUse: [script("no-reason.sh", decision("deny"))] }))).toEqual({
		block: true, reason: "sample hook no-reason.sh denied this call.",
	});
});

test("JSON ask prompts after hooks; accepted, declined, and headless paths", async () => {
	const hook = handler({ PreToolUse: [script("ask.sh", decision("ask", "check with user"))] });
	expect(await call(hook, { command: "echo hello" })).toBeUndefined();
	expect(confirmCalls).toEqual([["Confirm command", "check with user\n\necho hello"]]);
	confirmAnswer = false;
	expect(await call(hook, { timeout: 4 })).toEqual({ block: true, reason: "Not confirmed by the user. check with user" });
	expect(confirmCalls[1]).toEqual(["Confirm command", `check with user\n\n${JSON.stringify({ timeout: 4 })}`]);
	ctx = { ...ctx, hasUI: false } as ExtensionContext;
	expect(await call(hook)).toEqual({ block: true, reason: "check with user Blocked: nobody can confirm it in this session." });
	expect(confirmCalls).toHaveLength(2);
	expect(await call(handler({ PreToolUse: [script("ask-default.sh", decision("ask"))] }))).toEqual({
		block: true, reason: "sample hook ask-default.sh asks for confirmation. Blocked: nobody can confirm it in this session.",
	});
});

test("a later deny overrides an earlier ask, without prompting", async () => {
	const hook = handler({ PreToolUse: [script("ask.sh", decision("ask", "ask first")), script("deny.sh", decision("deny", "deny second"))] });
	expect(await call(hook)).toEqual({ block: true, reason: "deny second" });
	expect(confirmCalls).toEqual([]);
});

test("exit 2 uses stderr, not JSON stdout", async () => {
	const hook = handler({ PreToolUse: [script("stop.sh", `${decision("deny", "wrong reason")}\necho stop >&2\nexit 2`)] });
	expect(await call(hook)).toEqual({ block: true, reason: "stop" });
	expect(await call(handler({ PreToolUse: [script("silent-stop.sh", "exit 2")] }))).toEqual({
		block: true, reason: "sample hook silent-stop.sh blocked this call.",
	});
});

test("all malformed, unknown, and failed outcomes block", async () => {
	for (const [name, body] of [
		["exit-one.sh", "exit 1"], ["not-json.sh", "echo 'not json'"],
		["no-decision.sh", "echo '{}'"], ["maybe.sh", decision("maybe")],
	]) {
		const result = await call(handler({ PreToolUse: [script(name, body)] })) as { block: boolean; reason: string };
		expect(result.block).toBe(true);
		expect(result.reason).toContain("failed");
	}
	const result = await call(handler({ PreToolUse: [{ tool: "bash", claudeTool: "Bash", command: "missing.sh" }] })) as { block: boolean; reason: string };
	expect(result.reason).toContain("failed");
});

test("timeout kills the hook process group and returns promptly", async () => {
	const hook = handler({ PreToolUse: [script("linger.sh", 'sleep 30 & echo $! > "$CLAUDE_PLUGIN_ROOT/marker"; wait')] }, { timeoutMs: 200 });
	const start = performance.now();
	const result = await call(hook) as { block: boolean; reason: string };
	expect(result.reason).toContain("failed");
	expect(performance.now() - start).toBeLessThan(2000);
	const pid = readFileSync(path.join(root, "marker"), "utf8").trim();
	let stat = "";
	// This integration check observes a real OS child disappearing after SIGKILL; fake timers cannot drive ps.
	const deadline = performance.now() + 1000;
	do {
		const ps = Bun.spawnSync(["ps", "-o", "stat=", "-p", pid]);
		stat = ps.stdout.toString().trim();
		if (!stat || stat.startsWith("Z")) break;
		await Bun.sleep(25);
	} while (performance.now() < deadline);
	expect(stat === "" || stat.startsWith("Z")).toBe(true);
});

test("a child holding stdout open counts as a timeout", async () => {
	const hook = handler({ PreToolUse: [script("child.sh", "sleep 5 &")] }, { timeoutMs: 200 });
	const start = performance.now();
	const result = await call(hook) as { block: boolean; reason: string };
	expect(result.reason).toContain("failed");
	expect(performance.now() - start).toBeLessThan(2000);
});

test("a successful hook clears its timeout timer", async () => {
	const hook = handler({ PreToolUse: [script("fast.sh", "exit 0")] }, { timeoutMs: 100 });
	expect(await call(hook)).toBeUndefined();
	// Deliberately let Bun's real timer fire if the extension forgot to clear it.
	await Bun.sleep(300);
});

test("a hook exiting without reading large stdin does not cause EPIPE", async () => {
	const hook = handler({ PreToolUse: [script("ignore-stdin.sh", "exit 0")] });
	expect(await call(hook, { command: "a".repeat(1024 * 1024) })).toBeUndefined();
});

async function copiedDefault(config?: unknown, packageContent?: string): Promise<Handler> {
	const plugin = path.join(root, `copy-${crypto.randomUUID()}`);
	const extensions = path.join(plugin, "extensions");
	mkdirSync(extensions, { recursive: true });
	copyFileSync(path.join(import.meta.dir, "..", "claude-hooks.ts"), path.join(extensions, "claude-hooks.ts"));
	if (config !== undefined) writeFileSync(path.join(extensions, "claude-hooks.json"), JSON.stringify(config));
	if (packageContent !== undefined) writeFileSync(path.join(plugin, "package.json"), packageContent);
	// Each import must load a distinct on-disk plugin copy to exercise import.meta.dir.
	const imported = await import(pathToFileURL(path.join(extensions, "claude-hooks.ts")).href);
	return handler({ PreToolUse: [] }, undefined, imported.default);
}

test("default export loads adjacent config at registration and uses package name and plugin root", async () => {
	const plugin = path.join(root, `copy-${crypto.randomUUID()}`);
	const extensions = path.join(plugin, "extensions");
	mkdirSync(extensions, { recursive: true });
	copyFileSync(path.join(import.meta.dir, "..", "claude-hooks.ts"), path.join(extensions, "claude-hooks.ts"));
	writeFileSync(path.join(plugin, "package.json"), '{"name":"sample"}');
	// The config is created after import to ensure it is read only when OMP registers the extension.
	const imported = await import(pathToFileURL(path.join(extensions, "claude-hooks.ts")).href);
	writeFileSync(path.join(extensions, "claude-hooks.json"), JSON.stringify({ PreToolUse: [{ tool: "bash", claudeTool: "Bash", command: "fail.sh" }] }));
	writeFileSync(path.join(plugin, "fail.sh"), 'printf "%s" "$CLAUDE_PLUGIN_ROOT" > "$CLAUDE_PLUGIN_ROOT/seen"; exit 1\n');
	const result = await call(handler({ PreToolUse: [] }, undefined, imported.default)) as { reason: string };
	expect(result.reason.startsWith("sample hook fail.sh failed:")).toBe(true);
	expect(realpathSync(readFileSync(path.join(plugin, "seen"), "utf8"))).toBe(realpathSync(plugin));
});

test("default export falls back to directory name when package metadata is missing or invalid", async () => {
	for (const metadata of [undefined, "not JSON", "{}", '{"name":42}']) {
		const hook = await copiedDefault({ PreToolUse: [{ tool: "bash", claudeTool: "Bash", command: "missing.sh" }] }, metadata);
		const result = await call(hook) as { reason: string };
		expect(result.reason).toMatch(/^copy-[\w-]+ hook missing\.sh failed:/);
	}
});

test("default export fails closed for missing or invalid config, but not for other tools", async () => {
	for (const config of [undefined, { PreToolUse: "not an array" }]) {
		const hook = await copiedDefault(config, '{"name":"sample"}');
		const result = await call(hook) as { block: boolean; reason: string };
		expect(result.block).toBe(true);
		expect(result.reason).toContain("sample: extensions/claude-hooks.json cannot be read (");
		expect(result.reason).toContain("The call is blocked; reinstall the plugin.");
		expect(await call(hook, { path: "README.md" }, "read")).toBeUndefined();
	}
});
