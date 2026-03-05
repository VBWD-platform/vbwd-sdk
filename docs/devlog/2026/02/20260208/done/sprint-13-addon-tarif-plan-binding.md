# Sprint 13 — Add-On Tariff Plan Binding

**Priority:** HIGH
**Goal:** Add optional many-to-many relationship between add-ons and tariff plans, so that add-ons can be either independent (available to all users) or plan-specific (only available to subscribers of certain plans).

**Principles:** TDD-first, SOLID (SRP, OCP, LSP, ISP, DIP), Dependency Injection, DRY, Liskov Substitution, No Overengineering

---

## User Story

> As a platform admin, I want to optionally bind add-ons to one or more tariff plans, so that:
> - **Independent add-ons** (`tarif_plans = []`) are visible to all users regardless of subscription
> - **Plan-specific add-ons** (`tarif_plans = [plan_1, plan_2]`) are only visible to users currently subscribed to one of those plans

> As a subscribed user, I want to see:
> 1. All independent add-ons (no plan restriction)
> 2. Plan-specific add-ons that match my current subscription plan

---

## Scope

### Backend

| # | Task | Description |
|---|------|-------------|
| 13a | Migration | Create `addon_tarif_plans` junction table (addon_id FK, tarif_plan_id FK, unique constraint) |
| 13b | Model | Update `AddOn` model with `tarif_plans` many-to-many relationship |
| 13c | Repository | Update `AddOnRepository` — add `find_by_plan(plan_id)`, `find_available_for_plan(plan_id)` (returns independent + plan-specific) |
| 13d | Admin routes | Update `POST/PUT /admin/addons/` to accept `tarif_plan_ids: string[]`, update `GET` to return associated plan IDs/names |
| 13e | Public routes | Update `GET /addons/` to accept optional `plan_id` query param and filter accordingly |
| 13f | Tests | Unit tests for model relationship, repository queries, route input/output |

### Frontend — Admin

| # | Task | Description |
|---|------|-------------|
| 13g | Store | Update `AdminAddon` interface with `tarif_plan_ids: string[]` and `tarif_plans?: { id: string; name: string }[]` |
| 13h | AddonForm | Add multi-select/checkbox group for tariff plans (fetched from plan store). Label: "Restrict to Plans (optional)" |
| 13i | AddOns list | Show plan badges or "All Plans" indicator in the add-ons table |
| 13j | i18n | Add keys for all 8 locales (en, de, fr, es, ru, zh, ja, th) |
| 13k | Tests | Admin unit tests for form plan selector and list display |

### Frontend — User

| # | Task | Description |
|---|------|-------------|
| 13l | User view | Update user-facing add-on display to filter: show independent add-ons + add-ons matching user's active subscription plan |
| 13m | Tests | User unit tests for add-on filtering logic |

---

## Data Model

### New Table: `addon_tarif_plans`

```sql
CREATE TABLE addon_tarif_plans (
    addon_id UUID NOT NULL REFERENCES addon(id) ON DELETE CASCADE,
    tarif_plan_id UUID NOT NULL REFERENCES tarif_plan(id) ON DELETE CASCADE,
    PRIMARY KEY (addon_id, tarif_plan_id)
);
CREATE INDEX ix_addon_tarif_plans_plan ON addon_tarif_plans(tarif_plan_id);
```

### Behavior

- `addon.tarif_plans = []` → **Independent** — visible to everyone
- `addon.tarif_plans = [plan_A, plan_B]` → **Plan-specific** — visible only to subscribers of plan_A or plan_B
- Admin can add/remove plan bindings at any time
- Deleting a plan auto-removes it from the junction table (CASCADE)

---

## Design Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | Users with no subscription? | See independent add-ons (no plan restriction) |
| 2 | Admin plan selector UI? | Checkbox list of all active plans |
| 3 | Admin list display? | Plan name badges per add-on row (or "All Plans") |
| 4 | Public API filtering? | Auto-detect from user's active subscription (no explicit plan_id needed) |

## Public API Behavior

```
GET /api/v1/addons/
  - If user has active subscription to plan_X:
      → returns independent add-ons + add-ons bound to plan_X
  - If user has no subscription:
      → returns only independent add-ons
  - Admin endpoint returns all add-ons regardless
```

---

## Core Requirements

### Engineering Principles

1. **TDD (Test-Driven Development)** — Write tests BEFORE implementation. Red → Green → Refactor.
2. **SOLID**
   - **SRP** — Each class/module has one reason to change. Repository handles data access, routes handle HTTP, models handle domain.
   - **OCP** — Extend behavior without modifying existing code (e.g., new filter in repository, not rewriting existing queries).
   - **LSP (Liskov Substitution)** — Subtypes must be substitutable for their base types. AddOn with or without tarif_plans must behave consistently through all existing interfaces.
   - **ISP** — Don't force consumers to depend on methods they don't use.
   - **DIP (Dependency Injection)** — Depend on abstractions. Use the existing DI container (`dependency-injector`) for all service/repository wiring. Never instantiate repositories directly in routes.
3. **DRY** — No duplicate logic. Shared filtering logic lives in the repository, not repeated across routes.
4. **No Overengineering** — Minimal changes. No abstract factories, no extra config layers, no hypothetical future features. Just the junction table, relationship, and filtering.

### Testing Protocol

All changes MUST pass pre-commit checks before completion:

```bash
# Backend: lint + unit tests (via Docker)
cd vbwd-backend && make pre-commit-quick

# Frontend admin: style + unit tests
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --unit --style

# Frontend user: style + unit tests
cd vbwd-frontend && ./bin/pre-commit-check.sh --user --unit --style
```

### Acceptance Criteria

- [ ] All existing tests still pass (no regressions)
- [ ] New backend tests cover: model relationship, repository filtering, admin CRUD with plan IDs, public route auto-detection
- [ ] New frontend tests cover: checkbox plan selector in form, plan badges in list, user-side filtering
- [ ] `make pre-commit-quick` passes in backend
- [ ] `./bin/pre-commit-check.sh --admin --unit --style` passes
- [ ] `./bin/pre-commit-check.sh --user --unit --style` passes
