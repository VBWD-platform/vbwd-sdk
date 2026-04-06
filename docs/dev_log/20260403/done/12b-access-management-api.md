# Sprint 12b — Backend: Access Management API

**Status:** Pending
**Date:** 2026-04-03
**Principles:** TDD · SOLID · DI · Liskov · DRY · Clean Code · No over-engineering
**Parent:** [12 — Admin Access Levels](12-admin-access-levels.md)

---

## Goal

Admin CRUD API for roles (access levels), permission listing, user-role assignment, and export/import.

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | `GET /api/v1/admin/access/levels` — list all roles with permissions | Route tests |
| 2 | `POST /api/v1/admin/access/levels` — create role | Route tests |
| 3 | `GET /api/v1/admin/access/levels/<id>` — role detail with users | Route tests |
| 4 | `PUT /api/v1/admin/access/levels/<id>` — update role + permissions | Route tests |
| 5 | `DELETE /api/v1/admin/access/levels/<id>` — delete (non-system only) | Route tests |
| 6 | `GET /api/v1/admin/access/permissions` — list all available permissions (core + plugins) | Route tests |
| 7 | `GET /api/v1/admin/access/levels/<id>/users` — users with this role | Route tests |
| 8 | `POST /api/v1/admin/users/<id>/roles` — assign role to user | Route tests |
| 9 | `DELETE /api/v1/admin/users/<id>/roles/<role_id>` — revoke role | Route tests |
| 10 | `POST /api/v1/admin/access/export` — export roles + permissions as JSON | Route tests |
| 11 | `POST /api/v1/admin/access/import` — import roles + permissions from JSON | Route tests |
| 12 | All routes protected with `@require_permission('settings.system')` | Auth tests |
| 13 | `pre-commit-check.sh --full` | — |

---

## Permission Listing Endpoint

`GET /api/v1/admin/access/permissions` returns all available permissions grouped by source:

```json
{
  "permissions": {
    "core": [
      {"key": "users.view", "label": "View users", "group": "Users"},
      {"key": "users.manage", "label": "Manage users", "group": "Users"},
      {"key": "invoices.view", "label": "View invoices", "group": "Invoices"},
      {"key": "settings.system", "label": "System settings (dangerous)", "group": "Settings"}
    ],
    "shop": [
      {"key": "shop.products.view", "label": "View products", "group": "Shop"},
      {"key": "shop.products.manage", "label": "Manage products", "group": "Shop"},
      {"key": "shop.configure", "label": "Shop settings", "group": "Shop"}
    ],
    "cms": [...],
    "booking": [...]
  }
}
```

Core permissions are hardcoded. Plugin permissions come from `plugin.admin_permissions`.

---

## Export/Import Format

```json
{
  "version": 1,
  "roles": [
    {
      "slug": "content-manager",
      "name": "Content Manager",
      "description": "...",
      "is_system": false,
      "is_admin": true,
      "permissions": ["cms.pages.view", "cms.pages.manage", "cms.images.manage"]
    }
  ]
}
```

Import: upsert by slug. System roles are not overwritten.

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
```
