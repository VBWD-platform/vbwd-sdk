# Report — Access Level Security Hardening

**Date:** 2026-04-06
**Status:** Complete

---

## Problem

ADMIN users with limited access levels (e.g., CMS editor only) could:
1. Call any admin API endpoint (users, invoices, payment methods, etc.)
2. See all sidebar nav items regardless of permissions
3. Delete/update resources they only had view permission for

## Root Causes

1. **Backend**: All 73 core admin routes and 188 plugin routes used only `@require_admin` — no `@require_permission`
2. **Frontend routes**: Core admin routes had no `meta.requiredPermission`
3. **Frontend sidebar**: Core nav items had no `requiredPermission`; plugin nav items had it but `extensionRegistry._insertItem()` stripped it during copy
4. **Frontend buttons**: No plugin view had `v-if="canManage"` permission guards on destructive buttons

## Fix Summary

| Layer | What | Count |
|-------|------|-------|
| Backend core routes | Added `@require_permission` | 73 routes |
| Backend plugin routes | Added `@require_permission` | 188 routes |
| Frontend core routes | Added `meta.requiredPermission` | 15 routes |
| Frontend plugin routes | Already had `meta.requiredPermission` | 55 routes |
| Frontend sidebar | Added `requiredPermission` to core nav items | 5 items |
| Frontend sidebar bug | Fixed `_insertItem()` to preserve `requiredPermission` | 1 bug |
| Frontend edit pages | Changed from `manage` to `view` permission | 10 routes |
| Frontend button guards | Added `v-if="canManage"` | 29 view files |

**Total: 261 backend routes + 70 frontend routes + 29 view files secured**

## View vs Manage Pattern

Edit/detail pages now require `view` permission to open. Save/Delete buttons are hidden without `manage` permission. Backend enforces the same: GET → `view`, PUT/DELETE → `manage`.

This means a CMS editor with `cms.pages.view` can:
- Open the page list
- Click into any page and read its full content
- See the preview link

But CANNOT:
- See Save/Publish/Delete buttons
- Call PUT/DELETE API endpoints (403)
- Create new pages
- Import pages
