# Dev Log Status — 2026-03-15

## Completed Today

### Frontend Responsive UX ✅
- Admin burger menu matching fe-user pattern
- fe-user all pages smartphone-vertical-ready (Subscription, Invoices, InvoiceDetail, Plans, TarifPlanDetail)
- InvoiceDetail line items: table → mobile card layout
- Admin Plans table: scrollable with min-width
- i18n: `invoices.detail.itemsTableHeaders.type` + `plans.selectPlan` in 8 locales
- TarifPlanDetail: ← Back button + Select Plan → checkout route
- Design docs: fe-core/docs/styling.md, fe-user/docs/styling.md, fe-admin/docs/styling.md

### Sprint 09 — Plugin Event Bus ✅ (43 new tests)
- `EventBus` singleton pub/sub (`src/events/bus.py`) — `subscribe`, `unsubscribe`, `publish`, `has_subscribers`
- `DomainEventDispatcher.emit()` bridges to `event_bus.publish()` so plugins receive all domain events
- `BasePlugin.register_event_handlers(bus)` lifecycle hook called by `PluginManager` after `on_enable()`
- `EventContextRegistry` — open schema registry; any plugin can register email template schemas
- Fixed broken `from src.events import event_dispatcher` in email + GHRM plugins
- Docs updated: `docs/dev_docs/event-bus.md` (new), `developer-guide.md`, `plugin-bundles.md`

### Sprint 07 — GHRM Breadcrumb Widgets ✅ (42 new tests)
- Backend: `GET /api/v1/ghrm/widgets` (public) + `GET/PUT /api/v1/admin/ghrm/widgets/<id>` — stored in `plugins/ghrm/widgets.json`
- fe-user: `GhrmBreadcrumb.vue` — separator, root label/slug, show_category, max_label_length, CSS injection; injected into `GhrmCatalogueContent.vue` and `GhrmPackageDetail.vue`
- fe-admin: `GhrmBreadcrumbWidgetConfig.vue` (3-tab: General/CSS/Preview), `GhrmBreadcrumbPreview.vue`, `GhrmWidgets.vue` admin page at `/admin/ghrm/widgets`

### Sprint 08 — CMS Routing Rules ✅ (49 new tests)
- Backend: `CmsRoutingRule` model + migration, `CmsRoutingRuleRepository`, 6 matcher classes (`Default/Language/IpRange/Country/PathPrefix/Cookie`), `NginxConfGenerator`, `SubprocessNginxReloadGateway` + `StubNginxReloadGateway`, `CmsRoutingService` (CRUD + evaluate + sync_nginx), `CmsRoutingMiddleware` (before_request, skips `/api/`, `/admin/`, `/uploads/`, `/_vbwd/`)
- 7 new API endpoints: `GET/POST /api/v1/admin/cms/routing-rules`, `GET/PUT/DELETE /api/v1/admin/cms/routing-rules/<id>`, `POST /api/v1/admin/cms/routing-rules/reload`, `GET /api/v1/cms/routing-rules` (public)
- fe-admin: `routingRules` Pinia store, `RoutingRules.vue` list + layer filter + "Apply & Reload Nginx" button, `RoutingRuleForm.vue` modal with contextual match-value placeholders; route `/admin/cms/routing-rules` + sidebar nav link
- fe-user: `useLocale.ts` composable — cookie read/write + browser lang detection

---

## Sprint Summary

| Sprint | Tests Added | Pre-commit |
|--------|-------------|------------|
| Responsive UX | — | ✅ |
| 09 Plugin Event Bus | 43 | ✅ |
| 07 GHRM Breadcrumb Widgets | 42 | ✅ |
| 08 CMS Routing Rules | 49 | ✅ |
| **Total new** | **134** | |

---

## Sprints

| # | Sprint | Status |
|---|--------|--------|
| 07 | `sprints/done/07-ghrm-breadcrumb-widgets.md` | ✅ Done |
| 08 | `sprints/done/08-cms-routing-rules.md` | ✅ Done |
| 09 | `sprints/done/09-plugin-event-bus.md` | ✅ Done |
| 10 | `sprints/10-vbwd-org-and-plugin-repos.md` | ⏳ Requires user consent |

---

## Next Up

**Sprint 10 — GitHub Org + Plugin Repos**

- **Phase C** — developer docs in `docs/developer/` for all 26 plugins (no GitHub access needed)
- **Phase A** — create VBWD GitHub organisation → **requires explicit user consent**
- **Phase B** — transfer repos to org → **requires explicit user consent**
- **Phase D** — create plugin repos → **requires explicit user consent**
