import { afterEach, beforeEach, expect, test, vi } from "bun:test";
import { createHash } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
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
type SavedRecord = {
	version: string | null;
	title: string;
	url: string | null;
	round: number | null;
	startedAt: string;
	endedAt: string;
	outcome: "approve" | "approve-with-concerns" | "revise" | "unavailable" | "skipped" | "cancelled" | "exhausted" | "error";
	reason: string | null;
	reviewer: string | null;
	plan: { text: string; sha256: string } | null;
	answer: string | null;
	findings: { severity: "blocker" | "concern" | "nit"; location: string; issue: string; fix: string }[] | null;
	usage: unknown[] | null;
	proposeSha256: string | null;
};

const CONCERN = '```json\n{"findings": [{"severity": "concern", "location": "Task 1", "issue": "No test covers the change.", "fix": "Add a test."}]}\n```';
const BLOCKER = '{"findings": [{"severity": "blocker", "location": "Task 2", "issue": "The script it runs does not exist.", "fix": "Name the existing script."}, {"severity": "concern", "location": "Task 1", "issue": "No test covers the change.", "fix": "Add a test."}, {"severity": "nit", "location": "Summary", "issue": "Wording.", "fix": ""}]}';
const CONCERN_AND_NIT = '{"findings": [{"severity": "concern", "location": "Task 1", "issue": "No test covers\\nthe change.", "fix": "Add a test."}, {"severity": "nit", "location": "Summary", "issue": "Wording.", "fix": ""}]}';
const NIT_ONLY = 'Done.\n{"findings": [{"severity": "nit", "location": "Summary", "issue": "Wording.", "fix": ""}]}';
const USAGE = [
	{ input: 900, output: 40, cacheRead: 0, cacheWrite: 0, totalTokens: 940 },
	{ input: 300, output: 150, cacheRead: 900, cacheWrite: 0, totalTokens: 1350 },
];
const sha = (text: string) => createHash("sha256").update(text).digest("hex");
const VERSION = JSON.parse(readFileSync(join(import.meta.dir, "..", "package.json"), "utf8")).version;
const RECORDS_ON = "[plan-review]\nrecords = true\n";
// The interpreter behind `python3`, resolved once: version-manager shims add a long start-up to every call.
const PYTHON = Bun.spawnSync(["python3", "-c", "import sys; print(sys.executable)"]).stdout.toString().trim();

let root: string;
let planPath: string;
let ctx: ExtensionContext;
let hooks: Map<string, Hook>;
let tool: Tool;
let notifications: { message: string; level: string }[];
let answers: { text: string; stdout?: string; code?: number; killed?: boolean }[];
let reviewerCalls: number;
let reviewerPrompts: string[];
let duringReview: (() => void | Promise<void>) | undefined;
let abortedStdout: string;
let seenRecords: Set<string>;
let configHome: string;
let python: "real" | "missing";

function assistantMessage(content: unknown[], usage: unknown) {
	return { role: "assistant", provider: "openai-codex", model: "gpt-6-astra", content, usage };
}

function reviewerStdout(text: string): string {
	const toolTurn = assistantMessage([{ type: "toolCall", id: "read-1", name: "read", arguments: { path: "README.md" } }], USAGE[0]);
	const toolResult = { role: "toolResult", toolCallId: "read-1", content: [] };
	const finalTurn = assistantMessage([{ type: "thinking", thinking: "Checking the plan." }, { type: "text", text }], USAGE[1]);
	return [
		{ type: "agent_start" },
		{ type: "message_end", message: toolTurn },
		{ type: "message_end", message: toolResult },
		{ type: "message_end", message: finalTurn },
		{ type: "agent_end", messages: [{ role: "user", content: [] }, toolTurn, toolResult, finalTurn] },
	].map(event => JSON.stringify(event)).join("\n");
}

function continuedStdout(text: string): string {
	const toolTurn = assistantMessage([{ type: "toolCall", id: "read-1", name: "read", arguments: { path: "README.md" } }], USAGE[0]);
	const toolResult = { role: "toolResult", toolCallId: "read-1", content: [] };
	const finalTurn = assistantMessage([{ type: "thinking", thinking: "Checking the plan." }, { type: "text", text }], USAGE[1]);
	return [
		{ type: "agent_start" },
		{ type: "message_end", message: toolTurn },
		{ type: "message_end", message: toolResult },
		{ type: "agent_end", messages: [{ role: "user", content: [] }, toolTurn, toolResult] },
		{ type: "agent_start" },
		{ type: "message_end", message: finalTurn },
		{ type: "agent_end", messages: [finalTurn] },
	].map(event => JSON.stringify(event)).join("\n");
}

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
	abortedStdout = "";
	seenRecords = new Set();
	configHome = join(root, "config-home");
	mkdirSync(configHome);
	python = "real";
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
		exec: async (command: string, args: string[], options?: { cwd?: string; signal?: AbortSignal }) => {
			if (command === "python3") return runPython(args, options?.cwd);
			reviewerCalls++;
			reviewerPrompts.push(args.at(-1) ?? "");
			await duringReview?.();
			if (options?.signal?.aborted) return { stdout: abortedStdout, stderr: "", code: -1, killed: true };
			const answer = answers.shift();
			if (!answer) throw new Error("Unexpected reviewer call");
			if (answer.killed) return { stdout: "", stderr: "", code: -1, killed: true };
			return { stdout: answer.stdout ?? reviewerStdout(answer.text), stderr: "reviewer failed", code: answer.code ?? 0, killed: false };
		},
	} as unknown as ExtensionAPI);
});

afterEach(() => {
	vi.useRealTimers();
	rmSync(root, { recursive: true, force: true });
});

/** The records setting runs on the real python3 and reads only this test's user config home and repository. */
function runPython(args: string[], cwd: string | undefined) {
	if (python === "missing") throw new Error('Executable not found in $PATH: "python3"');
	const run = Bun.spawnSync([PYTHON, ...args], { cwd, env: { ...process.env, XDG_CONFIG_HOME: configHome } });
	return { stdout: run.stdout.toString(), stderr: run.stderr.toString(), code: run.exitCode ?? -1, killed: false };
}

function userConfig(table: string): void {
	mkdirSync(join(configHome, "av"), { recursive: true });
	writeFileSync(join(configHome, "av", "config.toml"), `version = 1\n\n${table}`);
}

function repositoryConfig(content: string): void {
	mkdirSync(join(root, ".av"), { recursive: true });
	writeFileSync(join(root, ".av", "config.toml"), content);
}

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

function newRecord(): SavedRecord {
	const dir = join(root, "artifacts", "plan-review");
	const names = (existsSync(dir) ? readdirSync(dir) : []).filter(name => !seenRecords.has(name));
	for (const name of names) seenRecords.add(name);
	expect(names).toHaveLength(1);
	return JSON.parse(readFileSync(join(dir, names[0]), "utf8"));
}

test("with records turned on, every review saves a record with the text sent to the reviewer, its raw answer, findings, usage and the hash the gate accepts", async () => {
	userConfig(RECORDS_ON);
	writeFileSync(planPath, "# Feature plan\n\nChange the code.\n\n## Open review findings\n\n- [concern] Old: stale.\n");
	answers.push({ text: BLOCKER });
	await review();
	const record = newRecord();
	const text = "# Feature plan\n\nChange the code.\n";
	expect(record).toMatchObject({
		version: VERSION,
		title: "feature",
		url: "local://feature-plan.md",
		round: 1,
		outcome: "revise",
		reason: null,
		reviewer: "openai-codex/gpt-6-astra",
		plan: { text, sha256: sha(text) },
		answer: BLOCKER,
		findings: [
			{ severity: "blocker", location: "Task 2", issue: "The script it runs does not exist.", fix: "Name the existing script." },
			{ severity: "concern", location: "Task 1", issue: "No test covers the change.", fix: "Add a test." },
			{ severity: "nit", location: "Summary", issue: "Wording.", fix: "" },
		],
		usage: USAGE,
		proposeSha256: sha(text),
	});
	expect(new Date(record.startedAt).toISOString()).toBe(record.startedAt);
	expect(new Date(record.endedAt).toISOString()).toBe(record.endedAt);
	expect(record.startedAt <= record.endedAt).toBe(true);
	expect(reviewerPrompts[0]).toContain(`<plan>\n${record.plan!.text}\n</plan>`);

	writeFileSync(planPath, "# Feature plan\n\nRevised.\n");
	answers.push({ text: CONCERN });
	await review();
	const revised = newRecord();
	expect(revised).toMatchObject({
		round: 2,
		outcome: "approve-with-concerns",
		answer: CONCERN,
		findings: [{ severity: "concern", location: "Task 1", issue: "No test covers the change.", fix: "Add a test." }],
		proposeSha256: sha(readFileSync(planPath, "utf8")),
	});
	expect(revised.proposeSha256).not.toBe(revised.plan!.sha256);
	expect(await propose()).toBeUndefined();
});

test("a record keeps the usage of every reviewer turn, also of turns before a continuation", async () => {
	userConfig(RECORDS_ON);
	answers.push({ text: "", stdout: continuedStdout('{"findings": []}') });
	expect(await review()).toContain(`round 1 of ${MAX_ROUNDS}: approved.`);
	expect(newRecord()).toMatchObject({
		outcome: "approve",
		usage: USAGE,
		answer: '{"findings": []}',
		reviewer: "openai-codex/gpt-6-astra",
	});
});

test("with records turned on, calls that end without a review still save one record each", async () => {
	userConfig(RECORDS_ON);
	const records: SavedRecord[] = [];
	answers.push({ text: "", code: 1 });
	await review();
	const failed = newRecord();
	records.push(failed);
	expect(failed).toMatchObject({
		outcome: "unavailable",
		round: 1,
		reason: expect.stringContaining("exited with code 1: reviewer failed"),
		reviewer: "openai-codex/gpt-6-astra",
		answer: "",
		usage: USAGE,
		findings: null,
		proposeSha256: failed.plan!.sha256,
	});

	writeFileSync(planPath, "# Feature plan\n\nRevision 2.\n");
	answers.push({ text: "", killed: true });
	await review();
	const timedOut = newRecord();
	records.push(timedOut);
	expect(timedOut).toMatchObject({
		outcome: "unavailable",
		round: 2,
		reason: expect.stringContaining("did not finish within 15 minutes"),
		reviewer: null,
		answer: null,
		usage: null,
	});

	const text = "# Feature plan\n\nRevision 3.\n";
	writeFileSync(planPath, text);
	abortedStdout = reviewerStdout("partial");
	let controller = new AbortController();
	duringReview = () => controller.abort(USER_INTERRUPT_LABEL);
	await expect(tool.execute("call", { title: "feature" }, controller.signal, undefined, ctx)).rejects.toThrow(
		"Plan review cancelled by the user",
	);
	const skipped = newRecord();
	records.push(skipped);
	expect(skipped).toMatchObject({
		outcome: "skipped",
		round: 3,
		plan: { text },
		proposeSha256: skipped.plan!.sha256,
		reviewer: "openai-codex/gpt-6-astra",
		answer: "partial",
		usage: USAGE,
		findings: null,
	});

	abortedStdout = "";
	controller = new AbortController();
	duringReview = () => controller.abort();
	await expect(tool.execute("call", { title: "feature" }, controller.signal, undefined, ctx)).rejects.toThrow(
		/^Plan review cancelled\.$/,
	);
	const cancelled = newRecord();
	records.push(cancelled);
	expect(cancelled).toMatchObject({
		outcome: "cancelled",
		round: 3,
		proposeSha256: null,
		answer: null,
		usage: null,
	});

	duringReview = undefined;
	answers.push({ text: "I think the plan is fine." });
	await review();
	const malformed = newRecord();
	records.push(malformed);
	expect(malformed).toMatchObject({
		outcome: "unavailable",
		round: 3,
		reason: expect.stringContaining("not the expected JSON"),
		answer: "I think the plan is fine.",
		findings: null,
	});

	expect(await review()).toContain(`All ${MAX_ROUNDS} plan review rounds`);
	const exhausted = newRecord();
	records.push(exhausted);
	expect(exhausted).toMatchObject({
		outcome: "exhausted",
		url: "local://feature-plan.md",
		round: null,
		plan: null,
	});

	rmSync(planPath);
	await expect(review()).rejects.toThrow("No plan file found");
	const missing = newRecord();
	records.push(missing);
	expect(missing).toMatchObject({
		outcome: "error",
		url: null,
	});
	expect(missing.reason).toStartWith('No plan file found for "feature".');
	for (const record of records) expect(record).toMatchObject({ title: "feature", version: VERSION });
});

test.each([
	"a file in place of the records directory",
	"a session without an artifacts directory",
])("a record that cannot be saved (%s) only warns: the review result and the gate stay the same", async (failure: string) => {
	userConfig(RECORDS_ON);
	if (failure === "a file in place of the records directory") {
		writeFileSync(join(root, "artifacts", "plan-review"), "");
	} else {
		const context = ctx as unknown as { localProtocolOptions: { getArtifactsDir: () => string; getSessionId: () => string } };
		context.localProtocolOptions = { getArtifactsDir: () => join(root, "artifacts"), getSessionId: () => "test-session" };
		const sessionManager = ctx.sessionManager as unknown as { getArtifactsDir: () => string | null };
		sessionManager.getArtifactsDir = () => null;
	}
	answers.push({ text: CONCERN });
	expect(await review()).toContain(`round 1 of ${MAX_ROUNDS}: approved with open concerns.`);
	expect(notifications).toEqual([
		expect.objectContaining({ level: "warning", message: expect.stringContaining("could not save its record") }),
	]);
	expect(await propose()).toBeUndefined();
});

test.each([
	"no configuration",
	"records = false in the user file",
	"a repository configuration without a [plan-review] table",
	"records = true but no python3 to read it",
])("records stay off with %s: a review saves none and warns about nothing", async (setup: string) => {
	if (setup === "records = false in the user file") userConfig("[plan-review]\nrecords = false\n");
	if (setup === "a repository configuration without a [plan-review] table") repositoryConfig('version = 1\n\n[code-review]\nafter_review = "none"\n');
	if (setup === "records = true but no python3 to read it") {
		userConfig(RECORDS_ON);
		python = "missing";
	}
	answers.push({ text: CONCERN });
	expect(await review()).toContain(`round 1 of ${MAX_ROUNDS}: approved with open concerns.`);
	expect(notifications).toEqual([]);
	expect(existsSync(join(root, "artifacts", "plan-review"))).toBe(false);
	expect(await propose()).toBeUndefined();
});

test("records = true in the repository's .av/config.toml turns records on too", async () => {
	repositoryConfig(`version = 1\n\n${RECORDS_ON}`);
	answers.push({ text: CONCERN });
	await review();
	expect(newRecord()).toMatchObject({ outcome: "approve-with-concerns", answer: CONCERN });
	expect(notifications).toEqual([]);
});

test.each([
	["a value that is not a boolean", '[plan-review]\nrecords = "yes"\n', "plan-review.records: expected true or false"],
	["a key the user file does not allow", "[plan-review]\nrecords = true\nrecord = true\n", "plan-review.record: not allowed in the user config"],
])("an invalid [plan-review] table (%s) turns records off with a warning; the review result and the gate stay the same", async (_case: string, table: string, problem: string) => {
	userConfig(table);
	answers.push({ text: CONCERN });
	expect(await review()).toContain(`round 1 of ${MAX_ROUNDS}: approved with open concerns.`);
	expect(notifications).toEqual([expect.objectContaining({ level: "warning", message: expect.stringContaining(problem) })]);
	expect(existsSync(join(root, "artifacts", "plan-review"))).toBe(false);
	expect(await propose()).toBeUndefined();
});

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

test("findings fold every JavaScript line terminator into one line in tool results and the plan", async () => {
	answers.push({
		text: JSON.stringify({
			findings: [{
				severity: "concern",
				location: "Task\r 1",
				issue: "No test\r\ncovers \n\t \n the\u2028change.",
				fix: "Add \u2029 \t a test.",
			}],
		}),
	});
	const expected = "- [concern] Task 1: No test covers the change. Fix: Add a test.";
	expect(await review()).toContain(expected);
	expect(readFileSync(planPath, "utf8")).toEndWith(`${expected}\n`);
});

test("findings preserve long interior whitespace runs without a line break", async () => {
	const issue = `No${" ".repeat(100_000)}test covers the change.`;
	answers.push({
		text: JSON.stringify({
			findings: [{ severity: "concern", location: "Task 1", issue, fix: "Add a test." }],
		}),
	});
	const expected = `- [concern] Task 1: ${issue} Fix: Add a test.`;
	expect(await review()).toContain(expected);
	expect(readFileSync(planPath, "utf8")).toEndWith(`${expected}\n`);
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

test.each(["```", "~~~"])("CRLF %s fences preserve example findings headings while real sections are removed", async (fence: string): Promise<void> => {
	const body = `# Feature plan\r\n\r\n${fence}markdown\r\n## Open review findings\r\nKeep this example.\r\n${fence}\r\n\r\n## Next step\r\nKeep this step.`;
	const original = `${body}\r\n`;
	writeFileSync(planPath, original);
	answers.push({ text: NIT_ONLY }, { text: NIT_ONLY });

	await review();
	expect(reviewerPrompts[0]).toContain(original);
	expect(readFileSync(planPath, "utf8")).toBe(original);

	writeFileSync(planPath, `${body}\r\n\r\n## Open review findings\r\n\r\n- [concern] Stale review.\r\n`);
	await review();
	expect(reviewerPrompts[1]).toContain(`${body}\n`);
	expect(reviewerPrompts[1]).not.toContain("Stale review.");
	expect(readFileSync(planPath, "utf8")).toBe(`${body}\n`);
	expect(await propose()).toBeUndefined();
});

test.each(["```", "````", "~~~", "~~~~"])("an unclosed %s fence is closed before findings so later reviews replace them", async (fence: string): Promise<void> => {
	const body = `# Feature plan\n\n${fence}markdown\n## Open review findings\nKeep this example.`;
	const closed = `${body}\n${fence}\n`;
	writeFileSync(planPath, body);
	answers.push(
		{ text: CONCERN },
		{ text: CONCERN.replace("No test covers the change.", "The rollout needs a check.") },
		{ text: NIT_ONLY },
	);

	await review();
	expect(readFileSync(planPath, "utf8")).toStartWith(`${closed}\n## Open review findings\n`);
	expect(await propose()).toBeUndefined();

	await review();
	expect(reviewerPrompts[1]).toContain(closed);
	expect(reviewerPrompts[1]).not.toContain("- [concern]");
	const replaced = readFileSync(planPath, "utf8");
	expect(replaced).toStartWith(`${closed}\n## Open review findings\n`);
	expect(replaced).toContain("- [concern] Task 1: The rollout needs a check.");
	expect(replaced).not.toContain("No test covers the change.");
	expect(replaced).not.toContain("round 1 of");
	expect(await propose()).toBeUndefined();

	await review();
	expect(reviewerPrompts[2]).toContain(closed);
	expect(reviewerPrompts[2]).not.toContain("- [concern]");
	expect(readFileSync(planPath, "utf8")).toBe(closed);
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

test("a plan edited during the last blocking round keeps the edit and hands its findings to the user", async (): Promise<void> => {
	const edited = "# Feature plan\n\nEdited during the last review.\n";
	let last = "";
	for (let round = 1; round <= MAX_ROUNDS; round++) {
		writeFileSync(planPath, `# Feature plan\n\nRevision ${round}.\n`);
		if (round === MAX_ROUNDS) duringReview = (): void => writeFileSync(planPath, edited);
		answers.push({ text: BLOCKER });
		last = await review();
	}
	expect(last).toContain(`round ${MAX_ROUNDS} of ${MAX_ROUNDS}: changes requested`);
	expect(last).toContain("- [blocker] Task 2: The script it runs does not exist. Fix: Name the existing script.");
	expect(last).toContain("- [concern] Task 1: No test covers the change. Fix: Add a test.");
	expect(last).toContain(`changed while the review ran, so the plugin did not list the open findings in it, and all ${MAX_ROUNDS} review rounds are used.`);
	expect(last).toContain('Tell the user about the findings above, then write "feature" to xd://propose; the user decides on them.');
	expect(last).not.toContain("xd://plan_review");
	expect(readFileSync(planPath, "utf8")).toBe(edited);
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
