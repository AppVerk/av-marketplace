import { afterEach, beforeEach, expect, test, vi } from "bun:test";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import * as zod from "@oh-my-pi/omptype/zod";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import { USER_INTERRUPT_LABEL } from "@oh-my-pi/pi-coding-agent/session/messages";
import planReviewExtension, { MAX_ROUNDS } from "../extensions/plan-review";

type Hook = (event: { toolName?: string; input?: unknown }, ctx: ExtensionContext) => Promise<unknown>;
type ToolResult = { content: { type: string; text: string }[] };
type Tool = {
	execute: (id: string, params: { title: string }, signal: AbortSignal | undefined, onUpdate: ((update: ToolResult) => void) | undefined, ctx: ExtensionContext) => Promise<ToolResult>;
};
type Blocked = { block: boolean; reason: string };

const CONCERN = '```json\n{"findings": [{"severity": "concern", "location": "Task 1", "issue": "No test covers the change.", "fix": "Add a test."}]}\n```';
const BLOCKER = '{"findings": [{"severity": "blocker", "location": "Task 2", "issue": "The script it runs does not exist.", "fix": "Name the existing script."}, {"severity": "concern", "location": "Task 1", "issue": "No test covers the change.", "fix": "Add a test."}, {"severity": "nit", "location": "Summary", "issue": "Wording.", "fix": ""}]}';
const CONCERN_AND_NIT = '{"findings": [{"severity": "concern", "location": "Task 1", "issue": "No test covers\\nthe change.", "fix": "Add a test."}, {"severity": "nit", "location": "Summary", "issue": "Wording.", "fix": ""}]}';
const NIT_ONLY = 'Done.\n{"findings": [{"severity": "nit", "location": "Summary", "issue": "Wording.", "fix": ""}]}';

let root: string;
let planPath: string;
let ctx: ExtensionContext;
let hooks: Map<string, Hook>;
let tool: Tool;
let notifications: { message: string; level: string }[];
let answers: { text: string; code?: number; killed?: boolean }[];
let reviewerCalls: number;
let reviewerPrompts: string[];
let duringReview: (() => void | Promise<void>) | undefined;

beforeEach(() => {
	root = mkdtempSync(join(tmpdir(), "plan-review-"));
	mkdirSync(join(root, "artifacts", "local"), { recursive: true });
	planPath = join(root, "artifacts", "local", "feature-plan.md");
	writeFileSync(planPath, "# Feature plan\n\nChange the code.\n");
	notifications = [];
	answers = [];
	reviewerCalls = 0;
	reviewerPrompts = [];
	duringReview = undefined;
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
		exec: async (_command: string, args: string[], options?: { signal?: AbortSignal }) => {
			reviewerCalls++;
			reviewerPrompts.push(args.at(-1) ?? "");
			await duringReview?.();
			if (options?.signal?.aborted) return { stdout: "", stderr: "", code: -1, killed: true };
			const answer = answers.shift();
			if (!answer) throw new Error("Unexpected reviewer call");
			if (answer.killed) return { stdout: "", stderr: "", code: -1, killed: true };
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

afterEach(() => {
	vi.useRealTimers();
	rmSync(root, { recursive: true, force: true });
});

function propose(title = "feature"): Promise<unknown> {
	const hook = hooks.get("tool_call");
	if (!hook) throw new Error("Missing tool_call hook");
	return hook({ toolName: "write", input: { path: "xd://propose", content: title } }, ctx);
}

async function review(title = "feature"): Promise<string> {
	const result = await tool.execute("call", { title }, undefined, undefined, ctx);
	return result.content[0].text;
}

function useCwdPlan(content: string): string {
	rmSync(planPath);
	const path = join(root, "PLAN.md");
	writeFileSync(path, content);
	const sessionManager = ctx.sessionManager as unknown as { getBranch: () => unknown[] };
	sessionManager.getBranch = () => [{ type: "mode_change", mode: "plan", data: { planFilePath: "PLAN.md" } }];
	return path;
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
	answers.push({ text: BLOCKER }, { text: NIT_ONLY });

	const first = await review();
	expect(first).toContain("by openai-codex/gpt-6-astra, round 1 of 3: changes requested");
	expect(first).toContain("- [blocker] Task 2: The script it runs does not exist. Fix: Name the existing script.");
	expect(readFileSync(planPath, "utf8")).not.toContain("## Open review findings");
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

test("a review with concerns and no blockers approves the plan and lists the concerns in the plan file", async () => {
	answers.push({ text: CONCERN_AND_NIT });
	const result = await review();
	expect(result).toContain(`round 1 of ${MAX_ROUNDS}: approved with open concerns.`);
	expect(result).toContain("- [nit] Summary: Wording.");
	expect(result).toContain('"## Open review findings" section');
	const plan = readFileSync(planPath, "utf8");
	expect(plan).toStartWith("# Feature plan\n\nChange the code.\n\n## Open review findings\n\nPlan Review (openai-codex/gpt-6-astra, round 1 of 3) found no blockers.");
	expect(plan).toEndWith("\n\n- [concern] Task 1: No test covers the change. Fix: Add a test.\n");
	expect(plan).not.toContain("[nit]");
	expect(await propose()).toBeUndefined();

	// An edit of the plugin's section is an edit of the plan: it needs a new review.
	writeFileSync(planPath, `${plan}Edited.\n`);
	expect(((await propose()) as Blocked).reason).toContain("changed since its last review");
});

test("every review removes the previous open findings section before the reviewer reads the plan, and keeps fenced headings", async () => {
	const fenced = "```markdown\n## Open review findings\n```\n";
	writeFileSync(planPath, `# Feature plan\n\nChange the code.\n\n${fenced}`);
	answers.push({ text: CONCERN }, { text: NIT_ONLY });
	await review();
	expect(readFileSync(planPath, "utf8")).toContain("- [concern] Task 1: No test covers the change.");

	writeFileSync(planPath, readFileSync(planPath, "utf8").replace("Change the code.", "Change the code and add a test."));
	expect(await review()).toContain(`round 2 of ${MAX_ROUNDS}: approved.`);
	expect(reviewerPrompts[1]).toContain(fenced);
	expect(reviewerPrompts[1]).not.toContain("- [concern]");
	expect(readFileSync(planPath, "utf8")).toBe(`# Feature plan\n\nChange the code and add a test.\n\n${fenced}`);
	expect(await propose()).toBeUndefined();
});

test("a plan edited while the review runs keeps the edit and needs a new review", async () => {
	duringReview = () => writeFileSync(planPath, "# Feature plan\n\nEdited during the review.\n");
	answers.push({ text: CONCERN });
	expect(await review()).toContain("changed while the review ran");
	expect(readFileSync(planPath, "utf8")).toBe("# Feature plan\n\nEdited during the review.\n");
	expect(((await propose()) as Blocked).reason).toContain("changed since its last review");
});

test("a plan outside the session's local:// directory is reviewed as it is and never written", async () => {
	const content = "# Feature plan\n\nChange the code.\n\n## Open review findings\n\nWritten by hand.\n";
	const path = useCwdPlan(content);
	answers.push({ text: CONCERN });
	const result = await review();
	expect(result).toContain("Plan review of PLAN.md by openai-codex/gpt-6-astra, round 1 of 3: approved with open concerns.");
	expect(result).toContain("only into plan files stored in this session's local:// directory. Tell the user about them");
	expect(reviewerPrompts[0]).toContain("Written by hand.");
	expect(readFileSync(path, "utf8")).toBe(content);
	expect(await propose()).toBeUndefined();
});

test("after the last round, the agent hands the findings of a plan outside the session's local:// directory to the user", async () => {
	const path = useCwdPlan("# Feature plan\n\nRevision 0.\n");
	let last = "";
	for (let round = 1; round <= MAX_ROUNDS; round++) {
		writeFileSync(path, `# Feature plan\n\nRevision ${round}.\n`);
		answers.push({ text: BLOCKER });
		last = await review();
	}
	expect(last).toContain(`round ${MAX_ROUNDS} of ${MAX_ROUNDS}: changes requested`);
	expect(last).toContain("does not list these findings");
	expect(last).toContain("Tell the user about the blockers and concerns above");
	expect(readFileSync(path, "utf8")).toBe(`# Feature plan\n\nRevision ${MAX_ROUNDS}.\n`);
});

test("a session-local plan that links outside the session's local:// directory is never written", async () => {
	const outside = join(root, "outside-plan.md");
	writeFileSync(outside, "# Feature plan\n\nChange the code.\n");
	rmSync(planPath);
	symlinkSync(outside, planPath);
	answers.push({ text: CONCERN });
	expect(await review()).toContain("only into plan files stored in this session's local:// directory");
	expect(readFileSync(outside, "utf8")).toBe("# Feature plan\n\nChange the code.\n");
	expect(await propose()).toBeUndefined();
});

test("a plan swapped for a symlink while the review runs is never written through it", async () => {
	const outside = join(root, "outside-plan.md");
	writeFileSync(outside, "# Feature plan\n\nChange the code.\n");
	duringReview = () => {
		rmSync(planPath);
		symlinkSync(outside, planPath);
	};
	answers.push({ text: CONCERN });
	expect(await review()).toContain("changed while the review ran");
	expect(readFileSync(outside, "utf8")).toBe("# Feature plan\n\nChange the code.\n");
	expect(((await propose()) as Blocked).reason).toContain("changed since its last review");
});

test("a review whose findings cannot be written still uses its round and hands the concerns to the agent", async () => {
	chmodSync(planPath, 0o444);
	answers.push({ text: CONCERN });
	const result = await review();
	expect(result).toContain(`round 1 of ${MAX_ROUNDS}: approved with open concerns.`);
	expect(result).toContain("the plugin could not write them");
	expect(readFileSync(planPath, "utf8")).toBe("# Feature plan\n\nChange the code.\n");
	expect(await propose()).toBeUndefined();

	chmodSync(planPath, 0o644);
	writeFileSync(planPath, "# Feature plan\n\nRevised.\n");
	answers.push({ text: NIT_ONLY });
	expect(await review()).toContain(`round 2 of ${MAX_ROUNDS}: approved.`);
});

test("review progress updates immediately and every 15 seconds, then stops when the review ends", async () => {
	vi.useFakeTimers();
	const updates: string[] = [];
	let start!: () => void;
	let release!: () => void;
	const started = new Promise<void>(resolve => {
		start = resolve;
	});
	const pending = new Promise<void>(resolve => {
		release = resolve;
	});
	duringReview = () => {
		start();
		return pending;
	};
	answers.push({ text: '{"findings": []}' });
	const result = tool.execute("call", { title: "feature" }, undefined, update => updates.push(update.content[0].text), ctx);

	await started;
	vi.advanceTimersByTime(15_000);
	vi.advanceTimersByTime(15_000);
	release();
	await result;

	const updateCount = updates.length;
	vi.advanceTimersByTime(60_000);
	expect(updates.map(text => text.match(/^Plan review round 1\/3: (\d+:\d\d) elapsed/)?.[1])).toEqual(["0:00", "0:15", "0:30"]);
	for (const text of updates) expect(text.split("\n")[0].length).toBeLessThan(70);
	expect(updates).toHaveLength(updateCount);
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

test("a reviewer run that fails, times out or answers badly uses one of the rounds", async () => {
	const failures = [
		{ answer: { text: "", code: 1 }, reason: "exited with code 1" },
		{ answer: { text: "", killed: true }, reason: "did not finish within 15 minutes" },
		{ answer: { text: "I think the plan is fine." }, reason: "not the expected JSON" },
	];
	for (const [index, { answer, reason }] of failures.entries()) {
		const round = index + 1;
		writeFileSync(planPath, `# Feature plan\n\nRevision ${round}.\n`);
		answers.push(answer);
		const result = await review();
		expect(result).toContain(`round ${round} of ${MAX_ROUNDS}`);
		expect(result).toContain(reason);
	}

	writeFileSync(planPath, "# Feature plan\n\nRevision 4.\n");
	expect(await review()).toContain(`All ${MAX_ROUNDS} plan review rounds`);
	expect(reviewerCalls).toBe(MAX_ROUNDS);
	expect(await propose()).toBeUndefined();
	expect(notifications.at(-1)?.message).toContain(`all ${MAX_ROUNDS} rounds are used`);
});

test("an abort with the user-interrupt reason lets that plan text through until the plan changes", async () => {
	const controller = new AbortController();
	duringReview = () => controller.abort(USER_INTERRUPT_LABEL);
	await expect(tool.execute("call", { title: "feature" }, controller.signal, undefined, ctx)).rejects.toThrow(
		"Plan review cancelled by the user",
	);
	expect(notifications.at(-1)?.level).toBe("warning");
	expect(await propose()).toBeUndefined();

	duringReview = undefined;
	writeFileSync(planPath, "# Feature plan\n\nRevised after cancelling.\n");
	expect(((await propose()) as Blocked).reason).toContain("changed since its last review");
	answers.push({ text: '{"findings": []}' });
	expect(await review()).toContain(`round 1 of ${MAX_ROUNDS}: approved`);
});

test("an abort without the user-interrupt reason keeps the plan blocked", async () => {
	const controller = new AbortController();
	duringReview = () => controller.abort();
	await expect(tool.execute("call", { title: "feature" }, controller.signal, undefined, ctx)).rejects.toThrow(
		/^Plan review cancelled\.$/,
	);
	expect(notifications).toEqual([]);
	expect(((await propose()) as Blocked).reason).toContain("This plan has not been reviewed");
});

test("after the last round its open blockers and concerns go to approval in the plan file, with a warning and no further review", async () => {
	for (let round = 1; round <= MAX_ROUNDS; round++) {
		writeFileSync(planPath, `# Feature plan\n\nRevision ${round}.\n`);
		answers.push({ text: BLOCKER });
		const result = await review();
		expect(result).toContain(`round ${round} of ${MAX_ROUNDS}: changes requested`);
		if (round === MAX_ROUNDS) expect(result).toContain('"## Open review findings" section');
	}
	const plan = readFileSync(planPath, "utf8");
	expect(plan).toContain("still found blockers in its last round");
	expect(plan).toContain("- [blocker] Task 2: The script it runs does not exist. Fix: Name the existing script.");
	expect(plan).toContain("- [concern] Task 1: No test covers the change. Fix: Add a test.");
	expect(plan).not.toContain("[nit]");
	expect(await review()).toContain(`All ${MAX_ROUNDS} plan review rounds`);
	expect(reviewerCalls).toBe(MAX_ROUNDS);

	expect(await propose()).toBeUndefined();
	expect(notifications.at(-1)).toEqual(expect.objectContaining({ level: "warning" }));
});

test("a session switch clears used rounds and reviews, so the next plan is reviewed again", async () => {
	for (let round = 1; round <= MAX_ROUNDS; round++) {
		writeFileSync(planPath, `# Feature plan\n\nRevision ${round}.\n`);
		answers.push({ text: BLOCKER });
		expect(await review()).toContain(`round ${round} of ${MAX_ROUNDS}: changes requested`);
	}

	const hook = hooks.get("session_switch");
	if (!hook) throw new Error("Missing session_switch hook");
	await hook({}, ctx);

	expect(await propose()).toEqual(expect.objectContaining({ block: true }));
	answers.push({ text: NIT_ONLY });
	expect(await review()).toContain(`round 1 of ${MAX_ROUNDS}: approved`);
	expect(reviewerCalls).toBe(MAX_ROUNDS + 1);
});
