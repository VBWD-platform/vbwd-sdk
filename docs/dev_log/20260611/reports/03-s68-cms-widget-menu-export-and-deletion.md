# Report 03 — S68: CMS widget admin bugs fixed (menu-item export + widget deletion)

**Date:** 2026-06-11 · **Sprint:** [S68](../../20260610/done/s68-cms-widget-menu-export.md) · **Repo:** `vbwd-backend` (`plugins/cms` only — plugin code is gitignored, changes live on disk)
**Gate:** `bin/pre-commit-check.sh --plugin cms --full` → **GREEN** (Part A lint · Part B unit **548 passed** · Part C integration **160 passed**). TDD-first: 27 RED on the new test set before implementation. **Not committed** per standing instruction.

---

## Bug A — unified `cms_widgets` export now carries the menu tree

**Was:** exporting a menu widget through the unified S46 Import/Export produced a structurally
empty widget (`config`/`content_json` null, no links) because the registered exchanger was a plain
`_CmsModelExchanger` serialising only scalar columns — menu items live in the separate
`cms_menu_item` table. Import was equally lossy.

**Fix** (`plugins/cms/src/services/data_exchange/cms_exchangers.py`): the `cms_widgets`
registration is now a thin subclass `_CmsWidgetsExchanger`, mirroring the S61 `booking_resources`
precedent for carrying a relation through `BaseModelExchanger`:

- **Export** — when `widget_type == "menu"`, attaches
  `menu_items = [item.to_dict() …]` from `CmsMenuItemRepository.find_tree_by_widget`; item dicts
  keep `id`/`parent_id` so the import two-pass remap works. Non-menu widgets are unchanged.
- **Import** — strips `menu_items` before the base upsert-by-slug, then calls
  `CmsMenuItemRepository(session).replace_tree(widget.id, menu_items)` (idempotent, remaps
  `parent_id`). Skipped on dry-run, absent/empty payload, or non-menu type.
- No new ports, no `BaseModelExchanger` change; the repo is built from the session the exchanger
  already holds. The unified path is now symmetric with the bespoke
  `CmsWidgetService.export_widget()`/`import_widget()` path.
- Legacy `cms_import_export_service.py` widgets export was **not** a one-line reuse (no menu-item
  repo wired there) → left a `# S68 TODO` per the sprint's no-scope-creep rule.

## Bug B — widget deletion never 500s, force-delete possible

**Was:** three tables FK-reference `cms_widget.id` with `ondelete=RESTRICT`
(`cms_layout_widget`, `cms_page_widget`, `cms_post_widget`) but `delete_widget()` guarded only
layouts → page/post-assigned widgets hit an uncaught `IntegrityError` → **500** + poisoned
session; `bulk_delete()` had no guard at all; nav widgets could never be deleted (always 409).

**Fix** (`cms_widget_repository.py`, `cms_widget_service.py`, `routes.py`):

1. `widget_usage(widget_id) -> {layouts, pages, posts}` in the repository (single
   `_ASSIGNMENT_MODELS` map of the three RESTRICT join tables), reused by single + bulk delete.
2. In-use without force → **409** `CmsWidgetInUseError` carrying the `usage` counts (route body
   includes `"usage"`).
3. **`?force=true`** on `DELETE /api/v1/admin/cms/widgets/<id>` (and `force` in the bulk JSON
   body / query): one transaction deletes the three kinds of join rows, then the widget;
   `cms_menu_item` cascades. Layout/page/post rows themselves survive.
4. `bulk_delete(ids, force)` applies the per-id guard/force logic and returns per-id results
   (`deleted` vs `blocked` + reason/usage) — no raw multi-row `DELETE`.
5. Backstop: the actual delete is wrapped in `try/except IntegrityError → rollback() →
   CmsWidgetInUseError` — no delete path 500s or leaves the session poisoned.
6. **No schema change** — RESTRICT stays as the safety net.

Cleanup: the now-dead `layout_widget_repo` constructor dependency of `CmsWidgetService` was
removed (its layout-only guard is replaced by `widget_usage`).

## Tests added

- `tests/integration/test_cms_exchangers.py` — `TestWidgetsMenuItemsRoundTrip` (5): nested
  export with full fields + correct `parent_id`; non-menu widget untouched; round-trip
  reconstructs the tree; re-import idempotent; payload without `menu_items` imports cleanly.
- `tests/unit/services/test_cms_widget_service.py` — delete/bulk rewritten (11): layout/page/post
  conflict cases (page/post = the regression), usage on the error, force detach, IntegrityError
  backstop, bulk mixed/force/not-found.
- `tests/integration/test_cms_widget_delete_routes.py` (new, 8): unused→200; each in-use kind→409
  with usage + session usable afterwards; force detaches+deletes; 404; bulk mixed + bulk force.
