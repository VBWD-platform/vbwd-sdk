# S9 — fe-user CMS: instant local navigation via viewport link prefetch

**Status:** PLANNED — 2026-05-25
**Track:** independent FE/CMS work — **not** a Sprint-11 (subscription-extraction)
sub-sprint. Numbered `s9` only to avoid the reserved `S8` (permissions rename) in
this folder's README.
**Risk:** low–medium. **Repo:** `vbwd-fe-user` only (`plugins/cms/`). No backend,
no core, no migration.
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI ·
DRY · Liskov · clean code · **no overengineering** —
[`_engineering-requirements.md`](_engineering-requirements.md). Gate:
`npm run lint` + `npm run test` (vitest) + the cms e2e spec green before "done".

---

## 1. Goal (user value)

When a visitor is on a CMS page, clicking a **menu item** or an **in-text link**
that points to another page **in this CMS** should feel instant. We achieve that
by **prefetching** the target page (its JSON + layout + style CSS) **while the
link is visible in the viewport**, and serving the click from cache.

Scope is strictly **local CMS links** ("from this cms"): hrefs that resolve to
the CMS page route. External links and app routes (`/login`, `/dashboard`, …)
are left untouched.

**Agnostic & automatic — covers every source of links.** The mechanism is
agnostic to *where* a link comes from: it acts on **any** anchor the CMS renders,
both the **main content area** and **every widget** (header/menu, footer, hero,
CTA, and any current or future/plugin widget). It never special-cases a widget
type or an area name — a link is classified purely by its href (via the router),
so new widget kinds get prefetch + instant nav automatically with zero changes
(Open-Closed). One mechanism, attached once at the CMS layout root.

## 2. Current-state analysis (why a naive prefetch would do nothing)

Two grounded facts decide the design:

1. **Local CMS links are raw `<a href>` and trigger a FULL PAGE RELOAD.**
   - In-content links are emitted as raw HTML and shown via `v-html`
     (`plugins/cms/src/views/CmsPage.vue:141`, rendered at `:82`).
   - Menu links are `<a :href="itemHref(item)">`
     (`plugins/cms/src/components/CmsWidgetRenderer.vue:69,96`; `itemHref` `:254`).
   - Only the breadcrumb and the page index use `<router-link>`. So a click on a
     menu/content CMS link reloads `index.html`, re-parses the JS bundle, re-boots
     the app, **and** re-fetches the page — the slowest possible path.
   - **Consequence:** prefetching into a JS/Pinia cache is *wiped by the reload* —
     useless on its own. To deliver the goal we must also convert local CMS link
     clicks into **SPA navigation** (`router.push`). These two pieces are coupled.

2. **The store has no cache.** `useCmsStore.fetchPage(slug)`
   (`plugins/cms/src/stores/useCmsStore.ts:130-167`) clears state and refetches
   every time; `fetchLayout` (`:169`) and `fetchStyleCss` (`:178`) likewise. So
   even SPA navigation re-hits the network on every click unless we cache.

There is **no** existing prefetch / `IntersectionObserver` / `requestIdleCallback`
anywhere in `vbwd-fe-user` — clean slate.

## 3. Design

Two coupled deliverables, each a small single-purpose unit.

### A. SPA navigation for local CMS links (prerequisite)

`useCmsSpaLinks(containerRef)` — a delegated **click** listener on the **CMS
layout root** (the element that wraps every area: widgets **and** the main
content). For a plain left-click (no modifier/middle-click, `target` not
`_blank`) on an anchor whose href the `LinkResolver` classifies as **cms**, it
calls `preventDefault()` + `router.push(path)`. Everything else (external, app
route, `#hash`, modified click) falls through to native behaviour.

- One delegated listener covers **every** anchor the CMS renders — `v-html`
  main-content links **and** widget links (menu, footer, hero, CTA, …) — with no
  per-link wiring and no markup change to any widget (DRY + agnostic).

### B. Viewport prefetch of visible local CMS links

`useCmsLinkPrefetch(containerRef)` — observes anchors inside the **CMS layout
root** (so it sees links in **widgets** *and* in **main content**) with an
`IntersectionObserver`. When a **cms** link enters the viewport (with a small
`rootMargin` so it warms slightly before), it schedules `store.prefetchPage(slug)`
on idle — automatically, no per-widget hookup. Guards: dedupe via the cache, a small concurrency cap, and **skip on
Save-Data / slow connections** (`navigator.connection.saveData` /
`effectiveType` `2g`). Re-observes when the rendered content changes (watch
`currentPage`).

### C. Store cache (single source of truth)

Add three `Map`s to `useCmsStore` keyed by id/slug:
`pageCache: Map<slug, CmsPageData>`, `layoutCache: Map<id, layout>`,
`styleCssCache: Map<id, string>`.

- `prefetchPage(slug)` — if cached, return; else GET the page (+ layout + style
  css) and populate the caches. Failures are swallowed (prefetch is best-effort)
  and the slug is marked "non-cacheable" so we don't retry (e.g. 404 non-CMS,
  403 gated).
- `fetchPage(slug)` — **read the cache first**; on hit, hydrate
  `currentPage/currentLayout/currentStyleCss` synchronously (no spinner). On
  miss, the existing network path runs and **also** fills the cache.
- `fetchLayout`/`fetchStyleCss` consult their caches. DRY: one caching home.

### Link classification — `LinkResolver` (DI seam, SRP)

`classifyLink(href): { kind: 'cms' | 'app' | 'external' | 'hash', path?, slug? }`.
Source of truth = the **router**: `router.resolve(href)`; `kind: 'cms'` iff the
matched route name is `cms-page` (`plugins/cms/index.ts:31`). External =
different origin / `mailto:` / `tel:`; `hash` = same-path `#…`. Pure function of
(href, router) — trivially unit-testable, and the **single** place "is this a
local CMS link?" is decided (used by both A and B).

### SOLID / DI / Liskov

- **SRP:** resolver classifies; prefetch composable observes+schedules; spa-links
  composable intercepts+pushes; store caches+fetches. Four reasons to change,
  four units.
- **DI:** the composables accept their collaborators —
  `useCmsLinkPrefetch(containerRef, { resolve, prefetch, createObserver, scheduleIdle })`
  with prod defaults (router resolver, store action, real `IntersectionObserver`,
  `requestIdleCallback`). Tests inject fakes (a manual observer trigger, a
  synchronous idle, a spy prefetch).
- **Liskov:** the fakes and the no-op fallback (when `IntersectionObserver` is
  absent or Save-Data is on) honour the same contract — the page renders and
  navigates correctly with prefetch simply disabled.
- **DRY:** classification + cache each have exactly one home.

### No overengineering (explicitly out of scope)

- No Service Worker, no `<link rel="prefetch">`, no HTTP-cache tricks.
- No "prefetch the whole site" / link-graph crawl — only links **currently
  visible** in the viewport.
- No new global store/library; composables live in the cms plugin.
- No cross-tab cache, no persistence. In-memory, per session.
- No prefetch of app routes or external URLs.

## 4. TDD plan (write RED first)

Unit (vitest, `vue/tests/unit/plugins/` — mock `@/api` per the existing pattern):

- **`cms-link-resolver.spec.ts`**: `/about` & `/category/x` → `cms`; `/login`,
  `/dashboard` → `app`; `https://x.com`, `mailto:` → `external`; `#sec` → `hash`;
  query/preview_token preserved on the resolved path.
- **`cms-store-prefetch.spec.ts`**: `prefetchPage` populates pageCache (+layout
  +css) once; second call is a no-op (dedupe); a failed prefetch marks
  non-cacheable and doesn't throw; `fetchPage` on a cached slug sets
  `currentPage` **without** calling `api.get` (cache hit) and never flips
  `loading`.
- **`cms-link-prefetch.spec.ts`** (composable, fake observer + sync idle):
  entering viewport on a `cms` anchor calls `prefetch(slug)`; `app`/`external`/
  `hash` anchors never prefetch; Save-Data on → no observer created; disconnect
  on unmount.
- **`cms-spa-links.spec.ts`**: left-click on a `cms` anchor → `preventDefault`
  + `router.push(path)`; ctrl/meta/middle-click, `target=_blank`, external, and
  app links → native (no push, no preventDefault).

E2E (playwright, extend `vue/tests/e2e/cms-pages.spec.ts`): on a CMS page,
clicking a local menu/content link **does not full-reload** (assert a sentinel
set on `window` survives the click) and lands on the target; optionally assert
the target page's request fired *before* the click (prefetch) via
`page.on('request')`.

## 5. Implementation steps (after tests are red)

1. `src/utils/cmsLinkResolver.ts` — `classifyLink`.
2. `useCmsStore`: add the three caches + `prefetchPage`; make `fetchPage` /
   `fetchLayout` / `fetchStyleCss` cache-aware.
3. `src/composables/useCmsLinkPrefetch.ts` and `src/composables/useCmsSpaLinks.ts`.
4. Wire both composables at the **`CmsLayoutRenderer.vue` root** — the element
   that wraps *every* area — so widget links (menu/footer/hero/cta/plugin) **and**
   the main-content links are all covered by a single attachment. (Attaching only
   at `CmsPage.vue`'s content area would miss widget links.) Re-observe on
   `currentPage` change.
5. `npm run lint` + `npm run test` + the cms e2e.

## 6. Files

| Action | Path |
| --- | --- |
| new | `plugins/cms/src/utils/cmsLinkResolver.ts` |
| new | `plugins/cms/src/composables/useCmsLinkPrefetch.ts` |
| new | `plugins/cms/src/composables/useCmsSpaLinks.ts` |
| edit | `plugins/cms/src/stores/useCmsStore.ts` — caches + `prefetchPage` + cache-aware fetch |
| edit | `plugins/cms/src/components/CmsLayoutRenderer.vue` — wire composables at the layout root (covers all widget areas **and** main content) |
| new tests | `vue/tests/unit/plugins/cms-link-resolver.spec.ts`, `cms-store-prefetch.spec.ts`, `cms-link-prefetch.spec.ts`, `cms-spa-links.spec.ts` |
| edit test | `vue/tests/e2e/cms-pages.spec.ts` — no-reload + prefetch assertions |

## 7. Acceptance criteria

- Clicking a **local CMS** link does an **SPA** navigation (no full reload) and,
  when the link was visible beforehand, renders with **no network round-trip**
  (served from cache).
- Coverage is **agnostic to source**: local CMS links are prefetched and
  SPA-navigated **wherever they appear** — in any widget (menu, footer, hero,
  CTA, plugin widgets) **and** in main content — with no widget-specific code.
  An e2e/unit case asserts a widget (menu) link **and** a main-content link are
  both prefetched.
- External links, app routes (`/login`…), `#` anchors, and modified clicks behave
  exactly as today (native).
- Prefetch only targets visible local CMS links; disabled under Save-Data / `2g`;
  no-ops where `IntersectionObserver` is unavailable — page still works.
- lint + unit + cms e2e green.

## 8. Risks / edge cases

- **Gated pages (403):** prefetch swallows the error and marks non-cacheable; the
  real click still routes (and shows the access-denied state) — no regression.
- **Non-CMS slugs (404):** classifier already excludes app routes; a stray 404 is
  swallowed and not retried.
- **Cache staleness:** in-memory, per session; acceptable for marketing content.
  If needed later, add a short TTL — deferred (no speculative TTL now).
- **Memory:** cap prefetch concurrency and rely on visible-only scope; pages are
  small JSON. No unbounded crawl.
- **`preview_token` / query:** preserved by the resolver on the pushed path;
  prefetch keys include the token so drafts don't poison the public cache.
- **SSR / no `window`:** composables guard on `typeof window` and IO presence.
- **Re-render:** observe/disconnect tied to `currentPage` so anchors added by a
  new page get observed and old observers are cleaned up (no leak).
