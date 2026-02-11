# Pentester Plugin

Passive web security scanner with multi-agent architecture.

**Version:** 1.0.0

## Commands

### `/pentest`

Run a comprehensive passive security audit of a target website.

```bash
# Basic scan
/pentest https://example.com

# Deeper crawl
/pentest https://example.com --depth 3

# Custom output directory
/pentest https://example.com --depth 3 --output-dir ./reports
```

The scan launches a coordinator agent that crawls the target, dispatches 4 parallel scanning agents (web app, API, infrastructure, supply chain), and consolidates findings into a single Markdown report.

**Output:** `audit-{domain}-security-{YYYY-MM-DD}.md`

## What It Scans

- **Web Application Security** — HTTP security headers (CSP, HSTS, X-Frame-Options), cookies (Secure/HttpOnly/SameSite), secrets in JavaScript, CSRF protection, error handling, server banners
- **API Security** — Endpoint discovery, CORS misconfiguration, rate limiting, authentication analysis, GraphQL introspection, response security
- **Infrastructure** — SSL/TLS configuration (via SSL Labs), DNS records (SPF, DMARC, DKIM), subdomain enumeration (crt.sh), CDN/WAF detection, port scanning, exposed paths (.git, .env)
- **Supply Chain** — JavaScript library identification and CVE lookup, Subresource Integrity (SRI), source map exposure, exposed dependency files

## Methodology

All checks are **passive, legal, and non-invasive**:
- No login attempts, brute-force, or exploits
- No data modification
- Passive port scanning only (nmap top ports, polite timing)
- Public resources only

## Required Tools

- curl (usually pre-installed)
- Playwright MCP server (for JS rendering and crawling)

## Optional Tools

For deeper analysis:
- nmap — port scanning (falls back to curl if unavailable)
- dig — DNS analysis
- jq — JSON processing
- openssl — TLS certificate inspection
