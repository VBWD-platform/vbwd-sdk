# S28.0 — Config keys + `GET /api/v1/messaging/limits` + iOS/web consumers

**Parent sprint:** [S28 — meinchat extension seams + meinchat-plus + retention](s28-meinchat-e2e-encryption-and-retention.md)
**Status:** PLANNED — 2026-05-28
**Depends on:** none (entry slice).
**Blocks:** S28.1 (retention prune reads these config keys), S28.2 (client cache reads the suggested-client-retention).

**Repos touched:** `vbwd-backend/plugins/meinchat/`, `vbwd-fe-user/plugins/meinchat`, `vbwd-ios-plugin-meinchat`.
**Engineering requirements (BINDING):** TDD-first · SOLID · DI · DRY · clean code · **core agnostic** · **NO OVERENGINEERING** — [`_engineering-requirements.md`](_engineering-requirements.md).
**Gate:** `bin/pre-commit-check.sh --plugin meinchat` GREEN; fe-user `npm run lint && npm run test` GREEN; iOS package `swift test` GREEN.

---

## 1. Goal

Backend exposes the four retention/size knobs as admin-configurable
per-instance values, plus a single read endpoint clients can poll on
cold start. Web + iOS replace any hard-coded retention text with the
fetched values. Zero crypto in this slice — it's pure config plumbing
+ one new GET route.

## 2. Backend — `plugins/meinchat/`

### 2.1 `config.json` + `admin-config.json` — 4 new keys

Add to `vbwd-backend/plugins/meinchat/config.json`:

```json
{
  "messages_retention_days_server": {
    "type": "integer", "default": 2, "min": 0, "max": 365,
    "description": "How many days the server keeps message rows before pruning. 0 = no server history (server-amnesic; clients keep everything)."
  },
  "messages_retention_days_client_suggested": {
    "type": "integer", "default": 10, "min": 0, "max": 365,
    "description": "Suggested client-side retention (days). Clients may shorten but never extend beyond this value."
  },
  "attachments_retention_days_server": {
    "type": "integer", "default": 2, "min": 0, "max": 365,
    "description": "Server-side retention for attachment objects (same semantics as messages)."
  },
  "ciphertext_max_bytes": {
    "type": "integer", "default": 16384, "min": 1024, "max": 65536,
    "description": "Upper bound on message envelope size in bytes (ciphertext + header). Allows envelope overhead vs the plaintext 4 000-char cap."
  }
}
```

Add four matching numeric form fields to `admin-config.json` under a new
**Retention** tab so they're tunable from the admin UI.

### 2.2 New route `GET /api/v1/messaging/limits`

File: `plugins/meinchat/meinchat/routes.py` (~25 LOC).

```python
@meinchat_bp.route("/limits", methods=["GET"])
@require_auth
@rate_limit("nickname_search")   # cheap reads; reuse the tight bucket
def get_limits():
    config = current_app.config_store.get_config("meinchat")
    return jsonify({
        "messages_retention_days_server": int(config["messages_retention_days_server"]),
        "messages_retention_days_client_suggested": int(config["messages_retention_days_client_suggested"]),
        "attachments_retention_days_server": int(config["attachments_retention_days_server"]),
        "ciphertext_max_bytes": int(config["ciphertext_max_bytes"]),
        "enabled_protocols": ["plain"],   # S28.3a will widen this to the registered capability set
    })
```

Auth required (same reason as other meinchat reads — minor info leak otherwise).
Returns 404 with the standard `Plugin not enabled` envelope when meinchat is disabled per-instance.

### 2.3 Tests (TDD-first)

New file: `vbwd-backend/plugins/meinchat/tests/unit/routes/test_limits_endpoint.py`. **≥ 5 specs** (red → green → refactor):

| # | Test | Asserts |
|---|---|---|
| 1 | `test_returns_all_5_fields` | all 5 keys present with expected types |
| 2 | `test_reflects_admin_changed_config` | flip `messages_retention_days_server` in the config store → next call returns the new value |
| 3 | `test_auth_required` | no bearer → 401 |
| 4 | `test_plugin_disabled_returns_404` | meinchat disabled → standard `Plugin not enabled` 404 envelope |
| 5 | `test_enabled_protocols_plain_only_in_this_slice` | locks the contract: with no downstream plugins this slice's response is `["plain"]` (so S28.3a can widen it without ambiguity) |

Plus extend `tests/unit/test_plugin.py` with one spec asserting the four
new config keys ship with their documented defaults.

## 3. Web (`vbwd-fe-user/plugins/meinchat`)

### 3.1 New composable

`src/composables/useMessagingLimits.ts` — fetches `/api/v1/messaging/limits`
on first call, caches in module-scope `ref`, re-fetches every 24 h or
on `forceRefresh()`. Returns `{ data, loading, error, refresh }`.

### 3.2 Profile section contribution

Use the existing `profileSectionsRegistry` (already shipped earlier
this session): register a new `MeinchatRetentionSection.vue` that
renders:

> *"We keep your chats on this device for **N days** and on the server
> for **M days**."*

Section uses `placement: 'bottom'` + `order: 50` so it sits below the
"Choose nickname" card without colliding.

### 3.3 Tests

New file: `plugins/meinchat/tests/unit/composables/use-messaging-limits.spec.ts`. **≥ 3 specs**:
1. fetches once; subsequent calls within 24 h use the cache.
2. `refresh()` forces a re-fetch.
3. on HTTP error, exposes `error` and leaves the previous cached value intact.

Plus one component spec on `MeinchatRetentionSection.vue` asserting the
rendered text reflects the composable's values.

## 4. iOS (`vbwd-ios-plugin-meinchat`)

### 4.1 `MeinChatLimitsService.swift` (new)

In `Sources/MeinChatPlugin/Domain/`:

```swift
public protocol MeinChatLimitsServiceProtocol {
    var current: MessagingLimits? { get }
    func refresh() async throws -> MessagingLimits
}

public final class MeinChatLimitsService: MeinChatLimitsServiceProtocol {
    // ... fetches GET /api/v1/messaging/limits, caches with 24h TTL
}

public struct MessagingLimits: Codable, Equatable {
    public let messagesRetentionDaysServer: Int
    public let messagesRetentionDaysClientSuggested: Int
    public let attachmentsRetentionDaysServer: Int
    public let ciphertextMaxBytes: Int
    public let enabledProtocols: [String]
}
```

### 4.2 Settings screen row

Add a row under Settings → Meinchat reading the service's `current`
value and displaying:

> *"Chats are kept for **N days** on this device and **M days** on the server."*

Refresh on `onAppear` (best-effort; non-blocking).

### 4.3 Tests

New file: `Tests/MeinChatPluginTests/MeinChatLimitsServiceTests.swift`. **≥ 4 specs**:
1. fetches on first call.
2. subsequent calls within TTL hit the cache (mock URLProtocol asserts 1 request).
3. expired TTL → re-fetch (2 requests).
4. server unreachable → previous cached value preserved.

## 5. Acceptance criteria

- `curl http://localhost:5000/api/v1/messaging/limits` returns all 5 fields after `docker compose restart api`.
- Flipping `messages_retention_days_server` from `2` to `7` in the admin UI immediately surfaces in the next `/limits` response (config store is hot-reloaded by meinchat already).
- fe-user Profile renders the retention card with the live numbers.
- iOS Settings → Meinchat renders the retention row with the live numbers.
- No hard-coded `2` / `10` / `16384` anywhere in fe-user or iOS sources (grep proof).
- `bin/pre-commit-check.sh --plugin meinchat` GREEN.

## 6. Out of scope

- Any crypto. The endpoint surfaces `enabled_protocols: ["plain"]` for now; S28.3a widens it once capabilities are registered.
- Any TTL enforcement. The endpoint *announces* retention windows; **S28.1** prunes the server, **S28.2** prunes the clients.
- Per-conversation retention overrides (legal hold). A `meinchat-enterprise` concern; out of scope.

## 7. Engineering-requirements check

- **TDD-first:** every change opens with a red spec. Limits-endpoint specs cover the contract before the route exists.
- **DRY:** the `RetentionService` of S28.1 will read from the same config keys via the same `config_store.get_config("meinchat")` lookup — no duplicated source-of-truth.
- **SOLID — D (DI):** route reads from `current_app.config_store` (already a port), not from a module-level singleton.
- **SOLID — I:** the contract is 5 fields; no kitchen-sink response envelope.
- **NO OVERENGINEERING:** one new route + 4 new config keys + 2 client consumers. No new abstractions.
- **Core agnostic:** all work inside `plugins/meinchat/` + the two client plugin repos. No `vbwd-backend/vbwd/` change.
