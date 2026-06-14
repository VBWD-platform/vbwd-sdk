# Report 11 — S86: meinchat Rooms (multi-party) + the bot-widget as a room

**Date:** 2026-06-13 → 2026-06-14 · **Area:** core `vbwd-backend` (`UserRole.GUEST`, one DRY auth helper) + `plugins/meinchat` (rooms, widget, token economy) + `plugins/meinchat_plus` (room E2E) + `plugins/bot_meinchat` (bots as room members, eager assistant provisioning) + `vbwd-fe-user/plugins/meinchat` (rooms UI + the widget) + `vbwd-fe-admin/plugins/{cms-admin,meinchat-admin}` (shared widget-editor seam + editor) · **Status:** 🟢 DONE on disk, all plugin gates green, **live-verified end-to-end + UI walkthrough**; **not committed.**

## Origin & shape

Requested as a "bot-widget" (a CMS widget that chats with a configured user/bot), the design was re-framed by the owner across the session into a proper **rooms** capability with the widget as a consumer:

1. **Rooms** — N-party conversations in meinchat.
2. **Encrypted unless invited** — only members read room content.
3. **Creator is admin**; **4. any member can invite.**
5. The **bot-widget is a room** auto-created on "Start Conversation" with editor-configured member nicknames (bots allowed).

Settled with the owner (recorded as locked decisions): **base meinchat owns rooms, meinchat-plus adds E2E**; **any BOT member ⇒ plain room** (bots can't decrypt E2E — the blocked S45.5.1); **keep a core GUEST role, drop the earlier ephemeral-relay idea** (privacy = membership gating + E2E); **multi-bot routing** = `/command` → owning bot, free text → the LLM bot (fallback); **token economy** = **1 token = 1 word**, admin sets the grant, chat works while balance > 0; **overuse protection level-1 only** (cookie+localStorage reuse + fingerprint file-log; real fingerprinting deferred).

Authoritative specs: umbrella [`s86-bot-widget.md`](../sprints/s86-bot-widget.md) + [`s86-1-rooms-foundation.md`](../sprints/s86-1-rooms-foundation.md) · [`s86-2-rooms-e2e.md`](../sprints/s86-2-rooms-e2e.md) · [`s86-3-bot-widget-room.md`](../sprints/s86-3-bot-widget-room.md).

## What was built

### S86.1 — Rooms foundation (core GUEST + base meinchat)
- **Core `UserRole.GUEST`** (public-scope only, cannot interactively log in — mirrors the BOT guard). Standalone enum-add migration; integrated cleanly with the concurrent role-lookup rework (seeded in `vbwd_user_role`).
- `meinchat_room` + `meinchat_room_member` (creator=`admin`, others=`member`, **any member may invite**, admin removes/renames). Messages reuse `meinchat_message` via a nullable `room_id` + an exactly-one-parent CHECK (no second message pipeline — attachments/meta/delivery/retention all reused). `RoomService` + repos + `RoomProtocolSelector` (bot⇒plain + the E2E seam). All room routes (`/api/v1/messaging/rooms/*`), **one-stream SSE** via a new `subscribe_many` (members auto-subscribed, strangers isolated), retention (already covered room rows; guard test added).
- fe-user: `useRoomsStore`, `RoomView`, create/invite/remove UI, inbox room rows, room SSE routing.

### S86.2a — E2E for rooms (meinchat-plus, backend)
- "Encrypted unless invited" via **per-recipient fan-out over the existing 1:1 Signal envelope** — no new group crypto. The 1:1 model (one CBOR envelope with per-device slots, server validates the addressed-device set, delivery rows created lazily on fetch) generalised from "the peer's devices" → "all members' devices."
- New `IRoomPolicy`/`IRoomCapabilities` ports; `AllMembersHaveDeviceKeys` **vetoes** (`member_has_no_device_keys` / `bot_member_cannot_e2e`) rather than silently downgrading a requested-secure room to plain. Forward-only history (a new member sees only post-join messages). The server still holds no keys.
- **fe-user crypto fan-out (S86.2b) deferred** by the owner — widget rooms are plain, so nothing is blocked.

### S86.3 — Bot-widget as a room
- **3a** `POST /messaging/widget/start` (public + logged-in) + `GUEST` provisioning + a **soft-dependency** `ICmsWidgetReader` (null when cms absent → 404; meinchat does NOT hard-depend on cms) + `meinchat_guest_session`. Server-trusts the widget's member list + visibility from the stored cms widget config. Added one small core DRY helper `AuthService.generate_access_token` (the guest JWT reuses the standard token path).
- **3b** bots reply *inside* rooms: the room send now fires the post-send hook chain (the missing trigger), the inbound bridge fires for a bot that is a room member, and the bot's reply posts back into the room. Parent kind is carried as an opaque `"room:<id>"` chat_id so `bot_base` stays neutral; D7 per-room routing (BotSession keyed by chat_ref) falls out for free.
- **3c** token economy + level-1 overuse protection — see "Billing" below.
- **3d** fe-admin: promoted the cms-admin widget-editor registry to a **shared seam** (re-exported), and registered a `MeinchatChatWidgetEditorTab` in meinchat-admin (member-nicknames comma-list, visibility, etc.) — no meinchat code in cms-admin.
- **3e** fe-user `MeinchatChatWidget`: permission gate, name/nickname prompt, "Start Conversation", **guest-scoped auth** (the guest JWT, not the app session) persisted in cookie + long-lived localStorage with return-visit reuse, the chat pane (composed from `MessageBubble`/`MessageComposer`, not the dashboard `RoomView`), bot styling, and the "Buy tokens to continue dialogue" block.

### Billing — REVISED to 1 token = 1 word (owner-confirmed 2026-06-14)
Initially a flat per-round charge; revised to **word-based**: the guest is granted `guest_initial_tokens` on activation (idempotent), and a **post-send hook** debits `word_count × guest_token_cost_per_word` for **both** the guest's question and the bot's answer. The send is **gated on balance > 0** (else `402 insufficient_tokens`); the in-flight round completes (spend-until-empty), the next send is gated. The buy-block links to a future public `/tokens` page (placeholder). Config: `guest_economy_enabled`, `guest_initial_tokens`, `guest_token_cost_per_word`.

### Admin enabler
`BOT` and `GUEST` are now selectable roles in the fe-admin user-create form (so bot members can be created), with backend acceptance pinned by test.

## Live verification & UI walkthrough — and the bugs they caught

Live testing against the running stack (the kind of validation green tests can't substitute) drove the full arc with the real `assistant`: `widget/start` grants tokens → guest question (201) → **assistant replies into the room** → balance depletes by words → next send `402 insufficient_tokens`. It surfaced **three real issues the test suites missed**:

1. **Config DEFAULT fallback bug (fixed).** `_meinchat_config()` returns only persisted overrides (`{}` on a fresh install) and does not merge `DEFAULT_CONFIG`; the economy reads fell back to `guest_initial_tokens=0` → a fresh install granted **0 tokens → the widget was unusable** (immediate 402). The integration tests passed only because they patched `config_store.get_config`. Fixed with a narrow `_economy_config()` that defaults the three economy keys from `DEFAULT_CONFIG` (admin overrides win), plus **real-path tests that don't patch the store**. The fix also exposed and repaired a latent double-hook-registration test leak.
2. **Lazy assistant provisioning (fixed).** The `assistant` bot user is provisioned lazily on first 1:1 inbound, so it didn't exist for a widget to invite. `bot_meinchat`'s populate now **eagerly** provisions it (idempotent, via the existing provisioner, DRY from `DEFAULT_CONFIG`); `on_enable` stays DB-free at boot.
3. **`bot_meinchat` was not enabled** in the dev env — enabled it (workspace `plugins.json`, gitignored) + restarted the api (clean boot).

The **UI walkthrough** (`walkthrough/s86-WALK-REPORT-bot-widget.html`, 6 screenshots, driver `s86-bot-widget-walkthrough.cjs`) captures the public guest flow in the browser: name prompt → Start → chat with the assistant → token arc **200 → 167 → 133 → 99 → … → 0** (≈34 words/turn: a short question + the ~30-word help-menu answer) → the buy-block at 0, 0 console errors. Setup findings: public CMS "pages" are served as **`CmsPost type=page`** (not `CmsPage`); the layout area type is `vue` (the renderer dispatches on the widget's `widget_type`); fe-user runs Vite-HMR so no stale bundle.

## Gates
- `bin/pre-commit-check.sh --plugin meinchat --full` ✅ (408 unit / 67 integration) · `--plugin meinchat_plus --full` ✅ · `--plugin bot_meinchat --full` ✅.
- Core `GUEST` slice green (its own tests + the enum-consistency oracle); whole-core `--full` has **pre-existing unrelated reds** from concurrent uncommitted work (currency / `vbwd_payment_method` / migration-graph fragmentation) — none from S86.
- fe-admin Vitest 905 / fe-user Vitest 964, ESLint 0, vue-tsc 0.

## Deferred / follow-ons
- **A real LLM-bot consumer** (the assistant currently answers with the bot help-menu) + **multiple distinct bot users** in one room each mapped to a namespace (the seam exists: per-bot inbound-hook instances; no `bot_base` change needed).
- **S86.2b** — fe-user E2E crypto fan-out for human-only rooms (deferred; widget rooms are plain).
- **Public `/tokens` buy page** (the buy-block target).
- Room **rename UI** (service exists; no route yet) and **history-on-invite** (current model is forward-only).

## Notes
- Plugin code lives on disk only (`plugins/` is gitignored in vbwd-backend). Nothing committed.
- Default `guest_initial_tokens=20` is low against verbose bot answers; the admin tunes it (the walkthrough used 200). This is expected — the real conversational length comes with the LLM bot.
