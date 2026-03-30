# Report 04 — Sprint 04d: Subscription Admin Frontend Plugin

**Date:** 2026-03-27
**Status:** Done

---

## What Was Done

Created `plugins/subscription-admin/` in fe-admin containing all plan/subscription/addon views, stores, and components.

### Files Moved to Plugin

- **Views (8):** Plans, PlanForm, CategoryForm, AddOns, AddonForm, Subscriptions, SubscriptionDetails, SubscriptionCreate
- **Stores (4):** planAdmin, subscriptions, addons, categoryAdmin
- **Components (1):** CategoriesTab
- **Tests (6):** PlanForm, Plans, Subscriptions, SubscriptionDetails, addon-form, addons

### Core Changes

- **Router:** Removed 11 routes (plans/*, add-ons/*, subscriptions/*)
- **AdminSidebar:** Removed "Subscriptions" from Sales nav, removed entire "Tarifs" section (Plans, Add-Ons)
- **Registered** in plugins.json + config.json + .gitignore

### Test Results

- Core unit tests: **192 passed** (21 files, all green)
- Pre-existing integration failures (6) unrelated to this sprint
- Plugin tests need path updates (deferred to plugin repo setup)

---

## Lessons Learned

### 1. Plugin routes as children of admin layout

fe-admin's `factory.ts` adds plugin routes as children of the `admin` route: `router.addRoute('admin', route)`. So plugin routes use relative paths (`plans`, not `/admin/plans`). This matches the booking plugin pattern.
