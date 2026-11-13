/**
 * Plan review extension: a second model reviews every plan before it reaches the approval dialog.
 *
 * - Plan mode: appends the review procedure to the system prompt.
 * - `write xd://plan_review` with `{"title": "<slug>"}`: runs a headless `omp -p` on the `advisor` model role
 *   with read-only tools over the plan file, and returns its findings to the agent.
 * - While the reviewer runs, the tool reports its round and elapsed time every PROGRESS_INTERVAL_MS.
 * - `write xd://propose`: blocked until a review found no blockers in the current plan text, the review could not run
 *   for that text, its run was aborted with OMP's user-interrupt reason (Esc, leaving plan mode, an RPC or ACP
 *   cancel, or an extension's ctx.abort()), or MAX_ROUNDS reviewer runs of the plan file were used;
 *   a run that fails or times out counts as one of them.
 * - Open findings: a review without blockers writes its concerns, and a last round with blockers its blockers and
 *   concerns, to a `## Open review findings` section at the end of the plan file, which the approval dialog shows.
 *   Every review attempt first removes that section; the recorded hash covers the file with the new section. Only a
 *   plan file whose real path lies in the session's `local://` directory is written, and never one edited while the
 *   reviewer ran.
 * - Records: every plan_review call, whatever its result, saves one JSON record in the session's artifacts directory
 *   (`plan-review/<start>-<id>.json`): the plan text sent to the reviewer, its raw answer, findings, outcome and token
 *   usage. A record that cannot be saved only warns; it never changes the result or the gate.
 */
import { createHash, randomUUID } from "node:crypto";
import { readFileSync, realpathSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { join, sep } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import type { ExecResult } from "@oh-my-pi/pi-coding-agent/exec/exec";
import { type LocalProtocolOptions, resolveLocalRoot } from "@oh-my-pi/pi-coding-agent/internal-urls/local-protocol";
import { resolveApprovedPlan } from "@oh-my-pi/pi-coding-agent/plan-mode/approved-plan";
import { listPlanFiles, readPlanFile, resolvePlanFilePath } from "@oh-my-pi/pi-coding-agent/plan-mode/plan-files";
import { USER_INTERRUPT_LABEL } from "@oh-my-pi/pi-coding-agent/session/messages";
import { parseXdUrl } from "@oh-my-pi/pi-tui/tools/xd-url";

export const MAX_ROUNDS = 3;
/** Plan path OMP's plan mode starts with when none was chosen. */
const DEFAULT_PLAN_URL = "local://PLAN.md";
const OPEN_FINDINGS_HEADING = "## Open review findings";
const REVIEW_TIMEOUT_MS = 15 * 60_000;
const PROGRESS_INTERVAL_MS = 15_000;
const REVIEWER_ARGS = [
	"-p",
	"--no-session",
	"--no-extensions",
	"--no-skills",
	"--no-title",
	"--no-lsp",
	"--mode",
	"json",
	"--model",
	"@advisor",
	"--tools",
	"read,grep,glob",
];

type Severity = "blocker" | "concern" | "nit";
const SEVERITIES: Record<Severity, true> = { blocker: true, concern: true, nit: true };

type Finding = { severity: Severity; location: string; issue: string; fix: string };
type Review = { hash: string; outcome: "approve" | "approve-with-concerns" | "revise" | "unavailable" | "skipped"; rounds: number };

const RECORDS_DIR = "plan-review";

type Outcome = Review["outcome"] | "cancelled" | "exhausted" | "error";
/** One plan_review call as saved in the session's artifacts directory; the field order is the file's. */
type ReviewRecord = {
	version: string | null;
	title: string;
	url: string | null;
	round: number | null;
	startedAt: string;
	endedAt: string;
	outcome: Outcome;
	reason: string | null;
	reviewer: string | null;
	plan: { text: string; sha256: string } | null;
	answer: string | null;
	findings: Finding[] | null;
	usage: unknown[] | null;
	proposeSha256: string | null;
};

const PLAN_REVIEW_PROMPT = `# Plan review

This session has the plan-review plugin: a reviewer model checks every plan before it goes to approval. When the plan file is ready, write \`{"title": "<slug>"}\` to xd://plan_review, using the slug you will write to xd://propose. Only blockers request another round. When a review reports a blocker, resolve every blocker and concern it reports in the plan file, or state in the plan why a finding does not apply, then run the review again. A review without blockers approves the plan: if it reports concerns, the plugin lists them in a \`${OPEN_FINDINGS_HEADING}\` section at the end of the plan file, where the user decides on them in the approval dialog. Propose the plan without revising it for those concerns, and never write or edit that section yourself. xd://propose is blocked until a review finds no blockers in the current plan text or ${MAX_ROUNDS} review rounds are used; when the last round still finds blockers, the plugin lists its blockers and concerns in the same section. If the user cancels a running review (Esc), do not review that unchanged plan text again unless the user asks: write the slug to xd://propose when the user wants the plan proposed, and that text goes to approval unreviewed. After any edit to the plan, review it again as usual.`;

const REVIEWER_PROMPT = `You review an implementation plan before a human approves it. The plan is quoted below; the repository is the current directory.

Check the plan against the repository with read, grep and glob: the files, symbols, commands and behaviour it relies on exist and work as it assumes. Look for wrong assumptions about the code, missing steps or files, steps in the wrong order, missing or unverifiable verification, risky or destructive steps without a safeguard, work beyond the plan's stated goal, and ambiguity that would stop an implementer.

Severity:
- blocker: executing the plan as written fails or causes damage.
- concern: a material gap or risk the author should fix before approval.
- nit: an optional improvement.

Report only findings you can tie to a plan section or a repository path. Do not rewrite the plan and do not edit files.

Answer with one JSON object and nothing else:
{"findings": [{"severity": "blocker" | "concern" | "nit", "location": "<plan section or repository path>", "issue": "<what is wrong>", "fix": "<what the plan should say instead>"}]}
An empty findings list approves the plan.`;

/** The branch's latest `mode_change` entry when it is plan mode. Interactive plan mode records one; `--plan-yolo` does not. */
function planModeChange(ctx: ExtensionContext): { data?: Record<string, unknown> } | undefined {
	const branch = ctx.sessionManager.getBranch();
	for (let i = branch.length - 1; i >= 0; i--) {
		const entry = branch[i];
		if (entry.type === "mode_change") return entry.mode === "plan" ? entry : undefined;
	}
	return undefined;
}

/**
 * `file` resolved through symlinks when it lies inside this session's `local://` directory, the only place the plugin
 * writes: plan_review is a read-tier tool, so it must not change repository files.
 */
function sessionFile(file: string, localProtocolOptions: LocalProtocolOptions): string | undefined {
	try {
		const root = realpathSync(resolveLocalRoot(localProtocolOptions));
		const real = realpathSync(file);
		return real.startsWith(`${root}${sep}`) ? real : undefined;
	} catch {
		return undefined;
	}
}

/** True when `file` still holds `text` at the same real path, so a write cannot follow a symlink swapped in meanwhile. */
async function stillHolds(file: string, text: string): Promise<boolean> {
	try {
		return realpathSync(file) === file && (await Bun.file(file).text()) === text;
	} catch {
		return false;
	}
}

/**
 * The plan `xd://propose` takes for this title. It runs OMP's own lookup (the title's slug, the plan-mode plan path,
 * then the newest `*plan.md`), so a title that names no file cannot slip an unreviewed plan past the gate. `slug` is
 * the clean title that names the resolved file, for the agent's next call.
 */
async function resolvePlan(
	title: string,
	ctx: ExtensionContext,
): Promise<{ url: string; slug: string; content: string; writable: string | undefined } | undefined> {
	const localProtocolOptions = ctx.localProtocolOptions ?? {
		getArtifactsDir: () => ctx.sessionManager.getArtifactsDir(),
		getSessionId: () => ctx.sessionManager.getSessionId(),
	};
	const statePath = planModeChange(ctx)?.data?.planFilePath;
	try {
		const { planFilePath, planContent } = await resolveApprovedPlan({
			suppliedTitle: title,
			statePlanFilePath: typeof statePath === "string" ? statePath : DEFAULT_PLAN_URL,
			readPlan: url => readPlanFile(url, { localProtocolOptions, cwd: ctx.cwd }),
			listPlanFiles: () => listPlanFiles({ localProtocolOptions }),
		});
		const slug = planFilePath.replace(/^.*\//, "").replace(/\.md$/i, "").replace(/-plan$/i, "");
		const file = resolvePlanFilePath(planFilePath, { localProtocolOptions, cwd: ctx.cwd });
		return { url: planFilePath, slug, content: planContent, writable: sessionFile(file, localProtocolOptions) };
	} catch {
		return undefined;
	}
}

function asFinding(value: unknown): Finding | undefined {
	if (typeof value !== "object" || value === null) return undefined;
	const { severity, location, issue, fix } = value as Record<string, unknown>;
	if (typeof severity !== "string" || !Object.hasOwn(SEVERITIES, severity) || typeof issue !== "string" || !issue.trim())
		return undefined;
	return {
		severity: severity as Severity,
		location: typeof location === "string" ? location.trim() : "",
		issue: issue.trim(),
		fix: typeof fix === "string" ? fix.trim() : "",
	};
}

/** Findings from the reviewer's answer: a bare JSON object, a fenced one, or one embedded in prose. */
function parseFindings(output: string): Finding[] | undefined {
	const text = output.trim();
	const candidates = [text, text.match(/```(?:json)?\s*([\s\S]*?)```/)?.[1], text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1)];
	for (const candidate of candidates) {
		if (!candidate) continue;
		let parsed: unknown;
		try {
			parsed = JSON.parse(candidate);
		} catch {
			continue;
		}
		const findings = (parsed as { findings?: unknown } | null)?.findings;
		if (!Array.isArray(findings)) continue;
		const valid = findings.map(asFinding);
		if (valid.every(finding => finding !== undefined)) return valid as Finding[];
	}
	return undefined;
}

type ReviewerMessage = { role?: string; provider?: string; model?: string; content?: { type?: string; text?: string }[]; usage?: unknown };

/**
 * The reviewer's stdout from `omp -p --mode json`: the model that answered and its final text, from the last
 * `agent_end` event, and the `usage` of every assistant `message_end` event. An `agent_end` lists only its own loop's
 * messages, and a continuation starts a new loop, so usage comes from the whole stream.
 */
function reviewerOutput(stdout: string): { answer: { reviewer: string; text: string } | undefined; usage: unknown[] | null } {
	let end: { messages?: ReviewerMessage[] } | undefined;
	let usage: unknown[] | null = null;
	for (const line of stdout.split("\n")) {
		let event: { type?: string; message?: ReviewerMessage; messages?: ReviewerMessage[] } | null;
		try {
			event = JSON.parse(line);
		} catch {
			continue;
		}
		if (event?.type === "agent_end") end = event;
		else if (event?.type === "message_end" && event.message?.role === "assistant") {
			usage ??= [];
			if (event.message.usage !== undefined) usage.push(event.message.usage);
		}
	}
	const message = end?.messages?.findLast(entry => entry.role === "assistant");
	if (!message) return { answer: undefined, usage };
	const text = (message.content ?? []).flatMap(part => (part.type === "text" && part.text ? [part.text] : [])).join("\n");
	return { answer: { reviewer: `${message.provider}/${message.model}`, text }, usage };
}

function sha256(text: string): string {
	return createHash("sha256").update(text).digest("hex");
}

/** One finding as a list item; line breaks inside the reviewer's text are folded so the item stays one line. */
function formatFinding({ severity, location, issue, fix }: Finding): string {
	const item = `- [${severity}]${location ? ` ${location}:` : ""} ${issue}${fix ? ` Fix: ${fix}` : ""}`;
	return item.split(/[\r\n\u2028\u2029]/).map(line => line.trim()).filter(Boolean).join(" ");
}

/** Track the fence enclosing a line, using the same rules when removing and appending findings. */
function fenceAfterLine(line: string, fence: string | undefined): string | undefined {
	const marker = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(line.trimEnd());
	if (fence !== undefined) {
		return marker && marker[1][0] === fence[0] && marker[1].length >= fence.length && !marker[2].trim() ? undefined : fence;
	}
	return marker?.[1];
}

/**
 * The plan without its `## Open review findings` sections. A section runs from its heading to the next `#` or `##`
 * heading or the end of the file; lines inside fenced code blocks are content. Returns the input itself when it has
 * no such section, so an unchanged plan keeps its hash.
 */
function withoutOpenFindings(content: string): string {
	const kept: string[] = [];
	let fence: string | undefined;
	let inSection = false;
	let removed = false;
	for (const line of content.split("\n")) {
		fence = fenceAfterLine(line, fence);
		if (fence === undefined) {
			if (line.trimEnd() === OPEN_FINDINGS_HEADING) {
				inSection = true;
				removed = true;
				continue;
			} else if (inSection && /^#{1,2}\s/.test(line)) {
				inSection = false;
			}
		}
		if (!inSection) kept.push(line);
	}
	return removed ? `${kept.join("\n").trimEnd()}\n` : content;
}

/** Append findings outside any fence the plan left open, so a later review can remove the section. */
function withOpenFindings(body: string, intro: string, findings: Finding[]): string {
	let fence: string | undefined;
	for (const line of body.split("\n")) fence = fenceAfterLine(line, fence);
	const closed = `${body.trimEnd()}${fence ? `\n${fence}` : ""}`;
	return `${closed}\n\n${OPEN_FINDINGS_HEADING}\n\n${intro}\n\n${findings.map(formatFinding).join("\n")}\n`;
}

function textResult(text: string, details: Record<string, unknown>) {
	return { content: [{ type: "text" as const, text }], details };
}

/** Elapsed time as m:ss for the progress line. */
function formatElapsed(ms: number): string {
	const seconds = Math.floor(ms / 1000);
	return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

/** The plugin version from its package.json, for the review records; null when it cannot be read. */
function pluginVersion(): string | null {
	try {
		const { version } = JSON.parse(readFileSync(join(import.meta.dir, "..", "package.json"), "utf8")) as { version?: unknown };
		return typeof version === "string" ? version : null;
	} catch {
		return null;
	}
}

/** Save the record of one plan_review call in the session's artifacts directory, never the repository; a failure only warns. */
async function saveRecord(record: ReviewRecord, ctx: ExtensionContext): Promise<void> {
	try {
		const artifactsDir = ctx.sessionManager.getArtifactsDir();
		if (!artifactsDir) throw new Error("this session has no artifacts directory");
		const dir = join(artifactsDir, RECORDS_DIR);
		await mkdir(dir, { recursive: true });
		const name = `${record.startedAt.replaceAll(":", "-")}-${randomUUID().slice(0, 8)}.json`;
		await Bun.write(join(dir, name), `${JSON.stringify(record, null, 2)}\n`);
	} catch (error) {
		ctx.ui.notify(`Plan review could not save its record of this call; the review result stands.\n${String(error)}`, "warning");
	}
}

export default function planReviewExtension(pi: ExtensionAPI): void {
	const version = pluginVersion();
	/** Latest review per plan file path, for the current session: `local://` plan files belong to one session. */
	const reviews = new Map<string, Review>();
	// `/new`, `/resume`, a fork and a session reload keep this extension loaded; their plan files need fresh reviews.
	pi.on("session_switch", () => {
		reviews.clear();
	});

	pi.on("before_agent_start", async (event, ctx) => {
		if (!planModeChange(ctx)) return undefined;
		return { systemPrompt: [...event.systemPrompt, PLAN_REVIEW_PROMPT] };
	});

	pi.registerTool({
		name: "plan_review",
		label: "Plan Review",
		description:
			"Review a plan-mode plan with the advisor-role model before proposing it. Pass the slug you will write to xd://propose; returns blockers, concerns and nits. Only blockers keep xd://propose blocked; the concerns of a review without blockers go to approval in the plan file.",
		parameters: pi.zod.object({
			title: pi.zod.string().describe("Plan slug, the same text you write to xd://propose"),
		}),
		approval: "read",
		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			const started = Date.now();
			const record: ReviewRecord = {
				version,
				title: params.title,
				url: null,
				round: null,
				startedAt: new Date(started).toISOString(),
				endedAt: "",
				outcome: "error",
				reason: null,
				reviewer: null,
				plan: null,
				answer: null,
				findings: null,
				usage: null,
				proposeSha256: null,
			};
			try {
				const plan = await resolvePlan(params.title, ctx);
				if (!plan) throw new Error(`No plan file found for "${params.title}". Write the plan to local://<slug>-plan.md first.`);
				record.url = plan.url;
				const rounds = reviews.get(plan.url)?.rounds ?? 0;
				if (rounds >= MAX_ROUNDS) {
					record.outcome = "exhausted";
					return textResult(
						`All ${MAX_ROUNDS} plan review rounds for ${plan.url} are used. Write "${plan.slug}" to xd://propose; the user decides on the plan without another review.`,
						{ url: plan.url, rounds },
					);
				}
				const round = rounds + 1;
				// Every review attempt replaces the section an earlier review wrote: the reviewer must not read stale findings,
				// and the plan must not go to approval with them. Only a plan file inside the session's local:// directory is written.
				const { writable } = plan;
				const body = writable ? withoutOpenFindings(plan.content) : plan.content;
				if (writable && body !== plan.content) await Bun.write(writable, body);
				const hash = sha256(body);
				record.round = round;
				record.plan = { text: body, sha256: hash };
				const unavailable = (reason: string) => {
					reviews.set(plan.url, { hash, outcome: "unavailable", rounds: round });
					record.outcome = "unavailable";
					record.reason = reason;
					record.proposeSha256 = hash;
					ctx.ui.notify(`Plan review could not run (round ${round} of ${MAX_ROUNDS}); the plan goes to approval unreviewed.\n${reason}`, "warning");
					return textResult(
						`Plan review could not run (round ${round} of ${MAX_ROUNDS}); write "${plan.slug}" to xd://propose, the plan goes to approval unreviewed.\n${reason}`,
						{ url: plan.url, round, outcome: "unavailable" },
					);
				};
				const skipped = () => {
					reviews.set(plan.url, { hash, outcome: "skipped", rounds });
					record.outcome = "skipped";
					record.proposeSha256 = hash;
					ctx.ui.notify(
						`Plan review skipped: the current text of ${plan.url} goes to approval unreviewed. Any edit to the plan needs a new review.`,
						"warning",
					);
					return new Error(
						`Plan review cancelled by the user. If the user asks to propose the plan, write "${plan.slug}" to xd://propose; its current text goes to approval unreviewed.`,
					);
				};
				const cancelled = () => {
					if (signal?.reason === USER_INTERRUPT_LABEL) return skipped();
					record.outcome = "cancelled";
					return new Error("Plan review cancelled.");
				};

				const progress = () =>
					onUpdate?.(
						textResult(
							`Plan review round ${round}/${MAX_ROUNDS}: ${formatElapsed(Date.now() - started)} elapsed (stops at ${REVIEW_TIMEOUT_MS / 60_000}:00). Esc skips it.\nReviewing ${plan.url} with the advisor model role.`,
							{ url: plan.url, round },
						),
					);
				progress();
				const heartbeat = setInterval(progress, PROGRESS_INTERVAL_MS);

				let result: ExecResult;
				try {
					result = await pi.exec("omp", [...REVIEWER_ARGS, `${REVIEWER_PROMPT}\n\nPlan (${plan.url}):\n\n<plan>\n${body}\n</plan>`], {
						cwd: ctx.cwd,
						signal,
						timeout: REVIEW_TIMEOUT_MS,
					});
				} catch (error) {
					if (signal?.aborted) throw cancelled();
					return unavailable(`${String(error)}.`);
				} finally {
					clearInterval(heartbeat);
				}
				const { answer, usage } = reviewerOutput(result.stdout);
				record.usage = usage;
				if (answer) {
					record.reviewer = answer.reviewer;
					record.answer = answer.text;
				}
				if (signal?.aborted) throw cancelled();
				if (result.killed) return unavailable(`the reviewer did not finish within ${REVIEW_TIMEOUT_MS / 60_000} minutes.`);
				if (result.code !== 0) return unavailable(`the reviewer exited with code ${result.code}: ${result.stderr.trim().slice(-500)}`);
				if (!answer) return unavailable(`the reviewer's output has no final answer: ${result.stdout.trim().slice(-500)}`);
				const { reviewer, text } = answer;
				const findings = parseFindings(text);
				if (!findings) return unavailable(`${reviewer}'s answer is not the expected JSON: ${text.trim().slice(0, 500)}`);
				record.findings = findings;

				const blocked = findings.some(finding => finding.severity === "blocker");
				const concerns = findings.filter(finding => finding.severity === "concern");
				const outcome = blocked ? "revise" : concerns.length > 0 ? "approve-with-concerns" : "approve";
				const lastRound = blocked && round >= MAX_ROUNDS;
				const open = lastRound ? findings.filter(finding => finding.severity !== "nit") : outcome === "approve-with-concerns" ? concerns : [];
				let reviewed = body;
				let listed = false;
				let changed = false;
				let unlisted = "the plugin writes open findings only into plan files stored in this session's local:// directory";
				if (open.length > 0 && writable) {
					// The review can run for minutes: never overwrite an edit made meanwhile, nor write through a swapped-in symlink.
					if (await stillHolds(writable, body)) {
						const by = `Plan Review (${reviewer}, round ${round} of ${MAX_ROUNDS})`;
						const intro = lastRound
							? `${by} still found blockers in its last round. These findings remain open: decide on them when you approve the plan. The plan-review plugin wrote this section; any later review of the plan replaces it.`
							: `${by} found no blockers. These concerns remain open and do not block approval: decide on them when you approve the plan. The plan-review plugin wrote this section; any later review of the plan replaces it.`;
						const annotated = withOpenFindings(body, intro, open);
						try {
							await Bun.write(writable, annotated);
							reviewed = annotated;
							listed = true;
						} catch (error) {
							unlisted = `the plugin could not write them (${String(error)})`;
						}
					} else {
						changed = true;
					}
				}
				// A plan that changed during the review gets no hash: this review does not cover its current text.
				const gateHash = changed ? "" : sha256(reviewed);
				reviews.set(plan.url, { hash: gateHash, outcome, rounds: round });
				record.outcome = outcome;
				record.proposeSha256 = gateHash || null;
				const status = { approve: "approved", "approve-with-concerns": "approved with open concerns", revise: "changes requested" }[outcome];
				const lines = [
					`Plan review of ${plan.url} by ${reviewer}, round ${round} of ${MAX_ROUNDS}: ${status}.`,
					...(findings.length > 0 ? ["", ...findings.map(formatFinding)] : []),
					"",
				];
				if (changed && round >= MAX_ROUNDS)
					lines.push(
						`${plan.url} changed while the review ran, so the plugin did not list the open findings in it, and all ${MAX_ROUNDS} review rounds are used. Tell the user about the findings above, then write "${plan.slug}" to xd://propose; the user decides on them.`,
					);
				else if (changed)
					lines.push(
						`${plan.url} changed while the review ran, so the plugin did not list the open findings in it and this review does not cover its current text. Write {"title": ${JSON.stringify(plan.slug)}} to xd://plan_review again.`,
					);
				else if (outcome === "approve") lines.push(`Write "${plan.slug}" to xd://propose to request approval.`);
				else if (outcome === "approve-with-concerns" && listed)
					lines.push(
						`The concerns are listed in the "${OPEN_FINDINGS_HEADING}" section at the end of ${plan.url}, where the user decides on them in the approval dialog. Do not revise the plan for them and do not edit that section: any edit to the plan needs a new review. Write "${plan.slug}" to xd://propose to request approval.`,
					);
				else if (outcome === "approve-with-concerns")
					lines.push(
						`${plan.url} does not list these concerns: ${unlisted}. Tell the user about them, then write "${plan.slug}" to xd://propose to request approval.`,
					);
				else if (lastRound && listed)
					lines.push(
						`All ${MAX_ROUNDS} review rounds are used. The blockers and concerns are listed in the "${OPEN_FINDINGS_HEADING}" section at the end of ${plan.url}. Write "${plan.slug}" to xd://propose; the user decides on these findings.`,
					);
				else if (lastRound)
					lines.push(
						`All ${MAX_ROUNDS} review rounds are used. ${plan.url} does not list these findings: ${unlisted}. Tell the user about the blockers and concerns above, then write "${plan.slug}" to xd://propose; the user decides on them.`,
					);
				else
					lines.push(
						`Resolve every blocker and concern in the plan file, or state in the plan why one does not apply. Then write {"title": ${JSON.stringify(plan.slug)}} to xd://plan_review again; xd://propose stays blocked until a review finds no blockers in the current plan.`,
					);
				return textResult(lines.join("\n"), { url: plan.url, reviewer, round, outcome, findings });
			} catch (error) {
				if (record.outcome === "error") record.reason = error instanceof Error ? error.message : String(error);
				throw error;
			} finally {
				record.endedAt = new Date().toISOString();
				await saveRecord(record, ctx);
			}
		},
	});

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "write") return undefined;
		const { path: target, content: title } = event.input as { path?: unknown; content?: unknown };
		if (typeof target !== "string" || typeof title !== "string" || parseXdUrl(target)?.name !== "propose") return undefined;
		const plan = await resolvePlan(title, ctx);
		// OMP's own proposal handler reports a missing plan file.
		if (!plan) return undefined;
		const hash = sha256(plan.content);
		const review = reviews.get(plan.url);
		if (review?.hash === hash && review.outcome !== "revise") return undefined;
		if (review && review.rounds >= MAX_ROUNDS) {
			ctx.ui.notify(
				`Plan review: all ${MAX_ROUNDS} rounds are used and the current plan text has no approving review; it goes to approval without another review.`,
				"warning",
			);
			return undefined;
		}
		const next = `write {"title": ${JSON.stringify(plan.slug)}} to xd://plan_review`;
		return {
			block: true,
			reason:
				review?.hash === hash
					? `Plan review requested changes (round ${review.rounds} of ${MAX_ROUNDS}) and the plan has not changed since. Resolve every blocker and concern in the plan file, or state in the plan why one does not apply, then ${next} again.`
					: `${review ? "The plan changed since its last review." : "This plan has not been reviewed."} Before proposing it, ${next} and follow its result, then write "${plan.slug}" to xd://propose again.`,
		};
	});
}
