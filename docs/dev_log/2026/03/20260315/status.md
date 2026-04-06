# Dev Log Status — 2026-03-15

## Completed Today

### Sprint 10 — Developer Docs (Phase C) ✅
- `vbwd-backend/docs/developer/` — 11 plugin docs (analytics, chat, cms, demoplugin, email, ghrm, mailchimp, paypal, stripe, taro, yookassa)
- `vbwd-fe-user/docs/developer/` — 10 plugin docs (chat, checkout, cms, ghrm, landing1, paypal-payment, stripe-payment, taro, theme-switcher, yookassa-payment)
- `vbwd-fe-admin/docs/developer/` — 5 plugin docs (analytics-widget, cms-admin, email-admin, ghrm-admin, taro-admin)
- Sprint 10 Phases A, B, D pending user consent (GitHub org, repo transfers, plugin repos)

### Email Plugin Bug Fixes ✅
- `payment_handler.py`: emit `invoice.paid` + `subscription.activated` to EventBus after payment capture
- `event_contexts.py`: added 4 missing event type schemas (subscription.expired, invoice.created, invoice.paid, contact_form.received) — 8→12 total
- `EmailTemplateEdit.vue` + new `CodeEditor.vue`: CodeMirror 6 syntax highlighting for HTML/text template editors
- Report: `docs/dev_log/20260315/reports/11-email-bugs-fix-report.md`

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
| 10 Developer Docs (Phase C) | — | ✅ |
| Email Bug Fixes | — | ✅ |
| **Total new** | **134** | |

---

## Sprints

| # | Sprint | Status |
|---|--------|--------|
| 07 | `sprints/done/07-ghrm-breadcrumb-widgets.md` | ✅ Done |
| 08 | `sprints/done/08-cms-routing-rules.md` | ✅ Done |
| 09 | `sprints/done/09-plugin-event-bus.md` | ✅ Done |
| 10 | `sprints/10-vbwd-org-and-plugin-repos.md` | ✅ Done (D5 link-from-READMEs pending) |

---

### Sprint 10 — Post-Sprint Updates ✅
- `recipes/dev-install-ce.sh`: all repo URLs updated `dantweb` → `VBWD-platform`
- `vbwd-backend/README.md`, `vbwd-fe-user/README.md`, `vbwd-fe-admin/README.md`: `dantweb` git clone URLs → `VBWD-platform`
- D5: plugin directory tables added to all 3 monorepo READMEs (links to 25 VBWD-platform plugin repos)
- `plugins/ghrm/src/bin/populate_ghrm.py`: VBWD-platform plugin entries use correct `github_owner` + `github_repo` names
- `vbwd-sdk` transferred to VBWD-platform org
- GitHub Actions: fe-user/fe-admin pick up updated `.gitmodules` automatically; no workflow changes needed
- Sprint 10 report: `reports/12-sprint-10-github-org-report.md`
