# Report 06 — s9 + s10 e2e verification (live local stack)

**Date:** 2026-05-25. Both plugins enabled locally and exercised end-to-end.

## Enabled locally
- Backend `token_payment` → `var/plugins/backend-plugins.json` (+ rates in
  `backend-plugins-config.json`), activated via
  `POST /api/v1/admin/plugins/token_payment/enable` → status **active**.
- fe-user `token-payment` → `var/plugins/fe-user-plugins.json` (enabled);
  fe-user dev restarted to pick up the new plugin.
- Rate used: `USD = 0.05` (1 token = $0.05).

## s10 — pay an invoice with tokens

**Backend API e2e** (user `test@example.com`):
- `$2.99` add-on invoice → quote `tokens_needed=60, sufficient`; `pay` → **PAID**,
  balance **8784 → 8724 (exactly −60)**. Clean debit. ✓
- `$10.00` token-bundle invoice → debit 200 **and** the capture event credited
  the 1000-token bundle (net +800) — proves `emit_payment_captured` → line-item
  registry activation works (subscriptions/bundles fire on token payment). ✓

**fe-user UI e2e** (Playwright): on the PENDING `$99.99` invoice detail the
"Pay with tokens" panel rendered (balance 8724, cost 2000, after 6724); clicking
**Pay** → invoice **PAID**, panel self-hid (no longer PENDING). Screenshot:
`screenshots/s10-token-payment-panel.png`.

## s9 — CMS link prefetch + instant SPA nav

Playwright on `:8080/` (→ CMS home):
- **Prefetch:** visible local links were warmed automatically —
  `/cms/pages/{home1,features,about,signup,demo}` requested after load (menu-widget
  + content links → agnostic, covers widgets and main content). ✓
- **SPA nav:** clicking a local CMS link kept a `window.__spaAlive` sentinel →
  **no full page reload**. ✓

## Minor follow-ups (cosmetic, non-blocking)
1. `invoice.payment_method` stays the original (`invoice`/`stripe`) after a token
   payment — `PaymentCapturedHandler` preserves it rather than setting
   `token_payment`. Reporting-only; optional to change.
2. `pay` response `new_balance` is computed pre-capture, so for token-bundle
   invoices it doesn't reflect the bundle credit. Cosmetic.
3. fe-user panel label/value spacing is tight — small CSS polish.

## Not done
- Backend integration/Playwright specs committed in-repo were not run as a suite
  here (the live API e2e above covers the path); the s9 "no-reload" assertion was
  done ad-hoc via Playwright, not yet a committed e2e spec.
- Nothing pushed to GitHub remotes.
