---
name: web-security-checklist
description: Checklist for passive web application security assessment. Covers HTTP security headers, cookies, TLS, secrets exposure, error handling, and common web vulnerabilities.
allowed-tools: Read, Grep, Glob, Bash(curl:*), Bash(grep:*), Bash(head:*), Bash(tail:*), Bash(echo:*), Bash(cat:*), mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_snapshot, mcp__plugin_playwright_playwright__browser_evaluate, mcp__plugin_playwright_playwright__browser_click, mcp__plugin_playwright_playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_console_messages, mcp__plugin_playwright_playwright__browser_network_requests, mcp__plugin_playwright_playwright__browser_run_code, mcp__plugin_playwright_playwright__browser_close, mcp__plugin_playwright_playwright__browser_tabs
---

# Web Security Checklist - Passive Assessment

Comprehensive, actionable checklist for passive web application security assessment. This skill guides the agent through systematic checks of HTTP security headers, cookie security, TLS configuration, secrets exposure, error handling, and common web vulnerabilities.

---

## 1. HTTP Security Headers

Check all security-relevant HTTP response headers against expected values.

| Header | Expected Value | Severity if Missing |
|--------|---------------|-------------------|
| Strict-Transport-Security | max-age=31536000; includeSubDomains; preload | High |
| Content-Security-Policy | Restrictive policy (no unsafe-inline, unsafe-eval) | High |
| X-Content-Type-Options | nosniff | Medium |
| X-Frame-Options | DENY or SAMEORIGIN | Medium |
| Permissions-Policy | Restrictive (camera=(), microphone=(), etc.) | Medium |
| Referrer-Policy | strict-origin-when-cross-origin or no-referrer | Low |
| Cache-Control | no-store for sensitive pages | Low |
| X-XSS-Protection | 0 (deprecated, should be disabled in favor of CSP) | Info |

### How to check

```bash
curl -sI https://TARGET | grep -i "strict-transport-security\|content-security-policy\|x-content-type-options\|x-frame-options\|permissions-policy\|referrer-policy\|cache-control\|x-xss-protection"
```

### Header Details and Remediation

**Strict-Transport-Security (HSTS)**
- Prevents: Protocol downgrade attacks, cookie hijacking
- nginx: `add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;`
- Apache: `Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"`

**Content-Security-Policy (CSP)**
- Prevents: Cross-site scripting (XSS), data injection, clickjacking
- nginx: `add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'" always;`
- Apache: `Header always set Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"`

**X-Content-Type-Options**
- Prevents: MIME type sniffing attacks
- nginx: `add_header X-Content-Type-Options "nosniff" always;`
- Apache: `Header always set X-Content-Type-Options "nosniff"`

**X-Frame-Options**
- Prevents: Clickjacking attacks
- nginx: `add_header X-Frame-Options "DENY" always;`
- Apache: `Header always set X-Frame-Options "DENY"`

**Permissions-Policy**
- Prevents: Unauthorized access to browser features (camera, microphone, geolocation)
- nginx: `add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;`
- Apache: `Header always set Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()"`

**Referrer-Policy**
- Prevents: Leaking sensitive URL information to third parties
- nginx: `add_header Referrer-Policy "strict-origin-when-cross-origin" always;`
- Apache: `Header always set Referrer-Policy "strict-origin-when-cross-origin"`

**Cache-Control**
- Prevents: Sensitive data cached by browsers or proxies
- nginx: `add_header Cache-Control "no-store" always;` (for sensitive pages)
- Apache: `Header always set Cache-Control "no-store"` (for sensitive pages)

**X-XSS-Protection**
- Should be set to `0` to disable the buggy XSS auditor in older browsers; CSP is the proper replacement
- nginx: `add_header X-XSS-Protection "0" always;`
- Apache: `Header always set X-XSS-Protection "0"`

---

## 2. Cookie Security

Check all Set-Cookie headers for security flags.

```bash
curl -sI https://TARGET | grep -i "set-cookie"
```

| Flag | What It Prevents | Severity if Missing |
|------|-----------------|-------------------|
| Secure | Cookie sent over HTTP (sniffing) | High |
| HttpOnly | JavaScript access (XSS cookie theft) | Medium |
| SameSite=Strict/Lax | Cross-site request forgery (CSRF) | Medium |
| __Secure- prefix | Cookie set without Secure flag | Low |
| __Host- prefix | Cookie scoped too broadly | Low |

### What to verify for each cookie

1. **Secure flag** - Every cookie on an HTTPS site must have the `Secure` flag. Without it, the cookie is transmitted over plain HTTP if the user visits an HTTP URL, allowing network attackers to intercept it.
2. **HttpOnly flag** - Session cookies and authentication tokens must have `HttpOnly`. Without it, JavaScript (including injected XSS payloads) can read the cookie via `document.cookie`.
3. **SameSite attribute** - Must be `Strict` or `Lax`. Without it (or with `SameSite=None`), the cookie is sent on cross-site requests, enabling CSRF attacks.
4. **__Secure- prefix** - Cookies with this prefix must be set with the `Secure` flag and over HTTPS. This is a defense-in-depth measure.
5. **__Host- prefix** - Cookies with this prefix must be set with `Secure`, must not have a `Domain` attribute, and `Path` must be `/`. Prevents domain-scoped cookie attacks.

---

## 3. TLS/HTTPS

### HTTP to HTTPS redirect

```bash
curl -sI http://TARGET -o /dev/null -w "%{redirect_url}"
```

Verify that:
- HTTP requests redirect to HTTPS (301 or 308, not 302)
- The redirect goes to the same hostname with HTTPS
- No content is served over plain HTTP before the redirect

### Mixed content detection

Using Playwright, check for HTTP resources loaded on HTTPS pages:

```javascript
// Collect all resource URLs loaded by the page
const resources = performance.getEntriesByType('resource');
const mixedContent = resources
  .filter(r => r.name.startsWith('http://'))
  .map(r => ({ url: r.name, type: r.initiatorType }));
```

Also check:
- `<img>`, `<script>`, `<link>`, `<iframe>` tags with `http://` src/href
- CSS `url()` references to `http://` resources
- XMLHttpRequest/fetch calls to `http://` endpoints

### HSTS preload list check

- Verify the site is on the HSTS preload list: check `https://hstspreload.org/?domain=TARGET`
- Requirements for preload: valid certificate, redirect HTTP to HTTPS, serve HSTS header with `max-age >= 31536000`, include `includeSubDomains`, include `preload`

---

## 4. Secrets in JavaScript

Search page source and JS bundles for exposed secrets using Playwright evaluate.

### Patterns to search

| Pattern | Regex | Example Match |
|---------|-------|---------------|
| API keys | `(?:api[_-]?key\|apikey)\s*[:=]\s*['"][A-Za-z0-9_\-]{20,}['"]` | `apiKey: "abc123..."` |
| AWS keys | `AKIA[0-9A-Z]{16}` | `AKIAIOSFODNN7EXAMPLE` |
| Tokens | `(?:token\|secret\|password\|credential)\s*[:=]\s*['"][^'"]{8,}['"]` | `token: "eyJhbG..."` |
| .env patterns | `process\.env\.\w+` | `process.env.SECRET_KEY` |
| Google Maps API keys | `AIza[0-9A-Za-z\-_]{35}` | `AIzaSyA1b2c3d4...` |
| Stripe keys | `(?:sk\|pk)_(?:test\|live)_[0-9a-zA-Z]{24,}` | `sk_live_abc123...` |
| Private keys | `-----BEGIN (?:RSA\|EC\|DSA)? ?PRIVATE KEY-----` | PEM private key |
| JWT tokens | `eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` | JWT token |
| GitHub tokens | `gh[pousr]_[A-Za-z0-9_]{36,}` | `ghp_abc123...` |

### Playwright snippet for extraction

```javascript
const scripts = Array.from(document.querySelectorAll('script'));
const inlineCode = scripts.filter(s => !s.src).map(s => s.textContent).join('\n');
const externalUrls = scripts.filter(s => s.src).map(s => s.src);
// Search inlineCode for patterns
// Fetch external scripts and search them too
```

For each external script URL:
```javascript
const response = await fetch(scriptUrl);
const code = await response.text();
// Apply regex patterns to code
```

### Important notes

- Check `<meta>` tags for tokens or keys
- Check `window.__INITIAL_STATE__` or similar hydration data for leaked server-side data
- Check `data-*` attributes on elements for API keys
- Check source maps (`.map` files) for leaked source code and secrets

---

## 5. Error Handling & Information Disclosure

### Server banners

```bash
curl -sI https://TARGET | grep -i "server\|x-powered-by\|x-aspnet-version\|x-debug"
```

Verify:
- `Server` header does not reveal software name/version (e.g., `Apache/2.4.51`, `nginx/1.21.4`)
- `X-Powered-By` header is absent (e.g., `X-Powered-By: Express`, `X-Powered-By: PHP/8.1.0`)
- `X-AspNet-Version` is absent
- No debug-related headers present

### Stack traces and verbose errors

Request non-existent paths and check for stack traces:

```bash
curl -s https://TARGET/non-existent-path-12345 | head -100
```

Also test:
- `https://TARGET/%00` (null byte)
- `https://TARGET/..%2f..%2f` (path traversal encoding)
- `https://TARGET/?id='` (SQL error trigger)

Look for in responses:
- Stack trace frames (file paths, line numbers)
- Database error messages (SQL syntax errors, connection strings)
- Framework-specific debug pages (Django debug page, Laravel Whoops, Express stack traces)
- Internal IP addresses or hostnames
- Environment variables or configuration values

### Version exposure

Check for version information in:
- Response headers (`Server`, `X-Powered-By`)
- HTML comments (`<!-- Built with Framework v1.2.3 -->`)
- Generator meta tags (`<meta name="generator" content="WordPress 6.4">`)
- JavaScript libraries with version comments
- `/robots.txt`, `/sitemap.xml`, `/humans.txt` for framework signatures

---

## 6. Forms & CSRF

Using Playwright, inspect all forms on the page.

### Checks to perform

For each `<form>` element:

1. **Action URL uses HTTPS** - The `action` attribute must use `https://` or be a relative path (which inherits the page protocol). An `http://` action on an HTTPS page leaks form data.
2. **CSRF token present** - Check for a hidden input with a name containing `csrf`, `token`, `_token`, `authenticity_token`, `__RequestVerificationToken`, or similar. Missing CSRF tokens allow cross-site request forgery.
3. **Autocomplete off on sensitive fields** - Password, credit card, and SSN fields should have `autocomplete="off"` or `autocomplete="new-password"` to prevent browser caching of sensitive data.
4. **Form method** - Sensitive operations (login, payment, data modification) must use `POST`, not `GET`. GET requests expose form data in the URL, browser history, referrer headers, and server logs.

### Playwright snippet

```javascript
const forms = Array.from(document.querySelectorAll('form'));
const formAnalysis = forms.map(form => ({
  action: form.action,
  method: form.method,
  hasCSRFToken: !!form.querySelector('input[name*="csrf"], input[name*="token"], input[name*="_token"], input[name*="authenticity_token"]'),
  sensitiveFields: Array.from(form.querySelectorAll('input[type="password"], input[type="credit-card"], input[autocomplete*="cc-"]')).map(f => ({
    name: f.name,
    autocomplete: f.autocomplete
  }))
}));
```

---

## 7. Clickjacking & MIME Sniffing

### Clickjacking protection

Two mechanisms protect against clickjacking:

1. **X-Frame-Options** - Set to `DENY` or `SAMEORIGIN` (checked in Section 1)
2. **CSP frame-ancestors** - `frame-ancestors 'none'` or `frame-ancestors 'self'` (checked in Section 1)

If both are present, `frame-ancestors` takes precedence in modern browsers.

### MIME sniffing protection

- **X-Content-Type-Options: nosniff** (checked in Section 1)
- Without this header, browsers may interpret files as a different MIME type than declared, leading to XSS via file upload or script injection via CSS/image files.

### Verification

Try embedding the target page in an iframe:

```javascript
// Playwright: check if the page can be framed
const frame = document.createElement('iframe');
frame.src = 'https://TARGET';
document.body.appendChild(frame);
// If X-Frame-Options or CSP frame-ancestors is set, the iframe will be blocked
```

---

## 8. Open Redirects

Check URL parameters that may contain redirect destinations.

### Common redirect parameters

- `redirect`
- `url`
- `next`
- `return`
- `returnTo`
- `redirect_uri`
- `continue`
- `dest`
- `destination`
- `rurl`
- `target`
- `view`
- `redir`
- `forward`
- `callback`

### How to test

For each parameter found in the URL or in forms:

```
https://TARGET/login?redirect=https://evil.com
https://TARGET/login?next=//evil.com
https://TARGET/login?returnTo=/\evil.com
https://TARGET/login?url=https:evil.com
```

### What to look for

- The response is a 3xx redirect to the attacker-controlled URL
- The page renders content that includes the attacker-controlled URL in a link or script
- The parameter value is reflected in a `Location` header without validation

### Using Playwright

```javascript
// Check all links and form actions for redirect parameters
const links = Array.from(document.querySelectorAll('a[href]'));
const redirectLinks = links.filter(link => {
  const url = new URL(link.href, window.location.origin);
  const redirectParams = ['redirect', 'url', 'next', 'return', 'returnTo', 'redirect_uri', 'continue', 'dest', 'destination', 'forward', 'callback'];
  return redirectParams.some(param => url.searchParams.has(param));
});
```

---

## Severity Assessment Guide

| Finding | Severity |
|---------|----------|
| No HTTPS / broken TLS | Critical |
| Secrets in JS source | Critical |
| Missing CSP | High |
| Missing HSTS | High |
| Cookies without Secure flag | High |
| Stack traces in errors | High |
| Missing CSRF tokens | High |
| Missing X-Content-Type-Options | Medium |
| Cookies without HttpOnly | Medium |
| Cookies without SameSite | Medium |
| Missing Permissions-Policy | Medium |
| Server banner exposure | Low |
| Missing Referrer-Policy | Low |
| X-XSS-Protection not disabled | Info |

---

## Finding Report Format

Each finding MUST follow this format:

```markdown
### [SEVERITY] Problem title
- **URL/Evidence:** specific URL, header, code fragment
- **Risk:** technical + business risk description
- **Recommendation:** what to do (with config/code example)
- **Verification:** how to confirm the fix
- **Owner:** Dev / DevOps / Security
```

### Example

```markdown
### [HIGH] Missing Strict-Transport-Security header
- **URL/Evidence:** `curl -sI https://example.com` - no HSTS header in response
- **Risk:** Users can be downgraded to HTTP via MITM attacks, exposing session cookies and credentials. Attackers on shared networks (coffee shops, airports) can intercept all traffic.
- **Recommendation:** Add HSTS header with minimum 1-year max-age:
  - nginx: `add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;`
  - Apache: `Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"`
- **Verification:** `curl -sI https://example.com | grep -i strict-transport-security` should return the header
- **Owner:** DevOps
```

---

## Assessment Workflow

1. **Collect headers** - Fetch response headers with curl
2. **Analyze cookies** - Extract and evaluate all Set-Cookie headers
3. **Check TLS** - Verify HTTPS redirect and mixed content
4. **Scan for secrets** - Search inline scripts and external JS bundles
5. **Probe error handling** - Request invalid paths and check responses
6. **Inspect forms** - Evaluate CSRF protection and form security
7. **Test framing** - Verify clickjacking protections
8. **Check redirects** - Identify open redirect parameters
9. **Generate report** - Document all findings using the report format above
