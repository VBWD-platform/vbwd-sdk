> **⚠ SUPERSEDED — merged into
> [`03-merged-decouple-core-and-relocate-subscription.md`](../done/03-merged-decouple-core-and-relocate-subscription.md)**
> (per report 02 §3a R1: model relocation can't precede importer removal, so
> 03+04 are one dependency-ordered sprint). Kept for history; do not execute
> from here.

# Sprint 04 — Backend: break live core→subscription couplings

**Phase:** 1 · **Repos:** `vbwd-backend`, `vbwd-backend/plugins/subscription`
**Effort:** L (~3–4 dev-days) ⚠ · **Depends on:** 03 · **Blocks:** 09
**Engineering requirements:** [`_engineering-requirements.md`](./_engineering-requirements.md) — binding (esp. **E2, E6**).

## Goal

Remove every **live** runtime dependency from core onto subscription. After
03, core no longer *defines* the models; after this sprint core no longer
*calls* subscription. Four couplings (report §3.1(a), §4):

1. `vbwd/routes/user.py` (registered `app.py:230`) serves `/checkout`
   (emits `CheckoutRequestedEvent`) and `/addons*` (uses
   `container.addon_subscription_repository()`).
2. `vbwd/services/feature_guard.py` — ctor depends on `SubscriptionRepository`;
   implements plan/tier gating in core.
3. `vbwd/models/invoice_line_item.py:45-63` — `_resolve_catalog_item_id()`
   hard-imports subscription models, branches on
   `LineItemType.SUBSCRIPTION/ADD_ON`.
4. `vbwd/container.py:19-26,91-106` — DI factories for the 5 subscription
   repos (under a docstring that already *claims* they're plugin-only).

## Baseline (E1)

Characterisation tests pinning current observable behaviour, GREEN on `main`:

- `test_checkout_route_char.py`: `POST /api/v1/.../checkout` with a known
  payload → exact status, body, and the emitted event (name + payload) via a
  spy dispatcher.
- `test_addons_routes_char.py`: each `/addons*` endpoint → status + body.
- `test_feature_guard_char.py`: for a user with/without an active plan,
  `FeatureGuard` allow/deny decisions for a representative feature matrix.
- `test_invoice_line_item_resolve_char.py`: `_resolve_catalog_item_id()` for
  SUBSCRIPTION, ADD_ON, TOKEN_BUNDLE line items → resolved id.

All four, unchanged, must be GREEN after the move (E2 Liskov: same I/O,
side-effects, exceptions at the new call site).

## TDD plan (RED → GREEN per coupling, in this order)

### 4.1 Line-item resolution via the registry (E6)
- The line-item handler registry already exists (Sprint 04a, 2026-03-27).
  Extend it with a `resolve_catalog_item_id(line_item)` capability.
- **RED:** `test_line_item_registry_resolves_subscription` in the *plugin*
  unit tests — registry has no subscription resolver yet ⇒ red.
- Implement `SubscriptionLineItemHandler.resolve_catalog_item_id`; register
  it in the plugin. Rewrite core `invoice_line_item._resolve_catalog_item_id`
  to delegate to the registry with a **null-object default** for unknown
  types (TOKEN_BUNDLE stays core via `core_line_item_handler`).
- Baseline `test_invoice_line_item_resolve_char` GREEN unchanged.
- New core test: `import vbwd.models.invoice_line_item` does **not**
  transitively import `vbwd...subscription` (assert via `sys.modules` after a
  clean import) — RED then GREEN.

### 4.2 `/checkout` + `/addons` → plugin blueprint
- Plugin already owns `subscription_bp` with checkout/addons modules.
  **RED:** plugin route char tests for `/checkout` + `/addons*` (copies of the
  Baseline assertions, pointed at the plugin blueprint) — currently the plugin
  may not register these exact paths ⇒ red.
- Move the route bodies from `vbwd/routes/user.py` into the plugin blueprint
  (verbatim handlers — E2). Remove them from `user_bp`. Keep any **generic**
  `/user/*` endpoints in core untouched.
- Baseline `test_checkout_route_char` / `test_addons_routes_char` GREEN
  unchanged (same URLs now served by the plugin — assert by blueprint name).
- Core test: `user_bp` exposes no `checkout`/`addons` rule.

### 4.3 `FeatureGuard` → plugin behind a generic capability port (E6)
- Define a **narrow core interface** (ISP) e.g.
  `IEntitlementProvider.is_feature_allowed(user_id, feature_key) -> bool` in
  core (no subscription vocabulary).
- Plugin implements `SubscriptionEntitlementProvider` (wraps the old
  `FeatureGuard` logic + `SubscriptionRepository`) and registers it.
- Core consumers resolve the provider via DI; absent provider ⇒ a permissive
  or configured default (decided in Open questions) — a booking-only install
  has no entitlement gating from subscription.
- **RED:** plugin `test_subscription_entitlement_provider` (the moved
  `FeatureGuard` matrix) ⇒ red until implemented.
- Baseline `test_feature_guard_char` re-pointed at the provider, GREEN
  unchanged. Delete `vbwd/services/feature_guard.py`.

### 4.4 Remove subscription DI from `container.py`
- **RED:** `test_core_container_has_no_subscription_factories` — asserts the
  container exposes none of the 5 subscription repo factories. Red now.
- Delete the factories + the misleading docstring. Plugin DI (already present
  in the plugin) becomes the only provider. Fix any core resolver (should be
  none after 4.1–4.3) — if one remains, it was missed coupling: handle here.
- GREEN; full suite green.

## SOLID / DI notes

- **DIP:** core depends on the `IEntitlementProvider` / line-item-registry
  *abstractions*; the subscription plugin supplies the concretions. The arrow
  now points the right way.
- **ISP:** `IEntitlementProvider` is one method — core uses only what it needs;
  subscription-specific richness stays in the plugin.
- **OCP (E6):** adding/removing subscription changes registrations, not core
  `if` branches. The `invoice_line_item` switch is gone.
- **Liskov (E2):** every Baseline char test is the substitution proof for its
  coupling; none may be edited to pass.
- **DRY:** one entitlement port, one line-item registry — no parallel gating
  logic left in core.

## Acceptance criteria

- `vbwd/services/feature_guard.py` deleted; `container.py` has no subscription
  factories; `invoice_line_item.py` has no subscription import/branch;
  `user_bp` serves no checkout/addons.
- All four Baseline char tests GREEN **unchanged**; new negative-import /
  no-factory / no-rule tests GREEN.
- Plugin-disabled app boots and serves all non-subscription `/user/*` routes;
  subscription endpoints return 404 (route not registered) — not 500.
- `make pre-commit` green.

### E3 oracle slice made true

"zero subscription routes registered by core; zero core call sites importing
or invoking subscription; `subscription.*` gating not evaluated by core when
the plugin is disabled."

## Risks ⚠

- A coupling the audit missed surfaces as a failing Baseline test or an import
  cycle. Mitigation: the `sys.modules` no-transitive-import assertions make
  hidden edges visible; per-coupling atomic commits.
- `IEntitlementProvider` default-when-absent is a behaviour decision — must be
  explicit (Open questions), with its own test, not an accident.
- Event name/payload drift when moving `/checkout` — the spy-dispatcher
  Baseline test pins it exactly.

## Decisions (LOCKED — report 02 §3, D3)

- Absent-provider entitlement default = **config flag, default `allow`**.
  When no `IEntitlementProvider` is registered (subscription plugin
  disabled), gated features are **allowed**; an explicit core config flag can
  flip the default to deny. Booking/shop installs have no plan concept and
  must not be gated by an absent one. This is no longer open — 4.3 must ship
  the flag + a test for both flag states (`allow` default, `deny` override)
  and the provider-present path.

## Effort

L — ~3–4 dev-days (4.3 the largest: introducing the port + provider + DI).
