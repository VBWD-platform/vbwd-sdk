# Sprint 41 Report — PromptPay (Thailand direct)

**Date:** 2026-04-24
**Sprint:** [41 — PromptPay Thailand direct](../done/41-promptpay-thailand.md)
**Status:** Scaffolded. 25 unit tests green. Pre-commit PASS.

## What shipped

### `vbwd-plugin-promptpay` (backend)

- `PromptPayPlugin(BasePlugin)` — not a classic gateway: it is a
  direct-bank-reconciliation model (QR issued server-side, bank
  confirms via webhook). Deep-merge `initialize()` preserves the
  nested `bank_credentials` dict across partial overrides.
- EMVCo QR renderer per Bot (Bank of Thailand) spec: PromptPay AID
  `A000000677010111` in tag 29, currency `764`, country `TH`,
  reference in tag 62.01, CRC16/CCITT-FALSE. Identifier
  normalisation strips non-digits (so caller can pass phone
  `+66-812-345-678` or a national ID seamlessly).
- `IBankReconciler` abstract interface with `KBankReconciler` +
  `ScbReconciler` concrete implementations. Each does HMAC-SHA256
  signature check over the raw body and normalises the bank's
  native payload shape into a `BankTransaction`.
- `PromptPayService.issue_qr(invoice_no, …)` is idempotent — a
  second call returns the same payment record rather than issuing
  a duplicate QR.
- `PromptPayReconciler.match(bank_tx)` — two-phase:
  1. Reference match (preferred): tag 62.01 reference + exact
     amount equality.
  2. Amount + timestamp-window fallback (reason: some Thai banks
     strip QR references on the statement line). Zero or >1
     candidates in the window ⇒ `None`, surfaces for manual
     review.
- Routes: `POST /payments` (issue), `GET /payments/:invoice/status`,
  `POST /webhooks/:bank` (per-bank signature check + matching).
- Migration `20260424_1200_promptpay` chains after
  `20260424_1100_conekta`.
- **25 unit tests**: QR structure (AID, currency, country, amount,
  CRC shape), identifier normalisation, QR determinism, HMAC
  verify accept/reject, payload extraction (with + without memo,
  ref1/ref2 fallback), reconciler match with exact reference +
  amount, amount/window fallback with 0/1/>1 candidates,
  deep-merge config.
- `pre-commit-check.sh --plugin promptpay --quick`: **PASS**.
- Commit: `935d0d6`.

### `vbwd-fe-user-plugin-promptpay-payment`

- Named-export `promptPayPaymentPlugin`.
- `PromptPayView` — issues QR via backend, displays payload +
  amount + reference, polls `/status` every 3 s, routes to
  dashboard on `completed`.
- Locales: `en`, `th`.
- Commit: `a625f8c`.

### `vbwd-fe-admin-plugin-promptpay-admin`

- Named-export `promptPayAdminPlugin`.
- Route `/admin/promptpay/payments` — list showing pending vs
  matched state, with matched bank + bank-tx id when present
  (operators reconcile manually when match fails).
- Commit: `e56cf9a`.

## Engineering-contract checks

- **TDD-first**: QR tag structure + CRC shape, identifier
  normalisation, reconciler reference-then-window priority — all
  spec'd first.
- **DevOps-first**: `pre-commit-check.sh` green. Unused imports
  (`Decimal`, `UUID`, `timedelta`) caught by flake8 and **deleted**,
  not suppressed with `# noqa`.
- **SOLID + Liskov**: `IBankReconciler` documents its
  postconditions explicitly; both concrete banks honour them
  (pure function for signature check; parse-only `ValueError` on
  structural failure). Adding a third bank only requires a new
  class — no changes to routes, service, or reconciler.
- **DRY**: per-bank clients are separate (different payload
  shapes), but both share the HMAC-SHA256 signing pattern; that
  duplication is deliberate at N=2 (3rd bank triggers promotion).
- **DI**: service + reconciler take `session`; fe-admin store
  takes `api`.
- **Clean code**: `render_promptpay_qr` is the full, readable
  name. One "why" comment on the fallback strategy (non-obvious
  business rule about Thai banks stripping references).
- **No over-engineering**: no generic "bank router" service; the
  `_bank_reconciler(bank)` function is a 5-line factory.
- **Drop deprecated**: unused imports removed rather than
  suppressed.

## Follow-ups

1. **`GET /payments` list endpoint** for admin UI — **S41.1**.
2. **BBL + Krungsri** reconcilers (scope deferred in sprint
  — S41.2).
3. **Manual-match UI** in fe-admin: surface unmatched bank
  transactions + allow operator to bind to invoice — **S41.3**.
4. **Mobile deep-link** `thaiqr://` on fe-user — **S41.4**.
5. **QR-expiry cron reconciler** — **S41.5**.

## Pre-commit output

```
Static analysis: ALL CHECKS PASSED
Unit tests:      25 passed in 0.22s
SUCCESS: All checks passed! Ready to commit.
```
