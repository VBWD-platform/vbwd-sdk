# Report 11 — Email Plugin Bug Fixes

**Date:** 2026-03-16
**Scope:** `vbwd-backend` · `vbwd-fe-admin/plugins/email-admin`
**Status:** Fixed

---

## Summary

Four related bugs in the email plugin were identified and fixed:

1. Emails never sent after checkout / payment completion
2. Several event types not selectable in the template editor
3. No variable hints shown for affected event types
4. No syntax highlighting in the HTML/text template editors

---

## Bug 1 — Emails Not Sent After Payment Capture

### Root Cause

`PaymentCapturedHandler` (`src/handlers/payment_handler.py`) processes invoice payment, activates subscriptions, credits tokens, and activates add-ons — but **never published any event to the `EventBus`**. The email plugin subscribes to bus events (`invoice.paid`, `subscription.activated`, etc.) via `register_handlers()`, so no emails were ever triggered.

### Fix

`payment_handler.py` — after all line items are processed:

1. Added `user_repository` to `_get_services()` so the handler can load the user's email address from `invoice.user_id`.
2. After successful processing, publish to the `EventBus`:
   - Always: `invoice.paid` with `user_name`, `user_email`, `invoice_id`, `amount`, `paid_date`, `invoice_url`
   - Conditionally (when a subscription was activated): `subscription.activated` with `user_name`, `user_email`, `plan_name`, `plan_price`, `billing_period`, `start_date`, `next_billing_date`, `dashboard_url`

```python
from src.events.bus import event_bus

user = repos["user"].find_by_id(invoice.user_id)
user_email = user.email if user else ""

event_bus.publish("invoice.paid", { ... })

if items_activated["subscription"]:
    sub = repos["subscription"].find_by_id(items_activated["subscription"])
    if sub and sub.tarif_plan:
        event_bus.publish("subscription.activated", { ... })
```

---

## Bug 2 — Cannot Select Correct Event Type in Template Editor

### Root Cause

`plugins/email/src/services/event_contexts.py` defined only 8 event types in `EVENT_CONTEXTS`. Four event types had active email handlers registered in `handlers.py` but **no corresponding schema** in the contexts dict. The API endpoint `/api/v1/admin/email/event-types` calls `EventContextRegistry.get_all()`, which is populated at import time from `EVENT_CONTEXTS`, so the 4 types were silently absent from the dropdown.

**Missing types:**
| Event type | Handler |
|---|---|
| `subscription.expired` | `on_subscription_expired` |
| `invoice.created` | `on_invoice_created` |
| `invoice.paid` | `on_invoice_paid` |
| `contact_form.received` | `on_contact_form_received` |

### Fix

Added all 4 missing entries to `EVENT_CONTEXTS` in `event_contexts.py` with full variable schemas (`type`, `description`, `example` per variable). They are auto-registered into `EventContextRegistry` at module import via the existing loop at the bottom of the file.

---

## Bug 3 — No Variable Hints for Affected Templates

### Root Cause

Same as Bug 2. `EmailTemplateEdit.vue` computes `eventInfo` as:

```ts
const eventInfo = computed(() =>
  store.eventTypes.find(e => e.event_type === form.value.event_type)
)
```

The "Available Variables" card renders `v-if="eventInfo"`. When a template's `event_type` was one of the 4 missing types, `eventInfo` resolved to `undefined` and the variables table was hidden entirely.

### Fix

Resolved by adding the missing schemas (Bug 2 fix). No frontend code change required.

---

## Bug 4 — No Syntax Highlighting in Template Editor

### Root Cause

The HTML and plain-text template fields were plain `<textarea>` elements styled with a dark background but no syntax highlighting. CodeMirror 6 packages were already installed in `vbwd-fe-admin/package.json`:

```json
"codemirror": "^6.0.2",
"@codemirror/lang-html": "^6.4.11",
"@codemirror/theme-one-dark": "^6.1.3"
```

They were unused.

### Fix

**New file:** `plugins/email-admin/src/components/CodeEditor.vue`

A minimal Vue 3 wrapper around CodeMirror 6 (`EditorView`) that:
- Accepts `modelValue` / emits `update:modelValue` (v-model compatible)
- Accepts `language` prop (`'html'` | `'text'`) — applies `@codemirror/lang-html` for HTML tab
- Uses `oneDark` theme
- Syncs external `modelValue` changes (e.g. when switching templates) without feedback loops via `ignoreUpdate` flag
- Cleans up `EditorView` on `onBeforeUnmount`

**Updated:** `EmailTemplateEdit.vue` — replaced both `<textarea>` elements with `<CodeEditor>`:

```vue
<!-- HTML tab -->
<CodeEditor v-model="form.html_body" language="html" />

<!-- Plain text tab -->
<CodeEditor v-model="form.text_body" language="text" />
```

---

## Files Changed

| File | Change |
|---|---|
| `vbwd-backend/src/handlers/payment_handler.py` | Added `user_repository` to services; publish `invoice.paid` + `subscription.activated` to EventBus |
| `vbwd-backend/plugins/email/src/services/event_contexts.py` | Added 4 missing event type schemas (8 → 12 total) |
| `vbwd-fe-admin/plugins/email-admin/src/components/CodeEditor.vue` | New — CodeMirror 6 editor component |
| `vbwd-fe-admin/plugins/email-admin/src/views/EmailTemplateEdit.vue` | Import `CodeEditor`; replace textarea elements |

---

## Remaining Notes

- `user_name` in bus event payloads currently falls back to `user.email` (the User model stores only `email`; personal details live in `UserDetails` for GDPR). If a display name is needed in emails, the handler can be extended to load `UserDetails`.
- The `invoice.created` event context was added but the corresponding bus event (`invoice.created`) is not yet published anywhere in the core. A separate task is needed to emit it when invoices are created in `CheckoutHandler` or `InvoiceService`.
