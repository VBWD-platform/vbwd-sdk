# Sprint: Email System

**Date:** 2026-03-14
**Scope:** `vbwd-backend` (email plugin + Mailchimp demo plugin) + `vbwd-fe-admin` (template editor + settings tab)

> **Status:** AWAITING FINAL APPROVAL — do not begin implementation until approved.

## Core Requirements

TDD-first (tests written before implementation), SOLID (especially ISP for sender interface, OCP for new senders), DRY, Liskov Substitution (every `IEmailSender` implementation is drop-in replaceable), clean code, no overengineering. Since the platform is pre-release, deprecated patterns must not be introduced — refactoring existing code requires explicit approval before execution.

## What we are building

A pluggable transactional email system:

- **Backend `email` plugin** — template storage, variable context per event type, SMTP sender, admin API
- **Backend `mailchimp` plugin** — demo transport-only sender (Mandrill API) as a reference for developers
- **fe-admin `email-admin` plugin** — CodeMirror HTML editor, text-only editor, live preview, active/inactive toggle
- **fe-admin settings extension** — new "Integrations → Email" tab (SMTP config, log flag, active sender)

## Core Requirements

TDD, SOLID (ISP for sender interface), DI, DRY, DevOps First, clean code, no overengineering.

---

## Architecture

### Sender interface (ISP)

```python
# plugins/email/src/services/base_sender.py
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

@dataclass
class EmailMessage:
    to: str
    subject: str
    html_body: str
    text_body: str
    from_address: Optional[str] = None

class IEmailSender(ABC):
    @abstractmethod
    def send(self, message: EmailMessage) -> None: ...

    @property
    @abstractmethod
    def sender_id(self) -> str: ...  # e.g. "smtp", "mailchimp"
```

### Sender registry (DI)

```python
# plugins/email/src/services/sender_registry.py
class EmailSenderRegistry:
    _senders: dict[str, IEmailSender] = {}

    def register(self, sender: IEmailSender) -> None:
        self._senders[sender.sender_id] = sender

    def get(self, sender_id: str) -> IEmailSender:
        return self._senders[sender_id]

    def available(self) -> list[str]:
        return list(self._senders.keys())
```

Plugins call `sdk.register_email_sender(MyCustomSender())` to register their sender. `EmailService` resolves the active sender by reading `active_sender_id` from admin settings.

### Variable context system (code-defined per event)

Each event type declares exactly what variables it exposes. Template authors see a reference panel in the editor; unknown variables render as empty string.

```python
# plugins/email/src/services/event_contexts.py
from typing import Protocol

class EventContext(Protocol):
    def get_context(self, event) -> dict: ...

EVENT_CONTEXTS: dict[str, EventContext] = {}  # populated at plugin init

def register_context(event_type: str, ctx: EventContext):
    EVENT_CONTEXTS[event_type] = ctx
```

Built-in contexts declared at plugin init:

| Event type | Available variables |
|------------|-------------------|
| `subscription.created` | `user.name`, `user.email`, `plan.name`, `plan.price`, `subscription.expires_at` |
| `payment.captured` | `user.name`, `user.email`, `invoice.amount`, `invoice.currency`, `plan.name` |
| `payment.failed` | `user.name`, `user.email`, `invoice.amount`, `plan.name`, `support_url` |
| `dunning.day3` | `user.name`, `user.email`, `invoice.amount`, `plan.name`, `support_url` |
| `dunning.day7` | `user.name`, `user.email`, `invoice.amount`, `plan.name`, `cancel_date` |
| `subscription.cancelled` | `user.name`, `user.email`, `plan.name`, `cancelled_at`, `grace_until` |
| `subscription.expired` | `user.name`, `user.email`, `plan.name`, `upgrade_url` |
| `trial.expiring` | `user.name`, `user.email`, `plan.name`, `trial_ends_at`, `upgrade_url` |

---

## Step 1 — Backend `email` plugin

### 1a. `EmailTemplate` model

**File:** `plugins/email/src/models/email_template.py`

```python
class EmailTemplate(BaseModel):
    __tablename__ = "email_template"

    slug        = db.Column(db.String(128), unique=True, nullable=False)
    name        = db.Column(db.String(256), nullable=False)
    event_type  = db.Column(db.String(64),  nullable=False, index=True)
    subject     = db.Column(db.String(512), nullable=False)
    html_body   = db.Column(db.Text, nullable=False)
    text_body   = db.Column(db.Text, nullable=False)
    is_active   = db.Column(db.Boolean, default=True, nullable=False)

    def to_dict(self):
        return {
            "id":         str(self.id),
            "slug":       self.slug,
            "name":       self.name,
            "event_type": self.event_type,
            "subject":    self.subject,
            "html_body":  self.html_body,
            "text_body":  self.text_body,
            "is_active":  self.is_active,
            "updated_at": self.updated_at.isoformat(),
        }
```

### 1b. `EmailService`

**File:** `plugins/email/src/services/email_service.py`

```python
class EmailService:
    def __init__(self, registry: EmailSenderRegistry, settings_service):
        self._registry = registry
        self._settings = settings_service

    def send_for_event(self, event_type: str, to: str, event) -> None:
        template = (
            EmailTemplate.query
            .filter_by(event_type=event_type, is_active=True)
            .order_by(EmailTemplate.updated_at.desc())
            .first()
        )
        if not template:
            return   # no active template — silent skip

        ctx  = EVENT_CONTEXTS.get(event_type)
        vars = ctx.get_context(event) if ctx else {}
        msg  = EmailMessage(
            to=to,
            subject=self._render(template.subject, vars),
            html_body=self._render(template.html_body, vars),
            text_body=self._render(template.text_body, vars),
            from_address=self._settings.get("email_from_address"),
        )

        sender_id = self._settings.get("email_active_sender", "smtp")
        sender    = self._registry.get(sender_id)

        if self._settings.get("email_log_enabled", False):
            logger.info("[Email] sending %s → %s via %s", event_type, to, sender_id)

        sender.send(msg)

    def _render(self, template_str: str, ctx: dict) -> str:
        from jinja2 import Environment, Undefined
        env = Environment(undefined=Undefined)   # unknown vars → empty string
        return env.from_string(template_str).render(**ctx)
```

### 1c. SMTP sender

**File:** `plugins/email/src/services/smtp_sender.py`

```python
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

class SmtpEmailSender(IEmailSender):
    sender_id = "smtp"

    def __init__(self, settings_service):
        self._settings = settings_service

    def send(self, message: EmailMessage) -> None:
        host     = self._settings.get("smtp_host", "localhost")
        port     = int(self._settings.get("smtp_port", 587))
        user     = self._settings.get("smtp_user", "")
        password = self._settings.get("smtp_password", "")
        use_tls  = self._settings.get("smtp_use_tls", True)

        msg = MIMEMultipart("alternative")
        msg["Subject"] = message.subject
        msg["From"]    = message.from_address or user
        msg["To"]      = message.to
        msg.attach(MIMEText(message.text_body, "plain"))
        msg.attach(MIMEText(message.html_body, "html"))

        with smtplib.SMTP(host, port) as smtp:
            if use_tls:
                smtp.starttls()
            if user:
                smtp.login(user, password)
            smtp.sendmail(msg["From"], [message.to], msg.as_string())
```

### 1d. Admin API routes

**File:** `plugins/email/src/routes.py`
**Prefix:** `/api/v1/admin/email`

| Method | Path | Description |
|--------|------|-------------|
| GET | `/templates` | List all templates |
| POST | `/templates` | Create template |
| GET | `/templates/<id>` | Get single template |
| PUT | `/templates/<id>` | Update template |
| DELETE | `/templates/<id>` | Delete template |
| POST | `/templates/<id>/toggle` | Toggle is_active |
| GET | `/event-types` | List all registered event types with their variable schemas |
| POST | `/preview` | Render template with sample data — returns `{subject, html, text}` |

`GET /event-types` returns the variable schema from `EVENT_CONTEXTS`:

```json
[
  {
    "event_type": "payment.failed",
    "variables": ["user.name", "user.email", "invoice.amount", "plan.name", "support_url"]
  }
]
```

### 1e. Event handlers — wire existing events to email

**File:** `plugins/email/src/handlers.py`

```python
class PaymentFailedEmailHandler:
    def handle(self, event: PaymentFailedEvent):
        user = User.query.get(event.user_id)
        email_service.send_for_event("payment.failed", user.email, event)

class SubscriptionCreatedEmailHandler:
    def handle(self, event: SubscriptionCreatedEvent):
        user = User.query.get(event.user_id)
        email_service.send_for_event("subscription.created", user.email, event)

# ... one handler per event type listed in the context table above
```

Register in plugin `on_enable()`:

```python
dispatcher.subscribe(PaymentFailedEvent, PaymentFailedEmailHandler())
dispatcher.subscribe(SubscriptionCreatedEvent, SubscriptionCreatedEmailHandler())
# etc.
```

### 1f. Migration

`alembic/versions/<date>_create_email_template.py` — creates `email_template` table.

### 1g. Seed default templates

`plugins/email/src/seeds.py` — `seed_default_templates()` idempotent function that creates one default template per event type (minimal but functional HTML + text). Called from plugin `on_enable()` if table is empty.

### 1h. Tests

- Unit: `EmailService.send_for_event` — mock sender, assert `send()` called with rendered subject/body
- Unit: inactive template → `send()` not called
- Unit: no template for event → silent skip, no exception
- Unit: `_render()` — unknown variable → empty string (not exception)
- Unit: `SmtpEmailSender.send()` — mock `smtplib.SMTP`, assert correct MIME structure
- Unit: `GET /event-types` → returns all registered contexts with variable lists
- Unit: `POST /preview` → returns rendered subject/html/text with sample context
- Integration: create template via API, update it, toggle active, delete it

---

## Step 2 — Backend `mailchimp` plugin (Mandrill transport demo)

**File:** `plugins/mailchimp/src/services/mandrill_sender.py`

```python
import httpx

class MandrillEmailSender(IEmailSender):
    sender_id = "mailchimp"
    MANDRILL_API = "https://mandrillapp.com/api/1.0"

    def __init__(self, settings_service):
        self._settings = settings_service

    def send(self, message: EmailMessage) -> None:
        api_key = self._settings.get("mailchimp_mandrill_api_key", "")
        if not api_key:
            raise ValueError("mailchimp_mandrill_api_key not configured")

        payload = {
            "key": api_key,
            "message": {
                "subject":    message.subject,
                "html":       message.html_body,
                "text":       message.text_body,
                "from_email": message.from_address,
                "to": [{"email": message.to, "type": "to"}],
            },
        }
        resp = httpx.post(f"{self.MANDRILL_API}/messages/send.json", json=payload, timeout=10)
        resp.raise_for_status()
```

Plugin `on_enable()` registers the sender:

```python
sdk.register_email_sender(MandrillEmailSender(settings_service))
```

Admin settings key needed: `mailchimp_mandrill_api_key` (added to "Integrations → Email" tab).

**Tests:**
- Unit: mock `httpx.post`; assert correct payload shape
- Unit: missing API key → `ValueError` before HTTP call
- Unit: non-2xx response → exception propagated

---

## Step 3 — fe-admin `email-admin` plugin

### 3a. Routes

| Path | View | Description |
|------|------|-------------|
| `/email-templates` | `EmailTemplateList.vue` | Table of all templates with active toggle |
| `/email-templates/new` | `EmailTemplateEdit.vue` | Create new template |
| `/email-templates/:id` | `EmailTemplateEdit.vue` | Edit existing template |

### 3b. `EmailTemplateEdit.vue` — editor layout

```
┌─────────────────────────────────────────────────────┐
│  Event Type: [dropdown]   Name: [input]              │
│  Subject: [input with variable hints]                │
├──────────────┬──────────────────────────────────────┤
│  Variables   │  HTML tab | Preview tab              │
│  panel       │  ─────────────────────────────────── │
│  ─────────── │  [CodeMirror — html mode]             │
│  user.name   │  or                                   │
│  user.email  │  [iframe preview — rendered HTML]     │
│  plan.name   ├──────────────────────────────────────┤
│  ...         │  Text tab | Text preview tab          │
│              │  ─────────────────────────────────── │
│              │  [CodeMirror — plain text mode]       │
│              │  or                                   │
│              │  [<pre> preview]                      │
└──────────────┴──────────────────────────────────────┘
│  [Save]  [Save & activate]  [Cancel]  is_active: ◉  │
└─────────────────────────────────────────────────────┘
```

- HTML preview calls `POST /api/v1/admin/email/preview` with current editor content + event type's sample context
- Variables panel populated from `GET /api/v1/admin/email/event-types` — clicking a variable inserts `{{ var }}` at cursor via CodeMirror API
- CodeMirror packages needed: `@codemirror/lang-html`, `@codemirror/lang-markdown`

### 3c. Store

**File:** `plugins/email-admin/src/stores/useEmailAdminStore.ts`

```typescript
export const useEmailAdminStore = defineStore('email-admin', {
  state: () => ({
    templates: [] as EmailTemplate[],
    eventTypes: [] as EventTypeSchema[],
    loading: false,
    error: null as string | null,
  }),
  actions: {
    async fetchTemplates() { ... },
    async fetchEventTypes() { ... },
    async saveTemplate(data: EmailTemplatePayload) { ... },
    async toggleActive(id: string) { ... },
    async deleteTemplate(id: string) { ... },
    async preview(eventType: string, subject: string, htmlBody: string, textBody: string) { ... },
  },
})
```

---

## Step 4 — fe-admin settings extension: "Integrations → Email" tab

### 4a. Settings page change

Add a second-level tab "Integrations" to the existing Settings view. Inside, an "Email" panel:

```
Integrations
└── Email
    ├── Active sender:         [dropdown: smtp | mailchimp | ...]
    ├── From address:          [input]
    ├── Log emails:            [toggle]  ← writes to app log when on
    │
    ├── ── SMTP (shown when active sender = smtp) ──
    ├── SMTP Host:             [input]
    ├── SMTP Port:             [input, default 587]
    ├── SMTP Username:         [input]
    ├── SMTP Password:         [password input]
    ├── Use TLS:               [toggle]
    │
    └── ── Mailchimp (shown when active sender = mailchimp) ──
        └── Mandrill API Key:  [password input]
```

Settings saved via the existing admin settings API (`PUT /api/v1/admin/settings`).

The "Active sender" dropdown is populated from `GET /api/v1/admin/email/senders` (returns registered sender IDs — `["smtp", "mailchimp"]` depending on enabled plugins).

Add route to email plugin: `GET /api/v1/admin/email/senders` → `registry.available()`.

---

## Step 5 — Mailpit local email testing service

Add Mailpit to `vbwd-backend/docker-compose.yaml` so developers can catch outgoing emails locally without a real SMTP server.

**`docker-compose.yaml` addition:**

```yaml
  mailpit:
    image: axllent/mailpit
    ports:
      - ${PORT_MAILPIT_SMTP}:1025   # SMTP — point SmtpEmailSender here in dev
      - ${PORT_MAILPIT_WEBUI}:8025  # Web UI — http://localhost:<PORT_MAILPIT_WEBUI>
    restart: unless-stopped
```

**`.env.example` additions:**

```
PORT_MAILPIT_SMTP=1025
PORT_MAILPIT_WEBUI=8025
```

**Dev SMTP defaults** (`.env.example` — used when `FLASK_ENV=development`):

```
SMTP_HOST=localhost
SMTP_PORT=1025
SMTP_USER=
SMTP_PASSWORD=
SMTP_USE_TLS=false
SMTP_FROM=noreply@localhost
```

Mailpit accepts any email without authentication and exposes them at `http://localhost:8025`. No changes to production config.

**Makefile target** (optional convenience):

```makefile
mailpit:
	@echo "Mailpit web UI: http://localhost:$$(grep PORT_MAILPIT_WEBUI .env | cut -d= -f2)"
```

---

## Step 6 — Navigation

Add "Email Templates" link to the fe-admin sidebar under a new "Messaging" group (or alongside CMS depending on nav structure).

---

## Verification

```bash
# Backend
cd vbwd-backend
./bin/pre-commit-check.sh              # lint + mypy
./bin/pre-commit-check.sh --quick      # + unit tests
./bin/pre-commit-check.sh              # + integration tests

# fe-admin
cd vbwd-fe-admin
./bin/pre-commit-check.sh --unit
```

All checks must be green. Specifically:

1. `POST /preview` with `event_type=payment.failed`, HTML body `Hello {{ user.name }}`, sample context `{user: {name: "Alice"}}` → returns `Hello Alice`
2. Unknown variable in template → renders as empty string, no 500
3. No active template for event → event fires, no email sent, no exception
4. SMTP send path: mock SMTP, fire `PaymentFailedEvent`, assert `smtplib.SMTP.sendmail` called
5. Mailchimp send path: mock `httpx.post`, fire event with mailchimp as active sender, assert Mandrill endpoint called
6. Log flag off → nothing written to log; flag on → log line written

## Files created (backend)

```
plugins/email/
├── __init__.py
├── config.json
├── README.md
├── src/
│   ├── models/email_template.py
│   ├── services/
│   │   ├── base_sender.py        ← IEmailSender, EmailMessage
│   │   ├── sender_registry.py    ← EmailSenderRegistry
│   │   ├── smtp_sender.py
│   │   ├── email_service.py
│   │   └── event_contexts.py     ← variable schemas + context builders
│   ├── handlers.py               ← event → email wiring
│   ├── routes.py
│   └── seeds.py                  ← default templates
└── tests/
    ├── unit/
    └── integration/

plugins/mailchimp/
├── __init__.py
├── config.json
├── README.md
├── src/services/mandrill_sender.py
└── tests/unit/
```

## Files created (fe-admin)

```
plugins/email-admin/
├── index.ts
├── locales/en.json
├── src/
│   ├── views/
│   │   ├── EmailTemplateList.vue
│   │   └── EmailTemplateEdit.vue   ← CodeMirror + preview
│   └── stores/useEmailAdminStore.ts
└── README.md
```
