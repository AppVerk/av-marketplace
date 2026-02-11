# Web Auditor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the `pentester` plugin into `web-auditor` — a comprehensive web audit plugin with 4 scopes (security, SEO, performance, compliance) and 7 parallel agents.

**Architecture:** Single `/audit` command with `--scope` flag dispatches to a coordinator agent that runs shared Phase 1 recon, then launches scope-specific agents in parallel. Security keeps its 4 existing agents; SEO, Performance, and Compliance each get 1 new agent with a dedicated checklist skill.

**Tech Stack:** Claude Code plugin system (markdown-based agents, skills, commands), Playwright MCP, curl, dig, nmap, openssl

**Design doc:** `docs/plans/2026-02-11-web-auditor-design.md`

---

### Task 1: Rename plugin directory and files

Rename the plugin from `pentester` to `web-auditor` using git mv to preserve history.

**Step 1: Rename directory and key files**

Run:
```bash
cd /Users/mef1st0/Projects/claude-code/av-marketplace
git mv plugins/pentester plugins/web-auditor
git mv plugins/web-auditor/commands/pentest.md plugins/web-auditor/commands/audit.md
git mv plugins/web-auditor/agents/pentester.md plugins/web-auditor/agents/web-auditor.md
git mv docs/plugins/pentester.md docs/plugins/web-auditor.md
```

**Step 2: Verify renames**

Run: `find plugins/web-auditor -type f | sort`

Expected: all files under `plugins/web-auditor/`, no `pentester` references in paths.

**Step 3: Commit**

```bash
git add -A
git commit -m "refactor: rename pentester plugin to web-auditor"
```

---

### Task 2: Update plugin.json

**File:** Modify `plugins/web-auditor/.claude-plugin/plugin.json`

**Step 1: Write updated plugin.json**

```json
{
  "name": "web-auditor",
  "description": "Comprehensive web audit with multi-agent architecture covering security, SEO, performance, and compliance",
  "version": "2.0.0"
}
```

**Step 2: Commit**

```bash
git add plugins/web-auditor/.claude-plugin/plugin.json
git commit -m "chore: update plugin.json for web-auditor v2.0.0"
```

---

### Task 3: Create commands/audit.md

Replaces the old `pentest.md` command. Adds `--scope` flag parsing and scope-aware agent dispatch.

**File:** Overwrite `plugins/web-auditor/commands/audit.md`

**Step 1: Write the audit command**

The command must:
- Parse arguments: `<url>`, `--scope <scope>`, `--depth N`, `--output-dir path`
- Validate URL and scope
- Display ethical disclaimer with scope info
- Launch the `web-auditor` coordinator agent via Task tool
- Display results summary with scope-specific findings

The `--scope` flag accepts: `security`, `seo`, `performance`, `compliance`, `all` (default).

Key differences from old pentest.md:
- `allowed-tools`: same as pentest.md (all tools needed by coordinator)
- `argument-hint`: `<url> [--scope all|security|seo|performance|compliance] [--depth N] [--output-dir path]`
- `description`: updated to mention all scopes
- Ethical disclaimer updated for non-security scopes
- Results display shows findings grouped by scope
- Output filename: `audit-{domain}-{scope}-{YYYY-MM-DD}.md` or `audit-{domain}-full-{YYYY-MM-DD}.md`

Full content for `audit.md`:

~~~markdown
---
allowed-tools: Bash(curl:*), Bash(dig:*), Bash(nmap:*), Bash(python:*), Bash(python3:*), Bash(openssl:*), Bash(timeout:*), Bash(base64:*), Bash(echo:*), Bash(jq:*), Bash(grep:*), Bash(head:*), Bash(tail:*), Bash(sort:*), Bash(wc:*), Bash(cat:*), Bash(date:*), Bash(mkdir:*), mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_snapshot, mcp__plugin_playwright_playwright__browser_evaluate, mcp__plugin_playwright_playwright__browser_click, mcp__plugin_playwright_playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_console_messages, mcp__plugin_playwright_playwright__browser_network_requests, mcp__plugin_playwright_playwright__browser_run_code, mcp__plugin_playwright_playwright__browser_close, mcp__plugin_playwright_playwright__browser_tabs
description: Perform a comprehensive passive web audit. Scans security, SEO, performance, and compliance.
model: claude-opus-4-6
argument-hint: <url> [--scope all|security|seo|performance|compliance] [--depth N] [--output-dir path]
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

### Validation

If no URL is provided or the URL is invalid, show usage and stop:

```
Usage: /audit <url> [--scope all|security|seo|performance|compliance] [--depth N] [--output-dir path]

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
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Starting scan...
```

## Execution

Launch the web-auditor coordinator agent using the Task tool:

```
Task(
  subagent_type: "web-auditor",
  description: "Web audit of {domain} ({scope})",
  prompt: "Perform a comprehensive passive web audit of {URL}. Scope: {scope}. Crawl depth: {depth}. Output directory: {output_dir}. Follow the complete workflow: Phase 1 (shared recon), Phase 2 (parallel scanning agents for the requested scope), Phase 3 (consolidation and report generation)."
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
~~~

**Step 2: Commit**

```bash
git add plugins/web-auditor/commands/audit.md
git commit -m "feat(web-auditor): add /audit command with --scope flag"
```

---

### Task 4: Create agents/web-auditor.md (coordinator)

Replaces the old `pentester.md` coordinator. Adds scope-aware Phase 1 recon (metadata, performance metrics, cookies/consent), scope-aware Phase 2 dispatch (only launches agents for requested scope), and expanded Phase 3 report template.

**File:** Overwrite `plugins/web-auditor/agents/web-auditor.md`

**Step 1: Write the coordinator agent**

Key differences from old pentester.md:
- `name`: `web-auditor`
- `description`: mentions all 4 scopes
- `skills`: adds `seo-checklist`, `performance-checklist`, `compliance-checklist`
- Phase 1: adds steps 6-8 (metadata collection, performance metrics, cookie/consent detection)
- Phase 2: scope-conditional agent dispatch
- Phase 3: expanded report template with all scope sections, SEO scorecard, Performance scorecard

Full content for `web-auditor.md`:

~~~markdown
---
name: web-auditor
description: Coordinator agent for comprehensive passive web auditing. Crawls target URL, dispatches up to 7 parallel scanning agents (security, SEO, performance, compliance), and consolidates findings into a Markdown report.
tools: Read, Write, Bash, Grep, Glob, Task, TaskOutput, WebFetch, WebSearch
allowed-tools: Bash(curl:*), Bash(dig:*), Bash(nmap:*), Bash(python:*), Bash(python3:*), Bash(openssl:*), Bash(timeout:*), Bash(base64:*), Bash(echo:*), Bash(jq:*), Bash(grep:*), Bash(head:*), Bash(tail:*), Bash(sort:*), Bash(wc:*), Bash(cat:*), Bash(date:*), Bash(mkdir:*), mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_snapshot, mcp__plugin_playwright_playwright__browser_evaluate, mcp__plugin_playwright_playwright__browser_click, mcp__plugin_playwright_playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_console_messages, mcp__plugin_playwright_playwright__browser_network_requests, mcp__plugin_playwright_playwright__browser_run_code, mcp__plugin_playwright_playwright__browser_close, mcp__plugin_playwright_playwright__browser_tabs
model: claude-opus-4-6
skills: web-security-checklist, api-security-checklist, infrastructure-checklist, supply-chain-checklist, seo-checklist, performance-checklist, compliance-checklist
---

# Web Auditor Coordinator Agent

You are a web audit coordinator performing a comprehensive passive assessment of a target website.

## Input

You receive:
- **Target URL** — the website to audit
- **Scope** — which areas to audit: `all`, `security`, `seo`, `performance`, `compliance`
- **Crawl depth** — how deep to crawl internal links (default: 2)
- **Output directory** — where to save the report (default: `.`)

## Ethical Rules — MANDATORY

- Legal and non-invasive methods ONLY
- No login attempts, brute-force, or exploits
- No data modification or destructive actions
- Passive port scanning only (nmap top ports, polite timing T2)
- Public resources only
- If in doubt, skip the check and note it as "skipped — out of scope"

## Workflow

### Phase 1: Shared Reconnaissance (sequential)

Perform ALL these steps regardless of the requested scope. The data collected here feeds every agent.

**1. Crawl target with Playwright**

Navigate to the target URL using Playwright. Collect all internal links recursively up to the specified depth:

```javascript
// Use browser_evaluate to collect links
const links = Array.from(document.querySelectorAll('a[href]'))
  .map(a => a.href)
  .filter(href => href.startsWith(window.location.origin));
```

For each discovered internal URL, navigate and collect more links (up to depth limit). Record for each URL: URL, status code, content type.

**2. Collect HTTP response headers**

For each URL in the inventory:
```bash
curl -sI "URL"
```

**3. Fetch robots.txt and sitemap.xml**

```bash
curl -s "https://DOMAIN/robots.txt"
curl -s "https://DOMAIN/sitemap.xml"
```

**4. Technology detection**

From headers, HTML meta tags, and JS globals, identify:
- Server software (from Server header)
- Frameworks (from X-Powered-By, meta generator tags)
- JavaScript libraries (from globals via Playwright evaluate)

**5. Build URL inventory**

Create a deduplicated list of all discovered URLs with metadata. This becomes the shared context for Phase 2.

**6. Collect page metadata (for SEO)**

For each URL in the inventory, extract via Playwright:

```javascript
const metadata = {
  title: document.title,
  metaDescription: document.querySelector('meta[name="description"]')?.content,
  metaRobots: document.querySelector('meta[name="robots"]')?.content,
  canonical: document.querySelector('link[rel="canonical"]')?.href,
  hreflang: Array.from(document.querySelectorAll('link[rel="alternate"][hreflang]')).map(el => ({
    lang: el.hreflang,
    href: el.href
  })),
  ogTitle: document.querySelector('meta[property="og:title"]')?.content,
  ogDescription: document.querySelector('meta[property="og:description"]')?.content,
  ogImage: document.querySelector('meta[property="og:image"]')?.content,
  twitterCard: document.querySelector('meta[name="twitter:card"]')?.content,
  jsonLd: Array.from(document.querySelectorAll('script[type="application/ld+json"]')).map(el => {
    try { return JSON.parse(el.textContent); } catch { return null; }
  }).filter(Boolean),
  h1: Array.from(document.querySelectorAll('h1')).map(el => el.textContent.trim()),
  headingStructure: ['h1','h2','h3','h4','h5','h6'].map(tag => ({
    tag,
    count: document.querySelectorAll(tag).length
  })),
  lang: document.documentElement.lang
};
JSON.stringify(metadata, null, 2);
```

**7. Capture performance metrics (for Performance)**

For each URL in the inventory, collect via Playwright:

```javascript
const perfData = {
  navigation: performance.getEntriesByType('navigation')[0],
  resources: performance.getEntriesByType('resource').map(r => ({
    name: r.name,
    type: r.initiatorType,
    size: r.transferSize,
    duration: r.duration,
    protocol: r.nextHopProtocol
  })),
  paint: performance.getEntriesByType('paint').map(p => ({
    name: p.name,
    startTime: p.startTime
  })),
  totalTransferSize: performance.getEntriesByType('resource').reduce((sum, r) => sum + (r.transferSize || 0), 0),
  resourceCount: performance.getEntriesByType('resource').length,
  domContentLoaded: performance.getEntriesByType('navigation')[0]?.domContentLoadedEventEnd,
  loadComplete: performance.getEntriesByType('navigation')[0]?.loadEventEnd
};
JSON.stringify(perfData, null, 2);
```

Also collect image data:
```javascript
const images = Array.from(document.querySelectorAll('img')).map(img => ({
  src: img.src,
  naturalWidth: img.naturalWidth,
  naturalHeight: img.naturalHeight,
  displayWidth: img.clientWidth,
  displayHeight: img.clientHeight,
  loading: img.loading,
  hasWidthAttr: img.hasAttribute('width'),
  hasHeightAttr: img.hasAttribute('height'),
  alt: img.alt
}));
JSON.stringify(images, null, 2);
```

**8. Detect cookies & consent (for Compliance)**

Before any interaction, collect via Playwright:

```javascript
const complianceData = {
  cookies: document.cookie.split(';').map(c => c.trim()).filter(Boolean),
  consentBanner: !!(
    document.querySelector('[class*="cookie"], [class*="consent"], [id*="cookie"], [id*="consent"], [class*="gdpr"], [id*="gdpr"]') ||
    document.querySelector('[aria-label*="cookie"], [aria-label*="consent"]')
  ),
  analyticsScripts: Array.from(document.querySelectorAll('script[src]')).filter(s => {
    const src = s.src.toLowerCase();
    return src.includes('google-analytics') || src.includes('googletagmanager') ||
           src.includes('gtag') || src.includes('facebook') || src.includes('fbevents') ||
           src.includes('hotjar') || src.includes('clarity') || src.includes('segment') ||
           src.includes('mixpanel') || src.includes('amplitude');
  }).map(s => s.src),
  privacyLinks: Array.from(document.querySelectorAll('a[href]')).filter(a => {
    const text = (a.textContent + ' ' + a.href).toLowerCase();
    return text.includes('privacy') || text.includes('prywatno') || text.includes('rodo') ||
           text.includes('gdpr') || text.includes('cookie') || text.includes('datenschutz');
  }).map(a => ({ text: a.textContent.trim(), href: a.href })),
  thirdPartyScripts: Array.from(document.querySelectorAll('script[src]'))
    .filter(s => !s.src.includes(window.location.hostname))
    .map(s => s.src)
};
JSON.stringify(complianceData, null, 2);
```

Also capture cookies from HTTP headers:
```bash
curl -sI "URL" | grep -i "set-cookie"
```

### Phase 2: Parallel Scanning

Launch agents in parallel (all with `run_in_background: true`) based on the requested scope.

Pass each agent the relevant data from Phase 1.

#### If scope is `security` or `all`:

**Agent 1: WebAppSecurityAgent**

```
Task(
  subagent_type: "web-auditor:web-security-agent",
  run_in_background: true,
  description: "Web app security scan of {domain}",
  prompt: "Perform a passive web application security assessment of {TARGET}.
    Here are the URLs to scan: {url inventory}.
    Here are the collected headers: {headers}.
    Follow your web-security-checklist skill systematically.
    Return ALL findings organized by severity: Critical, High, Medium, Low, Info."
)
```

**Agent 2: APISecurityAgent**

```
Task(
  subagent_type: "web-auditor:api-security-agent",
  run_in_background: true,
  description: "API security scan of {domain}",
  prompt: "Perform a passive API security assessment of {TARGET}.
    Here are the URLs to scan: {url inventory}.
    Here are the collected headers: {headers}.
    Discovered API endpoints: {api endpoints from Phase 1}.
    Follow your api-security-checklist skill systematically.
    Return ALL findings organized by severity: Critical, High, Medium, Low, Info."
)
```

**Agent 3: InfrastructureAgent**

```
Task(
  subagent_type: "web-auditor:infrastructure-agent",
  run_in_background: true,
  description: "Infrastructure security scan of {domain}",
  prompt: "Perform a passive infrastructure security assessment of {domain}.
    Here are the collected headers: {headers}.
    Follow your infrastructure-checklist skill systematically.
    Return ALL findings organized by severity: Critical, High, Medium, Low, Info."
)
```

**Agent 4: SupplyChainAgent**

```
Task(
  subagent_type: "web-auditor:supply-chain-agent",
  run_in_background: true,
  description: "Supply chain security scan of {domain}",
  prompt: "Perform a passive supply chain security assessment of {TARGET}.
    Here are the URLs to scan: {url inventory}.
    Detected technologies: {technologies from Phase 1}.
    Follow your supply-chain-checklist skill systematically.
    Return ALL findings organized by severity: Critical, High, Medium, Low, Info."
)
```

#### If scope is `seo` or `all`:

**Agent 5: SEOAgent**

```
Task(
  subagent_type: "web-auditor:seo-agent",
  run_in_background: true,
  description: "SEO audit of {domain}",
  prompt: "Perform a passive technical SEO audit of {TARGET}.
    Here are the URLs to scan: {url inventory}.
    Here are the collected headers: {headers}.
    Here is the page metadata per URL: {metadata}.
    Here is robots.txt: {robots_txt}.
    Here is sitemap.xml: {sitemap_xml}.
    Detected technologies: {technologies from Phase 1}.
    Follow your seo-checklist skill systematically.
    Return ALL findings organized by severity: Critical, High, Medium, Low, Info."
)
```

#### If scope is `performance` or `all`:

**Agent 6: PerformanceAgent**

```
Task(
  subagent_type: "web-auditor:performance-agent",
  run_in_background: true,
  description: "Performance audit of {domain}",
  prompt: "Perform a passive performance audit of {TARGET}.
    Here are the URLs to scan: {url inventory}.
    Here is the performance data per URL: {perf_data}.
    Here is the image data per URL: {image_data}.
    Here are the collected headers: {headers}.
    Detected technologies: {technologies from Phase 1}.
    Follow your performance-checklist skill systematically.
    Return ALL findings organized by severity: Critical, High, Medium, Low, Info."
)
```

#### If scope is `compliance` or `all`:

**Agent 7: ComplianceAgent**

```
Task(
  subagent_type: "web-auditor:compliance-agent",
  run_in_background: true,
  description: "Compliance audit of {domain}",
  prompt: "Perform a passive compliance and privacy audit of {TARGET}.
    Here are the URLs to scan: {url inventory}.
    Here is the compliance data per URL: {compliance_data}.
    Here are the collected headers: {headers}.
    Here are the Set-Cookie headers: {cookie_headers}.
    Follow your compliance-checklist skill systematically.
    Return ALL findings organized by severity: Critical, High, Medium, Low, Info."
)
```

### Phase 3: Consolidation (sequential)

After all dispatched agents complete:

1. **Collect results** — Use TaskOutput with `block: true` for each agent
2. **Deduplicate** — Same issue found by multiple agents → keep the most detailed version, tag with all relevant scopes
3. **Sort by severity** — Critical > High > Medium > Low > Info
4. **Count findings** — Tally per severity level and per scope
5. **Generate the final report** using the template below
6. **Write report to file** — `{output_dir}/audit-{domain}-{scope|full}-{YYYY-MM-DD}.md`

## Report Template

Write the report using this structure. **Include only sections relevant to the active scope(s).**

```markdown
# Web Audit Report: {domain}

**Date:** {YYYY-MM-DD}
**Scope:** {security, seo, performance, compliance | specific scope}
**Method:** Passive, outside-in, multi-agent scan
**URLs analyzed:** {count}

---

## Executive Summary

### Overall Assessment

{2-3 sentences per active scope describing the overall posture. Cover key strengths and weaknesses. End with the risk level justification.}

**Risk Level:** {Critical / High / Medium / Low} — based on the most severe finding

| Severity | Count |
|----------|-------|
| Critical | {n} |
| High | {n} |
| Medium | {n} |
| Low | {n} |
| Info | {n} |

{If scope = all, show findings per scope:}

| Scope | Critical | High | Medium | Low | Info |
|-------|----------|------|--------|-----|------|
| Security | {n} | {n} | {n} | {n} | {n} |
| SEO | {n} | {n} | {n} | {n} | {n} |
| Performance | {n} | {n} | {n} | {n} | {n} |
| Compliance | {n} | {n} | {n} | {n} | {n} |

### Critical & High Findings

{For each Critical and High finding, list in severity order:}

- **[Critical] {Finding title}** — {1-sentence description}. *Recommendation: {specific fix}.*
- **[High] {Finding title}** — {1-sentence description}. *Recommendation: {specific fix}.*

{If none: "No critical or high severity findings were identified."}

---

## Scope & Methodology

### URLs Analyzed
{List of all URLs in inventory}

### Tools Used
- Playwright (JS rendering, DOM analysis, performance metrics)
- curl (HTTP headers, API probing)
- dig (DNS analysis)
- nmap (port scanning, polite mode)
- SSL Labs API (TLS analysis)
- WebSearch (CVE lookup)

### Limitations
- Passive scanning only — no active exploitation
- No authenticated testing
- External perspective only

---

{If scope includes security:}

## Results — Security

### Web Application Security

{All WebAppSec findings, sorted by severity}

### API Security

{All APISec findings, sorted by severity}

### Infrastructure

{All Infra findings, sorted by severity}

### Supply Chain

{All SupplyChain findings, sorted by severity}

---

{If scope includes seo:}

## Results — Technical SEO

### Indexability

{Findings about robots.txt, meta robots, canonical, noindex}

### Metadata

{Findings about title, description, headings, duplicates}

### Structured Data

{Findings about JSON-LD, Schema.org, Rich Results}

### Rendering

{Findings about SSR/CSR, JS-dependent content}

### Internal Linking

{Findings about orphan pages, broken links, link depth}

---

{If scope includes performance:}

## Results — Performance

### Core Web Vitals

{LCP, CLS, INP findings per URL}

### Images

{Format, sizing, lazy loading findings}

### Fonts

{font-display, preload, FOUT/FOIT findings}

### JavaScript & CSS

{Bundle size, render-blocking, unused code findings}

### Caching & Compression

{Cache-Control, ETags, gzip/brotli findings}

---

{If scope includes compliance:}

## Results — Compliance & Privacy

### Cookie Consent

{Consent banner, pre-consent cookies findings}

### Cookie Inventory

{Table of all cookies with flags and classification}

| Cookie | Domain | Expiry | Type | Secure | HttpOnly | SameSite |
|--------|--------|--------|------|--------|----------|----------|

### Privacy Policy

{Presence, accessibility, GDPR completeness}

### Data Exposure

{Personal data in URLs, emails, phones}

### Analytics & Tracking

{Detected scripts, pre-consent firing}

---

## TOP 10 Problems

{Cross-scope, sorted by severity and business impact}

| # | Severity | Finding | Scope | Owner | Recommendation |
|---|----------|---------|-------|-------|----------------|
| 1 | Critical | ... | Security | Dev | ... |
| ... | ... | ... | ... | ... | ... |

---

## HTTP Headers Scorecard

| Header | Status | Value | Notes |
|--------|--------|-------|-------|
| Strict-Transport-Security | /  | ... | ... |
| Content-Security-Policy | /  | ... | ... |
| X-Content-Type-Options | /  | ... | ... |
| X-Frame-Options | /  | ... | ... |
| Permissions-Policy | /  | ... | ... |
| Referrer-Policy | /  | ... | ... |
| Cache-Control | /  | ... | ... |

---

{If scope includes seo:}

## SEO Scorecard

| Area | Status | Notes | Next Step |
|------|--------|-------|-----------|
| robots.txt | /  | ... | ... |
| sitemap.xml | /  | ... | ... |
| Meta titles | /  | ... | ... |
| Meta descriptions | /  | ... | ... |
| Canonical tags | /  | ... | ... |
| Structured data | /  | ... | ... |
| OpenGraph | /  | ... | ... |
| Mobile-friendly | /  | ... | ... |
| Heading hierarchy | /  | ... | ... |

---

{If scope includes performance:}

## Performance Scorecard

| Metric | Value | Target | Status | Notes |
|--------|-------|--------|--------|-------|
| LCP | {value}s | < 2.5s | /  | ... |
| CLS | {value} | < 0.1 | /  | ... |
| Total transfer size | {value} KB | ... | ... | ... |
| Resource count | {n} | ... | ... | ... |
| DOM Content Loaded | {value}ms | ... | ... | ... |

---

## Quick Wins (48h)

{List of findings that can be fixed quickly — headers, cookie flags, missing meta tags, image optimization, consent banner fixes}

---

## 90-Day Roadmap

| Week | Action | Severity | Scope | Owner |
|------|--------|----------|-------|-------|
| 1 | Fix critical findings | Critical | All | Security/Dev |
| 2-4 | Address high findings | High | All | Dev/DevOps |
| 4-8 | Address medium findings | Medium | All | Dev/Marketing |
| 8-12 | Address low findings | Low | All | Dev |

---

## Appendix

### Detected Technologies
{List of detected technologies, frameworks, libraries with versions}

### DNS Records Summary
{SPF, DMARC, DKIM status}

### Certificate Information
{SSL/TLS details}

### Full URL Inventory
{All discovered URLs with status codes}
```

## Final Checklist

Before completing, verify:
- [ ] Phase 1 recon completed, URL inventory built
- [ ] Phase 1 metadata, performance, and compliance data collected
- [ ] All scope-appropriate scanning agents launched and results collected
- [ ] Findings deduplicated across scopes and severity-sorted
- [ ] Executive Summary written with per-scope assessment
- [ ] TOP 10 table populated with cross-scope findings
- [ ] HTTP Headers Scorecard filled
- [ ] SEO Scorecard filled (if scope includes seo)
- [ ] Performance Scorecard filled (if scope includes performance)
- [ ] Quick Wins identified across all active scopes
- [ ] Report written to file
- [ ] Report file path communicated back
~~~

**Step 2: Commit**

```bash
git add plugins/web-auditor/agents/web-auditor.md
git commit -m "feat(web-auditor): add scope-aware coordinator agent"
```

---

### Task 5: Create skills/seo-checklist/SKILL.md

**File:** Create `plugins/web-auditor/skills/seo-checklist/SKILL.md`

**Step 1: Create directory and write the SEO checklist skill**

```bash
mkdir -p plugins/web-auditor/skills/seo-checklist
```

The checklist must follow the same pattern as existing skills:
- Frontmatter with `name`, `description`, `allowed-tools`
- Numbered sections with check procedures (commands, Playwright snippets)
- Severity assessment guide
- Finding report format

Full content: see `seo-checklist` section in the design doc. The skill should cover 8 sections:

1. **Indexability** — robots.txt parsing (disallow directives, crawl-delay), meta robots per URL, X-Robots-Tag header, canonical URL vs actual URL, noindex detection, redirect chains (301 vs 302)
2. **Metadata Quality** — title tag presence/length (30-60 chars ideal)/uniqueness, meta description presence/length (120-160 chars)/uniqueness, H1 presence/count (exactly 1 per page), heading hierarchy (no skipped levels), duplicate titles/descriptions across pages
3. **Structured Data** — JSON-LD presence, Schema.org type validation, required properties per type, nested entities, Google Rich Results eligibility
4. **Rendering** — SSR vs CSR detection (compare curl HTML vs Playwright HTML), JS-dependent content (content missing in curl but present in Playwright), `<noscript>` fallback, hydration errors in console
5. **Internal Linking** — orphan pages (in sitemap but no internal links), broken internal links (404s from inventory), link depth (clicks from homepage), anchor text diversity, navigation completeness
6. **OpenGraph & Social** — og:title, og:description, og:image (presence + dimensions), og:type, og:url, twitter:card, twitter:title, twitter:description, twitter:image
7. **Internationalization** — hreflang correctness (bidirectional), `<html lang>` attribute, locale consistency between hreflang and content
8. **Sitemap & Robots** — sitemap URLs vs crawled URLs (missing/extra), sitemap format (valid XML), lastmod accuracy, robots.txt blocking CSS/JS needed for rendering

Tools: Playwright (DOM analysis, rendered HTML comparison), curl (raw HTML, headers), Bash for text processing.

Severity guide:
| Finding | Severity |
|---------|----------|
| No robots.txt or blocks entire site | High |
| No sitemap.xml | Medium |
| Missing/duplicate title tags | High |
| Missing meta descriptions | Medium |
| Multiple H1 tags or no H1 | Medium |
| Missing canonical tags | Medium |
| Conflicting canonical vs actual URL | High |
| No structured data | Low |
| Invalid structured data | Medium |
| Content invisible without JS (and no SSR) | High |
| Orphan pages | Medium |
| Broken internal links | High |
| Missing OpenGraph tags | Low |
| Missing hreflang (if multilingual) | Medium |
| Sitemap URLs returning 404 | High |
| robots.txt blocks CSS/JS | Medium |

**Step 2: Commit**

```bash
git add plugins/web-auditor/skills/seo-checklist/SKILL.md
git commit -m "feat(web-auditor): add SEO checklist skill"
```

---

### Task 6: Create agents/seo-agent.md

**File:** Create `plugins/web-auditor/agents/seo-agent.md`

**Step 1: Write the SEO agent**

Follow the same pattern as `web-security-agent.md`:
- Frontmatter: `name: seo-agent`, tools, allowed-tools (Playwright + curl + Bash text tools), `model: claude-opus-4-6`, `skills: seo-checklist`
- Input section: target domain, URL inventory, headers, page metadata, robots.txt, sitemap.xml, tech stack
- Ethical rules (same as other agents)
- Workflow: follow `seo-checklist` systematically, execute every check
- Checklist sections list (8 sections from the skill)
- Output format: same finding format as other agents

Allowed tools for SEO agent:
```
Bash(curl:*), Bash(grep:*), Bash(head:*), Bash(tail:*), Bash(echo:*), Bash(cat:*), Bash(python3:*),
mcp__plugin_playwright_playwright__browser_navigate,
mcp__plugin_playwright_playwright__browser_snapshot,
mcp__plugin_playwright_playwright__browser_evaluate,
mcp__plugin_playwright_playwright__browser_take_screenshot,
mcp__plugin_playwright_playwright__browser_console_messages,
mcp__plugin_playwright_playwright__browser_network_requests,
mcp__plugin_playwright_playwright__browser_run_code,
mcp__plugin_playwright_playwright__browser_close,
mcp__plugin_playwright_playwright__browser_tabs
```

**Step 2: Commit**

```bash
git add plugins/web-auditor/agents/seo-agent.md
git commit -m "feat(web-auditor): add SEO scanning agent"
```

---

### Task 7: Create skills/performance-checklist/SKILL.md

**File:** Create `plugins/web-auditor/skills/performance-checklist/SKILL.md`

**Step 1: Create directory and write the performance checklist skill**

```bash
mkdir -p plugins/web-auditor/skills/performance-checklist
```

8 sections:

1. **Core Web Vitals** — LCP measurement via `performance.getEntriesByType('largest-contentful-paint')`, CLS via `PerformanceObserver` for `layout-shift`, INP estimation via event timing, per-URL metrics table
2. **Images** — format detection (check Content-Type for each image, flag PNG/JPG when WebP/AVIF available), oversized images (naturalWidth/Height vs display), lazy loading (`loading="lazy"` on below-fold images), missing width/height attributes (CLS cause), image count and total size
3. **Fonts** — detect `@font-face` declarations via Playwright, check `font-display` property (should be `swap` or `optional`), preload hints for critical fonts (`<link rel="preload" as="font">`), count font files and total size, detect FOUT/FOIT via rendering observation
4. **JavaScript** — total JS transfer size, render-blocking scripts (no `defer`/`async`), third-party JS size and count, inline script size, unused JS estimation (compare coverage if available), number of script requests
5. **CSS** — total CSS transfer size, render-blocking stylesheets, inline critical CSS detection, `<link rel="preload" as="style">` usage, number of CSS files, media query usage for conditional loading
6. **Caching** — Cache-Control headers for static assets (should have `max-age` > 86400), ETag presence, asset fingerprinting (hash in filename), CDN detection from headers, Vary header correctness
7. **Compression** — Content-Encoding header (gzip/br), check all text resources (HTML, CSS, JS, JSON, SVG), compare Content-Length vs uncompressed size where possible
8. **Resource Hints** — `<link rel="preconnect">` for third-party origins, `<link rel="dns-prefetch">` for secondary origins, `<link rel="preload">` for critical resources, `<link rel="modulepreload">` for ES modules

Severity guide:
| Finding | Severity |
|---------|----------|
| LCP > 4.0s | Critical |
| LCP > 2.5s | High |
| CLS > 0.25 | High |
| CLS > 0.1 | Medium |
| No compression on text resources | High |
| Render-blocking JS without defer/async | High |
| Images without width/height (causing CLS) | Medium |
| Oversized images (>2x display size) | Medium |
| No caching headers on static assets | Medium |
| Legacy image formats (PNG/JPG for photos) | Medium |
| Missing font-display: swap | Medium |
| No preconnect for third-party origins | Low |
| Missing lazy loading on below-fold images | Low |
| Large inline scripts (>10KB) | Low |

**Step 2: Commit**

```bash
git add plugins/web-auditor/skills/performance-checklist/SKILL.md
git commit -m "feat(web-auditor): add performance checklist skill"
```

---

### Task 8: Create agents/performance-agent.md

**File:** Create `plugins/web-auditor/agents/performance-agent.md`

**Step 1: Write the performance agent**

Same pattern as other agents. Frontmatter:
- `name: performance-agent`
- `skills: performance-checklist`
- `model: claude-opus-4-6`
- Allowed tools: Playwright (performance API, network requests, evaluate) + curl + Bash text tools

Input: target domain, URL inventory, performance data per URL, image data per URL, headers, tech stack.

Checklist sections: 8 sections matching the skill.

**Step 2: Commit**

```bash
git add plugins/web-auditor/agents/performance-agent.md
git commit -m "feat(web-auditor): add performance scanning agent"
```

---

### Task 9: Create skills/compliance-checklist/SKILL.md

**File:** Create `plugins/web-auditor/skills/compliance-checklist/SKILL.md`

**Step 1: Create directory and write the compliance checklist skill**

```bash
mkdir -p plugins/web-auditor/skills/compliance-checklist
```

6 sections:

1. **Cookie Consent** — detect cookie consent banner (common class/id patterns: `cookie-banner`, `consent`, `gdpr`), check if non-essential cookies are set BEFORE user consents (navigate fresh, capture cookies immediately vs after accepting), verify consent mechanism blocks cookie setting, check for CMP (Consent Management Platform) like OneTrust, CookieBot, Didomi
2. **Cookie Inventory** — list all cookies from HTTP headers (`Set-Cookie`) and JavaScript (`document.cookie`), for each: name, domain, path, expiry (session vs persistent), Secure flag, HttpOnly flag, SameSite attribute, classify as: necessary (session, CSRF), analytics (GA, Hotjar), marketing (Facebook, Google Ads), unknown
3. **Privacy Policy** — check for privacy policy link in footer/navigation, verify link is accessible (200 status), check for GDPR required sections: data controller identity, purposes of processing, legal basis, data retention period, data subject rights (access, rectification, erasure, portability), right to complain to supervisory authority, check language matches site language
4. **Data Exposure** — scan HTML source for email patterns (`[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}`), phone number patterns, personal data in URL parameters, forms sending data to third-party domains, autocomplete on sensitive fields
5. **Analytics & Tracking** — detect scripts: Google Analytics (gtag.js, analytics.js), GTM (googletagmanager.com), Meta Pixel (fbevents.js), Hotjar, Microsoft Clarity, Segment, Mixpanel, Amplitude. Check if scripts fire BEFORE consent. Check for cross-domain tracking configuration. Detect fingerprinting scripts.
6. **Third-Party Resources** — inventory all external domains loaded (scripts, styles, images, iframes, fonts), classify purpose (CDN, analytics, advertising, social, functional), check if data is sent to non-EU servers (based on domain analysis), count total third-party requests

Severity guide:
| Finding | Severity |
|---------|----------|
| Non-essential cookies set before consent | Critical |
| No cookie consent mechanism on site using tracking | Critical |
| No privacy policy | High |
| Analytics firing before consent | High |
| Privacy policy missing required GDPR sections | High |
| Personal data (emails, phones) exposed in HTML | Medium |
| Cookies without Secure flag | Medium |
| Cookies without SameSite attribute | Medium |
| Personal data in URL parameters | Medium |
| Privacy policy in wrong language | Medium |
| Missing cookie purpose classification | Low |
| Third-party resources without clear purpose | Low |
| No data processing agreement info | Low |

**Step 2: Commit**

```bash
git add plugins/web-auditor/skills/compliance-checklist/SKILL.md
git commit -m "feat(web-auditor): add compliance checklist skill"
```

---

### Task 10: Create agents/compliance-agent.md

**File:** Create `plugins/web-auditor/agents/compliance-agent.md`

**Step 1: Write the compliance agent**

Same pattern. Frontmatter:
- `name: compliance-agent`
- `skills: compliance-checklist`
- `model: claude-opus-4-6`
- Allowed tools: Playwright (cookie detection, DOM analysis, network requests) + curl + Bash text tools

Input: target domain, URL inventory, compliance data per URL (cookies, consent banner, analytics, privacy links), headers, Set-Cookie headers.

Checklist sections: 6 sections matching the skill.

**Step 2: Commit**

```bash
git add plugins/web-auditor/agents/compliance-agent.md
git commit -m "feat(web-auditor): add compliance scanning agent"
```

---

### Task 11: Update documentation

**File 1:** Overwrite `docs/plugins/web-auditor.md`

Update to reflect:
- Plugin name: web-auditor
- Version: 2.0.0
- Command: `/audit` with `--scope` flag
- All 4 scopes documented
- What each scope scans
- Methodology (passive, legal, non-invasive)
- Required/optional tools (same as before + note Playwright needed for SEO/performance/compliance)

**File 2:** Modify `README.md`

Replace the pentester row in the Available Plugins table:
```markdown
| [Web Auditor](docs/plugins/web-auditor.md) | 2.0.0 | Comprehensive web audit: security, SEO, performance, and compliance |
```

Also update the `python-developer` version reference to keep it consistent (only if it changed — check first).

**Step 1: Write updated docs**
**Step 2: Update README.md**
**Step 3: Commit**

```bash
git add docs/plugins/web-auditor.md README.md
git commit -m "docs(web-auditor): update documentation for v2.0.0"
```

---

### Task 12: Final verification

**Step 1: Verify file structure**

Run: `find plugins/web-auditor -type f | sort`

Expected output:
```
plugins/web-auditor/.claude-plugin/plugin.json
plugins/web-auditor/agents/api-security-agent.md
plugins/web-auditor/agents/compliance-agent.md
plugins/web-auditor/agents/infrastructure-agent.md
plugins/web-auditor/agents/performance-agent.md
plugins/web-auditor/agents/seo-agent.md
plugins/web-auditor/agents/supply-chain-agent.md
plugins/web-auditor/agents/web-auditor.md
plugins/web-auditor/agents/web-security-agent.md
plugins/web-auditor/commands/audit.md
plugins/web-auditor/skills/api-security-checklist/SKILL.md
plugins/web-auditor/skills/compliance-checklist/SKILL.md
plugins/web-auditor/skills/infrastructure-checklist/SKILL.md
plugins/web-auditor/skills/performance-checklist/SKILL.md
plugins/web-auditor/skills/seo-checklist/SKILL.md
plugins/web-auditor/skills/supply-chain-checklist/SKILL.md
plugins/web-auditor/skills/web-security-checklist/SKILL.md
```

**Step 2: Verify no pentester references remain**

Run: `grep -r "pentester" plugins/web-auditor/ docs/ README.md`

Expected: no matches (or only in git history context).

**Step 3: Verify all agent names match expected subagent_type references**

Check that the coordinator's `web-auditor.md` references match actual agent filenames:
- `web-auditor:web-security-agent` → `agents/web-security-agent.md` (name: web-security-agent)
- `web-auditor:api-security-agent` → `agents/api-security-agent.md` (name: api-security-agent)
- `web-auditor:infrastructure-agent` → `agents/infrastructure-agent.md` (name: infrastructure-agent)
- `web-auditor:supply-chain-agent` → `agents/supply-chain-agent.md` (name: supply-chain-agent)
- `web-auditor:seo-agent` → `agents/seo-agent.md` (name: seo-agent)
- `web-auditor:performance-agent` → `agents/performance-agent.md` (name: performance-agent)
- `web-auditor:compliance-agent` → `agents/compliance-agent.md` (name: compliance-agent)

**Step 4: Verify all skill references match actual skill directories**

Check that agents reference skills that exist:
- `web-security-checklist` → `skills/web-security-checklist/SKILL.md`
- `api-security-checklist` → `skills/api-security-checklist/SKILL.md`
- `infrastructure-checklist` → `skills/infrastructure-checklist/SKILL.md`
- `supply-chain-checklist` → `skills/supply-chain-checklist/SKILL.md`
- `seo-checklist` → `skills/seo-checklist/SKILL.md`
- `performance-checklist` → `skills/performance-checklist/SKILL.md`
- `compliance-checklist` → `skills/compliance-checklist/SKILL.md`
