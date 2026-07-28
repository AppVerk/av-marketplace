---
allowed-tools: Bash(curl:*), Bash(dig:*), Bash(nmap:*), Bash(python:*), Bash(python3:*), Bash(openssl:*), Bash(timeout:*), Bash(base64:*), Bash(echo:*), Bash(jq:*), Bash(grep:*), Bash(head:*), Bash(tail:*), Bash(sort:*), Bash(wc:*), Bash(cat:*), Bash(date:*), Bash(mkdir:*), mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_snapshot, mcp__plugin_playwright_playwright__browser_evaluate, mcp__plugin_playwright_playwright__browser_click, mcp__plugin_playwright_playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_console_messages, mcp__plugin_playwright_playwright__browser_network_requests, mcp__plugin_playwright_playwright__browser_run_code, mcp__plugin_playwright_playwright__browser_close, mcp__plugin_playwright_playwright__browser_tabs
description: Perform a comprehensive passive web audit. Scans security, SEO, performance, and compliance.
model: opus
argument-hint: <url> [--scope all|security|seo|performance|compliance] [--depth N] [--output-dir path] [--verify]
---

# Passive Web Audit

You are a web audit orchestrator performing a comprehensive passive assessment.

## Target

**Input:** $ARGUMENTS

Parse the arguments:
- First argument: **target URL** (required) — must start with `http://` or `https://`
- `--scope <scope>`: audit scope (default: `all`). Valid values: `all`, `security`, `seo`, `performance`, `compliance`
- `--depth N`: crawl depth for internal links (default: 2, max: 5)
- `--output-dir path`: directory for the report file (default: `.`)
- `--verify`: enable verification phase with Cross-Verifier and Challenger subagents (default: off)

### Validation

If no URL is provided or the URL is invalid, show usage and stop:

```
Usage: /audit <url> [--scope all|security|seo|performance|compliance] [--depth N] [--output-dir path] [--verify]

Scopes:
  all          Full audit: security + SEO + performance + compliance (default)
  security     Web app, API, infrastructure, and supply chain security
  seo          Indexability, metadata, structured data, rendering, internal linking
  performance  Core Web Vitals, images, fonts, JS/CSS optimization
  compliance   GDPR, cookies, privacy policy, analytics, data exposure

Examples:
  /audit https://example.com
  /audit https://example.com --scope security
  /audit https://example.com --scope seo --depth 3
  /audit https://example.com --scope all --output-dir ./reports
  /audit https://example.com --scope security --verify
```

If an invalid scope is provided, show the valid scopes and stop.

## Ethical Disclaimer

Display this before starting:

```
PASSIVE WEB AUDIT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
This audit uses ONLY passive, legal, non-invasive methods:
- No login attempts, brute-force, or exploits
- No data modification or destructive actions
- Passive port scanning only (nmap top ports, polite timing)
- Public resources only
- All findings are from an external, unauthenticated perspective

Target: {URL}
Scope:  {scope}
Depth:  {depth}
Output: {output_dir}/audit-{domain}-{scope|full}-{date}.md
Mode:   {if --verify: "Verified (cross-domain correlation + adversarial review)" else: "Standard"}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Starting scan...
```

## Execution

Launch the web-auditor coordinator agent using the Agent tool:

```
Agent(
  subagent_type: "web-auditor",
  description: "Web audit of {domain} ({scope})",
  prompt: "Perform a comprehensive passive web audit of {URL}. Scope: {scope}. Crawl depth: {depth}. Output directory: {output_dir}. Verify: {true|false}. Follow the complete workflow: Phase 1 (shared recon), Phase 2 (parallel scanning agents for the requested scope), {if verify: Phase 2.5 (Verification — cross-domain correlation and adversarial review),} Phase 3 (consolidation and report generation)."
)
```

Wait for the agent to complete.

## Results Display

After the agent completes, display a summary based on the scope:

```
AUDIT COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Target: {domain}
Scope:  {scope}
Duration: ~{minutes} minutes
Mode:   {if verify: "Verified" else: "Standard"}
{if verify:}
Verification:
  Findings verified: {n}
  False positives removed: {n}
  Severity adjustments: {n}
  Cross-domain findings: {n}

Findings by severity:
  Critical: {n}
  High:     {n}
  Medium:   {n}
  Low:      {n}
  Info:     {n}

{If scope includes security:}
Security: {n} findings
{If scope includes seo:}
SEO: {n} findings
{If scope includes performance:}
Performance: {n} findings
{If scope includes compliance:}
Compliance: {n} findings

Top 3 findings:
1. [{SEVERITY}] {finding title}
2. [{SEVERITY}] {finding title}
3. [{SEVERITY}] {finding title}

Full report: {output_dir}/audit-{domain}-{scope|full}-{date}.md
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Error Handling

- If the target URL is unreachable, report the error and stop
- If Playwright is not available, note that JS rendering checks will be limited
- If nmap is not available, note that port scanning will use curl fallback
- If any scanning agent fails, continue with remaining agents and note the failure
