---
name: performance-checklist
description: Checklist for passive web performance assessment. Covers Core Web Vitals, images, fonts, JavaScript, CSS, caching, compression, and resource hints.
allowed-tools: Read, Grep, Glob, Bash(curl:*), Bash(grep:*), Bash(head:*), Bash(tail:*), Bash(echo:*), Bash(cat:*), Bash(python3:*), mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_snapshot, mcp__plugin_playwright_playwright__browser_evaluate, mcp__plugin_playwright_playwright__browser_click, mcp__plugin_playwright_playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_console_messages, mcp__plugin_playwright_playwright__browser_network_requests, mcp__plugin_playwright_playwright__browser_run_code, mcp__plugin_playwright_playwright__browser_close, mcp__plugin_playwright_playwright__browser_tabs
---

# Performance Checklist - Passive Assessment

Comprehensive, actionable checklist for passive web performance assessment. This skill guides the agent through systematic checks of Core Web Vitals, images, fonts, JavaScript, CSS, caching, compression, and resource hints.

---

## 1. Core Web Vitals

Measure key performance metrics using Playwright's browser evaluation capabilities.

### Largest Contentful Paint (LCP)

```javascript
const lcpEntries = performance.getEntriesByType('largest-contentful-paint');
const lcp = lcpEntries.length > 0 ? lcpEntries[lcpEntries.length - 1].startTime : null;
```

| Rating | Threshold |
|--------|-----------|
| Good | < 2.5s |
| Needs Improvement | 2.5s - 4.0s |
| Poor | > 4.0s |

### Cumulative Layout Shift (CLS)

Use PerformanceObserver to collect `layout-shift` entries and sum their values:

```javascript
const clsEntries = performance.getEntriesByType('layout-shift');
const cls = clsEntries
  .filter(entry => !entry.hadRecentInput)
  .reduce((sum, entry) => sum + entry.value, 0);
```

| Rating | Threshold |
|--------|-----------|
| Good | < 0.1 |
| Needs Improvement | 0.1 - 0.25 |
| Poor | > 0.25 |

### Interaction to Next Paint (INP) Estimation

Check event timing entries via `performance.getEntriesByType('event')` and look at processing time:

```javascript
const eventEntries = performance.getEntriesByType('event');
const maxProcessingTime = eventEntries.length > 0
  ? Math.max(...eventEntries.map(e => e.processingEnd - e.processingStart))
  : null;
```

| Rating | Threshold |
|--------|-----------|
| Good | < 200ms |
| Needs Improvement | 200ms - 500ms |
| Poor | > 500ms |

### First Contentful Paint (FCP)

```javascript
const paintEntries = performance.getEntriesByType('paint');
const fcp = paintEntries.find(e => e.name === 'first-contentful-paint');
const fcpTime = fcp ? fcp.startTime : null;
```

- Target: < 1.8s

### Time to First Byte (TTFB)

```javascript
const navEntries = performance.getEntriesByType('navigation');
const ttfb = navEntries.length > 0 ? navEntries[0].responseStart - navEntries[0].requestStart : null;
```

- Target: < 800ms

### Per-URL Metrics Table

Present results as a table per URL:

| URL | LCP | CLS | INP est. | FCP | TTFB | Rating |
|-----|-----|-----|----------|-----|------|--------|
| /   | ... | ... | ...      | ... | ...  | ...    |

---

## 2. Images

Check all images on the page for format, sizing, lazy loading, and dimension attributes.

### Playwright snippet

```javascript
const images = Array.from(document.querySelectorAll('img')).map(img => ({
  src: img.src,
  naturalWidth: img.naturalWidth,
  naturalHeight: img.naturalHeight,
  displayWidth: img.clientWidth,
  displayHeight: img.clientHeight,
  loading: img.loading,
  hasWidthAttr: img.hasAttribute('width'),
  hasHeightAttr: img.hasAttribute('height')
}));
```

### Checks to perform

1. **Format detection** - Check Content-Type for each image resource. Flag PNG/JPG photos that should be WebP/AVIF for better compression.
2. **Oversized images** - Compare `naturalWidth/naturalHeight` vs `clientWidth/clientHeight` (display size). Flag if natural dimensions are > 2x the display dimensions.
3. **Lazy loading** - Check for `loading="lazy"` attribute on below-fold images. Above-fold images (hero, logo) should NOT have lazy loading.
4. **Missing width/height attributes** - `img.hasAttribute('width') && img.hasAttribute('height')` — missing dimensions cause layout shifts (CLS).
5. **Image count and total transfer size** - Collect from `performance.getEntriesByType('resource').filter(r => r.initiatorType === 'img')` and sum `transferSize`.
6. **Next-gen format support** - Look for `<picture>` elements with `<source type="image/webp">` or `<source type="image/avif">` for progressive enhancement.

```javascript
const pictureElements = Array.from(document.querySelectorAll('picture'));
const nextGenSources = pictureElements.map(p => ({
  hasWebP: !!p.querySelector('source[type="image/webp"]'),
  hasAVIF: !!p.querySelector('source[type="image/avif"]'),
  fallbackSrc: p.querySelector('img')?.src
}));
```

---

## 3. Fonts

Analyze font loading strategy and its impact on rendering performance.

### Checks to perform

1. **Detect @font-face declarations** - Use the `document.fonts` API or inspect stylesheets:

```javascript
const fontFaces = Array.from(document.fonts).map(f => ({
  family: f.family,
  style: f.style,
  weight: f.weight,
  status: f.status,
  display: f.display
}));
```

2. **Check font-display property** - Should be `swap` or `optional`. The value `font-display: block` causes Flash of Invisible Text (FOIT), hiding content until the font loads.

3. **Preload hints** - Check for `<link rel="preload" as="font" crossorigin>` for critical fonts:

```javascript
const fontPreloads = Array.from(document.querySelectorAll('link[rel="preload"][as="font"]')).map(l => ({
  href: l.href,
  crossorigin: l.hasAttribute('crossorigin'),
  type: l.type
}));
```

4. **Font file count and total size** - Collect from resource timing entries:

```javascript
const fontResources = performance.getEntriesByType('resource')
  .filter(r => r.initiatorType === 'css' && /\.(woff2?|ttf|otf|eot)(\?|$)/.test(r.name));
const totalFontSize = fontResources.reduce((sum, r) => sum + r.transferSize, 0);
```

5. **Detect FOUT/FOIT** - Observe rendering behavior by checking the `font-display` CSS property. Fonts without `font-display: swap` or `font-display: optional` risk FOIT (invisible text while font loads).

---

## 4. JavaScript

Analyze JavaScript payload size, loading strategy, and third-party impact.

### Checks to perform

1. **Total JS transfer size** - Sum from resource timing:

```javascript
const jsResources = performance.getEntriesByType('resource')
  .filter(r => r.initiatorType === 'script');
const totalJSSize = jsResources.reduce((sum, r) => sum + r.transferSize, 0);
const jsDetails = jsResources.map(r => ({
  url: r.name,
  transferSize: r.transferSize,
  duration: r.duration
}));
```

2. **Render-blocking scripts** - Scripts in `<head>` without `defer`, `async`, or `type="module"`:

```javascript
const headScripts = Array.from(document.head.querySelectorAll('script[src]'));
const renderBlocking = headScripts.filter(s =>
  !s.defer && !s.async && s.type !== 'module'
).map(s => s.src);
```

3. **Third-party JS** - Scripts with `src` not matching the page hostname:

```javascript
const allScripts = Array.from(document.querySelectorAll('script[src]'));
const thirdParty = allScripts.filter(s => {
  try {
    return new URL(s.src).hostname !== window.location.hostname;
  } catch { return false; }
}).map(s => s.src);
```

Count and total size of third-party scripts from resource timing entries.

4. **Inline script size** - Sum `textContent.length` of all inline `<script>` tags:

```javascript
const inlineScripts = Array.from(document.querySelectorAll('script:not([src])'));
const totalInlineSize = inlineScripts.reduce((sum, s) => sum + s.textContent.length, 0);
```

5. **Number of script requests total** - Count all script resource entries.

6. **Module usage** - Check for `<script type="module">` usage (modern loading pattern):

```javascript
const moduleScripts = document.querySelectorAll('script[type="module"]').length;
```

7. **Large scripts** - Flag individual scripts with transfer size > 100KB from resource timing entries.

---

## 5. CSS

Analyze CSS loading strategy, render-blocking behavior, and critical CSS usage.

### Checks to perform

1. **Total CSS transfer size** - Sum from resource entries with CSS type:

```javascript
const cssResources = performance.getEntriesByType('resource')
  .filter(r => r.initiatorType === 'link' && /\.css(\?|$)/.test(r.name));
const totalCSSSize = cssResources.reduce((sum, r) => sum + r.transferSize, 0);
```

2. **Render-blocking stylesheets** - `<link rel="stylesheet">` in `<head>` without `media` attribute targeting specific conditions:

```javascript
const stylesheets = Array.from(document.head.querySelectorAll('link[rel="stylesheet"]'));
const renderBlockingCSS = stylesheets.filter(l =>
  !l.media || l.media === 'all' || l.media === ''
).map(l => l.href);
```

3. **Critical CSS inlining** - Check for `<style>` tags in `<head>` with critical above-fold styles:

```javascript
const inlineStyles = Array.from(document.head.querySelectorAll('style'));
const hasCriticalCSS = inlineStyles.length > 0;
const criticalCSSSize = inlineStyles.reduce((sum, s) => sum + s.textContent.length, 0);
```

4. **Preload for stylesheets** - Check for `<link rel="preload" as="style">` usage:

```javascript
const cssPreloads = Array.from(document.querySelectorAll('link[rel="preload"][as="style"]')).map(l => l.href);
```

5. **CSS file count** - Count all external CSS resources.

6. **Media query conditional loading** - Check for deferred CSS loading pattern:

```javascript
const deferredCSS = Array.from(document.querySelectorAll('link[rel="stylesheet"][media="print"]'))
  .filter(l => l.hasAttribute('onload'))
  .map(l => l.href);
```

Pattern: `<link rel="stylesheet" media="print" onload="this.media='all'">` loads CSS non-blocking.

---

## 6. Caching

Check caching headers for static assets to ensure proper browser caching.

### How to check

```bash
curl -sI "ASSET_URL" | grep -i "cache-control\|etag\|expires\|vary\|last-modified"
```

### Checks to perform

1. **Cache-Control headers for static assets** (JS, CSS, images, fonts):
   - Should have `max-age` > 86400 (1 day) for static assets
   - `no-store` should only be used for dynamic/sensitive pages, not static assets
   - Ideal for immutable assets: `Cache-Control: public, max-age=31536000, immutable`

2. **ETag presence** - Check for `ETag` header for cache validation. Enables conditional requests (`If-None-Match`) to avoid re-downloading unchanged resources.

3. **Asset fingerprinting** - Check if filenames contain content hashes (e.g., `app.a1b2c3.js`, `styles.d4e5f6.css`). Fingerprinted assets can safely use long `max-age` values.

```javascript
const resources = performance.getEntriesByType('resource');
const fingerprinted = resources.filter(r =>
  /\.[a-f0-9]{6,}\./.test(r.name) || /[?&]v=[a-f0-9]+/.test(r.name)
);
```

4. **CDN detection** - Check for CDN headers indicating content delivery network usage:

```bash
curl -sI "URL" | grep -i "x-cache\|cf-ray\|x-amz-cf-id\|x-cdn\|via\|x-served-by\|x-cache-hits"
```

5. **Vary header correctness** - Should include `Accept-Encoding` to ensure proper caching of compressed vs uncompressed variants:

```bash
curl -sI "URL" | grep -i "vary"
```

---

## 7. Compression

Verify that text-based resources are served with compression enabled.

### How to check

```bash
curl -sI -H "Accept-Encoding: gzip, deflate, br" "URL" | grep -i "content-encoding"
```

Expected: `gzip` or `br` (brotli) for text-based resources.

### Checks to perform

1. **Content-Encoding header** - Check for compression on all text-based resources:
   - HTML pages
   - CSS files
   - JavaScript files
   - JSON responses
   - SVG images
   - XML documents

2. **Flag uncompressed text resources** - Any text resource served without `Content-Encoding: gzip` or `Content-Encoding: br` is a performance issue.

3. **Check each resource type separately** - Different resource types may have different compression configurations:

```bash
# Check HTML
curl -sI -H "Accept-Encoding: gzip, deflate, br" "https://TARGET" | grep -i "content-encoding"

# Check CSS
curl -sI -H "Accept-Encoding: gzip, deflate, br" "CSS_URL" | grep -i "content-encoding"

# Check JS
curl -sI -H "Accept-Encoding: gzip, deflate, br" "JS_URL" | grep -i "content-encoding"
```

4. **Transfer size vs content size** - Where available from resource timing, compare `transferSize` vs `decodedBodySize` to estimate compression ratio:

```javascript
const textResources = performance.getEntriesByType('resource')
  .filter(r => ['script', 'link', 'xmlhttprequest', 'fetch'].includes(r.initiatorType))
  .map(r => ({
    url: r.name,
    transferSize: r.transferSize,
    decodedBodySize: r.decodedBodySize,
    compressionRatio: r.decodedBodySize > 0 ? (r.transferSize / r.decodedBodySize).toFixed(2) : 'N/A'
  }));
```

---

## 8. Resource Hints

Check for resource hints that improve loading performance by pre-connecting to origins and preloading critical resources.

### Playwright snippet

```javascript
const hints = {
  preconnect: Array.from(document.querySelectorAll('link[rel="preconnect"]')).map(l => l.href),
  dnsPrefetch: Array.from(document.querySelectorAll('link[rel="dns-prefetch"]')).map(l => l.href),
  preload: Array.from(document.querySelectorAll('link[rel="preload"]')).map(l => ({href: l.href, as: l.as})),
  modulePreload: Array.from(document.querySelectorAll('link[rel="modulepreload"]')).map(l => l.href)
};
```

### Checks to perform

1. **Preconnect for critical third-party origins** - Check for `<link rel="preconnect">` for critical third-party origins such as `fonts.googleapis.com`, CDN domains, and analytics services. Preconnect performs DNS lookup, TCP connection, and TLS negotiation in advance.

2. **DNS prefetch for secondary third-party origins** - Check for `<link rel="dns-prefetch">` for secondary third-party origins that are used but not critical for initial render. Less aggressive than preconnect.

3. **Preload for critical resources** - Check for `<link rel="preload">` for critical resources such as:
   - Hero images
   - Main font files
   - Critical CSS
   - Above-fold resources that are discovered late by the browser

4. **Module preload for ES modules** - Check for `<link rel="modulepreload">` for ES module scripts. This allows the browser to fetch, parse, and compile modules before they are needed.

### What to look for

- Third-party origins used in the page that lack `preconnect` or `dns-prefetch` hints
- Critical resources (hero image, main font) that are discovered late and would benefit from `preload`
- ES modules that would benefit from `modulepreload`

---

## Severity Assessment Guide

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
| TTFB > 800ms | Medium |
| FCP > 1.8s | Medium |
| No preconnect for third-party origins | Low |
| Missing lazy loading on below-fold images | Low |
| Large inline scripts (>10KB) | Low |

---

## Finding Report Format

Each finding MUST follow this format:

```markdown
### [SEVERITY] Problem title
- **URL/Evidence:** specific URL, resource, metric value
- **Risk:** performance impact description (user experience, SEO ranking)
- **Recommendation:** what to do (with code/config example)
- **Verification:** how to confirm the fix
- **Owner:** Dev / DevOps / Frontend
```

### Example

```markdown
### [HIGH] Largest Contentful Paint exceeds 2.5s threshold
- **URL/Evidence:** `https://example.com/` - LCP measured at 3.8s, LCP element is hero image `<img src="/hero.jpg">`
- **Risk:** Poor user experience with slow visual load. Google uses LCP as a Core Web Vital ranking signal; pages with LCP > 2.5s may rank lower in search results.
- **Recommendation:** Optimize the LCP element:
  - Convert hero image to WebP/AVIF format
  - Add `<link rel="preload" as="image" href="/hero.webp">` to preload the hero image
  - Ensure the image is served from a CDN with proper caching
  - Consider using `fetchpriority="high"` on the hero `<img>` tag
- **Verification:** Re-measure LCP using Playwright `performance.getEntriesByType('largest-contentful-paint')` — target < 2.5s
- **Owner:** Frontend
```

---

## Assessment Workflow

1. **Measure Core Web Vitals** - Navigate to each URL and collect LCP, CLS, INP, FCP, TTFB metrics
2. **Audit images** - Check format, sizing, lazy loading, and dimension attributes
3. **Analyze fonts** - Inspect font-face declarations, font-display, and preloading
4. **Evaluate JavaScript** - Measure total JS size, render-blocking scripts, and third-party impact
5. **Evaluate CSS** - Check total CSS size, render-blocking stylesheets, and critical CSS
6. **Verify caching** - Inspect Cache-Control headers, ETags, and asset fingerprinting
7. **Check compression** - Verify Content-Encoding on text resources
8. **Review resource hints** - Check preconnect, dns-prefetch, preload, and modulepreload
9. **Generate report** - Document all findings using the report format above
