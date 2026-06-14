# Report 04 — S65 demo-data import: sprint verification, local walkthrough, and production import (hotel + doctor)

**Date:** 2026-06-11
**Author:** Claude (orchestrator) + Playwright UI automation
**Scope:** Verify which of S61–S65 / S68–S69 are actually done; then execute S65 phase 1–2 (author import envelopes, import the booking catalogue through the unified Import/Export **UI**) on local and on **production** (hotel.vbwd.cc, doctor.vbwd.cc), with a screenshot at every step.
**Engineering requirements honoured:** read-only verification first; non-destructive **upsert** imports (no deletions); production preconditions checked before any write; secrets handled via a `umask 077` temp file and deleted afterwards. Nothing committed ([[feedback_no_commit_without_ask]]).

---

## 1. Sprint completion audit (S61–S65, S68–S69)

Verified against code on disk + test execution, not doc claims.

| Sprint | Subject | Status | Evidence |
|--------|---------|--------|----------|
| **S61** | Booking unified import/export | ✅ **DONE** | `booking_exchangers.py` registers `booking_categories` + `booking_resources` with import-side slug resolution; tests green |
| **S62** | Subscription unified import/export | ✅ **DONE** | NEW `subscription_categories` + `_M2MSlugExchanger` for plans (`category_slugs`) and addons (`tarif_plan_slugs`); tests green |
| **S63** | GHRM slug-portable plan link | ✅ **DONE** | `_GhrmPackageExchanger` drops raw `tariff_plan_id`, round-trips `tariff_plan_slug`; tests green |
| **S64** | Shop unified import/export | ✅ **DONE** | NEW `shop_product_categories` + products carry category slug + nested variants/images; tests green |
| **S65** | Prod demo-data import + checkout proof | 🟡 **IN PROGRESS** (this report) | Phase 1–2 (envelopes + UI import) done for hotel & doctor on local **and prod**; checkout proof still pending |
| **S68** | CMS widget bugs (menu export + delete) | ❌ **NOT DONE** | Bug A 0% (`cms_widgets` still a plain exchanger, no `menu_items`); Bug B ~⅓ (layout-only guard, no 3-table `widget_usage`, no `?force`, no IntegrityError backstop) |
| **S69** | Plan/add-on driven user permissions | ❌ **NOT DONE** | No `user_permission_grant.py`, no `permission_sync_service.py`, no addon events, D5 emit gaps open, no tests |

The four exchanger test suites were run together as the proof for S61–S64:

```
plugins/booking/tests/integration/test_booking_catalog_exchangers.py
plugins/subscription/tests/integration/test_subscription_exchanger_links.py
plugins/ghrm/tests/integration/test_ghrm_packages_portable.py
plugins/shop/tests/unit/test_shop_catalog_exchangers.py
→ 40 passed in 24.7s
```

---

## 2. Import envelopes authored

Unified-format JSON (one file per `entity_key`), committed under `docs/marketing/cms-imports/<vertical>/booking/`:

| Vertical | `booking_categories.json` | `booking_resources.json` |
|----------|---------------------------|--------------------------|
| **hotel** | 5 hotels as categories (`grand-marina`, `alpine-lodge`, `seaside-resort`, `city-center`, `lakeview-retreat`) | 15 resources — rooms (`per_night`), SPA (`per_slot`), business (`per_day`), each linked via `category_slugs`, with availability/pricing/capacity |
| **doctor** | 12 nosologies (cardiology, urology, …, oncology) | 28 clinics as resources (`per_slot` consultation pricing), 2–3 per nosology, each with a symptoms/insurance `custom_fields_schema` |

Envelope contract (learned from a live export): top-level `{<entity_key>: [...], vbwd_export, format, instance, version, exported_at}`. Category rows carry `parent_slug` (export-only via base, resolved on import by the thin subclass); resource rows carry `category_slugs` (resolved on import).

---

## 3. Local walkthrough (proof of mechanism)

Drove the local fe-admin (`localhost:8081`) Import/Export UI with Playwright (host node + cached chromium, since the alpine dev container has no browsers). 12-step screenshot walkthrough:

login → dashboard → Import/Export → **categories** (file → dry-run `created 5` → confirm) → **resources** (file → dry-run `created 15, errors 0` → confirm) → **idempotent re-import** (`created 0, updated 15`) → dashboard counts (24 Resources / 9 Categories) → Resource List showing each hotel resource with its category.

**Report:** `docs/dev_log/20260611/walkthrough/s65-import-walkthrough.html` (12 shots, embedded).

Key behaviours proven: dry-run is non-writing; import is idempotent (upsert by slug, no duplicates); `category_slugs` resolves on import; **import order matters** — resources must follow committed categories, else per-row `unknown category_slug` errors (skip-with-error, never crash).

---

## 4. Production import (hotel + doctor)

**Preconditions checked (read-only) before any write:**
- Both prod instances reachable: `https://hotel.vbwd.cc` and `https://doctor.vbwd.cc` (`/api/v1/health` → 200).
- Admin login works with the supplied credentials on both.
- **Manifest confirmed to expose `booking_categories` + `booking_resources` on both** — i.e. the S61 exchanger code is genuinely deployed to prod. (Had it been absent, the import would have been aborted, since deploying the backend image is the CI-blocked manual step — see [[feedback_deploy_github_only]].)

**Execution:** parameterized Playwright script drove each production admin UI (`/admin/login` → Import/Export): upload categories (Preview → Confirm), upload resources (Preview → Confirm), verify in the Resource List. **Upsert mode — no deletions.**

| Instance | Categories created | Resources created | Errors | Verified live (`/api/v1/booking/resources`) |
|----------|--------------------|--------------------|--------|----------------------------------------------|
| **hotel.vbwd.cc** | 5 | 15 | 0 | 15 imported hotel resources (21 total) |
| **doctor.vbwd.cc** | 12 | 28 | 0 | 28 imported clinics (34 total) |

**Report:** `docs/dev_log/20260611/walkthrough/s65-prod-import-report.html` (20 shots across both instances, embedded). Raw shots in `s65-prod-hotel/` and `s65-prod-doctor/`.

---

## 5. Findings & incidents

1. **Backend crash during local run (transient, pre-existing).** The local api container exited with `NameError: DeviceTokenRepository` at `vbwd/container.py:84`. Root cause: gunicorn auto-reloaded mid-edit while `vbwd/container.py` (uncommitted working-tree change, ` M`) had the line-86 usage saved but not yet the line-11 import. The on-disk file is now consistent; `docker compose up -d api` restarted clean. **Not caused by the import; worth a heads-up that the working tree had a momentarily-inconsistent core file.**

2. **Idempotency screenshot read-race (fixed).** The first local run captured a stale results table for the re-import step (showed `created 15` instead of `updated 15`). Re-captured by waiting on the actual `/import` network response — now correctly shows `created 0, updated 15`. API cross-check confirmed the true behaviour.

3. **Public `/booking` is a CMS page.** The fe-user public catalogue route renders a CMS page (slug `booking`) that isn't configured on the dev instance → blank. Verification therefore uses the admin Resource List + the public `/api/v1/booking/resources` endpoint, which is authoritative for the data import. (Configuring the public storefront CMS page is separate content, out of scope here.)

4. **Auth guard vs hard reload.** fe-admin's router guard reads `admin_token`/`admin_token_user` from localStorage at boot; a full page `goto` races the guard and bounces to `/login`. Resolved by navigating via **SPA sidebar clicks** (also more authentic for a walkthrough). The Bookings submenu requires clicking its toggle caret (`[data-testid="nav-toggle-bookings"]`) before the Resources child link is visible.

---

## 6. Deliverables

```
docs/marketing/cms-imports/hotel/booking/{booking_categories,booking_resources}.json
docs/marketing/cms-imports/doctor/booking/{booking_categories,booking_resources}.json
docs/dev_log/20260611/walkthrough/s65-import-walkthrough.html        # local, 12 steps
docs/dev_log/20260611/walkthrough/s65-prod-import-report.html         # prod, 20 steps
docs/dev_log/20260611/walkthrough/s65-shots/                          # local raw shots + steps.json
docs/dev_log/20260611/walkthrough/s65-prod-hotel/                     # prod hotel raw shots + steps.json
docs/dev_log/20260611/walkthrough/s65-prod-doctor/                    # prod doctor raw shots + steps.json
vbwd-fe-admin/s65-*.cjs                                               # Playwright drivers (untracked, kept for reproducibility)
```

---

## 7. Security note

Production admin credentials were used only to authenticate, stored in a `umask 077` temp file (never echoed), and the temp file plus all tokens/manifests were deleted at the end of the run. The password was typed into the chat, so it exists in this conversation transcript — **rotating that prod admin login is advisable.**

---

## 8. Remaining work

- **S65 checkout proof** (the rest of the sprint): Stripe test card + token payment, with and without a coupon, on the demo instances, with an HTML walkthrough — not yet done.
- **Optional cleanup:** the S65 spec calls for *replacing* the generic demo (Dr. Smith / Yoga Studio, etc.). Imports were additive (upsert); the old generic resources remain on prod. Deletion is deferred pending explicit instruction.
- **Other verticals:** shop (`shop_product_categories` + `shop_products`) not imported.
- **Unrelated:** S68 and S69 remain unimplemented (see §1).
