/**
 * Claude Code PreToolUse command-hook adapter. Matching hooks run concurrently;
 * deny outranks ask and allow, with the first configured denial reason winning.
 * Known differences from Claude Code:
 * - Stdin includes only session_id, hook_event_name, tool_name, tool_input,
 *   tool_use_id and cwd. tool_input is OMP's bash input (timeout in seconds,
 *   cwd, env, pty, async, etc.). In subagents session_id is the subagent's own
 *   session; agent_id and agent_type are absent.
 * - Only CLAUDE_PLUGIN_ROOT and CLAUDE_PROJECT_DIR are set; CLAUDE_PROJECT_DIR
 *   is ctx.cwd (the subagent worktree when isolated).
 * - Exit 0 with non-JSON output or JSON lacking a PreToolUse decision, any exit
 *   other than 0 or 2 (even with JSON output), timeouts, and output exceeding
 *   1 MiB per pipe block. Each hook gets 10 s; Claude Code defaults to 600 s
 *   and permits a timeout key, which the generator rejects.
 * - On exit 2, stderr supplies the reason even when stdout contains JSON.
 * - allow does not bypass OMP approval; a blocked ask reason reaches the model.
 * - defer, updatedInput, additionalContext, systemMessage, continue/stopReason
 *   and the top-level decision field are unsupported.
 * - POSIX only: timeouts and output overflows kill a process group.
 */
import { readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

export type HookEntry = { tool: string; claudeTool: string; command: string };
export type HookConfig = { PreToolUse: HookEntry[] };

// These are the OMP tools HOOK_TOOL_MAP in scripts/build_omp_edition.py maps hooks to; keep both lists equal.
const HOOKABLE_TOOLS = ["bash"];

type RunResult = { code: number; stdout: string; stderr: string } | { error: string };
type Outcome = { decision: "allow" } | { decision: "ask" | "deny"; reason: string };
const MAX_HOOK_OUTPUT_BYTES = 1024 * 1024;
const OUTPUT_TOO_LARGE = Symbol("output too large");

async function readHookOutput(stream: ReadableStream<Uint8Array>): Promise<string> {
	const reader = stream.getReader();
	const decoder = new TextDecoder();
	const chunks: string[] = [];
	let bytes = 0;
	try {
		while (true) {
			const { done, value } = await reader.read();
			if (done) break;
			bytes += value.byteLength;
			if (bytes > MAX_HOOK_OUTPUT_BYTES) throw OUTPUT_TOO_LARGE;
			chunks.push(decoder.decode(value, { stream: true }));
		}
		chunks.push(decoder.decode());
		return chunks.join("");
	} finally {
		reader.releaseLock();
	}
}

function pluginName(root: string): string {
	try {
		const value: unknown = JSON.parse(readFileSync(path.join(root, "package.json"), "utf8"));
		if (value && typeof value === "object" && "name" in value && typeof value.name === "string") return value.name;
	} catch {
		// The directory name is the fallback when the package metadata cannot be read.
	}
	return path.basename(root);
}

function hookCwd(inputCwd: unknown, projectCwd: string): string | undefined {
	let cwd = projectCwd;
	if (typeof inputCwd === "string" && inputCwd.length > 0) {
		const p = inputCwd.startsWith("~") ? path.join(homedir(), inputCwd.slice(1)) : inputCwd;
		if (/^\/+$/u.test(p)) cwd = projectCwd;
		else if (path.isAbsolute(p)) cwd = p;
		else cwd = path.resolve(projectCwd, p);
	}
	try {
		return statSync(cwd).isDirectory() ? cwd : undefined;
	} catch {
		return undefined;
	}
}

async function runHook(root: string, entry: HookEntry, projectCwd: string, stdin: Blob, timeoutMs: number): Promise<RunResult> {
	try {
		const proc = Bun.spawn(["bash", path.join(root, entry.command)], {
			stdin,
			stdout: "pipe",
			stderr: "pipe",
			cwd: projectCwd,
			env: { ...process.env, CLAUDE_PLUGIN_ROOT: root, CLAUDE_PROJECT_DIR: projectCwd },
			detached: true,
		});
		const { promise, resolve } = Promise.withResolvers<RunResult>();
		let settled = false;
		const timer = setTimeout(() => {
			if (settled) return;
			settled = true;
			try { process.kill(-proc.pid, "SIGKILL"); } catch { /* The process group may have already exited. */ }
			resolve({ error: "timeout" });
		}, timeoutMs);
		// The timer stays armed until the exit and both bounded pipe reads have settled.
		Promise.all([proc.exited, readHookOutput(proc.stdout), readHookOutput(proc.stderr)]).then(
			([code, stdout, stderr]) => {
				if (settled) return;
				settled = true;
				clearTimeout(timer);
				resolve({ code, stdout, stderr });
			},
			error => {
				if (settled) return;
				settled = true;
				clearTimeout(timer);
				try { process.kill(-proc.pid, "SIGKILL"); } catch { /* The process group may have already exited. */ }
				resolve({ error: error === OUTPUT_TOO_LARGE ? "output too large" : String(error) });
			},
		);
		return await promise;
	} catch (error) {
		return { error: String(error) };
	}
}

function outcome(result: RunResult, entry: HookEntry, plugin: string): Outcome {
	const failed = (why: string): Outcome => ({
		decision: "deny", reason: `${plugin} hook ${entry.command} failed: ${why}. The call is blocked.`,
	});
	if ("error" in result) return failed(result.error);
	if (result.code === 2) return {
		decision: "deny", reason: result.stderr.trim() || `${plugin} hook ${entry.command} blocked this call.`,
	};
	if (result.code !== 0) return failed(`exit code ${result.code}`);
	if (!result.stdout.trim()) return { decision: "allow" };
	try {
		const output: unknown = JSON.parse(result.stdout);
		if (output && typeof output === "object" && "hookSpecificOutput" in output) {
			const specific = output.hookSpecificOutput;
			if (specific && typeof specific === "object" && "permissionDecision" in specific) {
				const decision = specific.permissionDecision;
				if (decision === "allow") return { decision };
				if (decision === "ask" || decision === "deny") {
					const supplied = "permissionDecisionReason" in specific ? specific.permissionDecisionReason : undefined;
					const reason = typeof supplied === "string" && supplied.trim() ? supplied :
						decision === "deny" ? `${plugin} hook ${entry.command} denied this call.` :
						`${plugin} hook ${entry.command} asks for confirmation.`;
					return { decision, reason };
				}
			}
		}
	} catch {
		return failed("invalid JSON output");
	}
	return failed("missing or unknown PreToolUse decision");
}

export function createClaudeHooks(root: string, config: HookConfig, options?: { timeoutMs?: number }): (pi: ExtensionAPI) => void {
	const plugin = pluginName(root);
	const timeoutMs = options?.timeoutMs ?? 10_000;
	return pi => {
		pi.on("tool_call", async (event, ctx) => {
			const first = config.PreToolUse.findIndex(entry => entry.tool === event.toolName);
			if (first === -1) return undefined;
			const input = event.input as Record<string, unknown>;
			const cwd = hookCwd(input?.cwd, ctx.cwd);
			if (!cwd) return {
				block: true,
				reason: `${plugin}: cannot resolve the bash cwd (${String(input?.cwd)}); use a plain absolute or relative path.`,
			};
			const runs: Promise<Outcome>[] = [];
			for (let index = first; index < config.PreToolUse.length; index++) {
				const entry = config.PreToolUse[index]!;
				if (entry.tool !== event.toolName) continue;
				const stdin = new Blob([JSON.stringify({
					session_id: ctx.sessionManager.getSessionId(), hook_event_name: "PreToolUse",
					tool_name: entry.claudeTool, tool_input: event.input, tool_use_id: event.toolCallId, cwd,
				})]);
				runs.push(runHook(root, entry, ctx.cwd, stdin, timeoutMs).then(result => outcome(result, entry, plugin)));
			}
			let askReason: string | undefined;
			// All hooks finish before deciding; config order selects the first deny or ask.
			for (const result of await Promise.all(runs)) {
				if (result.decision === "deny") return { block: true, reason: result.reason };
				if (result.decision === "ask") askReason ??= result.reason;
			}
			if (askReason !== undefined) {
				if (!ctx.hasUI) return { block: true, reason: `${askReason} Blocked: nobody can confirm it in this session.` };
				const lines = [typeof input?.command === "string" ? input.command : JSON.stringify(event.input)];
				if (cwd !== ctx.cwd) lines.push(`cwd: ${cwd}`);
				if (input?.env && typeof input.env === "object" && Object.keys(input.env).length > 0) lines.push(`env: ${JSON.stringify(input.env)}`);
				if (await ctx.ui.confirm("Confirm command", `${askReason}\n\n${lines.join("\n")}`)) return undefined;
				return { block: true, reason: `Not confirmed by the user. ${askReason}` };
			}
			return undefined;
		});
	};
}

function validConfig(value: unknown): value is HookConfig {
	return Boolean(value && typeof value === "object" && "PreToolUse" in value &&
		Array.isArray(value.PreToolUse) && value.PreToolUse.length > 0 &&
		value.PreToolUse.every((entry: unknown) => entry && typeof entry === "object" &&
			"tool" in entry && typeof entry.tool === "string" && HOOKABLE_TOOLS.includes(entry.tool) &&
			"claudeTool" in entry && typeof entry.claudeTool === "string" && entry.claudeTool.length > 0 &&
			"command" in entry && typeof entry.command === "string" && entry.command.length > 0 &&
			!path.isAbsolute(entry.command) &&
			!entry.command.split(/[\\/]/).includes("..")));
}

export default function claudeHooks(pi: ExtensionAPI): void {
	const root = path.dirname(import.meta.dir);
	try {
		const parsed: unknown = JSON.parse(readFileSync(path.join(import.meta.dir, "claude-hooks.json"), "utf8"));
		if (!validConfig(parsed)) throw new Error("invalid config");
		createClaudeHooks(root, parsed)(pi);
	} catch (error) {
		const plugin = pluginName(root);
		pi.on("tool_call", event => {
			if (!HOOKABLE_TOOLS.includes(event.toolName)) return undefined;
			return {
				block: true,
				reason: `${plugin}: extensions/claude-hooks.json cannot be read (${String(error)}). The call is blocked; reinstall the plugin.`,
			};
		});
	}
}
