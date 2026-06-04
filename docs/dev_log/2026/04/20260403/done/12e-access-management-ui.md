# Sprint 12e — Frontend: Access Management UI

**Status:** Pending
**Date:** 2026-04-03
**Principles:** TDD · SOLID · DI · Liskov · DRY · Clean Code · No over-engineering
**Parent:** [12 — Admin Access Levels](12-admin-access-levels.md)

---

## Goal

Admin Settings → Access section with two sub-tabs: Access Levels and Access Rules. CRUD for roles, permission matrix editor, user-role assignment, export/import.

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Add "Access" section to admin Settings routes | — |
| 2 | Create `AccessLevels.vue` — list roles with user count, create/edit/delete | Unit tests |
| 3 | Create `AccessLevelForm.vue` — name, slug, description, permission matrix | Unit tests |
| 4 | Permission matrix: grouped checkboxes by plugin, toggle all per group | Unit tests |
| 5 | Create `AccessUserRoles.vue` — list users, assign/revoke roles per user | Unit tests |
| 6 | Export button — downloads roles + permissions as JSON | — |
| 7 | Import button — uploads JSON, upserts roles | — |
| 8 | Update `UserDetails.vue` (admin) — show assigned roles, add/remove role | — |
| 9 | i18n: all labels in 8 languages | — |
| 10 | `pre-commit-check.sh --full` (fe-admin) | — |

---

## Permission Matrix UI

```
┌──────────────────────────────────────────────────────┐
│ Role: Content Manager                                 │
├──────────────────────────────────────────────────────┤
│                        view    manage   configure     │
│ ── Core ─────────────────────────────────────────    │
│ Users                  [x]      [ ]       —          │
│ Invoices               [x]      [ ]       —          │
│ Settings               [ ]      [ ]       —          │
│ Analytics              [x]       —        —          │
│                                                       │
│ ── CMS ──────────────────────────────────────────    │
│ Pages                  [x]      [x]       —          │
│ Images                 [x]      [x]       —          │
│ Widgets                [x]      [x]       —          │
│ CMS Settings            —        —       [ ]         │
│                                                       │
│ ── Shop ─────────────────────────────────────────    │
│ Products               [ ]      [ ]       —          │
│ Orders                 [ ]      [ ]       —          │
│ ...                                                   │
└──────────────────────────────────────────────────────┘
```

Checkboxes grouped by plugin. Each row = resource. Columns = actions (view, manage, configure). "—" means not applicable.

---

## Pre-commit Validation

```bash
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
```
