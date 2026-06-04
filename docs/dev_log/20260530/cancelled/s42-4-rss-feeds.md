# S42.4 — RSS feeds (optional): per category / tag / term

**Parent:** [S42 — vbwd-press](s42-vbwd-press.md) · **Depends on:** [S42.0](s42-0-data-model-terms-crud.md) · **Status:** DRAFT (OPTIONAL) — 2026-05-29
**Repos:** `vbwd-plugin-press` (backend feed), `vbwd-fe-user-plugin-press` (autodiscovery `<link>`).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · clean code · **core agnostic** · **NO OVERENGINEERING** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: `bin/pre-commit-check.sh --plugin press --full` GREEN.

---

## 1. Goal

Standards-compliant RSS for the blog and per-term archives, built from the **same post query** as the lists (DRY). Optional sprint — ship if subscriptions/syndication are wanted.

## 2. Backend — `vbwd-plugin-press`

- **Route:** `GET /api/v1/press/rss.xml` (whole blog) + filters `?term_type=&term_slug=` (per category/tag/any term_type). Returns `Content-Type: application/rss+xml; charset=utf-8`.
- **`RssFeedService.build(term=None) -> str`** — RSS 2.0 (channel: title, link, description, `lastBuildDate`, `language`; items: `title`, `link` (absolute post URL), `guid` (permalink, `isPermaLink=true`), `pubDate` (RFC-822 from `published_at`), `description` (excerpt or sanitized summary), optional `category` per term). Reuses the 42.0/42.2 post-query service (published only, newest first, capped e.g. 20 — config `rss_item_limit`). Build XML with a real serializer (`xml.etree`/`feedgen`), **escaping** all content; no string concatenation.
- Absolute URLs from the configured public base URL (config key; same source S40 uses for canonical).
- (Optional) `Atom` variant behind `?format=atom` if asked — default RSS 2.0 only (NO OVERENGINEERING).

## 3. fe-user — autodiscovery

On blog/term pages, emit `<link rel="alternate" type="application/rss+xml" title="…" href="/api/v1/press/rss.xml?…">` so readers/browsers discover the feed (via the S40 head path / the page's head injection). The term widget (42.1) can optionally show an RSS icon linking the current term's feed.

## 4. TDD (RED first)
- `RssFeedService`: valid RSS 2.0 (parses + validates against the spec/W3C feed schema in test); items are published-only, newest-first, capped; per-term filter; absolute links; correct `pubDate` RFC-822; XML escaping of titles/descriptions with special chars.
- Route: correct content-type; unknown term → empty but valid channel (not 500).
- fe-user: autodiscovery `<link>` present on blog/term pages with the right href.

## 5. Acceptance
- `GET /press/rss.xml` and `?term_type=category&term_slug=news` return valid RSS 2.0 (passes a feed validator) with the latest published posts.
- A feed reader subscribed to a category URL receives new posts in that category.
- Browser/readers autodiscover the feed from the blog pages.
- `--plugin press --full` GREEN.

## 6. Out of scope
WebSub/PubSubHubbub push, full-content (vs excerpt) feeds toggle beyond a config flag, podcast/media RSS, per-author feeds (trivial follow-on via the same service).

## 7. Engineering-requirements check
- **DRY:** feeds reuse the post-query service; no duplicate "fetch published posts" logic.
- **Core agnostic:** entirely in the press plugin; depends only on press's own query layer + the shared public-base-URL config.
- **NO OVERENGINEERING:** RSS 2.0 only by default; Atom/WebSub deferred; one serializer, escaped.
