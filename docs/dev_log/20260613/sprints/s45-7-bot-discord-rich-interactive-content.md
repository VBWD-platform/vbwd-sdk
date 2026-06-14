# Sprint 45.7 — `bot-discord` adapter (Discord, native rich interactive content)

**Parent:** [S45 umbrella](../../20260607/done/s45-bot-base-bridge.md) · **Depends on:** [45.0 bot-base](../../20260607/done/s45-0-bot-base-foundation.md) (+ the [S70](../../20260610/done/s70-bot-rich-choice-rendering-and-portable-styles.md) `BotReply.meta` rich-message contract) · **`dependencies=["bot-base"]`.**
**Status:** **PLANNED — 2026-06-14.** A new adapter plugin on the existing `IMessengerProvider` port (Open/Closed, D10): adding Discord adds a plugin only — **no `bot-base` or consumer change**. **Area:** `vbwd-backend/plugins/bot_discord/` (backend adapter) + `vbwd-fe-admin/plugins/bot-discord-admin/` (fe-admin companion — Discord carries secrets + per-row entities, same rationale as [45.4 Telegram](../../20260607/done/s45-4-fe-admin-bot-telegram.md)).

## Why Discord — and why "rich"

Telegram (45.1) and meinchat (45.5) proved the port. Discord is the first adapter whose **native UI is genuinely rich**: it has first-class **buttons**, **select menus**, **embeds** and **slash commands**. So `bot-discord` is the adapter that renders the S70 provider-neutral `BotReply.meta` vocabulary (`bot_choices`, `bot_menu`, `bot_cart`) as **native Discord components** instead of degrading to a numbered text menu:

| neutral `meta.kind` (S70) | Discord native rendering | fallback (non-rich) |
|---|---|---|
| `bot_choices` | message components: **buttons** (≤5/row, ≤25 total) or a **string select menu** when many; `hint` → button/option description; `meta.text` → embed/description | numbered list in `body` |
| `bot_menu` (`/help`) | an **embed** listing commands, each command also a **button** that re-sends it | the plain `body` list |
| `bot_cart` (`/cart`) | a **cart embed** (line items as fields + total) + a **"Checkout" button** | the plain `body` summary |
| `BotReply.choices` (legacy, no `meta`) | buttons | numbered list |

The whole point of the port (D6/D7/D10) is that **every consumer (`chat`, `taro`, `subscription`/S53 storefront) lights up over Discord with native buttons and embeds, with zero consumer edits** — the same proof S45.5 gave for meinchat, now on a button-native channel.

## Engineering requirements (BINDING)

Anchor: [`_engineering_requirements.md`](./_engineering_requirements.md) (this directory) → canonical [`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md).

**TDD-first** · **DevOps-first** · **SOLID** (esp. **Open/Closed** — `bot-base` is closed for modification, extended only by registering a provider; **Liskov** — `DiscordProvider` is a fully substitutable `IMessengerProvider`, and rich rendering degrades to the plain `body` so non-rich expectations still hold) · **DI** · **DRY** · clean code · **NO OVERENGINEERING** (narrowest change — reuse `bot-base`'s `MessengerService`/`UpdateDispatcher`/`LinkService`/`CommandRegistry`; reuse the S70 `meta` vocabulary; build no new abstractions in `bot-base`). Full, readable variable names ([[feedback_variable_naming]]). **`bin/pre-commit-check.sh` is the quality guard** — `--plugin bot_discord --full` green (lint + unit + integration, no network) + fe-admin `--full` (eslint + vue-tsc + vitest) = "done". Table names `bot_discord_*`; migration **in the plugin**, registered in `alembic.ini`, rev id ≤ 32 chars ([[feedback_plugin_migrations_in_plugin]]). Baseline `config.json` + `admin-config.json` (`debug_mode`) ([[feedback_plugin_baseline_config_files]]). Secrets encrypted at rest, masked in responses, admin-only write (D4). Test/demo data only through services ([[feedback_no_direct_db_for_test_data]]). **No core (`vbwd/`) change** — vbwd core stays agnostic ([[feedback_core_never_depends_on_plugins]]); `bot-discord`→`bot-base` is a **declared** `PluginMetadata.dependencies`. **Standalone repo (`vbwd-plugin-bot-discord`) + fe-admin repo built on-disk in the SDK plugin dirs; never committed to the monorepo, never pushed without the owner's word** ([[feedback_plugins_always_in_own_repos]], Q-packaging).

## Scope — the adapter

`DiscordProvider` implements the existing SPI and **self-registers** into `bot-base`'s `MessengerProviderRegistry` in `on_enable` (Open/Closed — `bot-base` never imports it):

```python
class IMessengerProvider(Protocol):           # bot-base (unchanged)
    provider_id = "discord"
    def parse_update(self, raw: dict) -> BotInbound: ...
    def send(self, reply: BotReply, *, to: ChatRef) -> None: ...
    def build_link_deeplink(self, token: str) -> str | None: ...
```

**Transport (D2-analogue, Discord-specific, lives entirely in the adapter):**
- **Inbound — HTTP Interactions Endpoint (prod).** Discord POSTs every slash command + component interaction (button click / select) to `POST /api/v1/plugins/bot-discord/interactions`. Every request is verified with **Ed25519** over `X-Signature-Ed25519` + `X-Signature-Timestamp` + raw body against the bot's **public key** (Discord's required authenticity check — our analogue of Telegram's secret-token). Discord's `PING` (type 1) is answered with `PONG` (type 1); real interactions (types 2/3) are normalized by `parse_update` and dispatched.
- **Inbound — Gateway worker (dev, TESTING-guarded).** A websocket gateway worker (identify → receive `INTERACTION_CREATE`/`MESSAGE_CREATE`) for local dev where no public Interactions URL exists — mirrors the Telegram TESTING-guarded long-poll worker pattern; **never started under `TESTING`** ([[feedback_ci_precommit_lessons]]).
- **Outbound — `send(BotReply)`** calls the Discord REST API: for an interaction response, an **interaction callback** (type 4) with `embeds` + `components`; for an unsolicited push (`MessengerService.send_to_channel`), a channel `POST /channels/{id}/messages`. Honor `429 + Retry-After` (S45 Security §5).
- **Slash-command sync.** On enable / config save, register `bot-base`'s collected `BotCommand`s as Discord **application commands** (global or per-guild) via the REST API, so they appear in Discord's `/` picker. Idempotent (diff-and-upsert), TESTING-guarded.

**Choices ↔ interactions (D7).** `BotReply.choices` / `meta.bot_choices` render as buttons (or a select menu past Discord's 5-buttons-per-row / 25-total limits, auto-chosen). Each component's `custom_id` carries the opaque, namespaced `action_data` (`"<plugin>:<action>:<arg>"`). A click → an interaction whose `parse_update` extracts `action_data` into `BotInbound.action_data` → `bot-base` routes by namespace to the consumer's `handle_action` — exactly as Telegram inline keyboards do. `custom_id` has a **100-char limit**: long `action_data` (e.g. storefront draft tokens) is stored in a short-lived `bot_discord_action_ref` row keyed by a generated short id placed in `custom_id` (resolved on click); never trust `action_data` for price/identity — the storefront recomputes server-side (S53 §Security).

**Identity (D3).** Reuse `bot-base` `LinkService`: `build_link_deeplink(token)` returns a generic connect URL (Discord has no `t.me`-style deep link, so the user runs `/start <token>` or follows a web connect link). Anonymous commands (e.g. taro `/draw`) need no link; billed actions (chat) require a verified `BotLink` keyed by `(provider_id="discord", chat_ref=discord_user_id)`.

**Models** (`bot_discord/bot_discord/models/`):

| model | table | fields (key) |
|---|---|---|
| `DiscordBot` | `bot_discord_bot` | `name`, `application_id`, `bot_token` (encrypted — D4), `public_key` (encrypted — D4), `default` (bool), `enabled` (bool), `guild_id` (nullable; null ⇒ global commands) |
| `DiscordActionRef` | `bot_discord_action_ref` | `short_id` (PK-ish, in `custom_id`), `action_data` (full namespaced payload), `created_at` (TTL-pruned) |

**Plugin class** — `metadata(name="bot-discord", dependencies=["bot-base"])`; `get_url_prefix()` returns `""` (absolute route paths for public interactions + admin); `on_enable` registers `DiscordBotRepository` + `DiscordActionRefRepository` as DI providers ([[project_plugin_di_provider_registration]]) **and** the `DiscordProvider` into `bot-base`'s registry. Config (`debug_mode`, `command_scope: global|guild`, gateway-worker toggle).

## fe-admin companion — `bot-discord-admin`

Discord has **secrets (bot token, public key) + per-row bot entities + a set-up flow** that can't ride the generic `admin-config.json` toggle surface — so it needs a companion, same as Telegram (S45 §"Admin / configuration surfaces"). Built in `vbwd-fe-admin/plugins/bot-discord-admin/` mirroring 45.4: bot CRUD (write-only token + public key, masked on read), set/clear Interactions Endpoint URL helper text, **"Sync slash commands"** action, a **429-aware test-send**, the provider-generic **linked-accounts** view (backed by `bot-base` `GET /admin/links`, `provider_id=discord`), R12 permission gating, locales. Three runtime manifests required ([[project_fe_admin_plugin_runtime_manifests]]).

## TDD plan (tests FIRST — no network; a fake Discord REST/gateway client)

**Backend (`--plugin bot_discord`):**
- `parse_update`: a slash-command interaction → `BotInbound(command, args)`; a button/select interaction → `BotInbound.action_data` (incl. the `action_ref` short-id resolution path); a `PING` (type 1) → a `PONG` (no dispatch).
- **Ed25519 verification:** a correctly signed interaction passes; a tampered body / bad signature / stale timestamp → **401**, no dispatch (no open relay — S45 Security §2/§3).
- `send`: `BotReply.choices` → buttons; **>5 choices** → a row split; **>25** → a select menu; `meta.kind="bot_menu"` → an embed + command buttons; `meta.kind="bot_cart"` → a cart embed + Checkout button; a reply **with no `meta`/choices** → plain content (Liskov fallback).
- `custom_id` carries `action_data`; **over-100-char** `action_data` → stored as a `DiscordActionRef` and resolved on click; round-trip equality.
- Secrets: `bot_token` + `public_key` stored **encrypted**, never returned (masked `1234****`); admin-only write.
- Slash-command **sync** is idempotent (diff/upsert; second sync is a no-op); TESTING-guarded.
- On enable, `DiscordProvider` appears in `bot-base`'s registry; gateway worker **not** started under `TESTING`.
- **Regression / agnosticism:** `chat` (billed when linked) + `taro` (free + anonymous) + S53 storefront commands **dispatch over Discord with no consumer edit** — the cross-provider parity proof, now on buttons/embeds.
- Migration up/down/up; rev id ≤ 32 chars.

**fe-admin (`bot-discord-admin`):** bot CRUD masks secrets; "Sync slash commands" + test-send call the right endpoints (mocked); linked-accounts renders provider-generic rows; permission-gated; Vitest + a thin e2e (navigate by URL — [[project_fe_admin_navbar_e2e_helper_rot]]; seed both auth keys — [[project_fe_admin_e2e_auth_harness]]).

## Sub-sprints

| # | Title | Scope | Gate |
|---|---|---|---|
| **45.7.0** | `bot-discord` adapter (backend) | `DiscordProvider` (parse/send/deeplink) + Ed25519-verified interactions route + TESTING-guarded gateway dev worker + slash-command sync + `DiscordBot`/`DiscordActionRef` models + migration; native rendering of S70 `meta` kinds; self-registration into `bot-base` | `--plugin bot_discord --full` green; signed-interaction round-trip vs a fake client; bad signature → 401; oracles green |
| **45.7.1** | `bot-discord-admin` (fe-admin companion) | bot CRUD (masked secrets) + endpoint/sync/test-send + linked-accounts (provider-generic) + R12 gating + locales + 3 manifests | fe-admin `--full` (eslint + vue-tsc + vitest) + 1 e2e green |

**Suggested order:** 45.7.0 → 45.7.1. Both purely additive on the existing port.

## Security (inherits S45 §Security; Discord specifics)

1. **Inbound authenticity — Ed25519 mandatory.** Every interaction is verified against the stored `public_key`; failure → 401 before any dispatch. This is Discord's required signature scheme (our analogue of the Telegram secret-token), and Discord itself blocks the endpoint until it validates.
2. **Secrets at rest (D4).** `bot_token` + `public_key` via `vbwd/utils/crypto.py` (`TokenCipher`/`EncryptedString`); decrypt only at call time; never in any API response; admin-only write; treat `bot_discord.manage` like API-key access.
3. **No untrusted `action_data`.** `custom_id`/`action_ref` payloads are opaque + namespaced; billed/priced actions recompute server-side (S53 §Security); never bill/mutate a vbwd user from an unlinked Discord id.
4. **Rate limits.** Honor Discord's `429 + Retry-After` on outbound; cap inbound per `(provider_id, chat_ref)` (S45 §5). Slash-command sync respects bucket limits.
5. **Input bounds.** Reuse `chat`'s `max_message_length`; reject oversized inbound before the LLM.
6. **`action_ref` hygiene.** Short-lived, TTL-pruned, single-purpose; a stale/unknown short id → a safe canned reply, never a trace.

## Cross-references
- Port + decisions: [S45 umbrella](../../20260607/done/s45-bot-base-bridge.md) (D1, D3, D4, D6, D7, D10) — Discord adds nothing to `bot-base`, only consumes its SPI.
- Sibling adapters: [45.1 Telegram](../../20260607/done/s45-1-bot-telegram-adapter.md) (webhook + secret-token + long-poll worker + fe-admin companion shape) · [45.5 meinchat](../../20260607/done/s45-5-bot-meinchat-adapter.md) (cross-provider parity proof) · [45.6 Zapier](./s45-6-bot-zapier-adapter.md) (deferred meta-adapter).
- Rich-content vocabulary reused verbatim: [S70](../../20260610/done/s70-bot-rich-choice-rendering-and-portable-styles.md) `BotReply.meta` (`bot_choices`/`bot_menu`/`bot_cart`, `BotChoice.hint`, `meta.text`) — Discord renders these natively where meinchat renders cards.
- Storefront consumer over Discord: [S53 bot commerce storefront](../../20260607/done/s53-bot-commerce-storefront.md) (server-side draft; the bridge mints no checkout tokens).
- [[project_plugin_di_provider_registration]] · [[feedback_plugin_migrations_in_plugin]] · [[project_fe_admin_plugin_runtime_manifests]] · [[feedback_ci_precommit_lessons]].

## Why this is not overengineering

`bot-discord` adds **one plugin on a port that already exists** and reuses the S70 `meta` vocabulary already shipped — no new `bot-base` abstraction, no consumer touch. The "rich" work is purely *rendering* neutral DTOs into Discord-native components + the one authenticity primitive Discord mandates (Ed25519). The two small models (`DiscordBot`, `DiscordActionRef`) exist only because Discord requires secrets and a `custom_id` length workaround — the narrowest shape that makes buttons/embeds/slash-commands work. The fe-admin companion ships **only because Discord carries secrets + entities** (same gate the umbrella set for Telegram); meinchat/zapier-style scalar adapters still wouldn't get one. The payoff is the umbrella's whole thesis re-proven on a button-native channel: a third provider, zero edits to `chat`/`taro`/`subscription`.