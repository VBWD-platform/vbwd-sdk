# Sprint 60 — contact form → meinchat (optional, bot-sender)

**Status:** DRAFT for negotiation — 2026-06-07.
**Repos touched:** `vbwd-backend` (core: new `BOT` role + migration; `meinchat` plugin: event handler + bot provisioning + posting; `cms` plugin: extend the contact-form event payload) · `vbwd-fe-admin` (`cms-admin`: contact-form widget config fields). No fe-user change (recipients use the existing `/dashboard/messages`).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core stays agnostic** (core gains only a *generic* `BOT` role — it knows nothing of contact forms or meinchat; all integration logic lives in the `meinchat` plugin) · **NO OVERENGINEERING** · optional integration (works whether or not meinchat is installed) · test/demo data through services ([[feedback_no_direct_db_for_test_data]]) · plugin migrations in the plugin, **core migration for the core enum** ([[feedback_plugin_migrations_in_plugin]], [[feedback_migrations_only]]). Gate: `bin/pre-commit-check.sh --plugin meinchat --full` + `--plugin cms --full` + core green; fe-admin `lint && test`.

---

## 1. Goal

When a CMS **contact-form** widget is submitted, deliver the submission into **meinchat** (if installed) as a message from a per-form **bot sender** to an admin-defined recipient list, so each recipient sees it in fe-user **`/dashboard/messages`**. Each contact form has its own sender identity, so recipients can tell which form a message came from.

## 2. Locked decisions (2026-06-07)

- **Sender = a real account per form.** Admin sets the sender's **email** + **nickname** in the contact-form widget config. The account is created (idempotently) with **default password `useruser`** and the new **`BOT` role**. Its meinchat nickname = the configured nickname, so messages show as `@<nickname>`.
- **New `BOT` role.** Add `BOT` to the `UserRole` enum (`SUPER_ADMIN, ADMIN, USER, VENDOR` → `+ BOT`). Bot accounts are **non-privileged** (not admin; minimal rights) and identifiable for security.
- **BOT accounts cannot log in (LOCKED 2026-06-07).** Block interactive login for `role == BOT` (they share the weak `useruser` password and only need to author meinchat messages server-side). Enforce in the auth/login path: a BOT account → login rejected (same generic "invalid credentials" response, no role leak).
- **Recipients** = admin-defined list, default `["@admin"]`. Resolution (proposed; flag if you want it changed): **`@admin` → the platform admin-role user(s)**; any other handle → meinchat nickname via `find_by_nickname_ci`; unresolvable handles are **skipped + logged** (never error the submission).
- **Optional / dependency-inverted.** meinchat subscribes to the existing `contact_form.received` event (the email plugin already does). No hard dependency either way; if meinchat is absent the contact form is unchanged.

## 3. Context (verified)

- **The contact form already emits the event.** `cms/src/routes.py:451-507` (`POST /api/v1/contact`) loads the widget config and `event_bus.publish("contact_form.received", payload)` (`:503`); `email` plugin subscribes (`plugins/email/__init__.py`). Payload today: `{widget_slug, recipient_email, fields[], remote_ip}`.
- **meinchat needs real user UUIDs.** `Conversation` is a real user pair (`participant_low_id`/`high_id`); `Message.sender_id` is a non-null FK to `vbwd_user.id` + `sender_nickname` (fetched from `NicknameRepository.find_by_user_id`). `MessageService.send_text(conversation_id, *, sender_user_id, body)` (`message_service.py:149`). There is **no** native virtual sender → the bot must be a real user. `NicknameRepository` has both `find_by_user_id` and **`find_by_nickname_ci`** (handle→user) — used for recipient + sender-nickname resolution.
- **Roles:** `UserRole` enum at `vbwd/models/enums.py:36`, stored as a **native Postgres enum** on `user.role` (`vbwd/models/user.py:31`). `is_admin` only covers SUPER_ADMIN/ADMIN (`user.py:79`) — BOT is non-admin by construction. `UserService` creates users with role + bcrypt password (min length 8 — `useruser` is 8) (`user_service.py:137-171`).
- **Event-handler pattern:** plugins implement `register_event_handlers(event_bus)` and `event_bus.subscribe(...)` (e.g. `booking/__init__.py:160`).

## 4. Design

### 4.1 Core — `BOT` role (agnostic)
- Add `BOT = "BOT"` to `UserRole` (`enums.py`). Keep it out of every admin/privilege check (it already is).
- **Core migration** `ALTER TYPE userrole ADD VALUE IF NOT EXISTS 'BOT'` (Postgres native enum; must run standalone — a *core* migration, not plugin-anchored). Note: `ADD VALUE` can't run inside a transaction on older PG — use the autocommit/`COMMIT` pattern Alembic needs.

### 4.2 cms — extend the event payload (small)
- In the `/api/v1/contact` route, include the widget's meinchat settings in the published payload (the route already has the config in hand): add `payload["meinchat"] = {enabled, sender_email, sender_nickname, recipients}` (read from the widget `config`). meinchat then reads everything from the event — **no cms↔meinchat repo coupling**. Also pass the source domain/page (`remote_ip` already there; add `source_url`/`host` if available) for the message body.

### 4.3 meinchat — the integration (gnostic)
New handler module `meinchat/meinchat/handlers/contact_form_handler.py`, wired in `meinchat`'s `register_event_handlers` → `bus.subscribe("contact_form.received", ...)`. On event, **only if** `payload.get("meinchat", {}).get("enabled")`:
1. **Provision the bot sender** (`BotSenderProvisioner`, idempotent): find user by `sender_email`. If found and `role == BOT` → reuse; if found and **not** BOT → log + abort (never hijack a real account). If absent → create via core `UserService` with `role="BOT"`, `password="useruser"`, the email; then ensure a `UserNickname` = `sender_nickname` (meinchat's own repo). All through services (no raw SQL).
2. **Resolve recipients:** for each handle in `recipients` (default `["@admin"]`): `@admin` → admin-role user(s) (core user repo by role); else `find_by_nickname_ci(handle)`. Collect distinct recipient user_ids; skip + log unresolved.
3. **Deliver:** for each recipient_id: `ensure_conversation(bot_user_id, recipient_id)` (the existing find-or-create pair logic), then `MessageService.send_text(conversation_id, sender_user_id=bot_user_id, body=<formatted submission>)`. Body = a readable summary of the form fields (name / email / message / custom fields) + the source page/domain.
4. **Resilience:** the whole handler is best-effort and wrapped so a meinchat failure never breaks the contact-form POST (the email handler + the HTTP 200 are independent). Log warnings on any skip/failure.

DI: register the provisioner/handler in `meinchat` `on_enable`/`register_event_handlers`, resolving the core `UserService` + meinchat services from the container.

### 4.4 fe-admin — widget config (`ContactFormEditorTab.vue`)
Add a **"meinchat delivery"** section: `meinchat_enabled` (toggle), `meinchat_sender_email`, `meinchat_sender_nickname`, `meinchat_recipients` (list of handles, default `["@admin"]`). Stored in the widget `config_json` (existing mechanism). i18n + validation (email shape, nickname non-empty when enabled).

### 4.5 Deliberately NOT built (NO OVERENGINEERING)
- No two-way replies (the bot sender is a no-reply identity; a recipient reply lands in a conversation no human reads — documented, not solved here).
- No new meinchat message type — a plain `send_text` body (renders naturally in the inbox).
- No eager bot-account creation at widget-save (lazy, idempotent, on first submission).
- meinchat declares **no** hard dependency on cms; the bridge is the event only.

## 5. Security
- **BOT accounts are non-privileged AND cannot log in (LOCKED):** never admin; the login path rejects `role == BOT` (generic invalid-credentials, no role disclosure). The default `useruser` password is weak by design but inert — a BOT cannot authenticate and has no privileged rights. Test the login-block explicitly.
- **No account hijack:** provisioning only reuses an existing account if it is already `BOT`; a non-BOT email match aborts with a log, never repurposes a real user.
- Submission body is the already-sanitized contact-form fields (`ContactFormService` sanitizes); no raw HTML into meinchat.

## 6. TDD plan (RED first)
- **Core:** `UserRole.BOT` exists; migration up/down/up adds the enum value; a BOT user is non-admin (`is_admin` False).
- **meinchat (unit, mocked repos/services):** provisioner creates a BOT user + nickname when absent; reuses when present-and-BOT; aborts on present-and-not-BOT; recipient resolver (`@admin`→admin role, nickname→user, unresolved→skipped); handler posts one message per resolved recipient via `send_text` with the bot as sender; disabled config / meinchat-absent → no-op; handler never raises.
- **cms:** the `/contact` route includes the `meinchat` block in the published payload when the widget config has it.
- **Integration (`db`):** end-to-end — publish `contact_form.received` → bot user+nickname created → conversation(s) created → message visible to the recipient. Contact-form POST still returns 200 when meinchat errors.
- **fe-admin (Vitest):** the meinchat config fields render/save; recipients default to `["@admin"]`.

## 7. Files (indicative)
| Action | Path |
|---|---|
| edit | `vbwd-backend/vbwd/models/enums.py` — `UserRole.BOT` |
| new | `vbwd-backend/alembic/versions/<core>_add_bot_role.py` — `ALTER TYPE userrole ADD VALUE 'BOT'` |
| edit | `vbwd-backend/plugins/cms/src/routes.py` — add `meinchat` block to the event payload |
| new | `vbwd-backend/plugins/meinchat/meinchat/handlers/contact_form_handler.py` |
| new | `vbwd-backend/plugins/meinchat/meinchat/services/bot_sender_provisioner.py` |
| edit | `vbwd-backend/plugins/meinchat/__init__.py` — `register_event_handlers` subscribe |
| edit | `vbwd-backend/plugins/meinchat/...` + `plugins/cms/...` tests |
| edit | `vbwd-fe-admin/plugins/cms-admin/src/widgets/ContactFormEditorTab.vue` — meinchat config section |

## 8. Acceptance
- With meinchat installed + a contact form configured (`meinchat_enabled`, sender email/nickname, recipients), submitting the form creates a message from `@<nickname>` to each resolved recipient, visible in their `/dashboard/messages`. A second submission reuses the same bot user/conversation.
- The sender account exists as a real user with role **BOT** (non-admin), password `useruser`, the configured email + nickname.
- `@admin` default resolves to the platform admin; unresolved recipients are skipped (logged), submission still succeeds (HTTP 200).
- With meinchat **disabled/absent**, the contact form behaves exactly as today (email path unaffected).
- Gates green (core + `--plugin cms` + `--plugin meinchat`; fe-admin lint+test).

## 9. Open question for you
- **Recipient `@admin`** resolution: confirm "@admin → admin-role user" (my default, proceeding) vs "must be a literal meinchat nickname".
- *(BOT login — RESOLVED 2026-06-07: blocked, see §2/§5.)*
