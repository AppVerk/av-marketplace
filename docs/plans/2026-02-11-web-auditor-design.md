# Design: Transform pentester into web-auditor

**Date:** 2026-02-11
**Status:** Approved

---

## Overview

Transform the `pentester` plugin into `web-auditor` — a comprehensive web audit plugin covering security, SEO, performance, and compliance. Single `/audit` command with `--scope` flag. Shared Phase 1 recon. 7 parallel agents (4 existing security + 3 new).

## Decisions

| Decision | Choice |
|----------|--------|
| Plugin structure | Transform pentester → web-auditor |
| Command interface | Single `/audit <url> --scope <scope>` |
| Scopes | security, seo, performance, compliance, all (default) |
| Recon phase | Shared across all scopes |
| Agent granularity | 4 security agents (existing) + 1 agent per new scope |
| Backward compat | No /pentest alias — clean break |

---

## Command Interface

```
/audit <url> [--scope <scope>] [--depth N] [--output-dir path]
```

**Scopes:**
- `security` — web app, API, infrastructure, supply chain (existing 4 agents)
- `seo` — indexability, metadata, structured data, rendering, internal linking
- `performance` — Core Web Vitals, images, fonts, JS/CSS optimization
- `compliance` — GDPR, cookies, privacy policy, analytics, data exposure
- `all` — all 4 scopes (default)

**Output file:** `audit-{domain}-{scope}-{YYYY-MM-DD}.md` (or `audit-{domain}-full-{YYYY-MM-DD}.md` for `all`)

---

## Architecture

### Coordinator: `web-auditor.md`

Replaces `pentester.md`. Same 3-phase workflow (recon → parallel scan → consolidation), but scope-aware. Based on `--scope`, launches only the relevant agents.

### Agent Map

| Scope | Agent | Source |
|-------|-------|--------|
| security | `web-security-agent` | existing, unchanged |
| security | `api-security-agent` | existing, unchanged |
| security | `infrastructure-agent` | existing, unchanged |
| security | `supply-chain-agent` | existing, unchanged |
| seo | `seo-agent` | **new** |
| performance | `performance-agent` | **new** |
| compliance | `compliance-agent` | **new** |

### Skills (Checklists)

| Agent | Skill |
|-------|-------|
| web-security-agent | `web-security-checklist` (existing) |
| api-security-agent | `api-security-checklist` (existing) |
| infrastructure-agent | `infrastructure-checklist` (existing) |
| supply-chain-agent | `supply-chain-checklist` (existing) |
| seo-agent | `seo-checklist` (**new**) |
| performance-agent | `performance-checklist` (**new**) |
| compliance-agent | `compliance-checklist` (**new**) |

---

## Phase 1: Shared Reconnaissance

Runs identically regardless of scope. Coordinator collects everything upfront and passes only the relevant data to each agent.

### Steps (sequential)

1. **Crawl with Playwright** — navigate target, collect internal links recursively up to depth limit. For each URL: status code, content type, redirect chain.
2. **HTTP headers** — `curl -sI` for each URL in inventory.
3. **robots.txt & sitemap.xml** — fetch and parse both.
4. **Technology detection** — Server headers, meta generator tags, JS globals via Playwright.
5. **Build URL inventory** — deduplicated list with metadata.
6. **Collect page metadata** — for each URL via Playwright: `<title>`, `<meta description>`, `<meta robots>`, canonical, hreflang, OpenGraph, Twitter cards, Schema.org JSON-LD. Feeds SEO agent.
7. **Capture performance metrics** — for each URL: `performance.getEntries()` and `PerformanceObserver` via Playwright for LCP, CLS, resource timing. Feeds Performance agent.
8. **Detect cookies & consent** — all cookies set on first visit (before interaction), cookie banners, analytics scripts (GA, GTM, Hotjar, etc.). Feeds Compliance agent.

### Data Distribution

| Agent(s) | Receives |
|----------|----------|
| All security agents | URL inventory, headers, tech stack, API endpoints |
| SEO agent | URL inventory, headers, metadata per page, robots.txt, sitemap.xml, tech stack |
| Performance agent | URL inventory, performance metrics per page, resource timing, tech stack |
| Compliance agent | URL inventory, cookies, consent banner detection, analytics scripts, headers |

---

## New Agent Checklists

### SEO Agent — `seo-checklist`

1. **Indexability** — robots.txt directives, meta robots tags, X-Robots-Tag header, canonical consistency, noindex pages, crawl budget issues
2. **Metadata quality** — title (length, uniqueness per page), meta description (length, uniqueness), heading hierarchy (H1-H6), duplicate content signals
3. **Structured data** — JSON-LD presence and validity, Schema.org types, required properties, Google Rich Results compatibility
4. **Rendering** — SSR vs CSR detection, JS-dependent content visibility, hydration issues, content visible without JS
5. **Internal linking** — orphan pages, broken links (from inventory), link depth, anchor text quality, navigation structure
6. **OpenGraph & Social** — og:title, og:description, og:image, Twitter card tags, image dimensions
7. **Internationalization** — hreflang tags, language declarations, locale consistency
8. **Sitemap & robots** — sitemap completeness vs crawled URLs, sitemap format validity, robots.txt blocking important resources

### Performance Agent — `performance-checklist`

1. **Core Web Vitals** — LCP (target <2.5s), CLS (target <0.1), INP estimation from event handlers
2. **Images** — format (WebP/AVIF vs PNG/JPG), dimensions vs display size, lazy loading, missing width/height attributes causing CLS
3. **Fonts** — font-display strategy, preload usage, number of font files, FOUT/FOIT detection
4. **JavaScript** — bundle size, render-blocking scripts, defer/async usage, unused JS estimation, third-party JS impact
5. **CSS** — render-blocking stylesheets, unused CSS estimation, critical CSS inlining
6. **Caching** — Cache-Control headers, ETags, static asset fingerprinting, CDN usage
7. **Compression** — gzip/brotli on text resources (check Content-Encoding)
8. **Resource hints** — preconnect, dns-prefetch, preload usage for critical resources

### Compliance Agent — `compliance-checklist`

1. **Cookie consent** — banner present before setting non-essential cookies, consent mechanism functional, cookies set before consent (violation check)
2. **Cookie inventory** — all cookies with: name, domain, expiry, purpose classification (necessary/analytics/marketing), Secure/HttpOnly/SameSite flags
3. **Privacy policy** — link present and accessible, covers required GDPR sections (data controller, purposes, legal basis, retention, rights)
4. **Data exposure** — personal data in URLs, email addresses in HTML source, phone numbers exposed, form data sent to third parties
5. **Analytics & tracking** — detected scripts (GA, GTM, Meta Pixel, Hotjar), data sent before consent, cross-domain tracking
6. **Third-party resources** — inventory of external domains loaded, data shared with third parties, purpose classification

---

## Phase 3: Consolidation & Report

### Consolidation logic

- **Cross-scope deduplication** — overlapping findings (e.g., cookie flags in both security and compliance) keep the most detailed version, tagged with both scopes.
- **Scope-aware assembly** — only include report sections for active scope(s).
- **Unified severity scale** — all scopes use Critical/High/Medium/Low/Info.

### Report template (full audit)

```markdown
# Web Audit Report: {domain}

**Date:** {YYYY-MM-DD}
**Scope:** {security, seo, performance, compliance | specific scope}
**Method:** Passive, outside-in, multi-agent scan
**URLs analyzed:** {count}

---

## Executive Summary
{5-10 bullet points covering all active scopes}
{Risk level per scope}
{Findings count table}
{Critical & High findings list}

---

## Scope & Methodology
{URLs analyzed, tools used, limitations}

## Results — Security
{Only if scope includes security}
### Web Application Security
### API Security
### Infrastructure
### Supply Chain

## Results — Technical SEO
{Only if scope includes seo}
### Indexability
### Metadata
### Structured Data
### Rendering
### Internal Linking

## Results — Performance
{Only if scope includes performance}
### Core Web Vitals
### Images
### Fonts
### JavaScript & CSS
### Caching & Compression

## Results — Compliance & Privacy
{Only if scope includes compliance}
### Cookie Consent
### Cookie Inventory
### Privacy Policy
### Data Exposure
### Analytics & Tracking

---

## TOP 10 Problems
{Cross-scope, sorted by severity and business impact}

| # | Severity | Finding | Scope | Owner | Recommendation |
|---|----------|---------|-------|-------|----------------|

## HTTP Headers Scorecard
{Always included}

| Header | Status | Value | Notes |
|--------|--------|-------|-------|

## SEO Scorecard
{Only if scope includes seo}

| Area | Status | Notes | Next Step |
|------|--------|-------|-----------|

## Quick Wins (48h)
## 90-Day Roadmap
## Appendix
```

### Finding format (all scopes)

```markdown
### [SEVERITY] Problem title
- **URL/Evidence:** specific URL, header, code fragment
- **Risk:** technical + business risk description
- **Recommendation:** what to do (with config/code example)
- **Verification:** how to confirm the fix
- **Owner:** Dev / DevOps / Security / Marketing
```

---

## File Structure

### Target state

```
plugins/web-auditor/
├── .claude-plugin/plugin.json        # name: web-auditor, version: 2.0.0
├── commands/audit.md                 # replaces pentest.md
├── agents/
│   ├── web-auditor.md                # coordinator (replaces pentester.md)
│   ├── web-security-agent.md         # moved, unchanged
│   ├── api-security-agent.md         # moved, unchanged
│   ├── infrastructure-agent.md       # moved, unchanged
│   ├── supply-chain-agent.md         # moved, unchanged
│   ├── seo-agent.md                  # NEW
│   ├── performance-agent.md          # NEW
│   └── compliance-agent.md           # NEW
└── skills/
    ├── web-security-checklist/SKILL.md    # moved, unchanged
    ├── api-security-checklist/SKILL.md    # moved, unchanged
    ├── infrastructure-checklist/SKILL.md  # moved, unchanged
    ├── supply-chain-checklist/SKILL.md    # moved, unchanged
    ├── seo-checklist/SKILL.md             # NEW
    ├── performance-checklist/SKILL.md     # NEW
    └── compliance-checklist/SKILL.md      # NEW
```

### Migration steps

1. Rename `plugins/pentester/` → `plugins/web-auditor/`
2. Update `plugin.json` — name: `web-auditor`, version: `2.0.0`, new description
3. Replace `commands/pentest.md` → `commands/audit.md` with `--scope` flag parsing
4. Replace `agents/pentester.md` → `agents/web-auditor.md` with scope-aware dispatch
5. Keep 4 security agents and 4 security skills unchanged
6. Create 3 new agents: `seo-agent.md`, `performance-agent.md`, `compliance-agent.md`
7. Create 3 new skills: `seo-checklist/SKILL.md`, `performance-checklist/SKILL.md`, `compliance-checklist/SKILL.md`
8. Update `docs/plugins/pentester.md` → `docs/plugins/web-auditor.md`
9. Update `README.md` — replace pentester row with web-auditor

### Counts

- Files to create (new content): 7
- Files to modify (update references): 3
- Files to delete: 0 (rename via git mv)
