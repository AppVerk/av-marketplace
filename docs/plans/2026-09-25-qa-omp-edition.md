# OMP edition of the `qa` plugin

## Context

`plugins/qa` (2.6.0: commands `create-plan`, `run`, `loop`; agents `fe-tester`, `be-tester`; 6 skills) has no OMP edition. A trial build with a stub overlay fails in `map_tools` with `no OMP mapping for tool 'mcp__postgres'`: both agents grant MCP tools (`mcp__plugin_playwright_playwright*`, `mcp__playwright*`, `mcp__postgres*`, `mcp__supabase*`, `mcp__neon*`, `mcp__mysql*`, `mcp__mongodb*`, `mcp__redis*`) and `TOOL_MAP` knows only Claude built-ins. End state: `omp plugin install qa@av-marketplace` gives `/qa:create-plan`, `/qa:run`, `/qa:loop` and the two tester agents in OMP; FE scenarios run in OMP's built-in browser (`browser` global inside `eval`) instead of Playwright MCP; the testers run through a new model role `tester`, and the model behind that role is chosen by a measured comparison of the candidates in the user's `~/.omp/agent/config.yml`.

Facts the design rests on (OMP 18.3.0, `~/.bun/install/global/node_modules/@oh-my-pi/pi-coding-agent`):

- A `task`-spawned subagent receives every MCP proxy tool of the session whatever its `tools:` allowlist says (`src/sdk.ts:3484-3493`: custom tools are "always included" unless `restrictToolNames`, which only OMP-internal sessions set), and names in `tools:` that no registered tool matches are silently dropped (`src/sdk.ts:3458`). MCP grants in agent frontmatter therefore grant and restrict nothing in OMP.
- OMP names MCP tools `mcp__<server>_<tool>` with one underscore (`src/mcp/tool-bridge.ts:406-418`), not Claude's `mcp__<server>__<tool>`.
- With `browser.enabled` (default `true`, `src/config/settings-schema.ts:4554-4556`) and `eval` active, OMP removes browser MCP servers, `@playwright/mcp` and any server named `playwright` included, from the session (`src/mcp/config.ts:357-414`). Playwright MCP is therefore not a viable FE backend in OMP; the built-in browser is.
- The built-in browser is the `browser` global of the `eval` tool (docs at `xd://eval/browser`): `browser.open(name=…, url=…)` → tab; `tab.goto`, `tab.observe()` (numeric ids → `tab.id(n)`), `tab.ariaSnapshot()` (`e5` refs → `tab.ref("e5")`), `click`/`fill`/`type`/`select`/`press`/`hover`, `tab.evaluate(expr)`, `tab.waitForSelector(selector, timeout=…, hidden=…)`, `tab.screenshot()` returns a file path (under `browser.screenshotDir` or the OS temp dir; it never accepts an output path). Managed Chromium is downloaded on first use.
- Prior overlay-only migrations (`bf01c00` code-review, `ab4ad37` developer plugins) bumped no plugin version; `plugins/qa/` is not touched by this plan, so `qa` stays 2.6.0 in all four places.
- The marketplace `av-marketplace` in this OMP is the local checkout (`omp plugin marketplace list` → `/Users/mef1st0/Projects/AppVerk/av-marketplace`), so installing from the working tree needs no push.

## Approach

### Task 1: Generator drops MCP grants and knows the `tester` role
**Commit:** feat(omp-edition): drop MCP grants from agent tools and add the tester model role

**Files:**
- Modify: `scripts/build_omp_edition.py`
- Test: `scripts/test_build_omp_edition.py`

1. In `scripts/build_omp_edition.py`, add `"tester"` to `MODEL_ROLES` (line 69) so it reads `{"code_review", "executor", "challenger", "analyst", "plan", "tester"}`, and extend the comment above it: the roles are documented in README.md, `tester` runs the QA testers.
2. Above `TOOL_MAP` (line 82) add the constant `MCP_GRANT_PREFIX = "mcp__"` with this comment: Claude MCP grants (`mcp__<server>`, `mcp__<server>__*`, `mcp__<server>__<tool>`) are dropped on purpose: an OMP subagent receives every MCP tool of the session regardless of its `tools:` list (OMP `src/sdk.ts`, custom tools are always included for task-spawned agents), so the grant cannot be expressed there; the preamble tells the model. Keep the existing `Skill: None` entry unchanged.
3. In `map_tools` (lines 173-185), after computing `name` and before the `if name not in TOOL_MAP` check, add `if name.startswith(MCP_GRANT_PREFIX): continue`. Everything else in `map_tools` and `build_agent` stays; in particular `build_agent`'s existing `if "tools" in fields and not tools: raise BuildError(...: declared tools map to no usable OMP tools)` (line 234) now also fails an agent whose `tools:` holds only MCP grants, which is the intended fail-closed behaviour.
4. In the module docstring, extend the paragraph "Every mapping is total: …" (lines 28-29) with one sentence: "The one prefix rule is `mcp__`: MCP grants in an agent's `tools:` are dropped, because an OMP subagent receives the session's MCP tools whatever its `tools:` says."
5. Tests in `scripts/test_build_omp_edition.py`, next to `test_unmapped_agent_tools_frontmatter_and_overlay_specs_fail_closed` (line 316), using the existing `fixture`/`put`/`build` helpers and the `AGENT` constant (`tools: Read, Bash`):
   - `test_drops_mcp_grants_from_agent_tools`: write the worker agent with `tools: Read, mcp__postgres, mcp__postgres__*, mcp__plugin_playwright_playwright__browser_navigate, Bash`; build; assert the generated `plugins-omp/sample/agents/worker.md` contains the line `tools: read, bash` and does not contain `mcp__`. In the same test, write the worker with `tools: mcp__postgres, mcp__postgres__*` only and assert `BuildError` matching `declared tools map to no usable OMP tools`.
   - `test_accepts_tester_role`, right after `test_accepts_documented_role_and_supported_tools_and_thinking` (line 374): same fixture with the overlay agent spec `{"role": "tester"}`; build; assert the generated `plugins-omp/sample/agents/worker.md` contains `model: "@tester"`. Keep the existing `exector` misspelling case in `test_rejects_invalid_overlay_role_tools_and_thinking` (line 355) untouched.

### Task 2: Overlay, preamble and the generated `qa` edition
**Commit:** feat(qa): generate the OMP edition with the built-in browser for FE tests

**Files:**
- Create: `omp/overlay/qa.json`
- Modify: `omp/preamble.md`
- Create: `plugins-omp/qa/`
- Modify: `plugins-omp/`
- Modify: `.omp-plugin/marketplace.json`

1. Create `omp/overlay/qa.json` with exactly:

```json
{
  "plugin": "qa",
  "agents": {
    "fe-tester": { "role": "tester", "add_tools": ["eval"] },
    "be-tester": { "role": "tester" }
  }
}
```

   No `autoload` key: the generator derives `autoloadSkills` from each agent's `skills:` line (`fe-testing`, `be-testing`). No `fallback_model`: both agents declare `model: opus`, which the generator appends after `@tester`.

2. In `omp/preamble.md`, insert three bullets after the `allowed-tools` bullet (the one that starts `> - **allowed-tools** and`) and before the `!` inline-context bullet, verbatim:

```markdown
> - **`mcp__<server>` and `mcp__<server>__*` grants** are not carried over: a subagent here gets every MCP tool of the session whatever its `tools:` list says, and a server the session has not configured is simply absent. MCP tools are named `mcp__<server>_<tool>` here (one underscore between server and tool), not `mcp__<server>__<tool>`.
> - **Playwright MCP** (`browser_navigate`, `browser_snapshot`, `browser_click`, `browser_fill_form`, `browser_type`, `browser_select_option`, `browser_press_key`, `browser_hover`, `browser_evaluate`, `browser_wait_for`, `browser_take_screenshot`, and any `mcp__playwright*` or `mcp__plugin_playwright_playwright*` tool) → the `browser` global inside `eval`, OMP's own Chromium (downloaded on first use; while it is enabled, OMP removes Playwright MCP servers from the session). Read `xd://eval/browser` before the first browser step. Open one tab per run, `tab = await browser.open(name="qa", url=<url>)`, then navigate with `await tab.goto(url)`; a probe such as "try `browser_navigate`" is that `browser.open` call, and an exception from it means the browser is unavailable. `browser_snapshot()` → `await tab.observe()` (numeric ids for `tab.id(n)`) or `await tab.ariaSnapshot()` (`e5`-style refs for `tab.ref("e5")`); act on those handles or on selectors (`text/Sign In`, `aria/Email`, CSS) with `click`, `fill`, `type`, `select`, `press`, `hover`. `browser_evaluate(expression)` → `await tab.evaluate(expression)`. `browser_wait_for` → `await tab.waitForSelector("text/Success", timeout=5000)` or `await tab.waitForSelector(selector, hidden=True, timeout=10000)`. `browser_take_screenshot()` → `path = await tab.screenshot()` returns a file in the OS temp directory: copy it with `bash` to the path the instructions name.
> - **Slash commands** are `/<plugin>:<name>` here: `/fix`, `/fix-report`, `/fix-all` and `/review` are `/code-review:fix`, `/code-review:fix-report`, `/code-review:fix-all` and `/code-review:review`; a command cited with its plugin prefix, such as `/qa:run`, keeps its name.
```

3. Run `python3 scripts/build_omp_edition.py`. It creates `plugins-omp/qa/` and, because the preamble changed, rewrites every agent and command under `plugins-omp/code-review/`, `plugins-omp/commit/`, `plugins-omp/frontend-developer/`, `plugins-omp/php-developer/`, `plugins-omp/python-developer/`, and adds the `qa` entry (version 2.6.0, category `testing`) to `.omp-plugin/marketplace.json`. Commit the generated files with the sources. Expected generated frontmatter:
   - `plugins-omp/qa/agents/fe-tester.md`: `name: "qa:fe-tester"`, `tools: read, write, bash, grep, glob, eval`, `model: "@tester, opus"`, `autoloadSkills: ["qa:fe-testing"]`;
   - `plugins-omp/qa/agents/be-tester.md`: `name: "qa:be-tester"`, `tools: read, write, bash, grep, glob`, `model: "@tester, opus"`, `autoloadSkills: ["qa:be-testing"]`;
   - `plugins-omp/qa/commands/{create-plan,run,loop}.md`: only `description` and `argument-hint`, then the preamble, then the unchanged body;
   - `plugins-omp/qa/skills/<name>/SKILL.md` for all six skills with `name: qa:<name>`, every other byte unchanged (the `fe-testing` and `be-testing` `allowed-tools` lines included).

### Task 3: Document the OMP edition of `qa` and the `tester` role
**Commit:** docs: document the OMP edition of qa and the tester model role

**Files:**
- Modify: `README.md`
- Modify: `docs/plugins/qa.md`
- Modify: `CLAUDE.md`

1. `README.md`, section `### Oh My Pi (OMP)` (line 16 on):
   - Line 18: "An OMP edition is generated from the same sources: Code Review, Commit, QA and the Frontend, PHP and Python developer plugins."
   - The install loop (line 22): `for p in code-review commit delivery plan-review qa python-developer frontend-developer php-developer; do`.
   - After the Delivery/Python paragraph (line 29) add one paragraph: In OMP, QA's FE scenarios run in OMP's built-in browser (`eval`'s `browser` global, a managed Chromium downloaded on first use) instead of Playwright MCP; OMP removes Playwright MCP servers from the session while `browser.enabled` is on, so no MCP setup is needed and a configured `@playwright/mcp` server is not used. BE scenarios use the same CLI clients as in Claude Code; database MCP servers configured for OMP are available to the tester without any grant. `/qa:loop` dispatches `code-review:fix-auto`, so it needs Code Review installed. Screenshots of failed FE scenarios land in `docs/testing/reports/screenshots/` as in Claude Code.
   - Line 41: "reviewers use `code_review`, fixers and developers `executor`, QA testers `tester`, adversarial verification `challenger`, …". In the YAML example (lines 43-50) add `  tester: openai-codex/gpt-5.5` after the `executor` line.
2. `docs/plugins/qa.md`: append a section `## Oh My Pi` after `## Prerequisites` (line 408-413) modelled on `docs/plugins/commit.md:119-127`: install command `omp plugin install qa@av-marketplace` (after `omp plugin marketplace update av-marketplace` if the marketplace was added earlier); commands are `/qa:create-plan`, `/qa:run`, `/qa:loop`; the two agents run through the `tester` model role (`modelRoles.tester` in `~/.omp/agent/config.yml`; without it OMP falls back to the `opus` selector, then the session model); FE testing uses OMP's built-in browser as described in the README paragraph, with `browser.enabled` (default on) as the prerequisite in place of Playwright MCP; `/qa:loop` needs `code-review@av-marketplace`; `/fix QA-001` and `/fix-report` are `/code-review:fix QA-001` and `/code-review:fix-report` in OMP. In `## Prerequisites`, change the Playwright bullet to: "**Playwright MCP** — required for FE testing in Claude Code (FE scenarios are skipped without it); Oh My Pi uses its built-in browser instead, see [Oh My Pi](#oh-my-pi)".
3. `CLAUDE.md`, section `## OMP edition`, the sentence "Its mappings are total: an agent without an overlay entry, a tool without a `TOOL_MAP` entry, or an agent frontmatter key the script does not know fails the build rather than being dropped." Add after it: "The one prefix rule is `mcp__`: MCP grants in an agent's `tools:` are dropped, because an OMP subagent receives the session's MCP tools whatever its `tools:` says, and the preamble tells the model so; an agent whose `tools:` holds only MCP grants still fails the build." Also add to the same section: overlay roles must be members of `MODEL_ROLES` in the generator and documented in the README's model-roles paragraph; `tester` is the QA testers' role.

## Critical files & anchors

- `scripts/build_omp_edition.py:173-185` (`map_tools`): the MCP prefix rule goes before the `TOOL_MAP` lookup; `:69` (`MODEL_ROLES`) gains `tester`.
- `scripts/test_build_omp_edition.py:23,38-52,316-330,354-360,374-388`: `AGENT` constant, `fixture`, the fail-closed and role/tool acceptance tests the new cases sit beside.
- `omp/preamble.md`: bullets are `> - **…**` lines inside one blockquote; the `allowed-tools` bullet is the insertion anchor.
- `docs/plugins/commit.md:119-127`: the only existing `## Oh My Pi` doc section; copy its shape.
- `README.md:16-50`: OMP install block, Delivery paragraphs, model-roles paragraph and YAML example.

## Verification

All commands from the repository root unless stated. Prerequisites: OMP 18.3.0 with the `av-marketplace` marketplace pointing at this checkout, `code-review@av-marketplace` and `commit@av-marketplace` installed in user scope, `jq` and `python3` on `PATH`, network access for the first Chromium download.

1. Gates: `python3 scripts/test_build_omp_edition.py` (all tests pass, including the two new ones); `python3 scripts/build_omp_edition.py --check` (exit 0); `python3 scripts/check_plugin_versions.py` (exit 0, `qa` 2.6.0 in all four places); `python3 scripts/check_omp_tools.py ~/.bun/install/global/node_modules/@oh-my-pi/pi-coding-agent` (exit 0); `bun test` in `omp/claude-hooks/` (22 pass, as before).
2. Generated content: `grep -n -E '^(name|tools|model|autoloadSkills):' plugins-omp/qa/agents/fe-tester.md plugins-omp/qa/agents/be-tester.md` prints the frontmatter listed in Task 2 step 3; `grep -c 'mcp__' plugins-omp/qa/agents/*.md` prints 0 for the frontmatter region (the bodies of the preamble mention `mcp__` by design, so check with `sed -n '1,8p'` instead); `grep -l 'Playwright MCP\*\*' plugins-omp/*/agents/*.md plugins-omp/*/commands/*.md | wc -l` equals the number of generated agents and commands (the preamble reached every file).
3. Install: `omp plugin marketplace update av-marketplace && omp plugin install qa@av-marketplace`; `omp plugin list` shows `qa@av-marketplace (2.6.0) (user)`; `diff -r plugins-omp/qa "$(readlink -f ~/.omp/plugins/node_modules/qa)"` prints nothing.
4. Benchmark fixture (also the end-to-end smoke). Create `/tmp/qa-bench` with `git init -q`, `git commit -q --allow-empty -m init` (set a local `user.name`/`user.email` if git asks), the file `app.py` below, and `docs/testing/plans/2026-09-24-qa-bench-test-plan.md` below. Start the app with `python3 app.py &` from `/tmp/qa-bench` and confirm `curl -s http://127.0.0.1:8765/api/users` prints `[{"id": 1, "name": "John"}]`.

`app.py` (two planted bugs: the About heading typo and the 500 on `POST /api/users`):

```python
#!/usr/bin/env python3
"""QA benchmark fixture: a tiny site and API with two planted bugs."""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

INDEX = """<!doctype html><html><head><title>QA Bench</title></head><body>
<h1>Hello QA</h1>
<nav><a href="/about">About</a></nav>
<form id="login">
  <label>Email <input name="email" type="text"></label>
  <label>Password <input name="password" type="password"></label>
  <button type="submit">Sign In</button>
</form>
<p id="message"></p>
<script>
document.getElementById('login').addEventListener('submit', async (e) => {
  e.preventDefault();
  const form = new FormData(e.target);
  const r = await fetch('/login', {method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({email: form.get('email'), password: form.get('password')})});
  const data = await r.json();
  document.getElementById('message').textContent = r.ok ? 'Welcome back' : data.error;
});
</script></body></html>"""

# Planted bug 1: the heading should read "About page".
ABOUT = """<!doctype html><html><head><title>About</title></head><body>
<h1>Abuot page</h1><a href="/">Home</a></body></html>"""

USERS = [{"id": 1, "name": "John"}]


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, body, ctype="application/json"):
        data = body.encode() if isinstance(body, str) else json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/":
            return self._send(200, INDEX, "text/html")
        if self.path == "/about":
            return self._send(200, ABOUT, "text/html")
        if self.path == "/api/users":
            return self._send(200, USERS)
        if self.path.startswith("/api/users/"):
            uid = self.path.rsplit("/", 1)[1]
            for user in USERS:
                if str(user["id"]) == uid:
                    return self._send(200, user)
            return self._send(404, {"error": "Not found"})
        self._send(404, {"error": "Not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            return self._send(400, {"error": "Invalid JSON"})
        if self.path == "/login":
            if body.get("email") == "user@example.com" and body.get("password") == "secret":
                return self._send(200, {"ok": True})
            return self._send(401, {"error": "Invalid credentials"})
        if self.path == "/api/users":
            if not body.get("name"):
                return self._send(422, {"error": "name is required"})
            # Planted bug 2: should create the user and answer 201.
            return self._send(500, {"error": "Internal server error"})
        self._send(404, {"error": "Not found"})

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
```

`docs/testing/plans/2026-09-24-qa-bench-test-plan.md`:

```markdown
# Test Plan: QA bench

## Source
- Type: branch main
- Base: main
- Date: 2026-09-24

## Changes Summary

Login form on the home page, About page, and the users API (`/api/users`). Base URL: http://127.0.0.1:8765

## Detected Tools
- Playwright MCP: available
- HTTP client: curl
- Database access: unavailable

## FE Test Scenarios

### FE-01: Login with valid credentials shows a welcome message
- **Area:** Home page login form
- **Preconditions:** App running at http://127.0.0.1:8765
- **Steps:**
  1. Open http://127.0.0.1:8765/
  2. Fill Email with `user@example.com` and Password with `secret`
  3. Click "Sign In"
- **Expected:** The text "Welcome back" is shown on the page
- **Edge cases:**
  - Password `wrong`: the text "Invalid credentials" is shown
  - Empty email and password: the text "Invalid credentials" is shown

### FE-02: About page shows its heading
- **Area:** About page
- **Preconditions:** App running at http://127.0.0.1:8765
- **Steps:**
  1. Open http://127.0.0.1:8765/
  2. Click the "About" link
- **Expected:** The page heading reads exactly "About page"
- **Edge cases:**
  - The page title is "About"
  - Clicking "Home" returns to a page whose heading is "Hello QA"

## BE Test Scenarios

### BE-01: GET /api/users returns the user list
- **Area:** Users API
- **Method:** GET /api/users
- **Headers:** none
- **Payload:** none
- **Expected:** 200, a JSON array containing a user with name "John"
- **Edge cases:**
  - GET /api/users/1 → 200 with `{"id": 1, "name": "John"}`
  - GET /api/users/999 → 404

### BE-02: POST /api/users creates a user
- **Area:** Users API
- **Method:** POST /api/users
- **Headers:** Content-Type: application/json
- **Payload:** `{"name": "Jane"}`
- **Expected:** 201, JSON body with the created user
- **Edge cases:**
  - Payload `{}` → 422
  - Body `not json` → 400
```

Ground truth for one run: FE-01 PASS, FE-02 FAIL (heading is "Abuot page"), BE-01 PASS, BE-02 FAIL (500), all eight edge cases PASS; the report `docs/testing/reports/2026-09-24-qa-bench-report.md` lists exactly two issues, `QA-001` and `QA-002`, and the FE-02 issue names a screenshot file that exists under `docs/testing/reports/screenshots/`.

5. Model comparison for the `tester` role, steps 5a-5e below. Candidates are the models already mapped in `~/.omp/agent/config.yml`: `openai-codex/gpt-6-sol:xhigh`, `anthropic/claude-opus-5-5:xhigh`, `anthropic/claude-fable-5-1:xhigh`, `openai-codex/gpt-6-astra`, `opencode-go/kimi-k2.7-code:off`. Back up the config first (`cp ~/.omp/agent/config.yml ~/.omp/agent/config.yml.bak-qa-bench`), then run 5a-5d for each candidate in that order, and 5e once.
6. Cleanup: stop the fixture server (`kill` the `python3 app.py` process), `rm -rf /tmp/qa-bench`. Restart OMP afterwards: the running session loaded plugins at start and will not see `qa` until then.

**5a. Set the role** (`M` is the candidate string):

```bash
python3 - "$M" <<'EOF'
import re, sys
from pathlib import Path
path = Path.home() / ".omp/agent/config.yml"
text = path.read_text()
line = f"  tester: {sys.argv[1]}"
if re.search(r"^  tester: .*$", text, re.M):
    text = re.sub(r"^  tester: .*$", line, text, count=1, flags=re.M)
else:
    text = text.replace("modelRoles:\n", f"modelRoles:\n{line}\n", 1)
path.write_text(text)
EOF
grep -n '^  tester:' ~/.omp/agent/config.yml
```

**5b. Reset the fixture:** `rm -rf /tmp/qa-bench/docs/testing/reports`.

**5c. Run** from `/tmp/qa-bench`, wall-clocked: `time omp -p "/qa:run docs/testing/plans/2026-09-24-qa-bench-test-plan.md"` with a 20-minute timeout (the first run of the day may download Chromium). If the reply treats `/qa:run` as plain text (no report written, no `qa:fe-tester` in the transcript), the slash command was not expanded in print mode: run instead `omp -p "Read the command file $(readlink -f ~/.omp/plugins/node_modules/qa)/commands/run.md and execute it with the argument docs/testing/plans/2026-09-24-qa-bench-test-plan.md"` and note the deviation in the report. A run that ends in a provider or authentication error is repeated once; if it fails again the candidate is recorded as unavailable and excluded.

**5d. Score** from the report file and the transcripts. Verdicts: compare the four scenario statuses and the eight edge-case results with the ground truth (12 items). Evidence: the FE-02 screenshot path exists as a file; the BE-02 entry records status 500. SKIPs: any scenario skipped for "unavailable" counts as a failure of the run. Cost and calls come from the tester transcripts, the `*.jsonl` files nested inside the run's session directory (the newest directory under `~/.omp/agent/sessions/--private-tmp-qa-bench--/`; if that path does not exist, take `ls -t ~/.omp/agent/sessions | head -1`). Each transcript line is JSON; sum over entries with `"type": "message"` the fields `message.usage.cost.total` and `message.usage.totalTokens`, and count `message.content` items with `"type": "toolCall"`:

```bash
python3 - <<'EOF'
import json
from pathlib import Path
root = Path.home() / ".omp/agent/sessions/--private-tmp-qa-bench--"
run = max((p for p in root.iterdir() if p.is_dir()), key=lambda p: p.stat().st_mtime)
cost = tokens = calls = 0
for transcript in sorted(run.glob("*.jsonl")):
    for line in transcript.read_text().splitlines():
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if entry.get("type") != "message":
            continue
        message = entry.get("message") or {}
        usage = message.get("usage") or {}
        cost += (usage.get("cost") or {}).get("total", 0)
        tokens += usage.get("totalTokens", 0)
        calls += sum(1 for item in message.get("content") or [] if isinstance(item, dict) and item.get("type") == "toolCall")
print(f"{run.name}: testers={[t.stem for t in run.glob('*.jsonl')]} cost=${cost:.4f} tokens={tokens} toolCalls={calls}")
EOF
```

**5e. Decide.** Highest verdict accuracy wins; ties are broken by evidence completeness, then lowest tester cost, then lowest wall time. If the top two tie on accuracy and evidence, run both once more and compare their summed costs. Write the winner to `modelRoles.tester` in `~/.omp/agent/config.yml` with the 5a snippet (leave the backup in place), and report a table with, per candidate: accuracy (n/12), evidence (screenshot yes/no, 500 recorded yes/no), SKIPs, tester cost in USD, tester tokens, tool calls, wall time, and any deviation.

## Assumptions & contingencies

- Version: `qa` stays 2.6.0 because `plugins/qa/` is unchanged (precedent: the code-review and developer-plugin overlays). If review insists on a bump, bump to 2.7.0 in all four places (`plugins/qa/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, the README row, `docs/plugins/qa.md` `**Version:**`) and regenerate.
- The already-installed OMP plugins (code-review, commit, developer plugins) keep their versions, so `omp plugin upgrade` will not refresh their copies with the new preamble bullets; only `qa` is installed. If the model comparison shows `/code-review:fix` naming or MCP-name confusion in an installed plugin, reinstall it with `omp plugin install <name>@av-marketplace`.
- Print mode and slash commands: print mode sends the prompt through `AgentSession.prompt()` (OMP `src/modes/print-mode.ts:268`), which expands a leading `/…` slash command (`src/session/agent-session.ts:6431-6433`), so `omp -p "/qa:run …"` is expected to work; the fallback in step 5.3 covers the case it does not.
- If `browser.open` fails in a tester subagent under `omp -p` (no Chromium download possible, or `browser.enabled: false`), the FE scenarios are reported as SKIP by the agent's own rule. In that case set `browser.enabled: true` in `~/.omp/agent/config.yml`, run `omp -p 'Use eval to open https://example.com with browser.open and print the title'` once to trigger the download, and repeat the run; do not change the plugin.
- If a candidate model rejects the `:xhigh` thinking suffix, run it with the suffix removed and note it in the table.
