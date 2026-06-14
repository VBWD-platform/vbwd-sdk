# S68 — CMS widget admin bugs: menu-item export + widget deletion

**Plugin:** `cms` · **Depends on:** core data-exchange framework (exists), S46 CMS exchangers (exist) · **Relates to:** S61 (`booking_resources` is the precedent for carrying a relation through `BaseModelExchanger`)
**Engineering requirements:** TDD-first, SOLID/DI/DRY/Liskov, no overengineering;
`bin/pre-commit-check.sh --plugin cms --full` green = done. See `_unified-import-export-overview.md`
and `docs/dev_log/20260526/sprints/_engineering-requirements.md`.

Two independent CMS widget-admin defects, both small, fixed in one pass.

---

## Bug A — Menu widget export drops its items

### Problem
Exporting a **menu** widget through the unified Import/Export (Settings → Import/Export, the
`cms_widgets` entity) yields a widget with **no menu items** — `config` and `content_json` are
`null` and the actual links are gone:

```json
{"cms_widgets":[{"config":null,"content_json":null,"is_active":true,"name":"Header Navigation",
"slug":"header-nav","sort_order":0,"source_css":null,"widget_type":"menu"}],
"exported_at":"…","format":"json","instance":"default","vbwd_export":"cms_widgets","version":1}
```

…even though the widget has items in the admin (Home/`home1`, Features/`features`, About/`about`,
Software/`/category`, Create an appointment/`booking`, with nesting via **+ Child**).

**Root cause.** Menu items do **not** live in `cms_widget.config`/`content_json`; they live in a
**separate table** `cms_menu_item` (`plugins/cms/src/models/cms_menu_item.py`: `widget_id` FK,
self-referential `parent_id`, `label`, `url`, `page_slug`, `target`, `icon`, `sort_order`). The
unified `cms_widgets` exchanger is a plain `_CmsModelExchanger` whose `public_fields` are only the
scalar widget columns (`plugins/cms/src/services/data_exchange/cms_exchangers.py`):

```python
_CmsModelExchanger(entity_key="cms_widgets", model_class=CmsWidget, natural_key="slug",
    public_fields=["slug","name","widget_type","content_json","source_css","config",
                   "sort_order","is_active"], …)
```

`BaseModelExchanger` serialises only `public_fields`, so the related `cms_menu_item` rows are never
queried → exported menu widgets are structurally empty, and **import is equally lossy** (no
`menu_items` consumed). The bespoke per-widget path is already correct and shows the intended shape:
`CmsWidgetService.export_widget()` attaches `data["menu_items"] = [i.to_dict() …]` for
`widget_type == "menu"`, and `import_widget()` → `CmsMenuItemRepository.replace_tree()` restores the
tree (two-pass `parent_id` remap from placeholder ids). The unified path must reach parity.

### Scope
Replace the plain `_CmsModelExchanger` registration for `cms_widgets` with a thin subclass
`_CmsWidgetsExchanger(BaseModelExchanger)` in
`plugins/cms/src/services/data_exchange/cms_exchangers.py` (mirror the S61 `booking_resources`
subclass that carries `availability` + the category link):

1. **Export** — after the base scalar serialisation, when `row.widget_type == "menu"` attach
   `menu_items = [i.to_dict() for i in CmsMenuItemRepository(session).find_tree_by_widget(str(row.id))]`.
   Item dicts **must include `id` and `parent_id`** (placeholder ids) so the import two-pass remap
   works — `CmsMenuItem.to_dict()` already emits them (same payload the bespoke `export_widget` uses).
   Non-menu widgets are unchanged (no `menu_items` key); `config`/`content_json` still export as-is
   for the types that use them (`vue-component`, `html`).
2. **Import** — after the base upsert resolves/creates the widget by `slug`, if the payload carries
   `menu_items` **and** the widget is `widget_type == "menu"`, call
   `CmsMenuItemRepository(session).replace_tree(str(widget.id), payload["menu_items"])` (already
   idempotent + remaps `parent_id`, so re-import does not duplicate). Skip cleanly when absent/empty.
3. **DI** — build `CmsMenuItemRepository(session)` from the `session` the exchanger already holds; no
   new ports, no `BaseModelExchanger` change.
4. **Legacy path (note, fix-if-cheap):** `cms_import_export_service.py` widgets export
   (`[w.to_dict() …]`) has the same omission. Unified S46 is canonical (the bug is the unified path).
   Bring legacy to parity only if it's a one-line reuse; otherwise leave a `# S68` TODO — no scope creep.

---

## Bug B — Widget deletion fails (500s / can't delete in-use widgets)

### Problem
Deleting a widget often fails. Three tables reference `cms_widget.id` with **`ondelete="RESTRICT"`**:
`cms_layout_widget`, `cms_page_widget`, `cms_post_widget` (only `cms_menu_item` is `CASCADE`). The
delete path mishandles this:

- `CmsWidgetService.delete_widget()` guards **only** against **layout** assignments
  (`_lw_repo.find_by_widget` → `CmsWidgetInUseError` → 409). A widget used by a **page or post** (but
  not a layout) passes the guard, then `repo.delete()` → `session.delete()` hits the RESTRICT FK →
  uncaught `IntegrityError` → **500** (and a poisoned session).
- `CmsWidgetService.bulk_delete()` → `repo.bulk_delete()` runs a raw `query(...).delete()` with **no
  guard** → RESTRICT FK → **500**.
- Nav widgets (`header-nav`/`footer-nav`) are always layout-assigned, so single-delete **always**
  refuses them (409) with no way to remove them → "deletion doesn't work".

### Scope (`cms_widget_service.py`, `cms_widget_repository.py`, `routes.py`)
Make deletion **predictable and possible**, never a 500:

1. **Complete the in-use check** — detect assignments across **all three** reference tables
   (layout + page + post), not just layouts. Default delete of an in-use widget returns a clear
   **409** listing where it's used (counts per kind). One helper `widget_usage(widget_id) -> {layouts,
   pages, posts}` reused by single + bulk.
2. **Allow intentional deletion via `?force=true`** on `DELETE /api/v1/admin/cms/widgets/<id>` (and the
   bulk endpoint): in one transaction, **detach** the widget — delete its `cms_layout_widget`,
   `cms_page_widget`, `cms_post_widget` rows (`cms_menu_item` already cascades) — then delete the
   widget row. Detaching just un-places the widget, which is the expected meaning of deleting it.
3. **Harden `bulk_delete`** — per-id apply the same guard/force logic; return per-id results
   (`deleted` vs `blocked` with reason). No raw multi-row `DELETE` into a FK error.
4. **Backstop** — wrap the actual delete in `try/except IntegrityError` → `rollback()` → raise
   `CmsWidgetInUseError` (→ 409). No delete path may 500 or leave the session poisoned.
5. **No schema change.** Keep `RESTRICT` (it's the safety net); deletion correctness lives in the
   service. (Rejected: flipping the FKs to `CASCADE` — it would silently strip widgets from layouts on
   any delete and removes the guard; overengineered/destructive vs. the explicit `force` path.)

---

## TDD (tests first) — `plugins/cms/tests/…`
**Bug A:**
- Export of a menu widget with nested items includes `menu_items` (every label/`url`/`page_slug`/
  `target`/`sort_order` + correct `parent_id`); a non-menu widget exports **no** `menu_items` and
  keeps `config`/`content_json`.
- Round-trip (export → import into a clean session) reconstructs the tree faithfully (labels, order,
  parent/child, `page_slug`/`url`); re-import is idempotent (no duplicate `cms_menu_item` rows); a
  payload without `menu_items` imports the widget with no menu rows and no error.

**Bug B:**
- Deleting an **unused** widget succeeds (200).
- Deleting an **in-use** widget (layout / page / post) without force → **409** with usage info (no
  500, session usable afterwards); page-assigned and post-assigned cases both covered (regression for
  the layout-only guard).
- `force=true` detaches and deletes: the widget and its `cms_layout_widget`/`cms_page_widget`/
  `cms_post_widget` rows are gone, the layout/page/post still exist, `cms_menu_item` rows cascade away.
- `bulk_delete` mixes used + unused ids → unused deleted, used reported blocked (or force-deleted with
  `force=true`); never 500.

## Definition of done
Exporting `cms_widgets` carries the full menu tree for menu widgets and import restores it (symmetric
with the bespoke path); widget deletion never 500s — it succeeds when unused, returns a clear 409 with
usage when in use, and removes an in-use widget on `force=true` (single + bulk); non-menu widgets,
scalar fields, and the DB schema are unchanged; reuses `find_tree_by_widget`/`replace_tree`;
`bin/pre-commit-check.sh --plugin cms --full` green. Not committed ([[feedback_no_commit_without_ask]]).