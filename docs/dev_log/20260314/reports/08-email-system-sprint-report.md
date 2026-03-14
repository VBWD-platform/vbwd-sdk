# Sprint Report: Email System — Transactional Email Plugin

**Date:** 2026-03-14
**Sprint:** `done/05-email-system.md`
**Pre-commit result:** `./bin/pre-commit-check.sh --full` → **ALL PASSED** (Black ✓ Flake8 ✓ Mypy ✓ | 1121 unit tests ✓ | 82 integration tests ✓)

---

## What Was Done

### Step 1 — Backend `email` plugin

**Model:**
- **`plugins/email/src/models/email_template.py`** — `EmailTemplate(BaseModel)`: `slug` (unique), `name`, `event_type` (indexed), `subject`, `html_body`, `text_body`, `is_active`

**Sender interface (ISP):**
- **`plugins/email/src/services/base_sender.py`** — `IEmailSender` (ABC with `send(message)` + `sender_id` property), `EmailMessage` dataclass

**Sender registry (DI):**
- **`plugins/email/src/services/sender_registry.py`** — `EmailSenderRegistry.register()`, `.get(sender_id)`, `.available()` → `list[str]`

**SMTP sender:**
- **`plugins/email/src/services/smtp_sender.py`** — `SmtpEmailSender(IEmailSender)`: reads `smtp_host/port/user/password/use_tls` from settings service; sends via `smtplib.SMTP` with `MIMEMultipart("alternative")` (HTML + plain text parts)

**Email service:**
- **`plugins/email/src/services/email_service.py`** — `EmailService.send_for_event(event_type, to, event)`:
  - Queries most-recently-updated active template for the event type
  - Resolves variable context via `EVENT_CONTEXTS`
  - Renders subject/html/text via Jinja2 (`undefined=Undefined` → unknown vars → empty string)
  - Resolves active sender from settings (`email_active_sender`, default `"smtp"`)
  - Logs if `email_log_enabled` is True
  - Silent skip if no active template

**Variable context system:**
- **`plugins/email/src/services/event_contexts.py`** — `EventContext` protocol, `EVENT_CONTEXTS` dict, `register_context()`. Built-in contexts for 8 event types:
  `subscription.created`, `payment.captured`, `payment.failed`, `dunning.day3`, `dunning.day7`, `subscription.cancelled`, `subscription.expired`, `trial.expiring`

**Event handlers:**
- **`plugins/email/src/handlers.py`** — one handler class per event type, each calls `email_service.send_for_event(...)`. Registered in plugin `on_enable()`.

**Admin API routes (`/api/v1/admin/email/`):**
- `GET /templates` — list all
- `POST /templates` — create
- `GET /templates/<id>` — fetch one
- `PUT /templates/<id>` — update
- `DELETE /templates/<id>` — delete
- `POST /templates/preview` — render template with provided context, returns `{subject, html_body, text_body}`
- `GET /event-types` — variable schemas per event type
- `GET /senders` — registered sender IDs from registry

**Seeds:**
- **`plugins/email/src/seeds.py`** — `seed_default_templates()` — idempotent, creates one minimal template per event type if table is empty; called from `on_enable()`.

**Migration:**
- **`alembic/versions/20260314_create_email_template_table.py`** — creates `email_template` table with all columns and index on `event_type`

---

### Step 2 — Backend `mailchimp` plugin (Mandrill transport demo)

- **`plugins/mailchimp/src/services/mandrill_sender.py`** — `MandrillEmailSender(IEmailSender)`:
  - `sender_id = "mailchimp"`
  - Reads `mailchimp_mandrill_api_key` from settings; raises `ValueError` if missing
  - Posts to Mandrill `POST /messages/send.json` via `httpx` with `timeout=10`
  - `resp.raise_for_status()` propagates HTTP errors
- Plugin `on_enable()` registers sender: `sdk.register_email_sender(MandrillEmailSender(settings_service))`

---

### Step 3 — fe-admin `email-admin` plugin

- **`plugins/email-admin/src/views/EmailTemplateList.vue`** — table of all templates; active toggle (inline PUT), delete, link to edit
- **`plugins/email-admin/src/views/EmailTemplateEdit.vue`** — 3-tab editor (HTML / Plain Text / Preview):
  - Preview tab: `POST /admin/email/templates/preview` with current content + event sample context
  - Variables panel: rendered from `GET /admin/email/event-types`; variable names shown as `{{ name }}` via `v-text` (avoids Vue compiler mis-parse of `{{` inside text interpolation)
  - Active toggle + subject field in header
  - Test-send input: `POST /admin/email/test-send`
- **`plugins/email-admin/src/stores/useEmailStore.ts`** — `fetchTemplates`, `fetchTemplate`, `saveTemplate`, `fetchEventTypes`, `renderPreview`, `sendTest`; uses `@/api` alias (corrected from wrong relative path)

---

### Step 4 — fe-admin navigation

- "Messaging → Email Templates" group added to fe-admin sidebar via `extensionRegistry`
- Route: `/admin/email/templates` → `EmailTemplateList`, `/admin/email/templates/:id` → `EmailTemplateEdit`

---

### Step 5 — Mailpit local email testing service

- **`docker-compose.yaml`** — added `mailpit` service (`axllent/mailpit`): SMTP port `${PORT_MAILPIT_SMTP}:1025`, web UI `${PORT_MAILPIT_WEBUI}:8025`
- **`.env.example`** — added `PORT_MAILPIT_SMTP=1025`, `PORT_MAILPIT_WEBUI=8025`, dev SMTP defaults pointing to Mailpit

---

### Additional fix (post-Sprint 05): fe-admin build failures

Resolved TypeScript / Vite build errors introduced by the email-admin plugin:

| File | Error | Fix |
|------|-------|-----|
| `plugins/email-admin/src/stores/useEmailStore.ts` | `Cannot find module '../../../vue/src/api/index'` | Changed to `@/api` alias |
| `plugins/email-admin/src/stores/useEmailStore.ts` | `Property 'data' does not exist on type 'EmailTemplate[]'` (×5) | Removed `.data` accesses — `api.get<T>()` returns `T` directly |
| `plugins/email-admin/tests/unit/emailAdminPlugin.spec.ts` | TS2722: `Cannot invoke object which is possibly 'undefined'` | Changed `plugin.install(...)` → `plugin.install!(...)` |
| `plugins/email-admin/tests/unit/EmailTemplateList.spec.ts` | TS2352: wrong mock cast | Changed to `vi.mocked(useEmailStore).mockReturnValue(store as never)` |
| `plugins/email-admin/src/views/EmailTemplateEdit.vue` | Vite: "Unterminated string constant" on `{{ '{{ ' + name + ' }}' }}` | Changed to `v-text="'{{ ' + name + ' }}'"` |
| `vitest.config.js` | `@` alias pointed to non-existent `./src` | Fixed to `./vue/src` |
| `vitest.config.js` | `setupFiles` pointed to non-existent `./tests/setup.ts` | Fixed to `./vue/tests/setup.ts` |
| `vitest.config.js` | `include` only covered `vue/tests/unit/**` | Added `vue/tests/integration/**`, `plugins/*/tests/unit/**`, `plugins/*/tests/integration/**` |
| `bin/pre-commit-check.sh` | `run_unit()` ran `npx vitest run vue/tests/unit/` (missed plugin tests) | Added `plugins/` arg |
| `bin/reset-database.sh` (backend) | `alembic upgrade head` fails with multiple heads | Changed to `alembic upgrade heads` |

---

## Tests Added

| File | Tests | Coverage |
|------|-------|----------|
| `plugins/email/tests/unit/services/test_email_service.py` | 7 | `send_for_event`: active template sends, inactive → skip, no template → skip, unknown var → empty string, log flag on/off, sender resolved from settings |
| `plugins/email/tests/unit/services/test_sender_registry.py` | 8 | register, get, available, overwrite, get-missing raises |
| `plugins/email/tests/unit/services/test_smtp_sender.py` | 8 | mock `smtplib.SMTP`: correct MIME parts, TLS branch, login branch, from_address fallback |
| `plugins/email/tests/integration/test_email_routes.py` | 28 | list/create/get/update/delete/toggle, preview renders, event-types schema, auth required, migration schema (`email_template` table + columns) |
| `plugins/email-admin/tests/unit/emailAdminPlugin.spec.ts` | — | plugin exports install/activate/deactivate, pluginLoader contract |
| `plugins/email-admin/tests/unit/EmailTemplateList.spec.ts` | — | list renders templates, toggle calls store, delete calls store |

---

## Pre-commit Verification

```
./bin/pre-commit-check.sh --quick  → PASS (lint ✓ | 1121 unit tests ✓)
./bin/pre-commit-check.sh --full   → PASS (lint ✓ | 1121 unit ✓ | 82 integration ✓)
```

fe-admin:
```
cd vbwd-fe-admin
./bin/pre-commit-check.sh --unit   → PASS (ESLint ✓ TypeScript ✓ | unit tests ✓)
```

---

## Deferred

| Item | Reason |
|------|--------|
| Settings tab "Integrations → Email" (SMTP config in UI) | Settings page redesign tracked separately |
| `plugins/mailchimp/tests/` | Mandrill sender unit tests straightforward but deferred to avoid scope creep |
| CodeMirror editor (syntax highlighting) | Plain `<textarea>` shipped instead; CodeMirror upgrade tracked separately |
