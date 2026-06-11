# Sprint 45 — `bot-base` + provider adapters: a provider-neutral bot bridge (umbrella)

**Status:** PLANNED — **D1–D10 decided** (D1–D5 2026-06-02; D6/D7/D9/D10 LOCKED 2026-06-06; D8 PROPOSED → impl in [S53](s53-bot-commerce-storefront.md)).

> **Implementation round — scope confirmed 2026-06-10 (owner):** build **45.0 → 45.5 + S53**, one sub-sprint at a time, each `--plugin … --full` green before the next. **45.6 (Zapier) stays DEFERRED** (no work this round). Pre-implementation clarifications are captured per-sub-sprint in a "## 2026-06-10 clarifications" block.
>
> **Clarifications (owner, 2026-06-10):**
> - **Q1 scope:** 45.0→45.5 + S53; 45.6 deferred.
> - **Q2 Telegram:** real Telegram smoke test IN scope (owner provides @BotFather token) + the fake-client CI gate; long-poll dev worker required (45.1).
> - **Q3 meinchat E2E:** the bot is a real **E2E participant with a server-held keypair** (client encrypts to the bot key; server decrypts) — expands 45.5 (see its clarifications).
> - **Q4 taro:** all taro bot commands **free + anonymous** (free teaser; paid readings web-only).
> - **Q5 packaging:** **each plugin ships as its own standalone repo** (created + pushed); **nothing committed to the vbwd-sdk-2 monorepo.** Build on-disk in the SDK plugin dirs (needed for the dev stack; gitignored in the monorepo). **Repo creation is BATCHED at the end** (Q-packaging, 2026-06-10): build all of 45.0→45.5+S53 on-disk gate-green first, then create + push all 4 `vbwd-plugin-*` repos in one pass with CI wired consistently (visibility confirmed then).
>
> **Progress:** ✅ **45.0 DONE & gate-green** (2026-06-10) — `vbwd-backend/plugins/bot_base/` on disk; SPI (`IMessengerProvider`/`BotCommandProvider` + DTOs) ready; 28 unit + 7 integ + oracles green. ✅ **45.1 DONE & gate-green** (2026-06-10) — `vbwd-backend/plugins/bot_telegram/`; `TelegramProvider` self-registers, encrypted/masked token + `username` deep-link, webhook secret-check, TESTING-guarded long-poll worker; 15 unit + 9 integ + oracles green. *(Minor DRY item: adapters re-assemble `UpdateDispatcher` from bot-base public pieces — consider exposing `container.update_dispatcher` in bot-base before 45.5.)* ✅ **45.2 DONE & gate-green** (2026-06-10) — `chat` consumer (`/hello-llm` + free-text → existing `ChatService`; linked=billed, unlinked=link-prompt); **optional-bridge proven** (lazy imports, no hard dep, bridge-absent test); 14 unit + 2 integ + 81 regression + oracles green; web chat untouched. ✅ **45.3 DONE & gate-green** (2026-06-10) — `taro` consumer (`/draw`+`/reading`, **free+anonymous, zero billing proven**, reuses existing reading service); 293 unit + 10 integ + oracles green; web taro untouched. ✅ **45.4 DONE & gate-green** (2026-06-10) — `bot-telegram-admin` fe-admin companion (`vbwd-fe-admin/plugins/bot-telegram-admin/`; bot CRUD write-only token, set-webhook, 429-aware test-send, provider-generic linked-accounts, R12 gating, 8 locales); fe-admin `--full` green (568 unit + 104 integ) + 4 e2e specs. ✅ **45.5 DONE & gate-green** (2026-06-10) — `bot-meinchat` adapter (in-process via meinchat `IPostSendHook`, auto identity, **adaptive plain/e2e selection**); **plain path fully built, cross-provider parity proven** (same `chat`/`/hello-llm` over meinchat AND Telegram); `--plugin bot_meinchat --full` + `--plugin meinchat --full` + oracles green. **⚠️ 45.5.1 flagged:** meinchat-plus's `e2e_v1` decrypt is `NotImplementedError` → the E2E bot-participant decrypt is deferred until meinchat-plus implements Signal decrypt. ✅ **S53.0 DONE & gate-green** (2026-06-10) — `subscription` bot storefront backend (`/tarifs`/`/add-ons`/`/tokens`/`/checkout`; `subscription_bot_checkout_draft` model+migration; public recompute-from-catalog `/checkout-draft/<token>`, single-use TTL, no charge); optional-bridge + provider-neutrality proven; `--plugin subscription --full` 55 integ + oracles green. ✅ **S53.1 DONE & gate-green** (2026-06-10) — fe-user `PublicCheckoutView` accepts `?draft=<token>` → fetch draft → hydrate fe-core cart → existing checkout (expired-link state; no-draft path unchanged); fe-user `--full` green (796 passed) + e2e spec.
>
> **🎉 EPIC COMPLETE (on-disk, gate-green) — 2026-06-10:** 45.0, 45.1, 45.2, 45.3, 45.4, 45.5, S53.0, S53.1 all built + their `--plugin … --full` / fe `--full` gates green; nothing committed. **Deferred:** 45.6 (Zapier, per Q1) · **45.5.1** (meinchat E2E bot-participant decrypt — blocked on meinchat-plus implementing `e2e_v1` Signal decrypt). **Remaining step:** batch-create + push the 4 standalone repos (existing plugin repos are PUBLIC + carry a `tests.yml` CI to replicate).
**Shape:** this is an **umbrella** sprint, split into small, independently-shippable sub-sprints (one keystone + thin adapters/consumers), following the `s48-*` pattern. Shared architecture, decisions, and security live **here**; each sub-sprint file owns its scope, backend design, TDD plan, and gate.

## Plugin family (D10)

The bridge is **not** one plugin — it is a `bot-base` core plus thin **adapter plugins**, each an *extension* of `bot-base` (`dependencies=["bot-base"]`, self-registering an `IMessengerProvider`). New providers are added by adding a plugin — never by editing `bot-base` or any consumer (Open/Closed).

| plugin | repo (2026-06-10: `vbwd-plugin-*` convention) | role | sub-sprint |
|---|---|---|---|
| **`bot-base`** | `vbwd-plugin-bot-base` | provider-neutral core: DTOs, `IMessengerProvider` SPI + provider registry, `MessengerService` (outbound), `CommandRegistry`/`UpdateDispatcher` (inbound), conversation mode, `LinkService`, built-in `/hello`·`/start`·`/stop`·`/help` | [45.0](s45-0-bot-base-foundation.md) |
| **`bot-telegram`** | `vbwd-plugin-bot-telegram` | Telegram adapter: `TelegramProvider`, Bot-API client, encrypted bot-token store, webhook + secret-token, **required** long-poll dev worker, `t.me` deep-link | [45.1](s45-1-bot-telegram-adapter.md) |
| **`bot-meinchat`** | `vbwd-plugin-bot-meinchat` | meinchat adapter: in-process transport, automatic identity, **E2E bot-participant (server keypair)** bot-conversation | [45.5](s45-5-bot-meinchat-adapter.md) |
| **`bot-zapier`** | *(deferred)* | Zapier meta-adapter: generic inbound/outbound webhooks → any Zapier-connected channel | [45.6](s45-6-bot-zapier-adapter.md) — **DEFERRED** |

> fe-admin companion repo: **`vbwd-fe-admin-plugin-bot-telegram`** (45.4). Consumers `chat`/`taro`/`subscription` are **existing** repos (`vbwd-plugin-chat`/`-taro`/`-subscription`) — modified, not new.

**Frontend (fe-admin) companions:** only **`fe-admin-bot-telegram`** ships (45.4) — Telegram is the only adapter with real configuration (secret bot tokens, webhook, test-send) + the linked-accounts view. See §Admin / configuration surfaces.

## Sub-sprint index

| # | Sprint | Depends on | Gate |
|---|---|---|---|
| **45.0** | [bot-base foundation](s45-0-bot-base-foundation.md) | — | `--plugin bot_base --full` green; built-ins round-trip vs a **fake** provider |
| **45.1** | [bot-telegram adapter](s45-1-bot-telegram-adapter.md) | 45.0 | `--plugin bot_telegram --full` green; `/hello` round-trips end-to-end over Telegram |
| **45.2** | [chat bot consumer](s45-2-chat-bot-consumer.md) | 45.0 (+45.1 to demo) | `--plugin chat --full` green; bot-chat round-trip debits tokens |
| **45.3** | [taro bot consumer](s45-3-taro-bot-consumer.md) | 45.0 (+45.1 to demo) | `--plugin taro --full` green; taro command round-trips |
| **45.4** | [fe-admin companion](s45-4-fe-admin-bot-telegram.md) | 45.1 | fe-admin lint + unit + e2e green |
| **45.5** | [bot-meinchat adapter](s45-5-bot-meinchat-adapter.md) | 45.0, `meinchat` | `--plugin bot_meinchat --full` + `--plugin meinchat --full` green; same consumers, 2nd provider, no edit |
| **45.6** | [bot-zapier adapter](s45-6-bot-zapier-adapter.md) | 45.0 | **DEFERRED** — future adapter on the same port, no `bot-base` change when un-deferred |
| **S53** | [bot commerce storefront](s53-bot-commerce-storefront.md) | 45.0 | (separate sprint — D8) |

**Suggested order:** 45.0 → 45.1 → (45.2 ∥ 45.3) → 45.4 → 45.5. `bot-zapier` (45.6) is deferred. 45.0 is the keystone; everything else is additive and can be parallelized after it.

## Admin / configuration surfaces (which adapters need a fe-admin plugin?)

A fe-admin plugin is warranted **only where an adapter has configuration that can't ride the generic plugin `admin-config.json` toggle surface** — i.e. **secrets or per-row entities**.

| plugin | config it needs | surface |
|---|---|---|
| `bot-base` | `link_token_ttl`, `conversation_idle_timeout`, `debug_mode` (scalars) | generic `admin-config.json` — **no dedicated fe-admin** |
| `bot-telegram` | **bot entities** (name, **token = secret**, default, `webhook_secret`, enabled) + set-webhook + test-send + linked-accounts | **`fe-admin-bot-telegram` (45.4) — REQUIRED** (secrets/entities can't live in a static toggle file) |
| `bot-meinchat` | `enabled`, designated `bot_conversation_id`, `debug_mode` (scalars; **no** token/webhook, identity automatic) | generic `admin-config.json` — **no dedicated fe-admin** |
| `bot-zapier` *(deferred)* | endpoint entities (`inbound_secret`, `outbound_url` = secret) | would need `fe-admin-bot-zapier` when un-deferred |

**Net:** ship **`fe-admin-bot-telegram`** only. Skip `fe-admin-bot-meinchat` and `fe-admin-bot-base` — their scalar settings ride the generic plugin admin surface; the linked-accounts view (backed by `bot-base` `GET /admin/links`) lives in the Telegram companion for now and is promoted to a bot-base admin only when a second *linking* provider ships.

## Engineering requirements (BINDING — restated in every sub-sprint)

**TDD-first** · **DevOps-first** · **SOLID** (esp. Open/Closed: `bot-base` closed for modification, open for adapter extension) · **Liskov** (every adapter is a substitutable `IMessengerProvider`) · **DI** · **DRY** · clean code · **NO OVERENGINEERING** (narrowest change). Full, readable variable names ([[feedback_variable_naming]]). **`bin/pre-commit-check.sh` is the quality guard** — the named `--plugin … --full` green = "done". S43 table names `bot_<plugin>_<model>`; migrations in each plugin, registered in `alembic.ini` ([[feedback_plugin_migrations_in_plugin]]), revision ids ≤ 32 chars. Baseline `config.json` + `admin-config.json` (`debug_mode`) per plugin ([[feedback_plugin_baseline_config_files]]). Test/demo data only through services ([[feedback_no_direct_db_for_test_data]]). No core change — vbwd core stays **agnostic** ([[feedback_core_never_depends_on_plugins]]); adapter→`bot-base` and `bot-meinchat`→`meinchat` are **declared** `PluginMetadata.dependencies`.

## Goal

A **two-way, provider-neutral bot bridge** any plugin can plug into, with **no core change**:

1. **Outbound** — `bot-base` exports a `MessengerService` (DI) that any plugin calls to post to a channel or DM a chat, routed to a provider by id.
2. **Inbound** — an **adapter** receives the native update, normalizes it, and hands it to `bot-base`, which dispatches the command to a plugin-registered handler and replies through the same adapter.
3. **Extensibility (two axes)** — **consumers** register commands without `bot-base` knowing them (D1 inversion); **providers** extend `bot-base` by registering an `IMessengerProvider` (D10), no `bot-base`/consumer change.

## Provider abstraction — `bot-base` (D6/D10)

The bot-command, conversation, identity-link and storefront-dispatch layers live in **`bot-base`**, on **normalized, provider-neutral DTOs** behind an `IMessengerProvider` port. An adapter implements the port and **registers itself** into `bot-base`'s provider registry on enable; `bot-base` never imports an adapter, adapters never import each other.

**SPI — what an adapter implements:**
```python
class IMessengerProvider(Protocol):
    provider_id: str                                       # "telegram", "meinchat", "zapier", ...
    def parse_update(self, raw: dict) -> BotInbound: ...    # native payload → normalized
    def send(self, reply: BotReply, *, to: ChatRef) -> None # normalized → native send
    def build_link_deeplink(self, token: str) -> str | None # provider-specific connect URL (or None)
    # transport lifecycle (webhook/poll/event-subscription) is provider-specific and stays in the adapter
```

**Extension mechanism (Open/Closed):** `bot-base` owns a `MessengerProviderRegistry` in the DI container. Each adapter's `on_enable` calls `container.messenger_provider_registry().register(TelegramProvider(...))`. `MessengerService` (outbound) and `UpdateDispatcher` (inbound) resolve a provider **by id** — a new provider is purely additive.

**Normalized DTOs (no provider specifics):**
- `BotInbound` — `provider_id`, `chat_ref`, `sender_ref`, `text`, `command`, `args`, `action_data` (a tapped choice), resolved `identity: BotIdentity | None`.
- `BotReply` — `text` + optional `choices: list[BotChoice]`. Each provider renders choices natively: Telegram → inline keyboard; Slack → block buttons; plain channel → numbered list.
- `BotChoice` — `label`, `action_data` (opaque, namespaced `"<plugin>:<action>:<arg>"`).

**Consumer seam (provider-neutral):**
```python
class BotCommandProvider(Protocol):
    bot_namespace: str                                     # "chat", "taro", "subscription"
    def get_bot_commands(self) -> list[BotCommand]: ...
    def handle_action(self, ctx: BotInbound) -> BotReply: ...   # optional: tapped-choice / callback
```
Consumers reference **only** these abstract types — never any `Telegram*`/`Meinchat*` class.

## Architecture (the two seams)

**Seam A — Outbound (`MessengerService`, provider-routed).** `bot-base.on_enable` registers `MessengerService` + the provider registry in `current_app.container` ([[project_plugin_di_provider_registration]]). Consumers resolve lazily:
```python
messenger_service = container.messenger_service()
messenger_service.send_to_chat("telegram", chat_ref, "Your reading is ready 🔮", choices=None)
messenger_service.send_to_channel("telegram", "@my_channel", "New post published")
```
It looks up the registered `IMessengerProvider` by id and calls its `send`; unregistered/disabled provider → clear error.

**Seam B — Inbound (dependency inversion, D1).** `bot-base`'s `CommandRegistry` asks each **enabled** plugin (via `PluginManager`) whether it implements `get_bot_commands()`; non-implementers are skipped. The `UpdateDispatcher` resolves identity via `BotLinkRepository`, resolves command/active-owner/tapped-action, invokes the handler, and sends the `BotReply`. No consumer imports a bridge plugin; `bot-base` imports nothing plugin-specific.

**Conversation mode.** `bot-base` persists a per-chat active owner (`bot_base_session.active_plugin`), keyed by `(provider_id, chat_ref)`, set when a command claims the conversation and cleared by `/stop` or timeout. Free text routes to the active owner; no owner → help/menu.

**Identity linking (D3).** `bot-base` owns the generic link (`bot_base_link`, `bot_base_link_token`); the adapter only renders the provider-specific connect URL via `build_link_deeplink`. Auth-native adapters (meinchat) resolve identity directly and skip linking. Anonymous commands (e.g. `/draw`) need no link; only billed/identity actions require it.

## Security (CRITICAL — applies across the family)

1. **Secrets encrypted at rest (D4)** — bot tokens / outbound URLs stored via `vbwd/utils/crypto.py` (`TokenCipher`/`EncryptedString`); decrypt only at call time; never returned in any API response (mask to `1234****`); admin-only write; treat `bot_<adapter>.manage` like API-key/shell access.
2. **Inbound authenticity** — each adapter validates its own secret (Telegram `X-Telegram-Bot-Api-Secret-Token`; Zapier per-endpoint secret); reject otherwise (no open relay).
3. **No unauth side effects** — an inbound update only dispatches to registered handlers; unknown commands get a safe canned reply, never an error trace.
4. **Identity** — billed actions require a verified `BotLink` (or an auth-native provider); never bill/mutate a vbwd user from an unlinked id.
5. **Rate limiting / abuse** — cap inbound per `(provider_id, chat_ref)`; honor providers' `429 + retry_after` on outbound.
6. **Input bounds** — reuse `chat`'s `max_message_length`; reject oversized inbound before the LLM.
7. **Checkout draft (D8)** — token security specified in [S53 §Security](s53-bot-commerce-storefront.md); the bridge mints no checkout tokens.

## Open decisions (summary)

- **D1** ✅ LOCKED — Inbound seam: dependency-inversion `BotCommandProvider` (`bot-base` collects from enabled plugins; no consumer import).
- **D2** ✅ LOCKED — Telegram transport: webhook (prod, secret-token) + TESTING-guarded long-poll worker (dev). *(adapter-specific — see 45.1)*
- **D3** ✅ LOCKED — Identity: deep-link `/start <token>` + anonymous mode; auth-native adapters skip linking.
- **D4** ✅ LOCKED — Secrets encrypted at rest, masked in responses, admin-only write.
- **D5** ✅ LOCKED — fe-admin surface in scope (45.4); fe-user "Connect" button a separate follow-up.
- **D6** ✅ LOCKED (2026-06-06) — Messenger-provider abstraction: neutral DTOs + `BotCommandProvider` owned by `bot-base`; `MessengerService` provider-routed.
- **D7** ✅ LOCKED (2026-06-06) — Interactive choices abstract: `BotReply.choices` + `BotInbound.action_data` routed by namespace to `handle_action`.
- **D8** 🟡 PROPOSED (2026-06-06; impl in [S53](s53-bot-commerce-storefront.md)) — bot→browser checkout via server-side draft.
- **D9** ✅ LOCKED (2026-06-06) — `bot-meinchat` adapter (in-process, auto identity, designated E2E bot conversation).
- **D10** ✅ LOCKED (2026-06-06) — Plugin layering: `bot-base` core + one adapter plugin per provider, each `dependencies=["bot-base"]` and self-registering an `IMessengerProvider` (Open/Closed).

## Why this is not overengineering

`bot-base` adds exactly two seams on a tiny DTO set and reuses what exists: the DI-provider registration pattern, the TESTING-guarded scheduler pattern, the `TokenCipher`/`EncryptedString` secret store, the token-billed `ChatService.send_message` (chat path is *not* reimplemented), taro's service. The layered family (D10) is the **cheaper** shape, not gold-plating: each adapter is a thin plugin holding only its transport; the alternative — one plugin owning the abstract core, later "extracted" — is strictly more churn for a Telegram-shaped seam. The abstraction's value is **proven, not asserted** by `bot-meinchat` (45.5/D9): a different transport, identity model and UI on the same port, with every consumer unchanged. Splitting into small sub-sprints keeps each unit independently testable and shippable.
