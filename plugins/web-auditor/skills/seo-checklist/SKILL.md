---
name: seo-checklist
description: Checklist for passive technical SEO assessment. Covers indexability, metadata quality, structured data, rendering, internal linking, OpenGraph, internationalization, and sitemap analysis.
allowed-tools: Read, Grep, Glob, Bash(curl:*), Bash(grep:*), Bash(head:*), Bash(tail:*), Bash(echo:*), Bash(cat:*), Bash(python3:*), mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_snapshot, mcp__plugin_playwright_playwright__browser_evaluate, mcp__plugin_playwright_playwright__browser_click, mcp__plugin_playwright_playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_console_messages, mcp__plugin_playwright_playwright__browser_network_requests, mcp__plugin_playwright_playwright__browser_run_code, mcp__plugin_playwright_playwright__browser_close, mcp__plugin_playwright_playwright__browser_tabs
---

# SEO Checklist - Passive Technical Assessment

Comprehensive, actionable checklist for passive technical SEO assessment. This skill guides the agent through systematic checks of indexability, metadata quality, structured data, rendering strategy, internal linking, OpenGraph tags, internationalization, and sitemap alignment.

---

## 1. Indexability

Check that search engines can discover, crawl, and index all intended pages.

### Parse robots.txt

```bash
curl -s "https://DOMAIN/robots.txt"
```

Verify:
- **Disallow directives** — identify overly broad rules (e.g., `Disallow: /`) that block the entire site
- **Crawl-delay** — note any `Crawl-delay` directives that may slow indexing
- **User-agent rules** — check for Googlebot-specific rules that differ from the wildcard `*` agent
- **Sitemap reference** — confirm a `Sitemap:` directive is present and points to a valid URL

### Meta robots per URL

Using Playwright, check the meta robots tag on each page:

```javascript
document.querySelector('meta[name="robots"]')?.content
```

Look for:
- `noindex` — page will not appear in search results
- `nofollow` — links on the page will not be followed
- Detect pages with `noindex` that should be indexed (e.g., product pages, blog posts)

### X-Robots-Tag header

```bash
curl -sI "URL" | grep -i "x-robots-tag"
```

The `X-Robots-Tag` HTTP header can override meta robots. Check that it does not conflict with the intended indexing strategy.

### Canonical consistency

Using Playwright, compare the canonical URL with the actual URL:

```javascript
document.querySelector('link[rel="canonical"]')?.href
```

Verify:
- Canonical URL is present on every page
- Canonical URL matches the actual page URL (no mismatch)
- Canonical is an absolute URL, not relative
- Pages with query parameters canonicalize to the clean version

### Redirect chains

```bash
curl -sIL "URL"
```

Flag:
- **302 redirects that should be 301** — temporary redirects do not pass full link equity
- **Redirect chains longer than 3 hops** — excessive redirects waste crawl budget and dilute link equity
- **Redirect loops** — infinite redirects that prevent page access
- **HTTP to HTTPS redirects followed by additional redirects** — consolidate into a single hop

---

## 2. Metadata Quality

Evaluate title tags, meta descriptions, and heading structure across all crawled pages.

### Title tag

Using Playwright:

```javascript
document.title
```

Check:
- **Presence** — every page must have a `<title>` tag
- **Length** — ideal range is 30-60 characters; flag titles shorter than 30 or longer than 60 characters
- **Uniqueness** — compare titles across all crawled URLs; flag duplicates
- **Content quality** — title should describe the page content, not be generic (e.g., "Home" or "Untitled")

### Meta description

Using Playwright:

```javascript
document.querySelector('meta[name="description"]')?.content
```

Check:
- **Presence** — every indexable page should have a meta description
- **Length** — ideal range is 120-160 characters; flag descriptions shorter than 120 or longer than 160 characters
- **Uniqueness** — compare descriptions across all crawled URLs; flag duplicates
- **Content quality** — description should be a compelling summary, not keyword stuffing

### H1 tag

Using Playwright:

```javascript
document.querySelectorAll('h1')
```

Check:
- **Exactly one H1 per page** — multiple H1 tags dilute heading structure; zero H1 means missing primary heading
- **Content quality** — H1 should describe the page topic and ideally include the primary keyword

### Heading hierarchy

Using Playwright:

```javascript
const headings = Array.from(document.querySelectorAll('h1, h2, h3, h4, h5, h6'));
const levels = headings.map(h => ({ tag: h.tagName, text: h.textContent.trim().substring(0, 80) }));
```

Check:
- **Skipped levels** — flag if the page goes from H1 directly to H3 without an H2
- **Multiple H1 tags** — flag if more than one H1 exists
- **Logical nesting** — heading levels should increase sequentially within sections

### Duplicate detection

Compare titles and meta descriptions across all crawled URLs:
- Build a map of `title -> [URLs]` and `description -> [URLs]`
- Flag any title or description appearing on more than one URL
- Pay special attention to paginated pages sharing the same metadata

---

## 3. Structured Data

Detect and validate JSON-LD structured data on each page.

### Detect JSON-LD

Using Playwright:

```javascript
const scripts = Array.from(document.querySelectorAll('script[type="application/ld+json"]'));
const structuredData = scripts.map(s => {
  try { return JSON.parse(s.textContent); }
  catch (e) { return { error: e.message, raw: s.textContent.substring(0, 200) }; }
});
```

### Check Schema.org types

Common types to look for:
- `Organization` — company information
- `WebSite` — site-level search action
- `BreadcrumbList` — breadcrumb navigation
- `Product` — product pages (e-commerce)
- `Article` / `BlogPosting` / `NewsArticle` — content pages
- `FAQ` / `HowTo` — rich snippet eligible content
- `LocalBusiness` — local SEO
- `Event` — event pages

### Validate required properties per type

| Schema Type | Required Properties |
|-------------|-------------------|
| Product | name, image, offers (with price, priceCurrency, availability) |
| Article | headline, image, author, datePublished |
| BreadcrumbList | itemListElement (with position, name, item) |
| Organization | name, url, logo |
| FAQ | mainEntity (with name, acceptedAnswer.text) |
| Event | name, startDate, location |
| LocalBusiness | name, address, telephone |

### Check nested entities and @id references

- Verify that `@id` references resolve to defined entities within the same page or site
- Check that nested objects have proper `@type` declarations
- Validate that `@context` is set to `https://schema.org`

### Assess Google Rich Results eligibility

Based on the Schema type and properties present, determine if the page is eligible for:
- Product rich results (requires name, image, offers with price)
- FAQ rich results (requires Question + Answer pairs)
- Breadcrumb rich results (requires itemListElement array)
- Article rich results (requires headline, image, author, datePublished, publisher)
- Review rich results (requires reviewRating, author)

---

## 4. Rendering (SSR vs CSR)

Determine whether the site uses server-side rendering (SSR) or client-side rendering (CSR) and assess SEO impact.

### Compare raw HTML vs rendered HTML

Fetch the raw HTML without JavaScript execution:

```bash
curl -s "URL" | python3 -c "
import sys
from html.parser import HTMLParser
class TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.text = []
        self.skip = False
    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'): self.skip = True
    def handle_endtag(self, tag):
        if tag in ('script', 'style'): self.skip = False
    def handle_data(self, data):
        if not self.skip and data.strip():
            self.text.append(data.strip())
p = TextExtractor()
p.feed(sys.stdin.read())
print('\n'.join(p.text[:50]))
"
```

Then compare with the rendered HTML from Playwright:

```javascript
document.body.innerText.substring(0, 5000)
```

If significant content is present in the rendered version but missing from the raw HTML, the site relies on client-side rendering, which is a major SEO risk.

### Check noscript fallback

Using Playwright:

```javascript
Array.from(document.querySelectorAll('noscript')).map(n => n.innerHTML.substring(0, 200))
```

Verify that `<noscript>` tags provide meaningful fallback content for search engine crawlers that may not execute JavaScript.

### Check for hydration errors

Use `browser_console_messages` to detect React, Next.js, or Nuxt hydration warnings:
- `Warning: Text content did not match`
- `Hydration failed because the initial UI does not match`
- `There was an error while hydrating`

Hydration errors can cause content mismatches between what the server renders and what the client displays.

### Check main content in initial HTML

```bash
curl -s "URL" | grep -i "<h1\|<article\|<main"
```

Verify that the primary content (H1, article body, product details) is present in the initial HTML response, not injected by JavaScript.

---

## 5. Internal Linking

Analyze the internal link structure for crawlability and link equity distribution.

### Identify orphan pages

Compare the sitemap URLs with pages that receive internal links:

```bash
curl -s "https://DOMAIN/sitemap.xml" | grep -oP '<loc>\K[^<]+'
```

Using Playwright on each page, collect all internal links:

```javascript
const links = Array.from(document.querySelectorAll('a[href]'));
const internalLinks = links
  .map(a => a.href)
  .filter(href => href.startsWith(window.location.origin));
```

An orphan page is a URL present in the sitemap but with no internal links pointing to it from any crawled page.

### Detect broken internal links

For each internal link found during crawling, verify it does not return a 4xx or 5xx status:

```bash
curl -sI "INTERNAL_URL" -o /dev/null -w "%{http_code}"
```

Flag any internal link returning 404 or other error status codes.

### Calculate link depth

Measure the number of clicks from the homepage to each page:
- Homepage = depth 0
- Pages linked from homepage = depth 1
- Pages linked only from depth-1 pages = depth 2
- Flag pages with depth > 3 as potentially difficult to crawl

### Check anchor text quality

Using Playwright:

```javascript
const links = Array.from(document.querySelectorAll('a[href]'));
const anchorTexts = links.map(a => ({
  text: a.textContent.trim(),
  href: a.href
})).filter(a => a.text);
```

Flag poor anchor text:
- "click here"
- "read more"
- "learn more"
- "here"
- Empty anchor text (image links without alt text)

### Verify navigation structure

Check that the main navigation is accessible from every page:

```javascript
const nav = document.querySelector('nav, [role="navigation"]');
const navLinks = nav ? Array.from(nav.querySelectorAll('a[href]')).map(a => a.href) : [];
```

Verify that key pages are reachable from the global navigation.

---

## 6. OpenGraph & Social

Verify that OpenGraph and Twitter Card meta tags are properly configured for social sharing.

### OpenGraph tags

Using Playwright:

```javascript
const ogTags = {};
document.querySelectorAll('meta[property^="og:"]').forEach(m => {
  ogTags[m.getAttribute('property')] = m.content;
});
```

Check:
- **og:title** — present, descriptive, not truncated (under 60 chars ideal)
- **og:description** — present, compelling summary (under 200 chars ideal)
- **og:image** — present, absolute URL, accessible (not 404)
- **og:type** — present (e.g., `website`, `article`, `product`)
- **og:url** — present and matches the canonical URL

### OpenGraph image dimensions

Verify that `og:image` meets minimum recommended dimensions:
- Minimum: 1200x630 pixels for high-resolution displays
- Facebook recommends 1.91:1 aspect ratio

Using Playwright to check image accessibility:

```javascript
const ogImage = document.querySelector('meta[property="og:image"]')?.content;
if (ogImage) {
  const img = new Image();
  img.src = ogImage;
  await new Promise(r => { img.onload = r; img.onerror = r; });
  return { width: img.naturalWidth, height: img.naturalHeight, src: ogImage };
}
```

### Twitter Card tags

Using Playwright:

```javascript
const twitterTags = {};
document.querySelectorAll('meta[name^="twitter:"]').forEach(m => {
  twitterTags[m.getAttribute('name')] = m.content;
});
```

Check:
- **twitter:card** — present, value is `summary`, `summary_large_image`, `app`, or `player`
- **twitter:title** — present (falls back to og:title if missing)
- **twitter:description** — present (falls back to og:description if missing)
- **twitter:image** — present (falls back to og:image if missing)

### Cross-validate

- Verify `og:url` matches the canonical URL (`link[rel="canonical"]`)
- If `og:url` and canonical differ, social shares may point to the wrong page

---

## 7. Internationalization

Check hreflang implementation for multilingual or multi-regional sites.

### Detect hreflang tags

Using Playwright:

```javascript
const hreflangs = Array.from(document.querySelectorAll('link[rel="alternate"][hreflang]')).map(l => ({
  hreflang: l.getAttribute('hreflang'),
  href: l.href
}));
```

### Verify bidirectional references

For each hreflang pair: if page A declares `hreflang="fr"` pointing to page B, then page B must declare `hreflang="en"` (or the source language) pointing back to page A. Missing return links cause hreflang to be ignored by search engines.

To verify:

```bash
# Fetch the target hreflang URL and check for the return reference
curl -s "HREFLANG_TARGET_URL" | grep -i 'hreflang'
```

### Check html lang attribute

Using Playwright:

```javascript
document.documentElement.lang
```

Verify:
- `<html lang="...">` attribute is present
- The value matches the actual content language
- Format is correct BCP 47 (e.g., `en`, `en-US`, `fr-FR`)

### Verify x-default

Check that an `x-default` hreflang exists for the language selector or default landing page:

```javascript
const xDefault = document.querySelector('link[rel="alternate"][hreflang="x-default"]');
```

The `x-default` value tells search engines which page to show when no other hreflang matches the user's language.

### Check locale format correctness

Common mistakes to flag:
- `en_US` instead of `en-US` (underscore vs hyphen)
- `eng` instead of `en` (ISO 639-2 vs ISO 639-1)
- `en-uk` instead of `en-GB` (incorrect country code)
- Missing region code when needed (e.g., `pt` when `pt-BR` and `pt-PT` should be distinguished)

---

## 8. Sitemap & Robots Alignment

Verify that the sitemap and robots.txt are consistent and accurately reflect the site's content.

### Compare sitemap URLs vs crawled URLs

```bash
curl -s "https://DOMAIN/sitemap.xml" | grep -oP '<loc>\K[^<]+'
```

Identify:
- **Missing pages** — URLs found during crawling but not present in the sitemap
- **Ghost pages** — URLs listed in the sitemap but returning 404 or non-200 status codes
- **Noindexed pages in sitemap** — URLs in sitemap that have `noindex` meta robots tag (contradictory)

### Validate sitemap XML format

```bash
curl -s "https://DOMAIN/sitemap.xml" | head -5
```

Check:
- Valid XML declaration (`<?xml version="1.0" encoding="UTF-8"?>`)
- Proper namespace (`xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"`)
- Well-formed XML (no parsing errors)
- Sitemap index file references valid child sitemaps

### Check lastmod dates

```bash
curl -s "https://DOMAIN/sitemap.xml" | grep -oP '<lastmod>\K[^<]+'
```

Verify:
- `<lastmod>` dates are present
- Dates are in W3C datetime format (e.g., `2024-01-15T10:30:00+00:00`)
- Dates are not all identical (suggests auto-generated, not reflecting actual changes)
- Dates are not in the future

### Verify robots.txt does not block rendering resources

```bash
curl -s "https://DOMAIN/robots.txt"
```

Check that the robots.txt does not block:
- CSS files needed for rendering (`Disallow: /css/` or `Disallow: *.css$`)
- JavaScript files needed for rendering (`Disallow: /js/` or `Disallow: *.js$`)
- Image directories (`Disallow: /images/`)
- Font files

Blocking these resources prevents search engines from properly rendering and understanding page content.

### Check sitemap file size limits

- Maximum file size: 50 MB (uncompressed)
- Maximum URLs per sitemap file: 50,000
- If limits are exceeded, a sitemap index file must be used to split into multiple sitemaps

```bash
curl -s "https://DOMAIN/sitemap.xml" | wc -c
curl -s "https://DOMAIN/sitemap.xml" | grep -c "<url>"
```

---

## Severity Assessment Guide

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

---

## Finding Report Format

Each finding MUST follow this format:

```markdown
### [SEVERITY] Problem title
- **URL/Evidence:** specific URL, tag, or content
- **Risk:** SEO impact description
- **Recommendation:** what to do (with code/config example)
- **Verification:** how to confirm the fix
- **Owner:** Dev / Marketing / SEO
```

### Example

```markdown
### [HIGH] Missing title tag on product pages
- **URL/Evidence:** `https://example.com/products/widget-x` — `<title>` tag is empty
- **Risk:** Pages without title tags are poorly represented in search results, leading to low click-through rates and potential ranking loss. Search engines may auto-generate a title from page content, which is often suboptimal.
- **Recommendation:** Add a unique, descriptive title tag to every page:
  ```html
  <title>Widget X - Premium Widgets | Example Store</title>
  ```
  Keep titles between 30-60 characters and include the primary keyword.
- **Verification:** `curl -s "https://example.com/products/widget-x" | grep -i "<title>"` should return a non-empty title tag
- **Owner:** Dev / Marketing
```

---

## Assessment Workflow

1. **Check indexability** — Parse robots.txt, verify meta robots, canonical tags, and redirect chains
2. **Evaluate metadata** — Audit title tags, meta descriptions, H1 tags, and heading hierarchy across all URLs
3. **Validate structured data** — Detect JSON-LD, verify Schema.org types and required properties
4. **Assess rendering** — Compare raw HTML vs rendered HTML to determine SSR/CSR strategy
5. **Analyze internal linking** — Identify orphan pages, broken links, link depth, and anchor text quality
6. **Verify social tags** — Check OpenGraph and Twitter Card meta tags on all pages
7. **Check internationalization** — Validate hreflang tags, bidirectional references, and locale formats
8. **Align sitemap and robots** — Compare sitemap URLs with crawled URLs, validate format and lastmod dates
9. **Generate report** — Document all findings using the report format above
