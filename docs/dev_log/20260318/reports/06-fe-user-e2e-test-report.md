# fe-user E2E Test Report

**Date:** 2026-03-18
**Status:** Blocked (prerequisites not met)

---

## Summary

All 222 Playwright E2E tests failed due to missing prerequisites — not code issues.

---

## Root Cause

Two blockers preventing E2E tests from running:

### 1. Playwright browsers not installed

```
Error: browserType.launch: Executable doesn't exist at
  /Users/dantweb/Library/Caches/ms-playwright/chromium_headless_shell-1208/
  chrome-headless-shell-mac-arm64/chrome-headless-shell

Please run: npx playwright install
```

### 2. Backend not running

```
Waiting for backend at http://localhost:5000/api/v1/health...
Backend not ready after 30000ms, proceeding anyway
```

E2E tests require the full stack running (backend API + frontend dev server).

---

## Test Inventory

| File | Tests | Description |
|------|-------|-------------|
| auth.spec.ts | 4 | Login, logout, redirect, invalid credentials |
| dashboard.spec.ts | ? | Dashboard page |
| profile.spec.ts | ? | Profile management |
| subscription.spec.ts | 4 | Subscription management |
| subscription-page.spec.ts | ? | Subscription detail page + invoice flow |
| subscription-data.spec.ts | ? | Subscription data display |
| plan-switching.spec.ts | ? | Plan upgrade/downgrade |
| invoices.spec.ts | ? | Invoice listing |
| addons-page.spec.ts | ? | Add-ons page |
| tokens-page.spec.ts | 7 | Token bundles page |
| cart.spec.ts | ? | Shopping cart |
| checkout/ | ? | Checkout flow (multi-file) |
| taro.spec.ts | ~30 | Taro plugin (sessions, cards, follow-ups) |
| taro-oracle-flow.spec.ts | 21 | Oracle card reveal mechanic |
| ghrm-catalogue.spec.ts | ? | GHRM software catalogue |
| ghrm-lifecycle.spec.ts | ? | GHRM subscription lifecycle |
| **Total** | **222** | |

---

## How to Run

```bash
# 1. Install Playwright browsers (one-time)
cd vbwd-fe-user
npx playwright install

# 2. Start backend
cd ../vbwd-backend && make up

# 3. Start frontend dev server (separate terminal)
cd ../vbwd-fe-user && npm run dev

# 4. Run E2E tests
npx playwright test vue/tests/e2e/

# 5. Interactive UI mode
npx playwright test vue/tests/e2e/ --ui
```

---

## Next Steps

1. Install Playwright browsers: `npx playwright install`
2. Start full stack: `make up` (backend) + `npm run dev` (frontend)
3. Re-run E2E tests
4. Create follow-up report with actual pass/fail results
