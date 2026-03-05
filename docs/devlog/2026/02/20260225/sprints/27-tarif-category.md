# Sprint 27: Tarif Plan Categories

## Context

Currently all tarif plans exist in a flat list with implicit `is_single=true` behavior — a user can only have one active subscription. We need hierarchical categories so plans can be grouped (e.g. "Customer Tier" with Basic/Developer/Pro, or "Software Packages" with multiple subscribable items). The `is_single` flag on a category controls whether a user can hold one or many active subscriptions within it. Users can also buy the same plan multiple times in `is_single=false` categories (like software licenses).

**Architecture decision**: Categories on TarifPlan (not a separate software_store entity). Reasoning: software packages ARE subscriptions — they share billing, invoicing, and payment infrastructure. A separate entity would duplicate all of that. Categories should also be registerable via the Plugin API for extensibility.

## Core Requirements

TDD, SOLID, DI, LSP, DRY, clean code, no overengineering.

## Data Model

**tarif_plan_category** table:
- `id` UUID PK, `name` VARCHAR(100), `slug` VARCHAR(100) UNIQUE, `description` TEXT NULL
- `parent_id` UUID FK(self) NULL — hierarchy
- `is_single` BOOLEAN DEFAULT true — one active sub per user in this category
- `sort_order` INTEGER DEFAULT 0
- `created_at`, `updated_at`, `version` — from BaseModel

**tarif_plan_category_plans** junction (M2M):
- `category_id` UUID FK PK, `tarif_plan_id` UUID FK PK
- Pattern: same as `addon_tarif_plans` in `src/models/addon.py`

**Migration default data**: Root category (slug="root", is_single=true), all existing plans attached to root.

---

## Steps

### Step 1: Model + Migration
**Create**: `src/models/tarif_plan_category.py`, Alembic migration
**Modify**: `src/models/__init__.py`
- TarifPlanCategory model with self-referential `parent_id`, `children` relationship, M2M `tarif_plans` relationship
- Junction table `tarif_plan_category_plans`
- Backref `plan.categories` (lazy="selectin") on TarifPlan — no TarifPlan file changes needed
- Migration: create tables, insert root category, attach all existing plans to root
- `to_dict()` with plan_count and nested children

### Step 2: Repository
**Create**: `src/repositories/tarif_plan_category_repository.py`
- Extends `BaseRepository[TarifPlanCategory]`
- Methods: `find_by_slug`, `find_root_categories`, `find_children`, `find_by_plan_id`

### Step 3: Service
**Create**: `src/services/tarif_plan_category_service.py`
- DI: receives `TarifPlanCategoryRepository` + `TarifPlanRepository`
- CRUD with validation: slug uniqueness, parent exists, cannot delete root, cannot delete category with children
- `attach_plans(category_id, plan_ids)`, `detach_plans(category_id, plan_ids)`
- `get_categories_for_plan(plan_id)`

### Step 4: DI Container
**Modify**: `src/container.py`
- Wire `TarifPlanCategoryRepository` and `TarifPlanCategoryService`

### Step 5: Admin Routes
**Create**: `src/routes/admin/categories.py`
**Modify**: `src/app.py` (register blueprint)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/admin/tarif-plan-categories` | List (flat or `?format=tree`) |
| POST | `/api/v1/admin/tarif-plan-categories` | Create |
| GET | `/api/v1/admin/tarif-plan-categories/<id>` | Get detail |
| PUT | `/api/v1/admin/tarif-plan-categories/<id>` | Update |
| DELETE | `/api/v1/admin/tarif-plan-categories/<id>` | Delete |
| POST | `/api/v1/admin/tarif-plan-categories/<id>/attach-plans` | Attach `{plan_ids:[]}` |
| POST | `/api/v1/admin/tarif-plan-categories/<id>/detach-plans` | Detach `{plan_ids:[]}` |

Auth: `@require_auth` + `@require_admin` (same pattern as `admin/plans.py`).

### Step 6: Update TarifPlan + Public API
**Modify**: `src/models/tarif_plan.py` — add `categories` to `to_dict()` output
**Modify**: `src/routes/tarif_plans.py` — add optional `?category=<slug>` filter

Response adds `"categories": [{"id", "name", "slug", "is_single"}]` — backwards compatible.

### Step 7: Subscription Enforcement
**Modify**: `src/repositories/subscription_repository.py` — add `find_active_by_user_and_plan`, `find_active_by_user_in_category`
**Modify**: `src/handlers/checkout_handler.py` — before creating subscription, check `is_single` categories: if user already has active sub in that category, return error (guide to upgrade/downgrade). For `is_single=false`, allow freely including same plan multiple times.
**Modify**: `src/services/subscription_service.py` — add `get_active_subscriptions` (plural, all categories), keep existing singular method for backwards compat.

### Step 8: Plugin API
**Modify**: `src/plugins/base.py` — add `register_categories() -> list` method (returns category definitions, default empty)
**Modify**: `src/plugins/manager.py` — on `enable_plugin()`, call `register_categories()` and create via service (idempotent, skip if slug exists)

### Step 9: Frontend — Category Store
**Create**: `vbwd-fe-admin/vue/src/stores/categoryAdmin.ts`
- Pinia store with CRUD actions matching admin API
- `attachPlans`, `detachPlans` actions
- Loading/error state (same pattern as `planAdmin.ts`)

### Step 10: Frontend — Categories Tab on Plans Page
**Modify**: `vbwd-fe-admin/vue/src/views/Plans.vue` — add tab system (Plans | Categories)
**Create**: `vbwd-fe-admin/vue/src/components/CategoriesTab.vue`
- Table: checkbox, name, slug, is_single badge, plan count, parent, actions (edit)
- Checkboxes + bulk delete
- "Create Category" button → `/admin/plans/categories/new`
- Lazy-load on tab switch via `watch(activeTab)` (Settings.vue pattern)

### Step 11: Frontend — Category Edit Page
**Create**: `vbwd-fe-admin/vue/src/views/CategoryForm.vue`
**Modify**: `vbwd-fe-admin/vue/src/router/index.ts` — add routes `plans/categories/new`, `plans/categories/:id/edit`
- Fields: name, slug (auto-gen), description, parent (dropdown), is_single (toggle), sort_order
- Delete with confirmation (block if has children)

### Step 12: Frontend — Categories on PlanForm
**Modify**: `vbwd-fe-admin/vue/src/views/PlanForm.vue`
- In edit mode only: two-panel layout (Available | Assigned categories)
- Assign/unassign with immediate API call (Countries tab pattern from Settings.vue)
- Show is_single/multi badge on each category

### Step 13: Backend Tests
**Create**: `tests/unit/models/test_tarif_plan_category.py` — model to_dict, defaults
**Create**: `tests/unit/services/test_tarif_plan_category_service.py` — CRUD validation, attach/detach, delete guards
**Create**: `tests/integration/test_admin_categories.py` — full API + subscription enforcement

### Step 14: Pre-commit
- `make pre-commit` (backend): lint + unit tests pass
- `npm run lint` + `npm run test` (frontend): pass

## Verification

1. `make pre-commit` — all backend tests green
2. Start backend: `make up` — migration runs, root category created, existing plans attached
3. Admin UI: http://localhost:8081/admin/plans — two tabs visible (Plans, Categories)
4. Create category "Software Packages" with is_single=false
5. Attach a plan to it
6. User checkout: can buy same plan twice (two active subscriptions)
7. Create category "Customer Tier" with is_single=true, attach plans
8. User checkout: second plan in same category returns error → must upgrade
9. `GET /api/v1/tarif-plans` returns plans with `categories` field
