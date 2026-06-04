# Sprint 18 — Access-Level-Driven Content Visibility

**Status:** Planned
**Date:** 2026-04-07
**Depends on:** Sprint 17 (User Access Levels — complete)
**Principles:** TDD-first · SOLID · Core agnostic · Server-side filtering · No over-engineering

---

## Summary

Admin can configure which widgets, buttons, pages, and navigation items are visible to each user access level — both in the **dashboard** (authenticated area) and on **public CMS pages** (including anonymous visitors). The server pre-filters content so restricted items never reach the client.

---

## Decisions

| Question | Answer |
|----------|--------|
| Anonymous visitors | Treated as implicit "new" access level |
| Filtering approach | Server-side: API pre-filters widgets before response |
| Where admin configures visibility | CMS layout editor (per-widget) + Access Level form (overview) |
| Dashboard widgets | Plugin-registered widgets declare `requiredUserPermission`; dashboard filters |
| Navigation menu | Sidebar items filtered by user permission (already done in Sprint 17e) |
| CMS page-level restriction | Optional: page can require an access level to view at all |
| Widget visibility default | "Everyone" — no restriction unless admin explicitly sets one |
| Multiple levels per widget | Multi-select: widget visible if user has ANY of the selected levels |

---

## Architecture

```
ADMIN configures:
  CMS Layout Editor → per-widget "Visible to" multi-select
  Access Level Form → overview of what each level can see

SERVER filters:
  GET /api/v1/cms/layouts/<id>
    → Load layout with assignments
    → For each CmsLayoutWidget:
        if required_access_level_ids is empty → include (everyone)
        else → include only if user has ANY of the required levels
    → Return filtered assignments

  GET /api/v1/cms/pages/<slug>
    → If page has required_access_level_ids → check user levels → 403 if denied
    → Load layout → filter widgets (as above)
    → Return page with filtered content

FRONTEND renders:
  CmsLayoutRenderer → renders only what the API returned
  Dashboard.vue → filters plugin widgets by requiredUserPermission
  Sidebar → already filtered by requiredUserPermission (Sprint 17e)
```

---

## Data Model Changes

### New column on `cms_layout_widget`

```
cms_layout_widget (existing join table)
  + required_access_level_ids  JSON  DEFAULT '[]'
    -- Array of vbwd_user_access_level UUIDs
    -- Empty = visible to everyone
    -- Non-empty = visible if user has ANY of these levels
```

### New column on `cms_page`

```
cms_page (existing)
  + required_access_level_ids  JSON  DEFAULT '[]'
    -- Empty = public page (everyone can view)
    -- Non-empty = restricted to users with ANY of these levels
```

### No new tables needed

Widget visibility is a property of the widget-in-layout assignment, not of the widget itself. The same widget can be unrestricted in one layout and restricted in another.

---

## Implementation Sub-Sprints

### 18a — Backend: Model + Migration + Server-Side Filtering

- Add `required_access_level_ids` (JSON, default `[]`) to `CmsLayoutWidget` model
- Add `required_access_level_ids` (JSON, default `[]`) to `CmsPage` model
- Alembic migration for both columns
- Update `GET /api/v1/cms/layouts/<id>` to filter assignments:
  - Determine user's access levels from JWT (or "new" for anonymous)
  - Filter out assignments where user lacks required level
- Update `GET /api/v1/cms/pages/<slug>` to check page-level restriction:
  - If `required_access_level_ids` is non-empty and user lacks any → return 403
- Update `PUT /api/v1/admin/cms/layouts/<id>/widgets` to accept `required_access_level_ids` per assignment
- Unit tests: filtered vs unfiltered responses for different user levels

### 18b — Admin: CMS Layout Editor "Visible to" Dropdown

- In `CmsLayoutEditor.vue`, add a multi-select "Visible to" dropdown per widget assignment
- Dropdown options: "Everyone" (default) + all user access levels from `/admin/access/user-levels`
- When saving assignments, include `required_access_level_ids` array
- In `CmsPageEditor.vue`, add a multi-select "Page visible to" field
- Options: "Everyone" (default) + all user access levels
- Save as `required_access_level_ids` on the page

### 18c — Admin: Access Level Form — Visibility Overview

- On the User Access Level edit form (`/admin/settings/access/:id?type=user`), add a read-only section:
  "Content visible to this level"
- List all CMS pages restricted to this level
- List all widget assignments restricted to this level
- Backend endpoint: `GET /admin/access/user-levels/:id/content` returns pages + widgets assigned to this level

### 18d — Frontend: Dashboard Widget Filtering

- `Dashboard.vue` in fe-user: filter `dashboardWidgets` by `requiredUserPermission`
- Each plugin registers dashboard widgets with `requiredUserPermission` metadata
- Already partially done: `sdk.addComponent('DashboardXxx', component)` — need to add permission metadata
- Add `hasUserPermission()` check before rendering each dashboard widget
- Dashboard cards (Profile, Tokens, Invoices) conditionally rendered based on permissions

### 18e — Frontend: Public CMS Widget Visibility

- No frontend changes needed for widget filtering (server pre-filters)
- Handle 403 response from page endpoint gracefully:
  - If user is anonymous → show "Login to view this page" prompt
  - If user is logged in but lacks level → show "Upgrade your plan" message
- Test: anonymous user sees fewer widgets than subscribed user on same page

### 18f — Frontend: Navigation Menu Filtering

- CMS menu widgets: filter menu items by `required_access_level_ids` (server-side)
- Add `required_access_level_ids` to `CmsMenuItem` model (optional)
- Menu API pre-filters items based on user's access levels
- Dashboard sidebar already filtered (Sprint 17e) — verify no gaps

### 18g — Tests + Pre-commit

- Backend unit tests: widget filtering for anonymous, logged-in, subscribed users
- Backend unit tests: page-level access restriction
- Playwright E2E: same CMS page shows different widgets for different users
- `pre-commit-check.sh --full` for all modules

---

## Detailed Flows

### Anonymous User Visits CMS Page

```
Browser → GET /api/v1/cms/pages/about-us
  → No JWT token → user_access_levels = ["new"] (implicit)
  → Page has no required_access_level_ids → allowed
  → Load layout → filter assignments:
      Widget "Company Info"     → required: []         → INCLUDE (everyone)
      Widget "Direct Phone"     → required: [logged-in] → EXCLUDE
      Widget "VIP Contact Form" → required: [pro]       → EXCLUDE
  → Return page with 1 widget (Company Info)
```

### Logged-In User Visits Same Page

```
Browser → GET /api/v1/cms/pages/about-us (JWT: user with "logged-in" level)
  → user_access_levels = ["logged-in"]
  → Page allowed
  → Load layout → filter assignments:
      Widget "Company Info"     → required: []         → INCLUDE
      Widget "Direct Phone"     → required: [logged-in] → INCLUDE ✓
      Widget "VIP Contact Form" → required: [pro]       → EXCLUDE
  → Return page with 2 widgets (Company Info + Direct Phone)
```

### Pro User Visits Same Page

```
Browser → GET /api/v1/cms/pages/about-us (JWT: user with "subscribed-pro" level)
  → user_access_levels = ["subscribed-pro"]
  → All 3 widgets visible
```

### Dashboard Widget Filtering

```
Dashboard.vue renders:
  Profile Card          → no permission required → SHOW
  Token Activity        → requiredUserPermission: "subscription.tokens.view" → check
  Recent Invoices       → requiredUserPermission: "subscription.invoices.view" → check
  Plugin Widget "Taro"  → requiredUserPermission: "taro.access" → check
```

---

## CMS Layout Editor UI

```
┌─────────────────────────────────────────┐
│  Layout: Default Page                    │
│                                          │
│  Area: header                            │
│  ┌─────────────────────────────────────┐ │
│  │ Widget: Main Menu                    │ │
│  │ Visible to: [Everyone         ▼]    │ │
│  └─────────────────────────────────────┘ │
│                                          │
│  Area: sidebar                           │
│  ┌─────────────────────────────────────┐ │
│  │ Widget: Direct Phone Number          │ │
│  │ Visible to: [Logged In, Basic, Pro▼] │ │
│  └─────────────────────────────────────┘ │
│  ┌─────────────────────────────────────┐ │
│  │ Widget: VIP Contact Form             │ │
│  │ Visible to: [Subscribed Pro    ▼]    │ │
│  └─────────────────────────────────────┘ │
│                                          │
│  Area: footer                            │
│  ┌─────────────────────────────────────┐ │
│  │ Widget: Footer Links                 │ │
│  │ Visible to: [Everyone         ▼]    │ │
│  └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

---

## Access Level Form — Visibility Overview

```
┌─────────────────────────────────────────────┐
│ Edit: Subscribed Basic                       │
│                                              │
│ [Name] [Slug] [Description] [Linked Plan]   │
│                                              │
│ ── Permissions ──                            │
│ [Permission Matrix]                          │
│                                              │
│ ── Visible Content ──                        │
│                                              │
│ Pages restricted to this level:              │
│   • Members Area (/members)                  │
│   • Premium Resources (/resources)           │
│                                              │
│ Widgets visible to this level:               │
│   • Direct Phone Number (sidebar, About Us)  │
│   • Booking Calendar (main, Services)        │
│                                              │
│ ── Assigned Users (3) ──                     │
│ [User list]                                  │
└─────────────────────────────────────────────┘
```

---

## Not in Scope

- Per-content-block access levels (TipTap content within a page area — too granular)
- Time-limited visibility (e.g., "visible for 7 days after signup")
- A/B testing based on access levels
- Widget-level analytics (impressions per access level)
- Drag-and-drop access level assignment (admin manually assigns via dropdown)
