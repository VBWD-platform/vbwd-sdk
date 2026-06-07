# Daily report — 2026-06-07

**Author:** Claude (assistant), driven by daniil.tkachev
**Scope:** sprint planning (S41/S45/S53/S54), S54 implementation + two follow-up fixes, prod demo-data seeding across all `*.vbwd.cc` instances, a CI-deploy failure diagnosis, a CMS page/post alignment fix rolled to all styles on local **and** prod, and a GHRM disconnect 500 fix patched to prod.

> **Commit status:** nothing was committed or pushed (per standing rule). Backend plugin code lives on disk (gitignored in `vbwd-backend`). Data/runtime changes were applied directly to the local + prod databases / containers as noted.

---

## 1. Sprint planning / docs

### S41 — CMS AI Helper (rewritten)
`docs/dev_log/20260530/sprints/s41-cms-ai-helper.md` was a thin "dummy button" scaffold; rewrote it into a real feature spec after negotiation:
- An **`AI ✨` drop-down** (Write-article / Re-generate-SEO / Restyle) + a **collapsible prompt panel** (3-row textarea, "Read excerpt" checkbox) on the unified `PostEditor.vue` (covers both pages and posts; `CmsPageEditor.vue` is retired).
- **Backend-proxied** LLM (key server-side), **OpenAI + Anthropic** compatible, **JSON-mode structured I/O** validated against a fixed CMS-field schema (incl. `content_html`, `source_css`, SEO fields).
- **Phased:** P1 text-only, P2 image/PDF upload (incl. "style like this image" → `source_css`).
- **loopai relationship decided:** adopt loopai's **YAML request-template format** + port its dual-protocol + JSON-repair core; do **not** embed the engine (it's a partial vendor of a standalone Flask app — won't import; session/DB/filesystem coupling). Templates ship in the plugin, admin-overridable in `VAR_DIR`.

### S45 — telegram-connect (status reconciled) + S53 created
- Locked D6/D7/D8; **carved the D8 subscription storefront** (commands + checkout-draft + fe-user `?draft=` hydration) out into a **new sprint `s53-bot-commerce-storefront.md`** (depends on the S45 bridge). Updated S45 status/consumers/security/sub-sprints to point at S53.

### S54 — CMS bulk-assign layout + default fallback (elaborated)
Turned a 4-line stub into a full sprint doc, grounded in the code — keyed on the insight that the CMS already does "explicit-else-default" for **styles**, so layouts just needed the same shape.

---

## 2. S54 implementation + two follow-up fixes (vbwd-backend `plugins/cms`, fe-admin, fe-user)

**Delivered (TDD via the `vbwd-tdd` agent, gate-green):**
- **Bulk "Assign layout"** — `PostService.bulk_assign_layout` + `POST /admin/cms/posts/bulk/assign-layout` (mirrors `assign-term`) + a layout picker in `CmsContentList.vue` bulk bar + store method + i18n.
- **Default-layout render fallback** — `_with_resolved_layout` mirroring `_with_resolved_style`; applied only on the public payload (editor keeps the raw value).

**Follow-up fix A — 500 regression (mine):** the first default mechanism read `default_layout_id` from plugin config; an operator set it to a **slug** (`content-page`), my code passed it to a UUID `find_by_id` → `DataError` → **500 on every layout-less published page** (`/open-source`). Fixed: slug-or-id resolution, exception-safe (bad value degrades to "none", never 500). Verified live (200, resolved to the content-page layout).

**Follow-up fix B — rework to the styles pattern:** per request, replaced the config-field approach with the **`is_default` flag pattern** used by styles — `CmsLayout.is_default` + migration (partial-unique index) + `find_default()` + `set_default`/`clear_default` + `POST/DELETE …/layouts/<id>/default` + a "Make default" button on `CmsLayoutList.vue`. Removed `default_layout_id` from config entirely. Gate green (124 integration + unit); migration applied to dev DB; the new endpoint verified live (content-page set as default; single-default invariant holds).

---

## 3. Prod demo-data seeding — all `*.vbwd.cc` instances

SSH'd `root@147.93.121.176` (Hostinger `srv701694`) and ran the per-plugin `populate_db` seeders inside each live `api` container (the `deploy.sh --seed` mechanism, minus a redeploy) across **main, shop, hotel, doctor, ghrm, saas**.

**Found + fixed two pre-existing seeder defects** (they also break the official `--seed`):
- `token_payment/populate_db.py` crashed (no Flask app context).
- `subscription`/`shop`/`discount`/`checkout` `populate_db.py` were **no-ops** (defined `populate()` but had no `__main__` entrypoint).

**Immediate:** re-ran the affected plugins via an app-context wrapper so the data landed on all instances now. **Durable:** added proper `if __name__ == "__main__": create_app().app_context()` entrypoints to all 5 (via `vbwd-tdd`, gate-green on each `--plugin`); verified via the exact deploy invocation (25 plans / 43 products / 6 coupons / token-balance method, etc.).

---

## 4. CI deploy failure (vbwd-demo-instances) — diagnosis

Run `27087876454` failed at **Deploy → Configure SSH**: `ssh-keyscan $VPS_HOST` timed out on all 5 retries → hard `exit 1`. Diagnosed:
- **Intermittent** (the four preceding deploys succeeded); VPS port 22 globally open; fail2ban had no GitHub IP banned; no foreign SYN reached sshd at keyscan time → a transient runner→VPS reachability blip turned into a hard failure by the strict keyscan guard.
- **Recommendations:** re-run the job (fresh runner IP); durably, **pin the VPS host keys** into `known_hosts` instead of live keyscanning. Flagged a latent risk: `recidive` bantime = **10 days** + recycled GitHub runner IPs.

---

## 5. CMS page/post alignment — header nav + breadcrumb + content on one line

**Problem:** on the `content-page` layout the content sat inset/narrow (194 vs the breadcrumb line at 170) and the header nav's first item was offset; **posts** on older/custom styles (e.g. `VBWD Core — Exhibition`) were misaligned differently.

**Diagnosis (empirical, via Playwright measurement):** alignment is governed by an **`--edge-inset` design system** inside each **style's `source_css`** (generated by `plugins/cms/docs/imports/_build_theme_styles.py`). Two gaps: the content area (`.cms-area--content .container`) wasn't in the edge-inset selector list, and the header nav's first link kept its padding. Also **11 of 38 styles lacked the system entirely**.

**Fix (data, not code — so prod is a data-only reseed, no fe-user deploy):**
- `services/style_edge_align.py` — canonical, marker-delimited `VBWD_EDGE_ALIGN:v1` block + idempotent `apply_edge_align()` (uses `var(--edge-inset)` with no fallback so styles lacking the token compute flush-left, while narrow/1200/fullwidth keep their value).
- `bin/apply_style_alignment.py` — standalone updater (app-context entrypoint, persists via `CmsStyleService`, no raw SQL).
- Baked into `populate_cms.py` + the builder (future styles born aligned). **14 backend tests pass.**

**Applied:** all **38 local styles** (idempotent: 38 updated → 0/38 on re-run), and **all 6 prod instances** (main 38, shop 37, hotel 39, doctor 37, ghrm 37, saas 27). Verified fresh-load alignment on `home`/`shop`/`ghrm`/the post (post now 120, others 170) locally and on `vbwd.cc/open-source` + `ghrm.vbwd.cc` in prod. **55 page screenshots + the post** saved to `var/screenshots/20260607/`.
- *Note surfaced:* the fe-user caches injected style CSS, so an open tab shows stale alignment until a hard refresh.

---

## 6. GHRM "Disconnect GitHub" 500 — fixed + patched to prod

**Root cause:** `disconnect_github` → `_tear_down_membership` → `remove_collaborator` → GitHub **403 "Resource not accessible by integration"** (the App lacks collaborator-management permission) → unhandled → **500**, aborting the whole disconnect.

**Fix:** made teardown **best-effort** — catch `GithubAppClientError`, log a warning, continue — mirroring the add path. Local disconnect now always completes (memberships + access record deleted). Added a symmetric `raise_on_remove_collaborator` mock flag + a regression test. **48 ghrm tests pass**; local API restarted clean.

**Prod stopgap:** applied a **targeted** in-place patch of `_tear_down_membership` to `vbwd-ghrm-api` (verified prod file matched the "before"; syntax-checked before write; restarted healthy; `ghrm.vbwd.cc` → 200). **Ephemeral — lost on the next ghrm deploy.**

**GitHub App permission note:** to make disconnect actually revoke repo access, grant the App **Administration: Read & write** (collaborator endpoints require it) and have each installation **accept the updated permission**. Open question flagged: add-collaborator works but remove 403s — check whether add uses the user OAuth token vs the App installation token for remove.

---

## Open follow-ups
- Commit + deploy the durable code: S54 layout default, the 5 seeder entrypoints, the CMS edge-align module/builder/populate, and the GHRM teardown fix (all currently on-disk only; prod ghrm + prod styles carry runtime/data changes that a redeploy/reseed must preserve).
- Optionally patch `saas` (also runs ghrm) for the disconnect 500.
- CI deploy: re-run + consider host-key pinning.
- CMS crawl: 3 pages timed out on load (`about/contact`, `about/privacy`, `blog/pricing-embedded`) — worth a load-speed check (unrelated to alignment).
