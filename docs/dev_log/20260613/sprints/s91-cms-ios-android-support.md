# S91 — CMS on mobile: a config-driven "Posts" browser for iOS (Android contract-ready)

**Status:** PLANNED — 2026-06-14
**Repos:** `vbwd-ios` (new plugin `vbwd-ios-plugin-cms` + two `vbwd_config.json` keys) · `vbwd-backend/plugins/cms` + `vbwd-fe-user/plugins/cms` (a chrome-light embedded archive render the WebView loads) · `docs/` (the platform-neutral contract + walkthrough). **No core change** (CMS is a plugin; the iOS CMS screen is a plugin).
**Track:** mobile feature. Brings the existing web CMS to the mobile app **without re-implementing CMS rendering natively**.

**The ask (verbatim intent):** the mobile app gets a burger-menu item **"Posts"** whose content is, **by default, a browser**. Which content it browses is configured on the device in `vbwd_config.json`:
```jsonc
{
  "root_ios_category_on_host":  "<category_slug>",        // which CMS category to browse
  "root_ios_post_type_on_host": "<post|page|video|pdf|…>" // which post type within it
}
```
i.e. the device points at a **category × post-type** on the backend **host**, and the Posts screen browses it.

---

## 0. Audit — what exists today (verified 2026-06-14)

**Mobile apps.** **iOS only** — `vbwd-ios/VBWD/` (Swift/SwiftUI, plugin-extensible). **There is no Android app in the repo** (confirmed). So this sprint ships **iOS now** and a **platform-neutral contract** that makes Android a thin future port (see §6, Decision D-Android). The file name keeps "android" to anchor that contract.

**iOS config.** `vbwd-ios/.../VBWDCore/VBWDConfig.swift` — a `Codable` struct with snake_case `CodingKeys`, loaded by `VBWDConfig.load()` and consumed in `SDKContainer.init()`. Today it holds `api_base_url` and `tarif_plan_root_cat_slug` (**precedent: a category-slug already drives a screen via config**). Adding two keys is the established pattern.

**iOS burger menu.** `VBWDCore/Plugins/SideMenu.swift` is **data-driven** — plugins contribute `MenuItem`s (`AppShellMenuItem.swift`: `icon`, `title`, `routePath`, `requiredPermission`, `order`, `section`) via `sdk.menuItems`; a plugin registers a route + menu item in its `install()` (template: `vbwd-ios-plugin-example`). **No WebView (`WKWebView`) exists anywhere yet**, and **no CMS API is wired**.

**iOS networking.** `VBWDCore/Networking/APIClient.swift` — `sdk.api.get/post/...`, base URL from config, auto-adds `X-Client-Platform: ios`. Plugins use `sdk.api` (DIP; `boundary-lint.sh` forbids raw `URLSession`).

**CMS backend — already has everything needed** (`vbwd-backend/plugins/cms/src/routes.py`):
- `GET /api/v1/cms/posts?type=&term_type=category&term_slug=<slug>&page=&per_page=` → paginated archive `{items, total, page, per_page, pages}` (each item: `type, slug, title, excerpt, content_html, featured_image_url, published_at, …`). (`routes.py:2213`, service `list_posts_by_term` → `find_by_term_slug`.)
- `GET /api/v1/cms/posts/<path:slug>?type=` → single post, enriched with `terms[]`, `content_blocks`, resolved layout/style. (`routes.py:2242`.)
- `GET /api/v1/cms/terms?type=category` → category list (slug-keyed, hierarchical via `parent_id`). (`routes.py:2267`.)
- **Post types are a registry** — `register_post_type(PostType(key,label,routable,hierarchical,default_template))` (`post_type_registry.py`); built-ins `page`/`post`; **custom types (`video` per S82, `pdf`) register with zero cms-core change.**

**CMS web — renders every post type already** (`vbwd-fe-user/plugins/cms`): `registerCmsPageType(slug, component)` + `CmsPage.vue` dispatcher → `CmsPageTypePage/Post/Video/…`; `PostTermList`/`PostList`/`PostCard` render a category archive; `CmsPageIndex.vue` is a category-filtered index. **This is the load-bearing fact:** the web already knows how to render `post`, `page`, `video`, `pdf` and any registered type, with layouts/styles/widgets. A native re-implementation would duplicate all of it.

> **Design consequence (NO OVERENGINEERING):** the Posts screen is a **WebView (browser) over a chrome-light host render** of the configured archive. One renderer (web) ⇒ every post type "just works" on mobile, including `video`/`pdf`/future custom types, with **no per-type native code**. This is exactly what "by default is a browser" buys us. Native rendering is a documented later option behind the same config (§5, Decision D-Native).

---

## 1. Goal

A device-configured **"Posts"** burger entry that opens a browser onto the backend's CMS, scoped to one **category × post-type**, themed like the web site, supporting **all** registered post types (incl. `video`/`pdf`), with auth-aware access (private/access-gated posts render for the logged-in user), **and no new CMS rendering code per platform.**

---

## 2. Architecture (one renderer, config-driven, platform-neutral)

```
vbwd_config.json (device)                 backend host (CMS plugin)
  root_ios_category_on_host  ─┐
  root_ios_post_type_on_host ─┤            GET /cms/embed/<type>/<category>   (chrome-light archive)
                              │   WebView   GET /cms/embed/<type>/post/<slug>  (chrome-light detail)
  api_base_url ──────────────┴──────────▶  (reuses registerCmsPageType → video/pdf/custom render)
                                  ▲
                          JWT seeded into the WebView (logged-in access levels honoured)
```

Three pieces, each independently gate-green:
1. **Contract (platform-neutral, §3):** the two config keys + a stable, embeddable **archive URL** the WebView loads, + a validation affordance so a mis-typed slug fails loudly not blankly.
2. **Web chrome-light embed render (cms plugin, §Slice 1):** an `embed` mode of the existing CMS render — **no global nav/burger/footer**, mobile viewport, deep-links that stay in embed mode — reusing `PostTermList`/`PostList` (archive) and `registerCmsPageType` (detail). Because it reuses the page-type registry, `video`/`pdf`/custom types render with zero extra work.
3. **iOS plugin (§Slice 2):** reads config, adds the "Posts" menu item + route, hosts a `WKWebView` pointed at the archive URL, forwards the auth token, and gives native affordances (pull-to-refresh, back, error/offline).

---

## 3. The platform-neutral contract (§deliverable)

**Config keys** (device-local; iOS now, Android later — same shape):

| key | meaning | example |
|---|---|---|
| `root_ios_category_on_host` | category **slug** on the host to browse | `"news"` |
| `root_ios_post_type_on_host` | registered post-type **key** to list within it | `"post"` / `"video"` / `"pdf"` |
| `root_android_category_on_host` | (Android, deferred) same | `"news"` |
| `root_android_post_type_on_host` | (Android, deferred) same | `"post"` |

- **iOS:** add `rootCategoryOnHost` / `rootPostTypeOnHost` to `VBWDConfig.swift` with the snake_case `CodingKeys` above (mirroring `tarif_plan_root_cat_slug`). Both **optional** — if either is missing, the Posts menu item is **not shown** (Liskov: absence is a clean no-op, not a crash). A `.dist` template documents them.
- **Archive URL** the WebView loads (host-rendered, chrome-light): `"<web_origin>/cms/embed/<post_type>/<category_slug>"` (web origin derived from `api_base_url` by stripping `/api/v1`). Post taps navigate **within** the WebView to `…/cms/embed/<post_type>/post/<slug>` (still chrome-light).
- **Validation affordance (fail-loud):** `GET /api/v1/cms/embed-manifest?type=<t>&category=<c>` → `{ ok, type, category:{slug,name}, post_count, archive_url }` or `404 {error}` if the type isn't registered / category slug doesn't exist. The app calls it once on entry so a mis-configured device shows a clear "category not found / type not registered" state instead of a blank browser. Cheap, reuses `terms` + the post-type registry + `list_posts_by_term` count.

---

## 4. What we are NOT doing to existing code

- **No new public list/detail API** — `/cms/posts`, `/cms/posts/<slug>`, `/cms/terms` already cover browsing. We add only the **embed render** (presentation) + the **manifest** (validation) — both in the **cms plugin**, not core.
- **No native CMS renderer** — the WebView reuses the web render; `video`/`pdf`/custom types are free.
- **No core change** — agnosticism/vocabulary oracles stay green.

---

## 5. Slices

Ordered so each lands independently; the web slice unblocks the iOS slice.

### Slice 0 — Contract + config keys (iOS + docs)
- Add `rootCategoryOnHost`/`rootPostTypeOnHost` to `VBWDConfig.swift` (+ `CodingKeys`), the `.dist` template, and a derived `webOrigin`/`archiveURL` helper. **No UI yet.**
- Write the platform-neutral contract doc (§3) — the single source for both platforms.
- **TDD (XCTest):** decoding a config with both keys populates the fields; missing keys → `nil`; `archiveURL(for:)` builds the right URL from `api_base_url` + the two keys; a config with `api_base_url` only still loads (back-compat).

### Slice 1 — Chrome-light embedded archive render (backend cms + fe-user cms)
- **Backend:** `GET /api/v1/cms/embed-manifest` (validation, §3) — `--plugin cms --full` test: valid type+category → `ok` + count; unregistered type → 404; unknown category slug → 404.
- **fe-user cms plugin:** an **`embed` mode** of the CMS render:
  - Route `/cms/embed/:type/:category` → renders the category archive (reuse `PostTermList`/`PostList`/`PostCard` with `type`+`term_slug=category`), **chrome-light**: no global nav/burger/footer, `<meta viewport>` mobile, the site's resolved CMS **style** still applied (so it looks on-brand). Pagination kept (infinite-scroll or pager).
  - Route `/cms/embed/:type/post/:slug` → renders the single post via the **existing** `registerCmsPageType` dispatcher (so `video`/`pdf`/custom render natively-on-web), chrome-light; post cards in the archive link here, staying in embed mode.
  - Embed mode is a thin layout flag (e.g. a query/route guard that sets a `embed` layout), **reusing** all existing render components — DRY, no fork of the renderer.
- **TDD (Vitest + 1 e2e):** the archive route lists posts of the configured type in the category and hides global chrome; a `video`-type post opens in the registered video component under embed; pagination works; an unknown category renders the not-found state (consistent with the manifest 404).

### Slice 2 — iOS `vbwd-ios-plugin-cms` (the "Posts" browser)
New plugin from the `vbwd-ios-plugin-example` template:
- `install(sdk)`: if both config keys are present, `sdk.addRoute("/posts", …)` + `sdk.addMenuItem(MenuItem(title:"Posts", icon:"doc.text", routePath:"/posts", section:"top", order:…))`. Absent keys ⇒ no menu item (Slice 0 contract).
- **`PostsBrowserView`** — a SwiftUI `UIViewRepresentable` wrapping `WKWebView`:
  - On appear: call `embed-manifest` via `sdk.api`; on `ok` load `archive_url`; on 404 show a clear "Posts not configured / category not found" native state (not a blank page).
  - **Auth forwarding:** seed the user's JWT into the WebView before load via a `WKUserScript` that sets the web app's expected `localStorage` keys (`token` + `isAuthenticated` + `user`) — same keys the web app reads ([[project_fe_admin_e2e_auth_harness]]) — so private/access-level-gated posts render for the logged-in user; logged-out ⇒ only public posts (the web already filters `page_assignments`/private by access level).
  - Native affordances: pull-to-refresh, a back control for in-WebView navigation, an external-link policy (open off-host links in Safari, keep host links in the WebView), and an error/offline state.
- Wire `CMSPlugin()` into `VBWDApp.swift` + `plugins.json`; keep raw `URLSession` out (`boundary-lint.sh`); `X-Client-Platform: ios` already set.
- **TDD (XCTest):** menu item registered iff both keys present; the view loads `archiveURL` when the manifest is `ok`; manifest 404 → the error state, no load; the auth bootstrap script contains the token when authenticated and not when logged out. (WebView content itself is covered by Slice 1's web tests — we don't re-test rendering natively.)

### Slice 3 — Android (deferred, contract-ready)
- **No Android app exists.** This slice is **specification only** this sprint (Decision D-Android, §6): the same two `root_android_*` keys + the same `/cms/embed/...` archive URL + the same manifest endpoint mean an Android port is a **thin WebView screen reusing the web render** — **zero backend/web change**. Interim, Android users reach the same content via the responsive web site.
- Deliverable: an "Android port checklist" section in the contract doc (the keys, the URL, the auth-seed requirement, the menu-entry shape) so the port is a known, additive task.

### Slice 4 — Verification + walkthrough
- iOS simulator screenshots of the **Posts** screen browsing a `post`-type category **and** a `video`-type category (proving custom-type support comes for free), plus the not-configured/404 state.
- Demonstrate **config-driven switching**: change `root_ios_post_type_on_host` from `post` → `video` (or the category slug) and show the Posts screen now browses the other set — the whole point of the device config.
- HTML walkthrough under `docs/dev_log/20260613/walkthrough/`.

---

## 6. Decisions to confirm (owner) + risks

**Decisions:**
- **D-Android — scope.** Recommend **defer the Android *app*** (none exists; building one is a separate, large sprint) and ship the **contract** so the port is additive. Alternative: greenlight a new `vbwd-android` app this sprint (much larger). **Recommend: defer + contract-ready.**
- **D-Native — render mode.** "By default a browser" ⇒ **WebView-first** (this sprint). A future **native** archive (native list via `/cms/posts`, native detail per type) is possible behind a `posts_render_mode: web|native` config flag, but it re-implements rendering per post type — **out of scope now**; flagged so the door stays open.
- **D-Embed origin.** Derive the web origin by stripping `/api/v1` from `api_base_url` (simplest, matches today's single-host deploys) vs a new explicit `web_base_url` key. **Recommend: derive**, add `web_base_url` only if a split-host instance needs it.
- **D-Auth.** Seed JWT into the WebView `localStorage` (recommended — reuses the web app's auth) vs forward a header/cookie. Confirm the web app reads token from `localStorage` for the embed routes too.

**Risks:**
- **WebView auth seeding fragility** — the web app must accept the seeded `localStorage` on first paint of the embed route (hard-reload can drop a token; [[project_fe_core_dist_vite_cache_staleness]] notes headless token-seed dies on hard reload). Mitigation: the embed route accepts a **one-time bootstrap** and verifies via a client-side nav, not a hard reload; tested in Slice 1's e2e.
- **Chrome-light leakage** — ensure the embed layout truly hides global nav/burger and isn't just CSS-hidden (a stray link could escape embed mode). Mitigation: an explicit `embed` layout + an in-WebView link policy in iOS that keeps host navigation inside the embed paths.
- **Custom-type availability** — `video`/`pdf` only render if their plugin (S82 video) is enabled on the host. The manifest's "type not registered" 404 makes this a **clear** failure, not a blank screen.
- **Private content + logged-out** — logged-out WebView shows only public posts (web already filters by access level); acceptable and tested.

---

## 7. Acceptance / Definition of Done
1. `bin/pre-commit-check.sh --plugin cms --full` green (manifest + embed routes); `vbwd-fe-user --full` (eslint + vue-tsc + vitest) green incl. the embed archive/detail tests + 1 e2e. **No core change** — oracles green.
2. iOS: `vbwd-ios` builds; `boundary-lint.sh` clean; the new plugin's XCTests green (menu-gating, archive-URL build, manifest-ok-loads / 404-error-state, auth-bootstrap token presence).
3. With `root_ios_category_on_host` + `root_ios_post_type_on_host` set, the **Posts** burger item appears and opens the host archive in a WebView; tapping a post opens its detail (incl. a `video`/`pdf` type) in embed chrome; pull-to-refresh + back work; a mis-configured device shows the clear not-found state.
4. Changing the two config keys demonstrably re-points the Posts screen (Slice 4 proof).
5. Logged-in users see access-gated posts; logged-out users see only public posts.
6. Deliverables: the **platform-neutral contract doc** (config keys + archive URL + manifest + Android port checklist) and the HTML walkthrough with simulator screenshots.
7. Completion report `docs/dev_log/20260613/reports/NN-s91-cms-mobile.md` with as-built deviations, the embed-route + manifest design, the iOS plugin structure, and the explicit Android-deferred decision.

## 8. Cross-references
- CMS page-type registry seam — [[project_cms_page_type_registry_seam]] (`registerCmsPageType`, `GET /cms/posts/<slug>` returns full `terms`) — the reason every post type renders on the WebView for free.
- CMS widgets/layout + import envelope — [[project_cms_global_widgets_and_import_envelope]] (the embed layout reuses CMS layout areas).
- [[project_fe_admin_e2e_auth_harness]] (the `token`+`isAuthenticated`+`user` localStorage contract the WebView seeds) · [[project_fe_core_dist_vite_cache_staleness]] (token-seed + hard-reload caveat) · [[feedback_plugins_always_in_own_repos]] (the iOS CMS plugin ships in its own `vbwd-ios-plugin-cms` repo) · [[feedback_plugin_baseline_config_files]].
- S82 video post type — [s82-video-hosting.md](s82-video-hosting.md) (the `video` custom type the Posts screen browses when configured).
