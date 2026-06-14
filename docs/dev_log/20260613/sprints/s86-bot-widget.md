# S86 — meinchat Rooms (multi-party) + the bot-widget as a room (UMBRELLA)

**Area:** `vbwd-backend` core (`UserRole.GUEST`) · `vbwd-backend/plugins/meinchat` (rooms foundation) · `vbwd-backend/plugins/meinchat_plus` (E2E for rooms) · `vbwd-backend/plugins/bot_meinchat` (bots as room members) · `vbwd-fe-user/plugins/{meinchat,meinchat-plus}` · `vbwd-fe-admin/plugins/{meinchat-admin,cms-admin}`. **No new plugin** — rooms extend the existing meinchat tier; one deliberate core identity addition.
**Engineering requirements:** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **NO OVERENGINEERING** — **BINDING per [`_engineering_requirements.md`](_engineering_requirements.md)**. Quality guard per sub-sprint: `bin/pre-commit-check.sh --full` (core, S86.1 touches `vbwd/`) + `--plugin meinchat --full` / `--plugin meinchat_plus --full` / `--plugin bot_meinchat --full` + fe Vitest/ESLint/vue-tsc green. **Not committed** without explicit instruction ([[feedback_no_commit_without_ask]]).

## Goal

Add **rooms** — multi-party conversations — to meinchat, and rebuild the bot-widget on top of them: the widget becomes a **room that is auto-created for the visitor** with a configured list of members (any of which may be bots). Five product requirements drive it:

1. **Rooms** (N-party conversations) are added to the meinchat tier.
2. Rooms are **encrypted unless invited** — only a member can read the room's content (encryption keeps non-members, including the server, out; members hold the keys).
3. The **creator of a room is its admin**.
4. **Any member can invite** another user into the room.
5. The **bot-widget is a room**, created automatically for the visitor. The CMS editor enters a list of nicknames (`user1, user2`) that are **invited as members the moment the visitor clicks "Start Conversation"**. Invitees may be **bots** — e.g. one checkout/subscription bot and one LLM bot in the same room.

## Architecture (locked decisions — inherited by every sub-sprint)

| # | Decision |
|---|----------|
| **AD1 — Rooms are a NEW N-party model in BASE meinchat, parallel to the 2-party `Conversation`.** | New `meinchat_room` + `meinchat_room_member`; the existing pair-keyed `Conversation` (rigid low/high constraints) stays for 1:1 DMs. No risky unification migration. **Rooms live in base meinchat so the bot-widget works WITHOUT the E2E plugin** (clarified direction: base owns rooms, plus adds E2E). |
| **AD2 — Room messages reuse the existing `meinchat_message` via a nullable `room_id`.** | `conversation_id` becomes nullable; add nullable `room_id`; a CHECK enforces exactly one. This reuses attachments, per-device delivery (plus), `meta` (bot rich cards, S70), codec, and retention with **no parallel message pipeline** (DRY > the schema churn of a second `room_message` table). |
| **AD3 — Roles: creator = `admin`; others = `member`. Any member may invite; admin may remove members / delete the room.** | `meinchat_room_member.role ∈ {admin, member}`, `invited_by`, `joined_at`, per-member `unread_count`/`last_read_at`. Invite = add a member row (idempotent by `(room_id, user_id)`). |
| **AD4 — "Only members read" is enforced two ways.** | **plain** rooms: every read/send/stream route checks membership. **e2e** rooms: only member devices ever receive ciphertext (the server holds no keys — it cannot read regardless). |
| **AD5 — Protocol is pinned at creation, chosen by membership.** | **Any BOT member ⇒ `plain`** (bots can't decrypt E2E — clarified direction). Else `e2e_v1` when meinchat-plus is enabled AND all members have device keys, else `plain`. Generalises the existing per-conversation negotiation (capabilities + `IConversationPolicy`). |
| **AD6 — E2E rooms (meinchat-plus) = per-recipient fan-out over the EXISTING pairwise Signal sessions — no new group-crypto.** | A room message is encrypted by the sender's client once per current member-device (reusing X3DH + double-ratchet + the per-device `message_delivery` already shipped); the server stores per-device deliveries and holds no keys. `BothPeersHaveDeviceKeys` generalises to `AllMembersHaveDeviceKeys`. **"Encrypted unless invited" falls out for free**: a newly-invited member only receives fan-outs sent *after* they joined — no ciphertext exists for prior messages (history re-encryption is **deferred**; sender-keys/MLS deferred — anti-overengineering). |
| **AD7 — Core `UserRole.GUEST` (public-scope only, no interactive login).** | The public widget visitor is a first-class GUEST who **creates and owns (admin of)** their widget room. Mirrors the existing plugin-provisioned `BOT` identity class; core defines the class, meinchat provisions it. |
| **AD8 — Widget rooms are STORED like any room (no ephemeral relay).** | Privacy comes from membership gating (AD4) + E2E (AD6), not transience (the earlier "not stored until kept" model is dropped per clarified direction). |
| **AD9 — The bot-widget is a room; its member list is editor-configured nicknames (bots allowed).** | On "Start Conversation": create a room, the visitor is creator/admin (AD3), the configured nicknames are auto-invited members. A room containing a bot is `plain` (AD5); the assistant/checkout/LLM bots participate as members via `bot_meinchat`. |
| **AD10 — The widget's behaviour-defining config (member list, visibility) is SERVER-TRUSTED.** | meinchat reads the CMS widget row by slug through a narrow declared `cms` port (DIP; declared `PluginMetadata.dependencies` on `cms`); the FE is never trusted for "who is invited" / "is this public" (anti-abuse). |

## Sub-sprints

| # | Sub-sprint | Area | Depends on |
|---|-----------|------|------------|
| **S86.1** | [Rooms foundation — core `GUEST` + base meinchat rooms](s86-1-rooms-foundation.md) | core + `plugins/meinchat` + fe-user/fe-admin meinchat | — |
| **S86.2** | [E2E for rooms — per-recipient fan-out in meinchat-plus](s86-2-rooms-e2e.md) | `plugins/meinchat_plus` + `vbwd-fe-user/plugins/meinchat-plus` | S86.1 |
| **S86.3** | [Bot-widget as a room — CMS widget that creates the room on "Start Conversation"](s86-3-bot-widget-room.md) | `plugins/meinchat` + `bot_meinchat` + fe-user `meinchat` + fe-admin `meinchat-admin`/`cms-admin` | S86.1 (S86.2 optional) |

**Sequencing:** S86.1 first (rooms + GUEST land plain, fully usable). S86.2 layers E2E onto human-only rooms. S86.3 builds the widget; it needs only S86.1 (widget-bot rooms are `plain` per AD5/AD9), so it can ship in parallel with S86.2.

## Definition of done (umbrella)
All three sub-sprints meet their own DoD + gates; a user can create a multi-party room, invite members (any member can), only members can read it (plain → membership-gated, human-only → E2E "encrypted unless invited"); and a CMS bot-widget auto-creates a room on "Start Conversation" with the editor's configured members (bots included) where the visitor is admin and the assistant/LLM/checkout bots reply. Not committed without explicit instruction.
