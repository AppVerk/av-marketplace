---
name: compliance-checklist
description: Checklist for passive compliance and privacy assessment. Covers cookie consent, cookie inventory, privacy policy, data exposure, analytics and tracking, and third-party resources.
allowed-tools: Read, Grep, Glob, Bash(curl:*), Bash(grep:*), Bash(head:*), Bash(tail:*), Bash(echo:*), Bash(cat:*), Bash(python3:*), mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_snapshot, mcp__plugin_playwright_playwright__browser_evaluate, mcp__plugin_playwright_playwright__browser_click, mcp__plugin_playwright_playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_console_messages, mcp__plugin_playwright_playwright__browser_network_requests, mcp__plugin_playwright_playwright__browser_run_code, mcp__plugin_playwright_playwright__browser_close, mcp__plugin_playwright_playwright__browser_tabs
---

# Compliance & Privacy Checklist - Passive Assessment

Comprehensive, actionable checklist for passive compliance and privacy assessment. This skill guides the agent through systematic checks of cookie consent mechanisms, cookie inventory, privacy policy completeness, data exposure risks, analytics and tracking scripts, and third-party resource loading.

---

## 1. Cookie Consent

Detect and evaluate the cookie consent mechanism on the target site.

### Detect cookie consent banner

Using Playwright, check for elements matching common consent banner patterns:

```javascript
const consentBanner = document.querySelector(
  '[class*="cookie"], [class*="consent"], [id*="cookie"], [id*="consent"], ' +
  '[class*="gdpr"], [id*="gdpr"], [aria-label*="cookie"], [aria-label*="consent"]'
);
```

### Check for CMP (Consent Management Platform)

Detect known Consent Management Platforms by their JavaScript files or DOM elements:

- **OneTrust** — `cdn.cookielaw.org`, `optanon`, `onetrust`
- **CookieBot** — `consent.cookiebot.com`, `CookieConsent`
- **Didomi** — `sdk.privacy-center.org`, `didomi`
- **TrustArc** — `consent.trustarc.com`, `truste`
- **Quantcast Choice** — `quantcast.mgr.consensu.org`, `__tcfapi`

### CRITICAL CHECK: Are non-essential cookies set BEFORE user consent?

Navigate fresh (incognito-like), capture cookies immediately after page load, before any interaction:

1. Open the target URL in a fresh browser context
2. Immediately after page load, capture all cookies via `document.cookie` and network response `Set-Cookie` headers
3. Classify each cookie — if any analytics (_ga, _gid, _hjSessionUser, _clarity) or marketing (_fbp, _gcl) cookies are present before consent, this is a **Critical** finding

### Verify consent mechanism actually blocks cookie setting

Compare cookies before and after accepting consent:

1. Record cookies on fresh page load (before interaction)
2. Click the "Accept All" button on the consent banner
3. Record cookies after acceptance
4. Verify that non-essential cookies only appear after consent is given

### Check consent banner accessibility

- Is the consent banner keyboard-navigable? (Tab key should reach all buttons)
- Does it have proper ARIA attributes? (`role`, `aria-label`, `aria-describedby`)
- Are buttons properly labeled for screen readers?

### Check for reject option

GDPR requires an equally prominent "Reject All" option alongside "Accept All":

- Look for a "Reject All", "Decline", or "Refuse" button
- Verify it has equal visual prominence (same size, same styling) as "Accept All"
- Check that rejecting actually prevents non-essential cookies from being set

---

## 2. Cookie Inventory

Build a complete inventory of all cookies set by the target site.

### List all cookies from HTTP headers

```bash
curl -sI "URL" | grep -i "set-cookie"
```

### List all cookies from JavaScript

Using Playwright:

```javascript
document.cookie
```

### For each cookie, document

- **Name** — cookie name
- **Domain** — which domain set the cookie
- **Path** — cookie path scope
- **Expiry** — session vs persistent, max-age/expires value
- **Secure flag** — must be set on HTTPS sites
- **HttpOnly flag** — should be set on server-side cookies
- **SameSite attribute** — Strict/Lax/None (None requires Secure)

### Classify each cookie

- **Necessary:** session IDs, CSRF tokens, load balancer affinity
- **Analytics:** `_ga`, `_gid`, `_gat`, `_hjSessionUser`, `_clarity`, `mp_` (Mixpanel)
- **Marketing:** `_fbp`, `_fbc`, `_gcl`, ads tracking cookies
- **Functional:** language preferences, UI settings
- **Unknown:** unrecognized cookies need investigation

### Flag cookies without proper security flags

For each cookie, verify:

1. **Secure flag** — every cookie on an HTTPS site must have the `Secure` flag
2. **HttpOnly flag** — server-side session cookies should have `HttpOnly`
3. **SameSite attribute** — must be `Strict` or `Lax`; `None` requires `Secure` and is only acceptable for legitimate cross-site use cases
4. Cookies with `SameSite=None` without `Secure` — browsers will reject these, but it indicates misconfiguration

---

## 3. Privacy Policy

Check for the presence, accessibility, and completeness of the privacy policy.

### Check for privacy policy link

Search footer and navigation for links containing privacy-related keywords:

```javascript
const privacyLinks = Array.from(document.querySelectorAll('a[href]')).filter(a => {
  const text = (a.textContent + ' ' + a.href).toLowerCase();
  return text.includes('privacy') || text.includes('datenschutz') ||
         text.includes('prywatno') || text.includes('rodo') || text.includes('gdpr');
});
```

### Verify link is accessible

Check HTTP status code is 200:

```bash
curl -sI "PRIVACY_POLICY_URL" -o /dev/null -w "%{http_code}"
```

### Check for GDPR required sections

Scan the privacy policy page content for the following required sections:

1. **Data controller identity and contact details** — who is responsible for data processing
2. **Purposes of data processing** — why data is collected and processed
3. **Legal basis for processing** — consent, legitimate interest, contract, legal obligation
4. **Data retention period** — how long data is stored
5. **Data subject rights** — access, rectification, erasure, portability, restriction, objection
6. **Right to lodge complaint with supervisory authority** — reference to relevant DPA
7. **Whether data is transferred outside EU/EEA** — international transfer safeguards
8. **Automated decision-making / profiling disclosure** — if applicable

### Check language matches site language

- The privacy policy must be available in the same language as the main site
- If the site serves multiple languages, the privacy policy should be available in all of them

### Check last updated date is present and recent

- Look for a "Last updated", "Effective date", or "Date of last revision" statement
- Flag if no date is present
- Flag if the date is older than 12 months

---

## 4. Data Exposure

Check for personal data exposed in page source, URLs, and forms.

### Scan HTML source for email patterns

```bash
curl -s "URL" | grep -oiE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
```

### Scan for phone number patterns in HTML

```bash
curl -s "URL" | grep -oiE '(\+?[0-9]{1,3}[-.\s]?)?(\(?[0-9]{2,4}\)?[-.\s]?){1,3}[0-9]{3,4}'
```

### Check for personal data in URL parameters

Look for personal data visible in URLs:

- `name=`, `email=`, `user=`, `uid=`, `phone=`
- User IDs, session tokens, or personal identifiers in query strings
- Personal data in URL path segments

### Check forms for third-party action URLs

Verify that form data is not sent to external domains:

```javascript
const forms = Array.from(document.querySelectorAll('form[action]'));
const externalForms = forms.filter(f => {
  const action = new URL(f.action, window.location.origin);
  return action.hostname !== window.location.hostname;
});
```

### Check autocomplete attributes on sensitive fields

```javascript
const sensitiveFields = document.querySelectorAll(
  'input[type="password"], input[type="email"], input[name*="card"], ' +
  'input[name*="ssn"], input[name*="tax"], input[autocomplete*="cc-"]'
);
```

Verify that sensitive fields have appropriate `autocomplete` attributes to prevent unwanted data caching.

### Check for exposed user data in page source

- Search for API responses embedded in HTML (`__INITIAL_STATE__`, `__NEXT_DATA__`, `__NUXT__`)
- Check for user objects, email addresses, or personal data in hydration data
- Look for comments containing personal data or internal information

---

## 5. Analytics & Tracking

Detect analytics and tracking scripts and verify they respect user consent.

### Detect analytics and tracking scripts

Using Playwright, identify known tracking scripts:

- **Google Analytics:** `gtag.js`, `analytics.js`, `ga.js`
- **Google Tag Manager:** `googletagmanager.com/gtm.js`
- **Meta (Facebook) Pixel:** `connect.facebook.net/en_US/fbevents.js`
- **Hotjar:** `static.hotjar.com`
- **Microsoft Clarity:** `clarity.ms`
- **Segment:** `cdn.segment.com/analytics.js`
- **Mixpanel:** `cdn.mxpnl.com`
- **Amplitude:** `cdn.amplitude.com`

```javascript
const trackingScripts = Array.from(document.querySelectorAll('script[src]')).filter(s => {
  const src = s.src.toLowerCase();
  return src.includes('google-analytics') || src.includes('googletagmanager') ||
         src.includes('gtag') || src.includes('facebook') || src.includes('fbevents') ||
         src.includes('hotjar') || src.includes('clarity') || src.includes('segment') ||
         src.includes('mixpanel') || src.includes('amplitude');
}).map(s => s.src);
```

### CRITICAL: Check if tracking scripts fire BEFORE consent is given

Load the page fresh, check network requests for analytics endpoints before any user interaction:

1. Navigate to the target URL in a fresh browser context
2. Immediately capture all network requests
3. Check for requests to analytics endpoints (google-analytics.com, facebook.com/tr, hotjar.com, clarity.ms)
4. If analytics requests are made before consent is given, this is a **High** finding

### Check for cross-domain tracking

- Inspect GTM container configuration for cross-domain tracking settings
- Check GA configuration for `linker` or cross-domain parameters
- Look for `_gl` parameters in URLs that indicate cross-domain tracking

### Detect browser fingerprinting

Search for fingerprinting techniques in scripts:

- **Canvas fingerprinting** — `toDataURL()`, `getImageData()` on canvas elements
- **WebGL fingerprinting** — `getExtension()`, `getParameter()` on WebGL contexts
- **AudioContext fingerprinting** — `createOscillator()`, `createDynamicsCompressor()` for audio fingerprinting

---

## 6. Third-Party Resources

Inventory and classify all external resources loaded by the page.

### Inventory all external domains loaded

Using Playwright:

```javascript
const thirdParty = {
  scripts: Array.from(document.querySelectorAll('script[src]'))
    .filter(s => !s.src.includes(window.location.hostname)).map(s => s.src),
  styles: Array.from(document.querySelectorAll('link[rel="stylesheet"]'))
    .filter(l => !l.href.includes(window.location.hostname)).map(l => l.href),
  images: Array.from(document.querySelectorAll('img[src]'))
    .filter(i => !i.src.includes(window.location.hostname)).map(i => i.src),
  iframes: Array.from(document.querySelectorAll('iframe[src]'))
    .filter(f => !f.src.includes(window.location.hostname)).map(f => f.src),
  fonts: performance.getEntriesByType('resource')
    .filter(r => r.initiatorType === 'css' && !r.name.includes(window.location.hostname) &&
            (r.name.includes('.woff') || r.name.includes('.ttf') || r.name.includes('.otf')))
    .map(r => r.name)
};
```

### Classify purpose

Categorize each third-party resource by purpose:

- **CDN:** cdnjs.cloudflare.com, cdn.jsdelivr.net, unpkg.com, cloudflare.com
- **Analytics:** google-analytics.com, facebook.com, hotjar.com, clarity.ms
- **Advertising:** doubleclick.net, googlesyndication.com, adsense
- **Social:** facebook.com widgets, twitter.com widgets, linkedin.com widgets
- **Functional:** fonts.googleapis.com, maps.googleapis.com, recaptcha

### Count total third-party requests and their share

- Count all third-party requests vs total requests
- Calculate percentage of third-party resources
- Identify domains with the most requests

### Check for data sent to non-EU domains

Based on domain TLD and known service locations:

- US-based services: Google, Facebook, Amazon, Microsoft (check for EU data processing agreements)
- Check for data transfers to domains outside EU/EEA jurisdiction
- Verify if appropriate safeguards (Standard Contractual Clauses, adequacy decisions) are likely in place

### Flag unknown third-party resources

Any third-party resource that does not fall into a recognized category needs investigation:

- Unknown tracking pixels
- Unfamiliar JavaScript includes
- Unrecognized iframe embeds

---

## Severity Assessment Guide

| Finding | Severity |
|---------|----------|
| Non-essential cookies set before consent | Critical |
| No cookie consent mechanism on site using tracking | Critical |
| No privacy policy | High |
| Analytics firing before consent | High |
| Privacy policy missing required GDPR sections | High |
| No "Reject All" option in consent banner | High |
| Personal data (emails, phones) exposed in HTML | Medium |
| Cookies without Secure flag | Medium |
| Cookies without SameSite attribute | Medium |
| Personal data in URL parameters | Medium |
| Privacy policy in wrong language | Medium |
| Missing cookie purpose classification | Low |
| Third-party resources without clear purpose | Low |
| No data processing agreement info | Low |
| Missing privacy policy last updated date | Low |

---

## Finding Report Format

Each finding MUST follow this format:

```markdown
### [SEVERITY] Problem title
- **URL/Evidence:** specific URL, cookie, script, or content
- **Risk:** compliance and legal risk description (GDPR fines, user trust)
- **Recommendation:** what to do (with implementation guidance)
- **Verification:** how to confirm the fix
- **Owner:** Dev / Legal / Marketing / DPO
```

### Example

```markdown
### [CRITICAL] Non-essential cookies set before user consent
- **URL/Evidence:** `_ga` and `_gid` cookies from Google Analytics are set immediately on page load at `https://example.com` before user interacts with the consent banner
- **Risk:** Violation of GDPR Article 5(1)(a) and ePrivacy Directive Article 5(3). Non-essential cookies require prior consent. Potential fine of up to 4% of annual global turnover or EUR 20 million.
- **Recommendation:** Configure Google Analytics to load only after user grants consent via the CMP. Use Google Tag Manager consent mode or implement a custom consent gate that blocks analytics script injection until consent is recorded.
- **Verification:** Open the site in a fresh incognito window, check `document.cookie` immediately after page load — no `_ga` or `_gid` cookies should be present before interacting with the consent banner.
- **Owner:** Dev / Marketing
```

---

## Assessment Workflow

1. **Detect consent mechanism** — Check for cookie consent banner and CMP presence
2. **Audit consent behavior** — Verify cookies are blocked before consent and set after consent
3. **Inventory cookies** — List and classify all cookies with security flags
4. **Check privacy policy** — Verify presence, accessibility, and GDPR completeness
5. **Scan for data exposure** — Search for personal data in HTML, URLs, and forms
6. **Detect tracking scripts** — Identify all analytics and tracking, verify consent gating
7. **Inventory third-party resources** — Catalog all external domains and classify their purpose
8. **Generate report** — Document all findings using the report format above
