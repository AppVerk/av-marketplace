import { afterEach, beforeEach, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import * as zod from "@oh-my-pi/omptype/zod";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import planReviewExtension, { MAX_ROUNDS } from "../extensions/plan-review";

type Hook = (event: { toolName?: string; input?: unknown }, ctx: ExtensionContext) => Promise<unknown>;
type ToolResult = { content: { type: string; text: string }[] };
type Tool = {
	execute: (id: string, params: { title: string }, signal: AbortSignal | undefined, onUpdate: undefined, ctx: ExtensionContext) => Promise<ToolResult>;
};
type Blocked = { block: boolean; reason: string };

const CONCERN = '```json\n{"findings": [{"severity": "concern", "location": "Task 1", "issue": "No test covers the change.", "fix": "Add a test."}]}\n```';
const NIT_ONLY = 'Done.\n{"findings": [{"severity": "nit", "location": "Summary", "issue": "Wording.", "fix": ""}]}';

let root: string;
let planPath: string;
let ctx: ExtensionContext;
let hooks: Map<string, Hook>;
let tool: Tool;
let notifications: { message: string; level: string }[];
let answers: { text: string; code?: number }[];
let reviewerCalls: number;

beforeEach(() => {
	root = mkdtempSync(join(tmpdir(), "plan-review-"));
	mkdirSync(join(root, "artifacts", "local"), { recursive: true });
	planPath = join(root, "artifacts", "local", "feature-plan.md");
	writeFileSync(planPath, "# Feature plan\n\nChange the code.\n");
	notifications = [];
	answers = [];
	reviewerCalls = 0;
	ctx = {
		cwd: root,
		sessionManager: {
			getBranch: () => [{ type: "mode_change", mode: "plan" }],
			getSessionId: () => "test-session",
			getArtifactsDir: () => join(root, "artifacts"),
		},
		ui: { notify: (message: string, level: string) => notifications.push({ message, level }) },
	} as unknown as ExtensionContext;
	hooks = new Map();
	planReviewExtension({
		zod,
		on: (name: string, handler: Hook) => hooks.set(name, handler),
		registerTool: (definition: Tool) => {
			tool = definition;
		},
		exec: async () => {
			reviewerCalls++;
			const answer = answers.shift();
			if (!answer) throw new Error("Unexpected reviewer call");
			// `omp -p --mode json` ends with an `agent_end` event carrying the whole transcript.
			const assistant = {
				role: "assistant",
				provider: "openai-codex",
				model: "gpt-6-astra",
				content: [
					{ type: "thinking", thinking: "Checking the plan." },
					{ type: "text", text: answer.text },
				],
			};
			const stdout = [{ type: "agent_start" }, { type: "agent_end", messages: [{ role: "user", content: [] }, assistant] }]
				.map(event => JSON.stringify(event))
				.join("\n");
			return { stdout, stderr: "reviewer failed", code: answer.code ?? 0, killed: false };
		},
	} as unknown as ExtensionAPI);
});

afterEach(() => rmSync(root, { recursive: true, force: true }));

function propose(title = "feature"): Promise<unknown> {
	const hook = hooks.get("tool_call");
	if (!hook) throw new Error("Missing tool_call hook");
	return hook({ toolName: "write", input: { path: "xd://propose", content: title } }, ctx);
}

async function review(title = "feature"): Promise<string> {
	const result = await tool.execute("call", { title }, undefined, undefined, ctx);
	return result.content[0].text;
}

test("xd://propose blocks an unreviewed plan and leaves other writes alone", async () => {
	const blocked = (await propose()) as Blocked;
	expect(blocked.block).toBe(true);
	expect(blocked.reason).toContain('write {"title": "feature"} to xd://plan_review');

	const hook = hooks.get("tool_call");
	expect(await hook?.({ toolName: "write", input: { path: "README.md", content: "feature" } }, ctx)).toBeUndefined();
});

test("a title that names no plan file is checked against the plan xd://propose falls back to", async () => {
	// OMP resolves an unusable title to the newest *plan.md; the gate must judge that same file.
	expect(((await propose("feature/Rename the script")) as Blocked).block).toBe(true);

	answers.push({ text: '{"findings": []}' });
	expect(await review("unrelated title")).toContain("Plan review of local://feature-plan.md");
	expect(await propose("feature/Rename the script")).toBeUndefined();
});

test("requested changes keep the plan blocked until a review approves its revised text", async () => {
	answers.push({ text: CONCERN }, { text: NIT_ONLY });

	const first = await review();
	expect(first).toContain("by openai-codex/gpt-6-astra, round 1 of 3: changes requested");
	expect(first).toContain("- [concern] Task 1: No test covers the change. Fix: Add a test.");
	expect(((await propose()) as Blocked).reason).toContain("has not changed since");

	writeFileSync(planPath, "# Feature plan\n\nChange the code and add a test.\n");
	expect(((await propose()) as Blocked).reason).toContain("changed since its last review");

	const second = await review();
	expect(second).toContain("round 2 of 3: approved");
	expect(second).toContain("- [nit] Summary: Wording.");
	expect(await propose()).toBeUndefined();

	writeFileSync(planPath, "# Feature plan\n\nSomething else entirely.\n");
	expect(((await propose()) as Blocked).block).toBe(true);
});

test("a review that cannot run lets that plan text through with a warning", async () => {
	answers.push({ text: "", code: 1 });
	expect(await review()).toContain("exited with code 1: reviewer failed");
	expect(notifications.at(-1)?.level).toBe("warning");
	expect(await propose()).toBeUndefined();

	writeFileSync(planPath, "# Feature plan\n\nRevised.\n");
	answers.push({ text: "I think the plan is fine." });
	expect(await review()).toContain("not the expected JSON");
	expect(await propose()).toBeUndefined();
});

test("after the last round the plan goes to approval with a warning and no further review runs", async () => {
	for (let round = 1; round <= MAX_ROUNDS; round++) {
		writeFileSync(planPath, `# Feature plan\n\nRevision ${round}.\n`);
		answers.push({ text: CONCERN });
		expect(await review()).toContain(`round ${round} of ${MAX_ROUNDS}: changes requested`);
	}
	expect(await review()).toContain(`All ${MAX_ROUNDS} plan review rounds`);
	expect(reviewerCalls).toBe(MAX_ROUNDS);

	expect(await propose()).toBeUndefined();
	expect(notifications.at(-1)).toEqual(expect.objectContaining({ level: "warning" }));
});
