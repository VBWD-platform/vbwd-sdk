# Report 03 (2026-06-10) — S45 bot-bridge epic + S53 storefront: implemented on-disk, gate-green

**Scope:** the full S45 bot-bridge epic (sub-sprints **45.0–45.5**) + **S53** (bot commerce storefront, 53.0 + 53.1). **Method:** clarify-first (owner Q&A, captured in each sprint doc) → implement each sub-sprint TDD-first via the `vbwd-tdd` agent, one at a time, `--plugin … --full` / fe `--full` green before the next. **Built on-disk** in the SDK plugin dirs (gitignored); **nothing committed**; no core change throughout. Standalone-repo packaging is the only remaining step.

## Pre-implementation clarifications (owner)

Before any code, 6+ questions were asked **one at a time** and folded into the sprint docs (each has a `## 2026-06-10 clarifications` block):

| # | Decision |
|---|---|
| Q1 scope | **45.0→45.5 + S53**; 45.6 Zapier **deferred**. |
| Q2 Telegram | **Real** smoke test (owner @BotFather token) **+** fake-client CI; the long-poll dev worker became **required**. |
| Q3→refined meinchat E2E | First "bot is an E2E participant w/ server keypair", then **refined**: the adapter is **adaptive** — `meinchat-plus` present → E2E path; absent → **plain** path (after discovering base meinchat has a *null* device-key seam). |
| Q4 taro | **All taro bot commands free + anonymous** (free teaser; paid stays web-only). |
| Q5 packaging | **Standalone repo per plugin**, created + pushed; **nothing committed to the monorepo**; **batched at the end**. |
| Q6 repo names | **`vbwd-plugin-*`** convention: `vbwd-plugin-bot-{base,telegram,meinchat}` + `vbwd-fe-admin-plugin-bot-telegram`. |

## What shipped (each gate-green)

| Sub-sprint | Plugin (on disk) | Highlights | Tests / gate |
|---|---|---|---|
| **45.0** bot-base | `plugins/bot_base/` | provider-neutral SPI (`IMessengerProvider`/`BotCommandProvider` + DTOs), `MessengerProviderRegistry` (Open/Closed extension point), `MessengerService` (Seam A), `CommandRegistry` (D1 enabled-plugin collection), `UpdateDispatcher` (Seam B + built-in `/hello`·`/start`·`/stop`·`/help`), `ConversationService`, `LinkService`; 3 models + migration (`down_revision=vbwd_001` → resolves standalone). | 28 unit + 7 integ + oracles ✅ |
| **45.1** bot-telegram | `plugins/bot_telegram/` | `TelegramProvider` (only TG-aware class) self-registers; **encrypted+masked** token, `username` deep-link field; `ITelegramClient` + fake (429-aware); webhook secret-check; **TESTING-guarded long-poll worker** (dev smoke transport). | 15 unit + 9 integ ✅ |
| **45.2** chat | `plugins/chat/` (modified) | consumer `/hello-llm` + free-text → **existing `ChatService`** (linked=billed exactly as web, unlinked=link-prompt no-debit). | 14 unit + 2 integ + 81 regression ✅ |
| **45.3** taro | `plugins/taro/` (modified) | `/draw`+`/reading` **free + anonymous, zero billing proven**; reuses existing reading service via a new read-only `draw_free_reading`. | 293 unit + 10 integ ✅ |
| **45.4** fe-admin | `vbwd-fe-admin/plugins/bot-telegram-admin/` | bot CRUD (**write-only token**, masked), set-webhook, **429-discriminated** test-send, **provider-generic linked-accounts** (reads bot-base `/admin/links`), R12 nav/route gating, 8 locales. | 23 unit + 4 e2e specs; fe-admin `--full` (568 unit/104 integ) ✅ |
| **45.5** bot-meinchat | `plugins/bot_meinchat/` | 2nd `IMessengerProvider`: in-process transport (meinchat `IPostSendHook`), **automatic identity**, **adaptive plain/e2e selection seam**; lazy bot-user provisioning (caught via TDD). | 16 unit + 2 integ; `--plugin bot_meinchat --full` + `--plugin meinchat --full` ✅ |
| **S53.0** storefront | `plugins/subscription/` (modified) | consumer `/tarifs`(replace)·`/add-ons`/`/tokens`(toggle)·`/checkout`(one-time TTL link); `subscription_bot_checkout_draft` model+migration; **public `/checkout-draft/<token>` recomputes prices from catalogs server-side** (no prices persisted, single-use, 404 on expired/redeemed); balance line linked-only; **bot creates no charge**. | 42 unit + 55 integ ✅ |
| **S53.1** fe-user | `vbwd-fe-user/plugins/checkout/` | `PublicCheckoutView ?draft=<token>` → fetch draft → **hydrate the fe-core cart** → existing checkout; expired-link state; no-draft path unchanged. | 9 specs; fe-user `--full` (796 passed) ✅ |

## Architectural proofs (the value, demonstrated not asserted)

- **Open/Closed (D10):** a new provider is purely additive — adapters self-register an `IMessengerProvider`; `bot-base` imports no adapter, adapters import no consumer/each other.
- **D1 optional bridge:** every consumer (chat/taro/subscription) works **with the bridge ABSENT** — `dependencies` has no `bot-base`, no top-level `import plugins.bot_base`, bot-command methods lazy-import the neutral types. Each has a test that re-imports the package with `plugins.bot_base` blocked.
- **Provider-neutrality (D6):** the **same** `chat` `/hello-llm` round-trips over **Telegram and meinchat** with zero consumer change (45.5's cross-provider integration test) — the abstraction is proven by a second, very different transport (in-process, auto-identity).
- **Security:** Telegram token encrypted at rest + masked in every response + write-only in the UI; webhook secret-token enforced; taro/storefront anonymous paths bill nothing and mutate no identity; the storefront token is random/single-use/TTL'd and carries no identity or prices (recomputed server-side); the bot never creates a charge.

## Deferred

- **45.6 Zapier** — per Q1 (no work this round).
- **45.5.1 meinchat E2E decrypt** — meinchat-plus's `e2e_v1` decrypt is `NotImplementedError` (the envelope is opaque client-side ciphertext; no server-side Signal decrypt exists). Building one would be inventing crypto (forbidden). The **plain path works today**; the adaptive seam auto-engages the E2E path once meinchat-plus ships Signal decrypt + a bot-device registration. Flagged in `s45-5` clarifications.

## Pending (not blocking the build)

- **Packaging:** create + push the **4 PUBLIC** `vbwd-plugin-*` repos (existing plugin repos are PUBLIC + carry a `tests.yml` CI to replicate) — **batched, awaiting the owner's go-ahead** (irreversible outward action).
- **Real-Telegram smoke test (Q2):** ready whenever the owner provides a @BotFather token — add the bot via `POST /admin/bots` (encrypted), then `/hello` over the dev long-poll worker.

## Notes / caveats

- Each adapter re-assembles bot-base's `UpdateDispatcher` from its public services (bot-base doesn't register it in the container) — a small accepted DRY duplication; candidate to fold into bot-base (`container.update_dispatcher`) later.
- A **pre-existing** `_test`-DB connection-leak flake (idle-in-transaction across separate `pytest` invocations → `drop_all` deadlock / leftover `userstatus` ENUM) surfaced during subscription/chat integration runs; from a clean connection state the suites are deterministic and green. Not introduced by this work.
- Nothing committed; sprint docs + `20260607/status.md` updated (rows 45 + 53 → 🟢 implemented on-disk).
