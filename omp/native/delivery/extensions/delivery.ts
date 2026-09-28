/**
 * Delivery extension: plan mode → delivery.
 *
 * - Plan mode in a git repository: appends the delivery task format to the system prompt.
 * - `write xd://propose`: rejects a plan whose `### Task` blocks the router cannot route.
 * - Plan approval (the interactive "Plan approved." prompt): when the plan has `### Task`
 *   headings, adds a message that hands it to the Delivery run of skill://delivery:orchestration.
 * - Plan approval that cannot start delivery (missing plan file, failed check, no valid task) warns instead of staying silent.
 */
import { existsSync } from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import { resolveLocalUrlToPath } from "@oh-my-pi/pi-coding-agent/internal-urls/local-protocol";
import { normalizePlanTitle, planFileUrlForSlug } from "@oh-my-pi/pi-coding-agent/plan-mode/approved-plan";
import approvedPlanPrompt from "@oh-my-pi/pi-coding-agent/prompts/system/plan-mode-approved" with { type: "text" };
import { parseXdUrl } from "@oh-my-pi/pi-tui/tools/xd-url";

const ROUTER = path.join(import.meta.dir, "..", "scripts", "route_task.py");
type PlanCheck = { tasks: number; problems: string[]; no_files: string[] };
const APPROVED_PLAN_PREFIX = approvedPlanPrompt.split("\n", 1)[0];
const APPROVED_PLAN_TAG = approvedPlanPrompt.match(/^<plan path="\{\{planFilePath\}\}">$/m)?.[0];

const PLAN_FORMAT = `# Delivery plans

This session has the delivery plugin. An approved plan that changes files in this git repository is delivered task by task: each \`### Task\` goes to the developer agent that owns its files and is reviewed and committed on its own; then the plan's \`## Verification\` runs and a full code review closes the delivery. Write such a plan's Approach as numbered tasks in exactly this shape:

### Task 1: <short title>
**Commit:** <conventional commit subject>

**Files:**
- Create: \`path/to/new_module.py\`
- Modify: \`path/to/existing.py\`
- Test: \`tests/test_new_module.py\`
- Delete: \`path/to/obsolete.py\`

<concrete steps; when behavior changes, the failing test comes first>

Rules:
- Every file change belongs to a task. Text outside tasks is context; nobody implements it.
- Number tasks 1, 2, 3… in execution order, each number once; producers before consumers.
- One stack per task: Python, React/TypeScript frontend, PHP, or everything else (docs, CI, configuration). A change that spans backend and frontend is two or more tasks.
- List every file the task creates, modifies, tests or deletes: repository-relative, in backticks. The file list picks the implementing agent.
- Each task stands alone: its agent implements only that task. Name the functions, types and signatures that later tasks rely on.
- Inside a task use no \`##\` or \`###\` headings outside fenced code blocks; the next one ends the task.
- Writing the slug to xd://propose checks these rules and lists every violation.
- A plan that changes no files (research, analysis, an answer) has no \`### Task\` headings and runs without delivery.`;

async function gitRoot(pi: ExtensionAPI, cwd: string): Promise<string | undefined> {
	try {
		const { code, stdout } = await pi.exec("git", ["-C", cwd, "rev-parse", "--show-toplevel"], { timeout: 5_000 });
		return code === 0 ? stdout.trim() || undefined : undefined;
	} catch {
		return undefined;
	}
}

async function checkPlan(pi: ExtensionAPI, root: string, file: string): Promise<PlanCheck> {
	const { code, stdout, stderr } = await pi.exec("python3", [ROUTER, "check", root, file], { timeout: 10_000 });
	if (code !== 0) throw new Error(`${ROUTER}: ${stderr.trim() || `exit code ${code}`}`);
	return JSON.parse(stdout);
}

function inPlanMode(ctx: ExtensionContext): boolean {
	const branch = ctx.sessionManager.getBranch();
	for (let i = branch.length - 1; i >= 0; i--) {
		const entry = branch[i];
		if (entry.type === "mode_change") return entry.mode === "plan";
	}
	return false;
}

function localPath(url: string, ctx: ExtensionContext): string | undefined {
	try {
		return resolveLocalUrlToPath(url, {
			getArtifactsDir: ctx.localProtocolOptions?.getArtifactsDir ?? (() => ctx.sessionManager.getArtifactsDir()),
			getSessionId: ctx.localProtocolOptions?.getSessionId ?? (() => ctx.sessionManager.getSessionId()),
		});
	} catch {
		return undefined;
	}
}

function proposedPlanUrl(title: string): string | undefined {
	try {
		const { title: normalized } = normalizePlanTitle(title);
		return planFileUrlForSlug(normalized.replace(/-plan$/i, "") || normalized);
	} catch {
		return undefined;
	}
}

function approvedPlanPath(prompt: string): string | undefined {
	if (!prompt.startsWith(APPROVED_PLAN_PREFIX) || !APPROVED_PLAN_TAG) return undefined;
	const [start, end] = APPROVED_PLAN_TAG.split("{{planFilePath}}");
	const tagStart = prompt.indexOf(start);
	if (tagStart < 0) return undefined;
	const tagEnd = prompt.indexOf("\n", tagStart);
	const tag = prompt.slice(tagStart, tagEnd < 0 ? undefined : tagEnd);
	return tag.endsWith(end) ? tag.slice(start.length, -end.length) : undefined;
}

export default function deliveryExtension(pi: ExtensionAPI): void {
	pi.on("before_agent_start", async (event, ctx) => {
		if (inPlanMode(ctx)) {
			if (!(await gitRoot(pi, ctx.cwd))) return undefined;
			return { systemPrompt: [...event.systemPrompt, PLAN_FORMAT] };
		}
		const url = approvedPlanPath(event.prompt);
		if (!url) return undefined;
		const root = await gitRoot(pi, ctx.cwd);
		if (!root) {
			ctx.ui.notify("Delivery skipped: not a git repository. The plan runs without delivery.", "warning");
			return undefined;
		}
		const file = url.startsWith("local:") ? localPath(url, ctx) : path.resolve(ctx.cwd, url);
		if (!file || !existsSync(file)) {
			ctx.ui.notify(`Delivery skipped: plan file not found for ${url}. The plan runs without delivery.`, "warning");
			return undefined;
		}
		let tasks: number;
		let problems: string[];
		try {
			({ tasks, problems } = await checkPlan(pi, root, file));
		} catch (error) {
			ctx.ui.notify(`Delivery skipped: plan check failed for ${url}: ${String(error)}. The plan runs without delivery.`, "warning");
			return undefined;
		}
		if (tasks === 0) {
			if (problems.length > 0)
				ctx.ui.notify(`Delivery skipped: ${url} has no valid task heading. ${problems.join(" ")} The plan runs without delivery.`, "warning");
			return undefined;
		}
		ctx.ui.notify(`Delivery: ${tasks} task(s) — starting the delivery run.`, "info");
		return {
			message: {
				customType: "delivery-run",
				content: [
					"<critical>",
					`Delivery takes over this approved plan: it has ${tasks} task(s) under \`### Task\` headings. This replaces the instruction above to execute the plan step by step yourself. Implementing this plan means running the delivery: each task goes to the developer agent that owns its files, is reviewed and committed; then the plan's Verification and the full code review run. Do not edit project files yourself.`,
					"",
					"`read skill://delivery:orchestration` and run its **Delivery run** section with:",
					`- PLAN_SOURCE: ${url}`,
					`- PLAN_FILE: ${file}`,
					"</critical>",
				].join("\n"),
				display: true,
				attribution: "agent",
			},
		};
	});

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "write") return undefined;
		const { path: target, content } = event.input as { path?: unknown; content?: unknown };
		if (typeof target !== "string" || typeof content !== "string" || parseXdUrl(target)?.name !== "propose")
			return undefined;
		const url = proposedPlanUrl(content);
		const file = url ? localPath(url, ctx) : undefined;
		if (!url) return undefined;
		if (!file || !existsSync(file)) {
			ctx.ui.notify(`Delivery plan check skipped: plan file not found for ${url}.`, "warning");
			return undefined;
		}
		const root = await gitRoot(pi, ctx.cwd);
		if (!root) return undefined;
		let result: PlanCheck;
		try {
			result = await checkPlan(pi, root, file);
		} catch (error) {
			ctx.ui.notify(`Delivery plan check skipped: router failed for ${url}: ${String(error)}`, "warning");
			return undefined;
		}
		const violations = [...result.problems, ...result.no_files];
		if (violations.length === 0) return undefined;
		return {
			block: true,
			reason: [
				`Delivery plan check failed for ${url}:`,
				...violations.map(problem => `- ${problem}`),
				"Fix these tasks in the plan file, then write the slug to xd://propose again.",
			].join("\n"),
		};
	});
}
