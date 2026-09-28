/**
 * Plan review extension: a second model reviews every plan before it reaches the approval dialog.
 *
 * - Plan mode: appends the review procedure to the system prompt.
 * - `write xd://plan_review` with `{"title": "<slug>"}`: runs a headless `omp -p` on the `advisor` model role
 *   with read-only tools over the plan file, and returns its findings to the agent.
 * - `write xd://propose`: blocked until a review approved the current plan text, the review could not run for
 *   that text, or MAX_ROUNDS reviews of the plan file were used.
 */
import { createHash } from "node:crypto";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import type { ExecResult } from "@oh-my-pi/pi-coding-agent/exec/exec";
import { resolveApprovedPlan } from "@oh-my-pi/pi-coding-agent/plan-mode/approved-plan";
import { listPlanFiles, readPlanFile } from "@oh-my-pi/pi-coding-agent/plan-mode/plan-files";
import { parseXdUrl } from "@oh-my-pi/pi-tui/tools/xd-url";

export const MAX_ROUNDS = 3;
/** Plan path OMP's plan mode starts with when none was chosen. */
const DEFAULT_PLAN_URL = "local://PLAN.md";
const REVIEW_TIMEOUT_MS = 15 * 60_000;
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
type Review = { hash: string; outcome: "approve" | "revise" | "unavailable"; rounds: number };

const PLAN_REVIEW_PROMPT = `# Plan review

This session has the plan-review plugin: a reviewer model checks every plan before it goes to approval. When the plan file is ready, write \`{"title": "<slug>"}\` to xd://plan_review, using the slug you will write to xd://propose. Resolve every blocker and concern it reports in the plan file, or state in the plan why a finding does not apply, then run the review again. xd://propose is blocked until a review approves the current plan text or ${MAX_ROUNDS} review rounds are used.`;

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
 * The plan `xd://propose` takes for this title. It runs OMP's own lookup (the title's slug, the plan-mode plan path,
 * then the newest `*plan.md`), so a title that names no file cannot slip an unreviewed plan past the gate. `slug` is
 * the clean title that names the resolved file, for the agent's next call.
 */
async function resolvePlan(
	title: string,
	ctx: ExtensionContext,
): Promise<{ url: string; slug: string; content: string } | undefined> {
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
		return { url: planFilePath, slug, content: planContent };
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

type ReviewerMessage = { role?: string; provider?: string; model?: string; content?: { type?: string; text?: string }[] };

/** The model that answered and its final text, from the `agent_end` event of `omp -p --mode json`. */
function reviewerAnswer(stdout: string): { reviewer: string; text: string } | undefined {
	const lines = stdout.trim().split("\n");
	for (let i = lines.length - 1; i >= 0; i--) {
		let event: { type?: string; messages?: ReviewerMessage[] };
		try {
			event = JSON.parse(lines[i]);
		} catch {
			continue;
		}
		if (event.type !== "agent_end") continue;
		const message = event.messages?.findLast(entry => entry.role === "assistant");
		if (!message) return undefined;
		const text = (message.content ?? []).flatMap(part => (part.type === "text" && part.text ? [part.text] : [])).join("\n");
		return { reviewer: `${message.provider}/${message.model}`, text };
	}
	return undefined;
}

function textResult(text: string, details: Record<string, unknown>) {
	return { content: [{ type: "text" as const, text }], details };
}

export default function planReviewExtension(pi: ExtensionAPI): void {
	/** Latest review per plan file path, for the current process. */
	const reviews = new Map<string, Review>();

	pi.on("before_agent_start", async (event, ctx) => {
		if (!planModeChange(ctx)) return undefined;
		return { systemPrompt: [...event.systemPrompt, PLAN_REVIEW_PROMPT] };
	});

	pi.registerTool({
		name: "plan_review",
		label: "Plan Review",
		description:
			"Review a plan-mode plan with the advisor-role model before proposing it. Pass the slug you will write to xd://propose; returns blockers, concerns and nits to resolve in the plan file.",
		parameters: pi.zod.object({
			title: pi.zod.string().describe("Plan slug, the same text you write to xd://propose"),
		}),
		approval: "read",
		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			const plan = await resolvePlan(params.title, ctx);
			if (!plan) throw new Error(`No plan file found for "${params.title}". Write the plan to local://<slug>-plan.md first.`);
			const { content } = plan;
			const hash = createHash("sha256").update(content).digest("hex");
			const rounds = reviews.get(plan.url)?.rounds ?? 0;
			if (rounds >= MAX_ROUNDS) {
				return textResult(
					`All ${MAX_ROUNDS} plan review rounds for ${plan.url} are used. Write "${plan.slug}" to xd://propose; the user decides on the open findings.`,
					{ url: plan.url, rounds },
				);
			}
			const unavailable = (reason: string) => {
				reviews.set(plan.url, { hash, outcome: "unavailable", rounds });
				ctx.ui.notify(`Plan review could not run; the plan goes to approval unreviewed.\n${reason}`, "warning");
				return textResult(`Plan review could not run; write "${plan.slug}" to xd://propose, the plan goes to approval unreviewed.\n${reason}`, {
					url: plan.url,
					outcome: "unavailable",
				});
			};

			onUpdate?.(textResult(`Reviewing ${plan.url} with the advisor model role…`, { url: plan.url }));

			let result: ExecResult;
			try {
				result = await pi.exec("omp", [...REVIEWER_ARGS, `${REVIEWER_PROMPT}\n\nPlan (${plan.url}):\n\n<plan>\n${content}\n</plan>`], {
					cwd: ctx.cwd,
					signal,
					timeout: REVIEW_TIMEOUT_MS,
				});
			} catch (error) {
				if (signal?.aborted) throw new Error("Plan review cancelled.");
				return unavailable(`${String(error)}.`);
			}
			if (signal?.aborted) throw new Error("Plan review cancelled.");
			if (result.killed) return unavailable(`the reviewer did not finish within ${REVIEW_TIMEOUT_MS / 60_000} minutes.`);
			if (result.code !== 0) return unavailable(`the reviewer exited with code ${result.code}: ${result.stderr.trim().slice(-500)}`);
			const answer = reviewerAnswer(result.stdout);
			if (!answer) return unavailable(`the reviewer's output has no final answer: ${result.stdout.trim().slice(-500)}`);
			const { reviewer, text } = answer;
			const findings = parseFindings(text);
			if (!findings) return unavailable(`${reviewer}'s answer is not the expected JSON: ${text.trim().slice(0, 500)}`);

			const round = rounds + 1;
			const outcome = findings.some(finding => finding.severity !== "nit") ? "revise" : "approve";
			reviews.set(plan.url, { hash, outcome, rounds: round });
			const lines = [
				`Plan review of ${plan.url} by ${reviewer}, round ${round} of ${MAX_ROUNDS}: ${outcome === "approve" ? "approved" : "changes requested"}.`,
				...(findings.length > 0
					? [
							"",
							...findings.map(
								({ severity, location, issue, fix }) =>
									`- [${severity}]${location ? ` ${location}:` : ""} ${issue}${fix ? ` Fix: ${fix}` : ""}`,
							),
						]
					: []),
				"",
			];
			if (outcome === "approve") lines.push(`Write "${plan.slug}" to xd://propose to request approval.`);
			else if (round >= MAX_ROUNDS)
				lines.push(`All ${MAX_ROUNDS} review rounds are used. Write "${plan.slug}" to xd://propose; the user decides on these findings.`);
			else
				lines.push(
					`Resolve every blocker and concern in the plan file, or state in the plan why one does not apply. Then write {"title": ${JSON.stringify(plan.slug)}} to xd://plan_review again; xd://propose stays blocked until a review approves the current plan.`,
				);
			return textResult(lines.join("\n"), { url: plan.url, reviewer, round, outcome, findings });
		},
	});

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "write") return undefined;
		const { path: target, content: title } = event.input as { path?: unknown; content?: unknown };
		if (typeof target !== "string" || typeof title !== "string" || parseXdUrl(target)?.name !== "propose") return undefined;
		const plan = await resolvePlan(title, ctx);
		// OMP's own proposal handler reports a missing plan file.
		if (!plan) return undefined;
		const hash = createHash("sha256").update(plan.content).digest("hex");
		const review = reviews.get(plan.url);
		if (review?.hash === hash && review.outcome !== "revise") return undefined;
		if (review && review.rounds >= MAX_ROUNDS) {
			ctx.ui.notify(
				`Plan review: all ${MAX_ROUNDS} rounds are used and the plan has no approving review. Check the last review's findings before approving.`,
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
					: `${review ? "The plan changed since its last review." : "This plan has not been reviewed."} Before proposing it, ${next} and resolve the blockers and concerns it reports, then write "${plan.slug}" to xd://propose again.`,
		};
	});
}
