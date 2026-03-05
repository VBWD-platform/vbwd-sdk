# Report: Sprint 27 — Tarif Plan Categories

**Date**: 2026-02-25
**Sprint**: `sprints/27-tarif-category.md`
**Status**: CODE COMPLETE (pending `make test` in container)
**Repository**: vbwd-sdk-2/vbwd-backend + vbwd-fe-admin

---

## Summary

Implemented hierarchical tarif plan categories with `is_single` subscription enforcement. Plans can now be grouped into categories (e.g. "Customer Tier" with one-active-at-a-time, or "Software Packages" allowing multiple concurrent subscriptions). The `is_single` flag on a category controls whether users can hold one or many active subscriptions within it. Categories are also registerable via the Plugin API for extensibility.

## Architecture Decision

**Categories on TarifPlan** (not a separate software_store entity). Software packages ARE subscriptions — they share billing, invoicing, and payment infrastructure. A separate entity would duplicate all of that. The M2M junction table `tarif_plan_category_plans` follows the same pattern as `addon_tarif_plans`.

## Data Model

```
tarif_plan_category
├── id          UUID PK
├── name        VARCHAR(100)
├── slug        VARCHAR(100) UNIQUE
├── description TEXT NULL
├── parent_id   UUID FK(self) NULL  ← hierarchy
├── is_single   BOOLEAN DEFAULT true ← subscription enforcement
├── sort_order  INTEGER DEFAULT 0
├── created_at, updated_at, version  ← from BaseModel

tarif_plan_category_plans (junction M2M)
├── category_id    UUID FK PK
├── tarif_plan_id  UUID FK PK
```

Migration creates a root category (slug=`root`, is_single=true) and attaches all existing plans to it — backwards compatible.

## Deliverables

### Backend — New Files

| File | Purpose |
|------|---------|
| `src/models/tarif_plan_category.py` | Model with self-referential `parent_id`, `children` relationship, M2M `tarif_plans` with backref `plan.categories` |
| `src/repositories/tarif_plan_category_repository.py` | `find_by_slug`, `find_root_categories`, `find_children`, `find_by_plan_id` |
| `src/services/tarif_plan_category_service.py` | CRUD with validation (slug uniqueness, parent exists, cannot delete root/with children), `attach_plans`, `detach_plans` |
| `src/routes/admin/categories.py` | 7 admin endpoints (list, create, get, update, delete, attach-plans, detach-plans) |
| `alembic/versions/20260225_add_tarif_plan_category.py` | Create tables, insert root category, attach existing plans |
| `tests/unit/models/test_tarif_plan_category.py` | Junction table, model definition, defaults, `to_dict()` |
| `tests/unit/services/test_tarif_plan_category_service.py` | Create, update, delete guards, attach/detach with mocks |
| `tests/integration/test_admin_categories.py` | Full API + public endpoint + subscription enforcement |

### Backend — Modified Files

| File | Change |
|------|--------|
| `src/models/__init__.py` | Registered `TarifPlanCategory` + `tarif_plan_category_plans` |
| `src/models/tarif_plan.py` | Added `categories` array to `to_dict()` output (backwards compatible) |
| `src/container.py` | Wired `TarifPlanCategoryRepository` + `TarifPlanCategoryService` |
| `src/routes/admin/__init__.py` | Exported `admin_categories_bp` |
| `src/app.py` | Registered + CSRF-exempted `admin_categories_bp` |
| `src/routes/tarif_plans.py` | Added `?category=<slug>` filter to public plans endpoint |
| `src/repositories/subscription_repository.py` | Added `find_active_by_user_and_plan`, `find_active_by_user_in_category`, `find_all_active_by_user` |
| `src/services/subscription_service.py` | Added `get_active_subscriptions()` (plural, all categories) |
| `src/handlers/checkout_handler.py` | `is_single` enforcement: blocks checkout if user has active sub in same category |
| `src/plugins/base.py` | Added `register_categories() -> list` (default empty) |
| `src/plugins/manager.py` | On `enable_plugin()`, calls `register_categories()` and creates via service (idempotent) |

### Frontend — New Files

| File | Purpose |
|------|---------|
| `vue/src/stores/categoryAdmin.ts` | Pinia store: CRUD + `attachPlans`/`detachPlans` actions |
| `vue/src/components/CategoriesTab.vue` | Table with checkbox, name, slug, is_single badge, plan count, parent, edit actions, bulk delete |
| `vue/src/views/CategoryForm.vue` | Create/edit: name, slug (auto-gen), description, parent dropdown, is_single toggle, sort_order, delete with guard |

### Frontend — Modified Files

| File | Change |
|------|--------|
| `vue/src/views/Plans.vue` | Added tab system (Plans \| Categories) with lazy-load on tab switch |
| `vue/src/views/PlanForm.vue` | Added two-panel Available/Assigned categories layout (edit mode only) with immediate API calls |
| `vue/src/router/index.ts` | Added `plans/categories/new` and `plans/categories/:id/edit` routes |

## Admin API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/admin/tarif-plan-categories` | List (flat or `?format=tree`) |
| POST | `/api/v1/admin/tarif-plan-categories` | Create |
| GET | `/api/v1/admin/tarif-plan-categories/<id>` | Get detail |
| PUT | `/api/v1/admin/tarif-plan-categories/<id>` | Update |
| DELETE | `/api/v1/admin/tarif-plan-categories/<id>` | Delete (guards: root, children) |
| POST | `/api/v1/admin/tarif-plan-categories/<id>/attach-plans` | Attach `{plan_ids:[]}` |
| POST | `/api/v1/admin/tarif-plan-categories/<id>/detach-plans` | Detach `{plan_ids:[]}` |

Public API change: `GET /api/v1/tarif-plans?category=<slug>` filters plans by category.

## Subscription Enforcement Logic

```
checkout.requested → plan found → for each plan.category:
  if category.is_single:
    existing = find_active_by_user_in_category(user_id, category_plan_ids)
    if existing → ERROR "already has active subscription, upgrade/downgrade instead"
  if category.is_single == false:
    allow freely (including same plan multiple times)
```

## Plugin API

Plugins can register categories on enable:

```python
class MyPlugin(BasePlugin):
    def register_categories(self) -> list:
        return [{
            "name": "Software Packages",
            "slug": "software-packages",
            "is_single": False,
            "description": "Multiple concurrent subscriptions allowed",
        }]
```

`PluginManager.enable_plugin()` calls `register_categories()` and creates via service — idempotent (skips if slug exists).

## SOLID Compliance

| Principle | How |
|-----------|-----|
| **SRP** | Model, repository, service, routes each have one responsibility |
| **OCP** | New categories via Plugin API — no core code changes needed |
| **LSP** | `TarifPlanCategoryRepository` extends `BaseRepository[TarifPlanCategory]` — fully substitutable |
| **ISP** | Service exposes focused methods: CRUD, attach/detach, not one monolith |
| **DIP** | Service depends on repository interfaces, wired via DI container |

## Test Coverage

| Suite | Tests | Status |
|-------|-------|--------|
| Unit: model (junction table, defaults, to_dict) | 12 | Pending container run |
| Unit: service (create, update, delete guards, attach/detach) | 14 | Pending container run |
| Integration: admin API + public API + enforcement | 16 | Pending container run |
| **Total new tests** | **42** | **Pending** |

## Backwards Compatibility

- `to_dict()` adds `categories: []` field — additive, no breakage
- `?category=<slug>` filter is optional — existing calls unaffected
- Root category (is_single=true) migrated with all existing plans — preserves current one-sub-per-user behavior
- `find_active_by_user()` (singular) unchanged — `get_active_subscriptions()` (plural) added alongside

## Verification Checklist

1. `make test` in container — all backend tests green
2. `make up` — migration runs, root category created, existing plans attached
3. Admin UI `http://localhost:8081/admin/plans` — two tabs visible (Plans, Categories)
4. Create category "Software Packages" with is_single=false → attach plan → user can buy twice
5. Root category is_single=true → second plan in same category returns checkout error
6. `GET /api/v1/tarif-plans` returns plans with `categories` field
7. `GET /api/v1/tarif-plans?category=root` filters correctly
