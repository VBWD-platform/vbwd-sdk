# S72.4 — Netto/brutto price display: global toggle + per-entity override + "netto price" tag

**Part of:** [S72 — Taxes & Countries (umbrella)](s72-taxes.md) · **Area:** **core** (settings) + plugins `subscription` / `shop` / `booking` (override field + pricing) + `vbwd-fe-admin` (toggles) + `vbwd-fe-user` (rendering) · **Depends on:** core settings store S57 (exists), S72.3 (pricing carries net + gross — soft dep).
**Engineering requirements:** TDD-first, SOLID/DI/DRY, no overengineering; core `--full` + `--plugin subscription|shop|booking --full` + fe Vitest/ESLint green. **Not committed.**

## Problem
The user-facing frontend has no notion of showing prices **netto** (net, excluding tax) vs **brutto** (gross, including tax). The platform computes both (`Price` net+gross, `Tax.calculate_gross`/`extract_net`) but there's no global switch and no per-item override.

## Locked decisions
- **D-global** — add `prices_display_mode` (`"brutto"` default | `"netto"`) to `DEFAULT_CORE_SETTINGS` in `vbwd/services/core_settings_store.py` (file-backed, **no migration**); surfaced via the existing `GET|PUT /api/v1/admin/settings` (known-key whitelist).
- **D-override** — add a nullable `price_display_mode VARCHAR(8)` to each of the 3 entity tables (per-plugin migration; `null` = inherit global; `"netto"`/`"brutto"` = override). In `to_dict()` + accepted on create/update; validated to the two enum values. (Chosen over JSON for queryability + a clear validated column.)
- **D-tag** — **effective mode** per entity = `override ?? global`. When effective is `netto` **and** the global is `brutto` (the item differs), the price component renders a localized **"netto price"** tag. Pricing responses already carry net + gross (S72.3), so the FE just picks the number + whether to tag.

## Scope
- **core:** whitelist `prices_display_mode`; settings route round-trips it (no new endpoint).
- **fe-admin:** a switch on the Taxes&Countries Taxes tab (or core settings) bound to `prices_display_mode`; a per-entity **"Price display"** select (`Inherit | Netto | Brutto`) on `PlanForm` / `ProductForm` / `ResourceForm` bound to `price_display_mode`.
- **per plugin:** migration + `price_display_mode` field + create/update + `to_dict()`; pricing response exposes `effective_display_mode` (= `override ?? global`).
- **fe-user:** the price-rendering component reads `effective_display_mode`, shows net or gross accordingly, and renders the **"netto price"** tag when the item is netto under a brutto global. i18n key `price.nettoTag` (all locales).

## TDD
- **core:** `prices_display_mode` persists, defaults `brutto`, rejects unknown values.
- **per plugin:** `price_display_mode` persists (null = inherit); pricing returns `effective_display_mode = override ?? global`.
- **fe-user (Vitest):** a netto item under a brutto global shows the **net** price + "netto price" tag; a brutto item shows **gross**, no tag; global netto shows net everywhere with no per-item tag.
- **fe-admin (Vitest):** the global switch and the per-entity select save correctly.

## Definition of done
A global netto/brutto switch (core setting, default brutto) drives FE price display; any plan/product/booking resource can override it; an item shown netto under a brutto global carries a "netto price" tag; FE renders net vs gross accordingly. All touched repos green under `--full` + fe Vitest/ESLint. Not committed.
