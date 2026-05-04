# Sprint 35 Report — Conekta (Mexico)

**Date:** 2026-04-24
**Sprint:** [35 — Conekta Mexico](../done/35-conekta-mexico.md)
**Status:** Scaffolded end-to-end. 34 unit tests green, pre-commit PASS.

## What shipped

### `vbwd-plugin-conekta` (backend)

- `ConektaPlugin` with MXN-only enforcement and method allow-list
  (`card` / `oxxo_cash` / `spei`). Liskov-safe `initialize` merge.
- `ConektaSDKAdapter` with Basic-auth (private key + `:`), pinned
  `Accept: application/vnd.conekta-v2.2.0+json` header, cents-integer
  amount conversion, MSI propagation for cards, OXXO/SPEI via
  `payment_method.type`.
- `compute_msi_plans(amount, card_brand, plans=None)` — Visa/MC/Amex
  only + minimum 300 MXN; returns `[1] + plans` if eligible, else
  `[1]`.
- `ConektaService` with idempotent `apply_provider_update`.
- `ConektaWebhookHandler` reads `data.object.metadata.invoice_no`
  per Conekta webhook envelope.
- Digest-header HMAC (base64-encoded SHA-256) webhook verification.
- Migration `20260424_1100_conekta` chains after `20260424_1000_toss`.
- Routes: create order / status / webhook / refund.
- **34 unit tests**: basic-auth bytes, cents conversion, MSI
  propagation, OXXO payload shape, refund amount-in-cents,
  full-refund omits amount, digest-HMAC round-trip, details[0].message
  parsing, MSI eligibility rules.
- `pre-commit-check.sh --plugin conekta --quick`: **PASS**.
- Commit: `c08c496`.

### `vbwd-fe-user-plugin-conekta-payment`

- Named-export `conektaPaymentPlugin`.
- Views: `ConektaPaymentView` (method picker + token + MSI selector),
  `ConektaVoucherView` (OXXO reference / SPEI CLABE display),
  `ConektaSuccessView`.
- Locales: `en`, `es` (Mexican Spanish baseline).
- Commit: `35a9382`.

### `vbwd-fe-admin-plugin-conekta-admin`

- Named-export `conektaAdminPlugin`.
- Route: `/admin/conekta/orders` — list with method filter + refund.
- Pinia store `useConektaStore` with DI on `api`.
- Commit: `8fe385d`.

## Engineering-contract checks

- **TDD-first**: cents conversion, MSI propagation, Digest HMAC
  round-trip, details[0].message parsing — all spec'd first.
- **DevOps-first**: `pre-commit-check.sh` green. Flake8 F401
  (`pytest imported but unused`) was caught by the linter and
  deleted, not suppressed with `# noqa`.
- **SOLID + Liskov**: `release_authorization` returns
  `SDKResponse(success=False, error=…)` — preserves ISDKAdapter
  contract, doesn't raise. `capture_payment` delegates to
  `get_order` (Conekta has no true capture because Orders API
  is charge-on-create).
- **DRY**: one `_post` / `_get` in the adapter; cents conversion in
  `_to_cents` helper.
- **DI**: service takes `session`; fe-admin store takes `api`.
- **Clean code**: `compute_msi_plans` is the full, readable name
  (no `cmp()` abbrev).
- **No over-engineering**: MSI rules are a baseline function, not a
  full BIN-table lookup service — merchant refines per-bank via
  config when the data exists.

## Follow-ups

1. **`GET /api/v1/plugins/conekta/orders`** list endpoint — **S35.1**.
2. **Integration tests** against Conekta sandbox — **S35.2**.
3. **Conekta.js token generation** in fe-user (secure PCI-scoped
   card capture) — **S35.3**.

## Pre-commit output

```
Static analysis: ALL CHECKS PASSED
Unit tests:      34 passed in 0.26s
SUCCESS: All checks passed! Ready to commit.
```
