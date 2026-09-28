import { afterEach, beforeEach, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import approvedPlanPrompt from "@oh-my-pi/pi-coding-agent/prompts/system/plan-mode-approved" with { type: "text" };
import deliveryExtension from "../extensions/delivery";

type Hook = (event: { toolName?: string; input?: unknown; prompt?: string; systemPrompt?: string[] }, ctx: ExtensionContext) => Promise<unknown>;

const invalidPlan = `# Plan

### Task 1: Missing files
Do the work without listing files.
`;
const validPlan = `# Plan

### Task 1: Update docs
**Commit:** docs: update guide
**Files:**
- Modify: \`README.md\`

Update the guide.
`;
let root: string;
let artifacts: string;
let ctx: ExtensionContext;
let hooks: Map<string, Hook>;
let notifications: string[];
let execute: ExtensionAPI["exec"];
let notificationLevels: string[];

beforeEach(() => {
	root = mkdtempSync(join(tmpdir(), "delivery-hooks-"));
	artifacts = join(root, "artifacts");
	mkdirSync(join(artifacts, "local"), { recursive: true });
	execFileSync("git", ["init", "-q", root]);
	writeFileSync(join(root, "README.md"), "# Guide\n");
	notifications = [];
	notificationLevels = [];
	ctx = {
		cwd: root,
		sessionManager: {
			getBranch: () => [],
			getSessionId: () => "test-session",
			getArtifactsDir: () => artifacts,
		},
		ui: { notify: (message: string, level: string) => { notifications.push(message); notificationLevels.push(level); } },
	} as unknown as ExtensionContext;
	execute = async (command, args, options) => {
		const process = Bun.spawn([command, ...args], {
			cwd: options?.cwd ?? root,
			stdout: "pipe",
			stderr: "pipe",
		});
		const [stdout, stderr, code] = await Promise.all([
			new Response(process.stdout).text(),
			new Response(process.stderr).text(),
			process.exited,
		]);
		return { stdout, stderr, code, killed: false };
	};
	hooks = new Map();
	deliveryExtension({ on: (name: string, handler: Hook) => hooks.set(name, handler), exec: (...args) => execute(...args) } as unknown as ExtensionAPI);
});

afterEach(() => rmSync(root, { recursive: true, force: true }));

async function callHook(name: string, event: Parameters<Hook>[0]): Promise<unknown> {
	const hook = hooks.get(name);
	if (!hook) throw new Error(`Missing ${name} hook`);
	return hook(event, ctx);
}

test("xd://propose blocks an unroutable plan, including an uppercase XD scheme", async () => {
	writeFileSync(join(artifacts, "local", "feature-plan.md"), invalidPlan);
	const result = await callHook("tool_call", { toolName: "write", input: { path: "XD://propose", content: "feature" } }) as { block: boolean; reason: string };
	expect(result.block).toBe(true);
	expect(result.reason).toContain("Task 1");
	expect(result.reason).toContain("local://feature-plan.md");

	writeFileSync(join(artifacts, "local", "feature-plan.md"), validPlan);
	expect(await callHook("tool_call", { toolName: "write", input: { path: "xd://propose", content: "feature.md" } })).toBeUndefined();
});

test("xd://propose warns when the plan file is missing or the router fails, but allows the proposal", async () => {
	const event = { toolName: "write", input: { path: "xd://propose", content: "feature" } };
	expect(await callHook("tool_call", event)).toBeUndefined();
	expect(notifications[0]).toContain("Delivery plan check skipped: plan file not found");
	expect(notificationLevels[0]).toBe("warning");

	writeFileSync(join(artifacts, "local", "feature-plan.md"), Buffer.from([0xff]));
	expect(await callHook("tool_call", event)).toBeUndefined();
	expect(notifications[1]).toContain("Delivery plan check skipped:");
	expect(notifications[1]).toContain("route_task.py");
	expect(notificationLevels[1]).toBe("warning");
});

test("nonzero process codes do not accept a repository or a router result", async () => {
	const event = { toolName: "write", input: { path: "xd://propose", content: "feature" } };
	writeFileSync(join(artifacts, "local", "feature-plan.md"), invalidPlan);
	const realExec = execute;
	execute = async (command, args, options) => {
		const result = await realExec(command, args, options);
		return command === "python3" ? { ...result, code: 1 } : result;
	};
	expect(await callHook("tool_call", event)).toBeUndefined();
	expect(notifications[0]).toContain("Delivery plan check skipped: router failed");

	execute = async () => ({ stdout: root, stderr: "", code: 1, killed: false });
	expect(await callHook("tool_call", event)).toBeUndefined();
	expect(notifications).toHaveLength(1);
});

test("approved OMP prompt hands an existing task plan to delivery", async () => {
	const url = "local://feature-plan.md";
	writeFileSync(join(artifacts, "local", "feature-plan.md"), validPlan);
	const prompt = approvedPlanPrompt.replaceAll("{{planFilePath}}", url).replace("{{planContent}}", validPlan);
	const result = await callHook("before_agent_start", { prompt, systemPrompt: [] }) as { message: { customType: string; content: string } };
	expect(result.message.customType).toBe("delivery-run");
	expect(result.message.content).toContain(`PLAN_SOURCE: ${url}`);
	expect(result.message.content).toContain(`PLAN_FILE: ${join(artifacts, "local", "feature-plan.md")}`);
	expect(notifications).toContain("Delivery: 1 task(s) — starting the delivery run.");
});

test("approved task-free plan does not start delivery", async () => {
	const url = "local://research-plan.md";
	writeFileSync(join(artifacts, "local", "research-plan.md"), "# Research\nNo files change.\n");
	const prompt = approvedPlanPrompt.replaceAll("{{planFilePath}}", url).replace("{{planContent}}", "# Research");
	expect(await callHook("before_agent_start", { prompt, systemPrompt: [] })).toBeUndefined();
	expect(notifications).toEqual([]);
});

test("approval warns when the plan file is missing", async () => {
	const url = "local://gone-plan.md";
	const prompt = approvedPlanPrompt.replaceAll("{{planFilePath}}", url).replace("{{planContent}}", validPlan);
	expect(await callHook("before_agent_start", { prompt, systemPrompt: [] })).toBeUndefined();
	expect(notifications[0]).toContain("Delivery skipped: plan file not found for local://gone-plan.md");
	expect(notificationLevels[0]).toBe("warning");
});

test("approval warns when the router fails", async () => {
	const url = "local://feature-plan.md";
	writeFileSync(join(artifacts, "local", "feature-plan.md"), validPlan);
	const prompt = approvedPlanPrompt.replaceAll("{{planFilePath}}", url).replace("{{planContent}}", validPlan);
	const realExec = execute;
	execute = async (command, args, options) => {
		const result = await realExec(command, args, options);
		return command === "python3" ? { ...result, code: 1 } : result;
	};
	expect(await callHook("before_agent_start", { prompt, systemPrompt: [] })).toBeUndefined();
	expect(notifications[0]).toContain("Delivery skipped: plan check failed for local://feature-plan.md");
});

test("xd://propose blocks a plan whose only task heading is malformed", async () => {
	const badPlan = "# Plan\n\n### Task 1 - Docs\n**Files:**\n- Modify: `README.md`\n";
	writeFileSync(join(artifacts, "local", "bad-plan.md"), badPlan);
	const result = await callHook("tool_call", { toolName: "write", input: { path: "xd://propose", content: "bad" } }) as { block: boolean; reason: string };
	expect(result.block).toBe(true);
	expect(result.reason).toContain("Invalid task heading");
});

test("approval warns and skips a plan whose only task heading is malformed", async () => {
	const url = "local://bad-plan.md";
	const badPlan = "# Plan\n\n### Task 1 - Docs\n**Files:**\n- Modify: `README.md`\n";
	writeFileSync(join(artifacts, "local", "bad-plan.md"), badPlan);
	const prompt = approvedPlanPrompt.replaceAll("{{planFilePath}}", url).replace("{{planContent}}", badPlan);
	expect(await callHook("before_agent_start", { prompt, systemPrompt: [] })).toBeUndefined();
	expect(notifications[0]).toContain("has no valid task heading");
	expect(notifications[0]).toContain("Invalid task heading");
	expect(notificationLevels[0]).toBe("warning");
});
