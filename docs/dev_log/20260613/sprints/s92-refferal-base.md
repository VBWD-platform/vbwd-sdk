# S92 — Referral base (umbrella): partner payment-provision tracking + internal VBWD referral coupons

**Status:** PLANNED — 2026-06-14
**Shape:** an **umbrella** sprint over **two independent tracks** that share the word "referral" but almost nothing else:
- **Track A — Payment-provision referral base** (B2B): a separate deployable that tracks the provision **VBWD owes its partners** for sales settled through payment providers' native referral/Connect programs (Stripe Connect, PayPal Partner, …). **Architecture + foundation this sprint; live provider wiring phased/deferred** (needs external platform accounts).
- **Track B — Internal VBWD referral coupons** (B2C, fully implementable now): a meinchat chat command mints per-user referral coupons (`<PREFIX>_<NICKNAME>_<HEX8BYTES>`), redemption pays the **issuer** a token commission, and an admin **Promotions → VBWD Referral** page configures the program + shows exportable statistics.

**Repos:** Track B — `vbwd-backend` (new `referral` plugin + a thin additive event on `discount`) · `vbwd-fe-admin` (new `referral-admin` plugin). Track A — a **new** standalone service/repo `vbwd-provision-base` (design only this sprint) + a `vbwd-backend` provider-referral port.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID (Open/Closed — `referral` extends via the existing `BotCommandProvider` + a new `discount` domain event, never by editing core; Liskov — the bot command is a substitutable `BotCommandProvider`) · DI · DRY · clean code · **core agnostic** (the `referral` work is a plugin; core gains nothing referral-specific — token credit goes through the existing core `TokenService`) · **NO OVERENGINEERING** — [`_engineering_requirements.md`](_engineering_requirements.md). Full readable names ([[feedback_variable_naming]]). **Gate:** `bin/pre-commit-check.sh --plugin referral --full` + `--plugin discount --full` green, fe-admin `--full` (eslint + vue-tsc + vitest) green. Plugin migrations in the plugin, registered in `alembic.ini`, rev id ≤ 32 chars ([[feedback_plugin_migrations_in_plugin]]). Baseline `config.json` + `admin-config.json` (`debug_mode`) ([[feedback_plugin_baseline_config_files]]). Demo/test data only through services ([[feedback_no_direct_db_for_test_data]]). Plugin→plugin deps **declared** in `PluginMetadata.dependencies` ([[feedback_core_never_depends_on_plugins]]); plugins ship in their own repos ([[feedback_plugins_always_in_own_repos]]).

---

## 0. Audit — what exists (verified 2026-06-14)

**Coupons/discounts** live in the **`discount` plugin** (`vbwd-backend/plugins/discount/`):
- `Coupon` (`discount/models/coupon.py`): `code` (unique, upper-cased), `discount_id`→`DiscountRule`, `max_uses`, `max_uses_per_user`, `current_uses`, `is_active`, `starts_at`/`expires_at`.
- `CouponUsage` (`coupon_usage.py`): redemption junction — `coupon_id`, `user_id`, `invoice_id`, **`discount_amount` (actual money off)**, `used_at`. Written on invoice commit by `checkout_adjustment.py`.
- `DiscountRule` carries `discount_type` (percent/fixed/…), `value`, `currency`.
- Admin CRUD at `/api/v1/admin/coupons` (`discount/routes.py:238-400`, incl. `/generate`); public `POST /api/v1/coupons/validate`. Permissions `discount.coupons.{view,manage}`.
- Exchangers `discount_rules`/`discount_coupons` registered in `on_enable` (`discount/services/data_exchange/discount_exchangers.py`), cluster `sales`.
- fe-admin **`discount-admin`** injects **Promotions** under the core **Sales** nav section with children **Discounts**/**Coupons** (`vbwd-fe-admin/plugins/discount-admin/index.ts:54-71`); pages at `/admin/promotions/{discounts,coupons}`.

**Bot command seam** (`bot_base`, S45): a plugin implements `BotCommandProvider` — `bot_namespace` + `get_bot_commands() -> [BotCommand(name, description, namespace)]` + `handle_action(BotInbound) -> BotReply`; commands are collected from **enabled** plugins by `CommandRegistry` (no hard import). Args arrive as `BotInbound.args` (`MeinchatProvider._split_command` turns `/cmd --coupon X` into `command="cmd", args=["--coupon","X"]`). meinchat is **auth-native** → `BotInbound.identity` is the linked vbwd user. (`plugins/bot_base/bot_base/{types,ports}.py`, `plugins/chat/__init__.py:53-121` as the reference consumer.)

**Permissions** are arbitrary strings declared per-plugin via `admin_permissions` and checked with `user.has_permission("…")` (`vbwd/models/user.py:109-120`; `permission_catalog.py`). meinchat already declares `meinchat.*` keys (`plugins/meinchat/__init__.py:117-130`) — a new `meinchat_can:generate_coupons` key is just another string.

**Tokens** credited via core **`TokenService.credit_tokens(user_id, amount, transaction_type, reference_id, description)`** (`vbwd/services/token_service.py:38-78`), recording a `TokenTransaction`. New `TokenTransactionType` value needed for the commission.

**Nickname** = `UserNickname.nickname` (`plugins/meinchat/meinchat/models/user_nickname.py`, unique via `nickname_ci`); fetched by `nickname_repository.find_by_user_id`.

**fe-admin reusable bits:** `DualListSelector` (`vue/src/components/DualListSelector.vue`, `v-model:string[]` + `options:{value,label}[]` — the "available/selected" picker used by countries/user-groups); the generic list pattern (bulk checkbox + quick-search + sort + filters + bulk-delete) as on `UserGroups.vue`/`CustomFieldsSettings.vue`/`TaxesTab.vue`; per-list export via **`ImportExportControls`** (`vbwd-fe-core/src/dataExchange/`, `entity-key` + `selected-ids` + capabilities); the tab pattern from `TaxAndCountriesSettings.vue` / `CustomFieldsSettings.vue`.

---

# Track B — Internal VBWD referral coupons (implementable now)

## B.1 Design

A new **`referral` plugin**, `dependencies=["discount", "meinchat"]` (and the soft bot seam from `bot-base`), reusing core `TokenService`. It owns the referral link between an **issuer** (the user who minted a coupon) and a **discount coupon**, pays the issuer a **token commission on redemption**, and surfaces config + stats in fe-admin.

### Models (`referral/referral/models/`)
| model | table | key fields |
|---|---|---|
| `ReferralCoupon` | `referral_coupon` | `issuer_user_id` (FK `vbwd_user`), `coupon_id` (FK `discount_coupon`), `coupon_code` (denormalized, for masking/display), `issuer_nickname`, `template_coupon_id` (the cloned-from template), `commission_type` (`percent_of_sale`\|`absolute_tokens`), `commission_value` (Numeric), `status` (`issued`\|`used`\|`expired`), `issued_at`, `used_at` (nullable), `discount_amount` (nullable, filled on use, default currency), `commission_tokens_paid` (nullable int, filled on use), `invoice_id` (nullable) |
| `ReferralSettings` | `referral_settings` | **singleton** — `commission_type`, `commission_value`, `selected_template_coupon_ids` (JSON array of `discount_coupon` ids that may be cloned as referral templates) |

> `commission_type`/`commission_value` are **snapshotted onto each `ReferralCoupon` at mint time**, so changing program settings later doesn't retroactively repay old coupons (auditable). Migration in the plugin.

### Coupon-code generation (the exact rule)
- Canonical pattern: **`<PREFIX>_<NICKNAME>_<HEX8BYTES>`** where `HEX8BYTES = secrets.token_hex(8).upper()` (8 random bytes → **16 uppercase hex chars**, e.g. `F45E2A5DBB6677FF`).
- The command's `--coupon <PREFIX>` supplies the prefix; the system **normalizes** it (uppercase, strip trailing `_`, collapse repeats), appends `_<NICKNAME>_<HEX16>`. Example: `--coupon REF_USER_` + nickname `BOB` → **`REF_USER_BOB_F45E2A5DBB6677FF`**.
- Uniqueness: regenerate the hex on the (vanishingly rare) `discount_coupon.code` collision; bounded retries then error.

### Commission (on redemption, not at mint)
- **`absolute_tokens`** → credit a fixed token count to the issuer on each redemption.
- **`percent_of_sale`** → commission tokens = `commission_value%` of the sale's net amount (default currency), converted to tokens at the configured token rate (reuse the token-bundle price). **Decision D-Commission** (§B.6) pins the exact conversion.
- Paid via `TokenService.credit_tokens(issuer_user_id, tokens, TokenTransactionType.REFERRAL_COMMISSION, reference_id=referral_coupon_id, description=…)`; the `ReferralCoupon` row is stamped `status=used`, `used_at`, `discount_amount`, `commission_tokens_paid`, `invoice_id`. **Idempotent** — a re-fired redemption event for the same `(coupon, invoice)` does not double-pay (guarded by a unique `(coupon_id, invoice_id)` check).

### The redemption signal (Open/Closed, additive on `discount`)
`discount` currently records `CouponUsage` on invoice commit but emits no event. This sprint adds **one additive domain event** in the `discount` plugin — `discount.coupon_redeemed` (payload: `coupon_id`, `coupon_code`, `user_id`, `invoice_id`, `discount_amount`, sale net amount) — published right after `CouponUsage` is written. `referral` **subscribes** and pays the commission. No core change; `discount` doesn't know `referral` exists (event bus inverts the dependency). *(If an equivalent payment/coupon event already exists at impl time, subscribe to that instead — confirm in B2.)*

### Stats masking (privacy / anti-harvest)
The admin must **not** see a still-unused active code in full (or they could harvest live codes). Display rule, applied server-side in the stats read **and** export:
- `status != used` → masked: **prefix + nickname + first 4 hex + `x`×10 + last 2 hex** → `REF_USER_BOB_F45ExxxxxxxxxxFF`.
- `status == used` → **full** code revealed (it's spent; safe to show).

## B.2 Slices

### B0 — `referral` plugin foundation (backend)
Plugin class (`metadata(name="referral", dependencies=["discount","meinchat"])`), `ReferralCoupon` + `ReferralSettings` models + repos + migration; `ReferralService` (mint, settings get/set, redemption-pay, stats query); declares the **`meinchat_can:generate_coupons`** permission (label "Generate referral coupons", group "Meinchat") + `referral.view`/`referral.manage` for the admin page; DI provider registration in `on_enable` ([[project_plugin_di_provider_registration]]); baseline config files.
**TDD:** settings singleton get/set; mint produces a correctly-patterned, unique code cloned from a selected template; permission-key appears in the catalog; migration up/down/up.

### B1 — Bot command `/referral_program_new_coupon` (backend, referral)
`referral` implements `BotCommandProvider` (`bot_namespace="referral"`); `get_bot_commands()` returns `BotCommand("referral_program_new_coupon", …)` **only when enabled**; `handle_action`:
1. require `identity` (auth-native meinchat) → resolve issuer user.
2. enforce `user.has_permission("meinchat_can:generate_coupons")` → else a friendly refusal `BotReply`.
3. parse `--coupon <PREFIX>` (and optional `--template <code>` to pick among the selected templates; default = the program's primary selected template) from `BotInbound.args`.
4. resolve issuer nickname (`UserNickname`); no nickname → friendly "set a nickname first".
5. clone the selected discount template into a new `discount` `Coupon` with the generated code; create the `ReferralCoupon` (snapshotting commission settings); reply with the new code + a short how-to.
**TDD (no network):** permitted user mints a coupon → correct pattern, bound to the cloned discount, `ReferralCoupon` row created; unpermitted user → refusal, no coupon; missing nickname → guided refusal; missing `--coupon` → usage help; unknown `--template` → error listing valid templates; the command is absent from `get_bot_commands` when the plugin is disabled (Liskov). **Cross-provider:** works over meinchat **and** Telegram with no change (the seam is provider-neutral).

### B2 — Commission payout on redemption (backend, discount + referral)
- **discount:** emit the additive `discount.coupon_redeemed` event after `CouponUsage` write (`checkout_adjustment.py`); a `--plugin discount --full` regression proves existing checkout/usage behaviour is unchanged.
- **referral:** subscribe; on a redeemed coupon that maps to a `ReferralCoupon`, compute commission per the snapshotted settings, `credit_tokens` to the issuer, stamp the row. New `TokenTransactionType.REFERRAL_COMMISSION`.
**TDD:** redeeming a referral coupon credits the issuer the right tokens (both `absolute_tokens` and `percent_of_sale`), stamps `used`/`used_at`/`discount_amount`/`commission_tokens_paid`/`invoice_id`; a non-referral coupon redemption pays nothing; **idempotent** — duplicate event for the same `(coupon, invoice)` pays once; a self-referral (issuer == buyer) is rejected per policy (Decision D-SelfRef).

### B3 — fe-admin **Promotions → VBWD Referral** page (`referral-admin` plugin)
New fe-admin plugin injecting a **"VBWD Referral"** child under the existing **Promotions** group (sibling of Discounts/Coupons; `requiredPermission: 'referral.view'`), route `/admin/promotions/referral`. One tabbed page (mirror `TaxAndCountriesSettings.vue`), two tabs:
- **Settings** (`referral.manage`):
  - block **"Issuer's commission"** — a type toggle (`% of sale` | `absolute tokens`) + value input; saved via `PUT /api/v1/admin/referral/settings`.
  - block **"Coupon template"** — a **`DualListSelector`** of the admin's existing discount coupons (fetched from `/admin/coupons`): right = available, left = selected (exactly like countries); selection saved into `selected_template_coupon_ids`.
- **Referral Statistics** (`referral.view`) — the generic list (UserGroups/CustomFields pattern): columns **bulk-checkbox · issuer (user) · coupon code (masked unless used, per B.1) · discount % · discount in default currency (empty if unused) · commission tokens paid (empty if unused)**; **quick search**; **sortable**; **filter by** status / issuer / date-issued / date-used; **bulk delete**; **export CSV/JSON** via `ImportExportControls` (`entity-key="referral_coupons"`, `selected-ids`).
- 3 runtime manifests for the fe-admin plugin ([[project_fe_admin_plugin_runtime_manifests]]); navigate-by-URL e2e + seed both auth keys ([[project_fe_admin_navbar_e2e_helper_rot]], [[project_fe_admin_e2e_auth_harness]]).
**Backend admin routes (referral plugin):** `GET|PUT /admin/referral/settings`; `GET /admin/referral/coupons` (stats list — paginated, searchable, filterable, **masking applied server-side**); `POST /admin/referral/coupons/bulk-delete`.
**TDD:** settings round-trip; template selector persists ids; stats list masks unused codes / reveals used; filters + sort + bulk-delete; fe-admin Vitest for the two tabs + the dual-list + the masked-vs-full rendering.

### B4 — Data-exchange + verification
- Register a **`referral_coupons`** `BaseModelExchanger` (cluster `sales`, natural key `coupon_code`, permissions `referral.view`/`referral.manage`, JSON+CSV) in `on_enable` — **export honours the same masking rule** (used→full, unused→masked) so it can't leak live codes (Decision D-ExportMask).
- HTML walkthrough: mint a coupon via the meinchat command → see it masked in stats → redeem it in checkout → see it revealed + commission tokens credited to the issuer's balance → export the stats CSV.
**TDD:** exchanger round-trip; masking preserved through export; appears in the data-exchange manifest under `sales`.

---

# Track A — Payment-provision referral base (architecture + foundation; live wiring phased)

## A.1 What it is
A **separate deployable** (`vbwd-provision-base`, its own container/server) that records the **provision VBWD owes its partners** when customer payments settle through a provider's native referral/Connect program — e.g. as a **Stripe Connect platform** (application fees / Connect transfers) or a **PayPal Partner** (partner-referral revenue share). It is an **append-only partner-commission ledger** fed by provider webhooks/reports, with an admin view of "what we owe whom".

## A.2 Why it is its own track (and mostly deferred)
- **External prerequisites not yet in place:** a Stripe Connect **platform** account, a PayPal **Partner** account, and the partner agreements that define the revenue split. Without these there is nothing real to integrate against.
- **Separate trust boundary + scaling profile:** it ingests provider webhooks and holds financial-settlement data — it belongs on its **own container/server** (as the request states), not inside the monolith.
- Per **NO OVERENGINEERING**, this sprint delivers the **architecture + a thin, testable foundation**, and **defers live provider wiring** to a follow-up gated on the accounts above.

## A.3 Foundation deliverable this sprint (design + skeleton only)
- **Architecture doc** `docs/architecture/payment-provision-referral-base.md`: the ledger model (`PartnerProvisionEntry` — append-only: partner, provider, source ref (charge/transfer id), gross, fee, provision owed, currency, status), the **`IPaymentReferralProvider` port** (`StripeConnectProvider`, `PayPalReferralProvider` as future impls), webhook-ingest flow, idempotency/replay safety, reconciliation against provider reports, and the deploy shape (separate compose service).
- **A vbwd-backend port stub** `IPaymentReferralProvider` (no concrete provider) so the monolith can later *emit* the partner attribution it knows about — kept inert/disabled.
- **Decisions captured** (§A.4) so the follow-up sprint is a wiring exercise, not a redesign.

## A.4 Track-A decisions to confirm (owner)
- **DA-1 Scope now:** confirm Track A is **design + foundation only** this sprint, live integration deferred. (Recommended.)
- **DA-2 First provider:** Stripe Connect vs PayPal Partner first (drives the first concrete adapter).
- **DA-3 Deployable:** new repo `vbwd-provision-base` + its own container (recommended) vs a gated module in the monolith.
- **DA-4 Prerequisites owner:** who establishes the Stripe Connect platform / PayPal Partner accounts + partner agreements.

---

## 2. Out of scope (named)
- **Track A live provider integration** (Stripe Connect / PayPal Partner webhooks, the running `vbwd-provision-base` service) — deferred to a follow-up (DA-1).
- **fe-user "my referral coupons / my earnings" surface** — issuers see results in chat + token balance for now; a dedicated fe-user dashboard is a follow-up.
- **Multi-tier / sub-affiliate referral** (issuer-of-issuer chains) — single-hop only.
- **Coupon-template *creation*** from the referral page — templates are the admin's existing `/admin/promotions/coupons`; the referral page only **selects** among them.
- **Retroactive re-pricing** of already-minted coupons when settings change (settings are snapshotted at mint).

## 3. Acceptance / Definition of Done (Track B)
1. `--plugin referral --full` + `--plugin discount --full` green; fe-admin `--full` green. No new lint suppressions ([[feedback_no_noqa_without_permission]]). No core change — agnosticism oracles green.
2. A permitted meinchat user running `/referral_program_new_coupon --coupon REF_USER_` gets `REF_USER_<NICK>_<16-HEX>` bound to the selected discount template; an unpermitted user is refused; works over Telegram too.
3. Redeeming a referral coupon credits the issuer the configured commission (both modes), idempotently, and stamps the stats row.
4. **Promotions → VBWD Referral** shows the two tabs; Settings persists commission + the dual-list template selection; Referral Statistics lists with the exact columns, masks unused codes / reveals used, supports search/sort/filter/bulk-delete/export.
5. `referral_coupons` exchanger round-trips JSON+CSV under cluster `sales`, masking preserved.
6. HTML walkthrough (mint → masked stat → redeem → revealed + tokens credited → export) under `docs/dev_log/20260613/walkthrough/`.
7. **Track A:** the architecture doc + the inert port stub land; DA-1…DA-4 recorded.
8. Completion report `docs/dev_log/20260613/reports/NN-s92-referral-base.md`.

## 4. Decisions to confirm + risks (Track B)
**Decisions:**
- **D-Commission** — `percent_of_sale` → tokens conversion: use the configured token-bundle price (currency→tokens) at redemption time. Confirm the rate source. (Recommended.)
- **D-SelfRef** — reject self-referral (issuer == buyer) to prevent self-dealing. (Recommended on.)
- **D-ExportMask** — the stats **export** applies the same used/unused masking as the on-screen stats (no live-code leak via CSV). (Recommended on.)
- **D-Permission-name** — keep the user's exact key `meinchat_can:generate_coupons` (declared by `referral`, grouped under "Meinchat"), despite differing from the `meinchat.*` dot-convention. (Recommended — honor the request.)
- **D-Redeem-signal** — add the `discount.coupon_redeemed` event vs subscribe to an existing payment event. Confirm at impl which exists.

**Risks:**
- **Commission on refund/chargeback** — if a sale that paid a commission is later refunded, the issuer was over-credited. Mitigation: a `discount.coupon_refunded`/payment-reversal subscription that debits/claws back the commission — **flagged**, minimal handler in B2 or a fast-follow (don't silently ignore).
- **Template coupon edited/deleted after selection** — a selected template removed from `/admin/coupons` must degrade gracefully (mint errors clearly; stale ids pruned from settings). Tested.
- **Masking correctness** — the first-4/last-2 reveal must never expose enough to guess the 8-byte middle; with 10 hidden hex chars (~40 bits) it's safe. Tested with an exact-format assertion.
- **Idempotency under webhook replay** — the `(coupon_id, invoice_id)` unique guard is the single source of no-double-pay; tested with a replayed event.

## 5. Cross-references
- Discount/coupon system (`discount` plugin) — coupon + `CouponUsage` + exchangers (the template source + redemption record).
- Bot command seam — [S45 bot-base](../../20260607/done/s45-bot-base-bridge.md) (`BotCommandProvider`, provider-neutral; the same command works on meinchat + Telegram).
- Core `TokenService.credit_tokens` + token pricing (commission payout + percent→tokens conversion).
- meinchat `UserNickname` (the `<NICKNAME>` in the code).
- fe-admin reuse: `DualListSelector` (countries/user-groups), the generic list pattern (UserGroups/CustomFields/Taxes), `ImportExportControls`, the tabbed-page pattern (TaxAndCountries).
- [[project_plugin_di_provider_registration]] · [[feedback_plugin_migrations_in_plugin]] · [[project_fe_admin_plugin_runtime_manifests]] · [[reference_admin_config_select_static_only]] (why the template picker is a dedicated dual-list + settings model, not a static admin-config `select`).
