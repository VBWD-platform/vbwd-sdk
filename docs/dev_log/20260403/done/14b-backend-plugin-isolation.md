# Sprint 14b — Backend: Plugin Isolation Tests

**Status:** Planned
**Date:** 2026-04-04
**Principles:** TDD · SOLID · DI · Liskov · DRY · Clean Code · No over-engineering
**Parent:** [14 — Access Control Bulletproof Tests](14-access-bulletproof-tests.md)

---

## Goal

Integration tests proving that when a plugin is disabled, its API routes are completely inaccessible — no data leaks, no partial responses.

---

## Test Cases

### Plugin Disabled → Routes Blocked

For each plugin that has admin routes, test:

| # | Plugin | Route Example | When Disabled |
|---|--------|--------------|---------------|
| 1 | **shop** | `GET /api/v1/admin/shop/products` | 404 or 503 |
| 2 | **shop** | `POST /api/v1/admin/shop/products` | 404 or 503 |
| 3 | **shop** | `GET /api/v1/shop/products` (public) | 404 or 503 |
| 4 | **booking** | `GET /api/v1/admin/booking/resources` | 404 or 503 |
| 5 | **booking** | `GET /api/v1/booking/resources` (public) | 404 or 503 |
| 6 | **cms** | `GET /api/v1/admin/cms/pages` | 404 or 503 |
| 7 | **cms** | `GET /api/v1/cms/pages/home` (public) | 404 or 503 |
| 8 | **discount** | `GET /api/v1/admin/discounts` | 404 or 503 |
| 9 | **discount** | `POST /api/v1/coupons/validate` (public) | 404 or 503 |

### Plugin Re-enabled → Routes Work

| # | Test | Expected |
|---|------|----------|
| 10 | Disable shop → routes blocked → re-enable shop → routes work again | 200 OK after re-enable |
| 11 | Disable shop → permissions listing lacks shop → re-enable → shop permissions reappear | Listing is dynamic |

### No Data Leakage

| # | Test | Expected |
|---|------|----------|
| 12 | Disabled plugin's data not returned in cross-plugin queries | Invoices don't leak shop order data |
| 13 | Disabled plugin's nav items not in sidebar config | Extension registry doesn't include disabled plugin |
| 14 | Disabled plugin's email templates still exist but events not fired | Templates in DB, no delivery |

### Plugin Blueprint Registration

| # | Test | Expected |
|---|------|----------|
| 15 | Disabled plugin's blueprint not registered with Flask app | URL rules don't exist |
| 16 | Plugin's `on_disable()` called — cleanup happens | Event handlers unsubscribed |

---

## How Plugin Disable Works (Current Architecture)

```
PluginManager.disable_plugin(name)
  → plugin.on_disable()       # cleanup hook
  → plugin._status = DISABLED
  → Blueprint remains registered (Flask limitation)
  → BUT: routes should check plugin status before processing
```

**Key Question:** Flask doesn't support unregistering blueprints at runtime. Options:
1. Each route checks `plugin.status == ENABLED` (middleware approach)
2. A before_request hook on plugin blueprints checks status
3. Plugin routes are never registered if plugin is disabled at startup

**Current state:** Plugins register blueprints at startup. If a plugin is disabled in `plugins.json`, it's never enabled and its blueprint is never registered. But runtime disable (via admin toggle) doesn't unregister the blueprint.

**Test strategy:** Test both scenarios:
- Plugin disabled in `plugins.json` → routes never exist
- Plugin disabled at runtime → routes should return 503 "Plugin disabled"

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Add `@plugin_required(plugin_name)` decorator or before_request check | TDD |
| 2 | Integration tests: disabled plugin routes (cases 1-9) | TDD |
| 3 | Integration tests: re-enable flow (cases 10-11) | TDD |
| 4 | Integration tests: no data leakage (cases 12-14) | TDD |
| 5 | `pre-commit-check.sh --full` (backend) | — |

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
```
