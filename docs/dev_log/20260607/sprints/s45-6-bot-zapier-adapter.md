# Sprint 45.6 — `bot-zapier` adapter (Zapier meta-provider) — optional

**Parent:** [S45 umbrella](s45-bot-base-bridge.md) · **Depends on:** [45.0 bot-base](s45-0-bot-base-foundation.md) · **`dependencies=["bot-base"]`.**
**Status:** **DEFERRED** (decided 2026-06-06) — a documented future adapter on the same port. When un-deferred it adds a plugin only; **no `bot-base` or consumer change** (Open/Closed, D10). It would also need a `fe-admin-bot-zapier` companion (endpoint entities carry secrets). Spec retained below so it's ready to pick up.

## Engineering requirements (BINDING)
**TDD-first** · **DevOps-first** · **SOLID** (Liskov) · **DI** · **DRY** · **NO OVERENGINEERING**. Full readable names ([[feedback_variable_naming]]). **Gate:** `bin/pre-commit-check.sh --plugin bot_zapier --full` green. Migration in the plugin; secrets encrypted at rest (D4). Baseline config files ([[feedback_plugin_baseline_config_files]]). No core change.

## Scope — a meta-provider

Rather than a bespoke adapter per channel, `ZapierProvider` bridges to **any** Zapier-connected channel (Slack, SMS, Discord, MS Teams, …) through Zapier's generic hooks:
- **Inbound** — a Zapier "Catch Hook" POSTs a normalized payload to `POST /api/v1/plugins/bot-zapier/hook`, validated by a per-endpoint `inbound_secret`. The route hands it to `ZapierProvider.parse_update` → `bot-base` `UpdateDispatcher`.
- **Outbound** — `send(BotReply)` POSTs to a Zapier-provided URL stored **encrypted** (D4).
- **Choices** — degrade to a **numbered text menu** (Zapier passthrough rarely supports native buttons); a numbered reply maps back to `action_data`.
- **Identity** — uses the same `bot-base` `LinkService` deep-link/token flow as Telegram (`build_link_deeplink` returns a generic connect URL), or anonymous for unbilled commands.

**Models** (`bot_zapier/bot_zapier/models/`):
| model | table | fields (key) |
|---|---|---|
| `ZapierEndpoint` | `bot_zapier_endpoint` | `name`, `inbound_secret`, `outbound_url` (encrypted — D4), `enabled` |

**Plugin class** — `metadata(name="bot-zapier", dependencies=["bot-base"])`; `on_enable` registers `ZapierEndpointRepository` **and** the `ZapierProvider` into `bot-base`'s registry. Config (`debug_mode`).

## TDD plan (tests FIRST — no network)
- `parse_update`: a Zapier hook payload → `BotInbound`; a numbered reply → `action_data`.
- `send` POSTs to the (fake) outbound URL; `choices` rendered as a numbered menu.
- Inbound with **valid** `inbound_secret` dispatches; **invalid** → 401.
- `outbound_url` stored encrypted, never returned (masked).
- On enable, `ZapierProvider` appears in `bot-base`'s registry.
- **Regression/agnosticism:** `chat`/`taro` consumers light up over Zapier with no change.

## Gate
`--plugin bot_zapier --full` green; round-trip via a fake Zapier hook; invalid inbound secret rejected; outbound URL encrypted/masked.
