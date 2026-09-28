import { expect, test } from "bun:test";
import { mkdtempSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import commitHooks from "../../../plugins-omp/commit/extensions/claude-hooks.ts";

type Event = { toolName: string; toolCallId: string; input: Record<string, unknown> };
type Handler = (event: Event, ctx: ExtensionContext) => Promise<unknown>;

function git(...args: string[]): void {
	const result = Bun.spawnSync(["git", ...args], { env: { ...process.env } });
	if (result.exitCode !== 0) throw new Error(`git ${args.join(" ")} failed: ${result.stderr.toString()}`);
}

test("the shipped commit and push hooks guard bash calls in a real git repo", async () => {
	const oldNoSystem = process.env.GIT_CONFIG_NOSYSTEM;
	const oldGlobal = process.env.GIT_CONFIG_GLOBAL;
	process.env.GIT_CONFIG_NOSYSTEM = "1";
	process.env.GIT_CONFIG_GLOBAL = "/dev/null";
	const root = realpathSync(mkdtempSync(path.join(tmpdir(), "commit-edition-")));
	try {
		const repo = path.join(root, "repo");
		const bare = path.join(root, "origin.git");
		git("init", "-q", "-b", "feature/x", repo);
		git("-C", repo, "config", "user.name", "t");
		git("-C", repo, "config", "user.email", "t@t.t");
		git("-C", repo, "commit", "-q", "--allow-empty", "-m", "init");
		git("init", "-q", "--bare", bare);
		git("-C", repo, "remote", "add", "origin", bare);

		let captured: Handler | undefined;
		commitHooks({ on: (name: string, callback: Handler) => {
			if (name === "tool_call") captured = callback;
		} } as unknown as ExtensionAPI);
		if (!captured) throw new Error("tool_call handler not registered");
		const handler = captured;
		const confirmations: [string, string][] = [];
		let accepted = true;
		let ctx = {
			cwd: repo,
			hasUI: true,
			sessionManager: { getSessionId: () => "commit-edition-session" },
			ui: { confirm: async (title: string, message: string) => {
				confirmations.push([title, message]);
				return accepted;
			} },
		} as unknown as ExtensionContext;
		const call = (command: string) => handler({ toolName: "bash", toolCallId: "call-1", input: { command } }, ctx);

		const direct = await call('git commit -m "feat: x"') as { block: boolean; reason: string };
		expect(direct.block).toBe(true);
		expect(direct.reason).toContain("/commit");
		expect(await call('AV_COMMIT_SKILL=1 git commit -m "feat: x"')).toBeUndefined();
		expect(await call("git commit --amend --no-edit")).toBeUndefined();

		const forced = await call("git push --force origin feature/x") as { block: boolean; reason: string };
		expect(forced.block).toBe(true);
		expect(forced.reason).toContain("Force-push");
		expect(confirmations).toEqual([]);
		expect(await call("git push origin feature/x")).toBeUndefined();
		expect(await call("ls -la")).toBeUndefined();
		expect(confirmations).toEqual([]);

		const protectedPush = "git push origin main";
		expect(await call(protectedPush)).toBeUndefined();
		expect(confirmations).toEqual([["Confirm command", expect.stringContaining(`\n\n${protectedPush}`)]]);
		const askReason = confirmations[0]![1].split("\n\n")[0]!;
		expect(askReason).toContain("protected branch");
		accepted = false;
		const declined = await call(protectedPush) as { block: boolean; reason: string };
		expect(declined).toEqual({ block: true, reason: `Not confirmed by the user. ${askReason}` });
		expect(confirmations).toHaveLength(2);
		ctx = { ...ctx, hasUI: false } as ExtensionContext;
		const headless = await call(protectedPush) as { block: boolean; reason: string };
		expect(headless).toEqual({ block: true, reason: `${askReason} Blocked: nobody can confirm it in this session.` });
		expect(confirmations).toHaveLength(2);
		expect(await handler({ toolName: "read", toolCallId: "call-2", input: { path: "README.md" } }, ctx)).toBeUndefined();
	} finally {
		rmSync(root, { recursive: true, force: true });
		if (oldNoSystem === undefined) delete process.env.GIT_CONFIG_NOSYSTEM;
		else process.env.GIT_CONFIG_NOSYSTEM = oldNoSystem;
		if (oldGlobal === undefined) delete process.env.GIT_CONFIG_GLOBAL;
		else process.env.GIT_CONFIG_GLOBAL = oldGlobal;
	}
});
