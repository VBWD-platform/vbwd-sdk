# S47.5 — RSS feeds (optional): per blog / category / tag / term

**Parent:** [S47 — Unified Content + SEO](s47-unified-content-seo.md) · **Depends on:** [S47.0](s47-0-unified-data-model-and-registries.md) · **Status:** DRAFT (OPTIONAL) — 2026-06-03
**Repos:** `vbwd-plugin-cms` (feed backend), `vbwd-fe-user-plugin-cms` (autodiscovery `<link>`).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · clean code · **core agnostic** · **NO OVERENGINEERING** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: `bin/pre-commit-check.sh --plugin cms --full` GREEN.

---

## 1. Goal

Standards-compliant RSS for the blog and per-term archives, built from the **same post query** as the lists (DRY). Optional — ship if syndication is wanted. (Feeds are server-rendered XML → fully crawler/reader-friendly, no SPA involvement.)

## 2. Backend — `vbwd-plugin-cms`

- **Route:** `GET /api/v1/cms/rss.xml` (whole blog) + filters `?type=&term_type=&term_slug=`. `Content-Type: application/rss+xml; charset=utf-8`.
- **`RssFeedService.build(*, type='post', term=None) -> str`** — RSS 2.0 (channel: title, link, description, `lastBuildDate`, `language`; items: `title`, absolute `link`, `guid` permalink `isPermaLink=true`, `pubDate` RFC-822 from `published_at`, `description` excerpt/sanitized summary, optional `category`). Reuses the 47.0/47.4 **post-query service** (published only, newest first, capped — config `rss_item_limit`, default 20). Build XML with a real serializer (`xml.etree`/`feedgen`), **escaping** all content — **no string concatenation**.
- Absolute URLs from the configured public base URL (same config key S47.1 uses for canonical).
- (Optional) `?format=atom` behind a flag; default RSS 2.0 only (NO OVERENGINEERING).

## 3. fe-user — autodiscovery

On blog/term pages emit `<link rel="alternate" type="application/rss+xml" title="…" href="/api/v1/cms/rss.xml?…">` (via the 47.1 head path / the page head injection). The term widget (47.3) may show an RSS icon linking the current term's feed.

## 4. TDD (RED first)
- `RssFeedService`: valid RSS 2.0 (parses + validates against the spec in test); published-only, newest-first, capped; per-term filter; absolute links; correct RFC-822 `pubDate`; XML escaping of special chars.
- Route: correct content-type; unknown term → empty but valid channel (not 500).
- fe-user: autodiscovery `<link>` present on blog/term pages with the right href.

## 5. Acceptance
- `GET /cms/rss.xml` and `?type=post&term_type=category&term_slug=news` return valid RSS 2.0 (passes a feed validator) with the latest published posts.
- A reader subscribed to a category URL receives new posts in that category; browsers autodiscover the feed.
- `--plugin cms --full` GREEN.

## 6. Out of scope
WebSub/PubSubHubbub, full-content vs excerpt toggle beyond a config flag, podcast/media RSS, per-author feeds (trivial follow-on via the same service).

## 7. Engineering-requirements check
- **DRY:** feeds reuse the post-query service; no duplicate "fetch published posts" logic.
- **Core agnostic:** entirely in cms; uses the shared public-base-URL config.
- **NO OVERENGINEERING:** RSS 2.0 only by default; one serializer, escaped.
