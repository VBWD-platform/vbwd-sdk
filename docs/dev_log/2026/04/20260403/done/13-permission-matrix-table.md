# Sprint 13 — Permission Matrix Table UI

**Status:** Draft — pending Q&A
**Date:** 2026-04-04
**Principles:** TDD · SOLID · DRY · Clean Code · No over-engineering

---

## Goal

Redesign the access level form's permission section from a flat checkbox grid to a structured table where columns represent access actions (view, manage, configure) and rows represent resources.

---

## Current State

The current `AccessLevelForm.vue` shows permissions as a flat grid of checkboxes grouped by plugin:

```
── Shop ──
[x] View products          shop.products.view
[x] Manage products        shop.products.manage
[ ] View orders            shop.orders.view
...
```

## Target State

A table where:
- **Rows** = resources (grouped by plugin)
- **Columns** = actions: `☐ (bulk)` | `Resource` | `view` | `manage` | `configure` | `custom`
- Checkboxes only visible where the resource declares that action
- Bulk checkbox per row toggles all actions for that resource
- Group header row per plugin with "select all" for the entire plugin

```
┌──────┬─────────────────────┬──────┬────────┬───────────┬─────────┐
│  ☐   │ Resource            │ view │ manage │ configure │ custom  │
├──────┼─────────────────────┼──────┼────────┼───────────┼─────────┤
│      │ ── Core ──────────  │      │        │           │         │
│ [x]  │ Users               │ [x]  │ [x]    │    —      │    —    │
│ [x]  │ Invoices            │ [x]  │ [x]    │    —      │    —    │
│ [ ]  │ Analytics           │ [ ]  │   —    │    —      │    —    │
│ [ ]  │ Settings            │ [ ]  │ [ ]    │   [ ]     │    —    │
│      │                     │      │        │           │         │
│      │ ── Shop ──────────  │      │        │           │         │
│ [x]  │ Products            │ [x]  │ [x]    │    —      │    —    │
│ [x]  │ Orders              │ [x]  │ [x]    │    —      │    —    │
│ [ ]  │ Stock               │  —   │ [ ]    │    —      │    —    │
│ [ ]  │ Categories          │  —   │ [ ]    │    —      │    —    │
│ [ ]  │ Warehouses          │  —   │ [ ]    │    —      │    —    │
│ [ ]  │ Shop Settings       │  —   │  —     │   [ ]     │    —    │
│      │                     │      │        │           │         │
│      │ ── CMS ───────────  │      │        │           │         │
│ [x]  │ Pages               │ [x]  │ [x]    │    —      │    —    │
│ [x]  │ Images              │ [x]  │ [x]    │    —      │    —    │
│ ...  │                     │      │        │           │         │
└──────┴─────────────────────┴──────┴────────┴───────────┴─────────┘
```

---

## Data Transformation

The backend returns permissions as flat list:
```json
{"key": "shop.products.view", "label": "View products", "group": "Shop"}
{"key": "shop.products.manage", "label": "Manage products", "group": "Shop"}
{"key": "shop.configure", "label": "Shop settings", "group": "Shop"}
```

Frontend transforms into table structure:
```typescript
interface PermissionRow {
  resource: string;        // "products", "orders", "analytics"
  group: string;           // "Shop", "Core", "CMS"
  label: string;           // "Products", "Orders"
  permissions: {
    view?: string;         // "shop.products.view" or undefined
    manage?: string;       // "shop.products.manage" or undefined
    configure?: string;    // "shop.configure" or undefined
    custom?: string[];     // any permissions not matching view/manage/configure
  };
}
```

Parsing logic: split permission key by `.`:
- `shop.products.view` → group="Shop", resource="products", action="view"
- `shop.configure` → group="Shop", resource="shop", action="configure"
- `analytics.view` → group="Core", resource="analytics", action="view"
- `settings.system` → group="Core", resource="settings", action="system" (custom column)

---

## Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | Custom permissions | **(C) Separate section** below the table for special permissions (e.g., `settings.system`) |
| 2 | Group header checkbox | **(B) Toggle view + manage only** (not configure — more sensitive) |
| 3 | Row bulk checkbox | **(A) Toggle view + manage** for that resource (not configure) |

---

## Sub-Steps

| # | What |
|---|------|
| 1 | Create `buildPermissionTable()` utility — transforms flat permissions into PermissionRow[] |
| 2 | Create `PermissionMatrixTable.vue` component — table with group headers, action columns |
| 3 | Replace checkbox grid in `AccessLevelForm.vue` with PermissionMatrixTable |
| 4 | Add group-level "select all" rows |
| 5 | Add row-level bulk checkbox |
| 6 | Style: sticky header, zebra stripes, responsive |
| 7 | Unit tests for buildPermissionTable |
| 8 | `pre-commit-check.sh --full` (fe-admin) |

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **DRY** | Single `buildPermissionTable()` function for parsing |
| **Clean Code** | Table component is self-contained, receives permissions + selected set |
| **No over-engineering** | Start with view/manage/configure columns. Custom column if needed. |
