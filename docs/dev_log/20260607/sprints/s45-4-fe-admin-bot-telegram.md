# Sprint 45.4 — fe-admin companion (`bot-telegram` management) — D5

**Parent:** [S45 umbrella](s45-bot-base-bridge.md) · **Depends on:** [45.1 bot-telegram](s45-1-bot-telegram-adapter.md) (+ [45.0](s45-0-bot-base-foundation.md) for linked-accounts). · **Repo:** `fe-admin-bot-telegram` ([[feedback_plugins_always_in_own_repos]]). · **Only fe-admin companion in the family** — meinchat/base need none (umbrella §Admin / configuration surfaces).

## Engineering requirements (BINDING)
**TDD-first** · **DevOps-first** · **SOLID** · **DRY** · **NO OVERENGINEERING**. Full readable names ([[feedback_variable_naming]]). Generic UI styles via `var(--vbwd-*)` from fe-core; entity navigation = canonical detail views, never inline modals ([[feedback_entity_navigation]]). **Gate:** fe-admin `npm run lint` + unit (Vitest) + e2e (Playwright) green. e2e: navigate by URL, seed both `admin_token` + `admin_token_user` (see [[project_fe_admin_e2e_auth_harness]] / [[project_fe_admin_navbar_e2e_helper_rot]]).

## Scope

> **✅ D5 LOCKED — ship the fe-admin trio this sprint.** Build once `bot-base` + `bot-telegram` (45.0–45.1) are green.

- **Bot CRUD** — list/create/edit/delete Telegram bots. Token **shown masked** (`1234****`), set only on create/rotate (write-only field); never rendered back. Backed by `bot-telegram` `/admin/bots` (D4).
- **Set webhook** — calls `POST /admin/bots/<id>/set-webhook`.
- **Send test message** — calls `POST /admin/bots/<id>/test`; surfaces success/`429`/error.
- **Linked-accounts view** — external id ↔ vbwd user, backed by **`bot-base`** generic `GET /admin/links` (so it already covers future providers, not just Telegram).
- The user-side "Connect" deep-link button (D3) belongs in **fe-user** and is a **separate follow-up** (not here).

## TDD plan (tests FIRST)
- Unit (Vitest): bot list/form stores; token field is write-only and never populated from the API; masked display; test-send + set-webhook actions dispatch the right calls and handle error/`429`.
- e2e (Playwright): create a bot (token masked after save) → set webhook → send test → see result; open linked-accounts and see a seeded link row. Navigate by URL; auth seeded per the harness notes above.

## Gate
fe-admin lint + unit + e2e green; token never leaves the server unmasked; linked-accounts reads `bot-base` `/admin/links`.
