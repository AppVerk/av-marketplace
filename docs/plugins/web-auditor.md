# Web Auditor Plugin

Comprehensive web audit with multi-agent architecture covering security, SEO, performance, and compliance.

**Version:** 2.1.2

## Commands

### `/audit`

Run a comprehensive passive web audit of a target website.

```bash
# Full audit (all scopes)
/audit https://example.com

# Security only
/audit https://example.com --scope security

# SEO audit with deeper crawl
/audit https://example.com --scope seo --depth 3

# Performance audit with custom output
/audit https://example.com --scope performance --output-dir ./reports

# Compliance audit
/audit https://example.com --scope compliance
```

**Scopes:**

| Scope | Description |
|-------|-------------|
| `all` | Full audit: security + SEO + performance + compliance (default) |
| `security` | Web app, API, infrastructure, and supply chain security |
| `seo` | Indexability, metadata, structured data, rendering, internal linking |
| `performance` | Core Web Vitals, images, fonts, JS/CSS optimization |
| `compliance` | GDPR, cookies, privacy policy, analytics, data exposure |

The scan launches a coordinator agent that crawls the target, dispatches up to 7 parallel scanning agents based on scope, and consolidates findings into a single Markdown report.

**Output:** `audit-{domain}-{scope|full}-{YYYY-MM-DD}.md`

## What It Scans

### Security (4 agents)

- **Web Application Security** — HTTP security headers (CSP, HSTS, X-Frame-Options), cookies (Secure/HttpOnly/SameSite), secrets in JavaScript, CSRF protection, error handling, server banners
- **API Security** — Endpoint discovery, CORS misconfiguration, rate limiting, authentication analysis, GraphQL introspection, response security
- **Infrastructure** — SSL/TLS configuration (via SSL Labs), DNS records (SPF, DMARC, DKIM), subdomain enumeration (crt.sh), CDN/WAF detection, port scanning, exposed paths (.git, .env)
- **Supply Chain** — JavaScript library identification and CVE lookup, Subresource Integrity (SRI), source map exposure, exposed dependency files

### SEO (1 agent)

- **Indexability** — robots.txt, meta robots, canonical tags, redirect chains
- **Metadata** — title tags, meta descriptions, heading hierarchy, duplicate content
- **Structured Data** — JSON-LD validation, Schema.org types, Rich Results eligibility
- **Rendering** — SSR vs CSR detection, JS-dependent content, hydration errors
- **Internal Linking** — orphan pages, broken links, link depth, anchor text quality

### Performance (1 agent)

- **Core Web Vitals** — LCP, CLS, INP, FCP, TTFB
- **Images** — format optimization (WebP/AVIF), sizing, lazy loading, missing dimensions
- **Fonts** — font-display strategy, preload, FOUT/FOIT detection
- **JavaScript & CSS** — bundle size, render-blocking, defer/async, unused code
- **Caching & Compression** — Cache-Control, ETags, gzip/brotli, CDN detection

### Compliance (1 agent)

- **Cookie Consent** — banner detection, pre-consent cookie setting, CMP identification
- **Cookie Inventory** — all cookies with security flags and purpose classification
- **Privacy Policy** — presence, accessibility, GDPR required sections
- **Data Exposure** — emails/phones in HTML, personal data in URLs, form data to third parties
- **Analytics & Tracking** — script detection, pre-consent firing, fingerprinting

## Methodology

All checks are **passive, legal, and non-invasive**:
- No login attempts, brute-force, or exploits
- No data modification
- Passive port scanning only (nmap top ports, polite timing)
- Public resources only

## Verification Mode

Add `--verify` to enable cross-domain correlation and adversarial review of findings.

### Usage

```bash
/audit https://example.com --verify
/audit https://example.com --scope security --verify
```

### What It Does

After the standard scanning phase, two verification subagents analyze the findings in parallel:

- **Cross-Verifier**: identifies correlations between scanning domains (e.g., an open port found by infrastructure + missing auth found by API security), coverage gaps, and composite findings
- **Challenger**: challenges every Critical/High finding for false positives, validates severity levels, and calibrates severity across domains

### Additional Report Sections

Reports generated with `--verify` include a Verification Summary showing:
- Number of findings verified, removed, and adjusted
- Cross-domain correlations discovered
- Coverage gaps identified

### Cost Considerations

Verification mode spawns 2 additional subagent instances. Use it when accuracy matters more than speed.

## Required Tools

- curl (usually pre-installed)
- Playwright MCP server (for JS rendering, crawling, performance metrics, cookie detection)

## Optional Tools

For deeper analysis:
- nmap — port scanning (falls back to curl if unavailable)
- dig — DNS analysis
- jq — JSON processing
- openssl — TLS certificate inspection
