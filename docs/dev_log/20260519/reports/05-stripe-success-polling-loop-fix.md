# Report 05 — Stripe success page polls "paid" 15× in a loop (fixed)

**Date:** 2026-05-24 · **Author:** Claude (Opus 4.7) · **Severity:** medium
(UX: ~30s "Verifying…" spinner + 15× redundant requests after every successful
card payment)

## Symptom

After paying for the Basic plan via Stripe (`/pricing-native` →
`choose-plan-basic` → Stripe → `/pay/stripe/success`), the success page fired the
same `GET /api/v1/plugins/stripe/session-status/<id>` repeatedly — **every
response `200 {"status":"paid"}`** — until it gave up.

## Measured (Playwright, real test-card 4242 purchase)

**Before fix — 15 requests, ~2.0s apart, all "paid":**
```
t+79.94s  first   200 {"status":"paid", invoice_id:…, amount_total:999}
t+82.21s  Δ2.27s  200 {"status":"paid", …}
 … 15 total (Δ 1.85–2.27s, ≈ intervalMs 2000) …
t+108.35s Δ2.13s  200 {"status":"paid", …}
→ stops at attempt 15 (maxAttempts) → timedOut → redirect at t+114.55s
```
User saw a "Verifying…" spinner for **~30s** then a 2s timeout-redirect. **14 of
15 requests were pure waste** (the first already said "paid"); each also re-ran
the server-side `_reconcile_payment`.

**After fix — 1 request, instant redirect:**
```
t+80.28s  first   200 {"status":"paid", …}
→ redirect to /checkout/confirmation
redirect latency after success: 0.75s   (was ~32s)
```

## Root cause

- Backend `/plugins/stripe/session-status` returns Stripe's native
  `session.payment_status` → **`"paid"`** (lowercase).
- The shared fe-core composable `usePaymentStatus` only treated
  `status === 'complete' || status === 'PAID'` as done. `"paid"` matched
  neither → `confirmed` never flipped → it polled all 15 attempts and exited via
  the *timeout* path, not the *confirmed* path.

## Fix

`vbwd-fe-core/src/composables/usePaymentStatus.ts` — normalise the status and
accept the real provider terms (shared by stripe / paypal / yookassa, so the
right layer):
```js
const status = String(data?.status ?? '').toLowerCase();
if (status === 'complete' || status === 'paid' || status === 'succeeded') {
  confirmed.value = true; stopPolling(); return true;
}
```
Stops on the **first** success response.

### ⚠️ Gotcha — two fe-core checkouts

The fe-user dev container mounts **`../vbwd-fe-core`** (the top-level
`vbwd-sdk-2/vbwd-fe-core/`), **not** the submodule `vbwd-fe-user/vbwd-fe-core/`
(`docker inspect`: `bind …/vbwd-sdk-2/vbwd-fe-core -> /app/vbwd-fe-core`). The
app consumes the **built `dist/`** (package `exports` → `./dist/index.mjs`), so a
fix requires: edit src → rebuild dist (`docker compose --profile build`) →
clear `node_modules/.vite` → restart the dev container. The first attempt fixed
the *submodule* and showed no effect; fixing the **top-level** dir was what
landed. Both checkouts now carry the source fix + the test.

## Tests / verification

- `vbwd-fe-core/tests/unit/composables/usePaymentStatus.spec.ts` — added 4
  `it.each(['paid','PAID','Complete','succeeded'])` cases asserting **single
  poll** (`api.get` called once) + `confirmed`. **8/8 pass** in both checkouts.
  (Two unrelated pre-existing fe-core failures: `auth-login`, `package-config`.)
- Live Playwright purchase after the fix: **1** `session-status` request,
  redirect in **0.75s**.

## Follow-up

- fe-core change needs the standard propagation to ship (dist build committed +
  fe-user/fe-admin submodule pin bump per the lockfile-pin process).
