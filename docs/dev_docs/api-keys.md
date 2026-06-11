# API Keys — how they work, how to use them, how plugins expose scopes

API keys are a **core platform auth mechanism** (the same class as JWT). A user holds
scoped, IP-restricted keys; **plugins declare the scopes** their endpoints need and
guard those endpoints with the core `require_api_key(scope)` decorator. Core owns the
*mechanism*; plugins own the *meaning* (the scope strings + the protected endpoints).

Implemented in S52. See also `docs/dev_log/20260607/sprints/s52-user-api-key.md`.

---

## 1. How a key is stored (one row per key, in the `api_key` table)

The plaintext token is **never stored or logged**. Only a hash + a short display prefix
are persisted.

| column | type | notes |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → `vbwd_user.id` (ON DELETE CASCADE) | the **owner**; a key-authenticated call acts as this user |
| `label` | String(120) | human label, e.g. "CI pipeline" |
| `key_hash` | String(64), unique, indexed | **sha256 of the token** — the only copy of the secret |
| `key_prefix` | String(16) | first chars of the token (e.g. `vbwdk_5lqc`) for list display |
| `scopes` | JSONB list[str] | explicit allow-list of scope keys, e.g. `["cms:posts:create"]` |
| `ip_whitelist` | JSONB list[str] | exact IPs and/or CIDRs; **empty = any IP** |
| `is_active` | bool | revoke = set `false` (the audit row is kept) |
| `created_by_user_id` | UUID, nullable | admin who created it, else `== user_id` (self-service) |
| `last_used_at` | DateTime, nullable | stamped by the guard on every successful call |
| `created_at / updated_at / version` | — | `BaseModel` |

**Token format:** `vbwdk_` + `secrets.token_urlsafe(32)`. It is returned **once** at
creation; afterwards only `key_prefix` is shown. Lookup is `key_hash = sha256(presented)`,
compared in constant time (`hmac.compare_digest`). `to_dict()` never includes `key_hash`.

Code: `vbwd/models/api_key.py`, `vbwd/repositories/api_key_repository.py`,
`vbwd/services/api_key_service.py`.

## 2. Lifecycle

1. **Create** — in fe-admin (User edit → **API** tab, an admin manages any user's keys) or
   fe-user (**Manage API** page, a user with the `manage_api` permission manages their own).
   Both surfaces mount the *same* fe-core `ApiKeysManager` component. The plaintext is shown
   **once** — copy it then; it cannot be retrieved again.
2. **Use** — send it in the `X-API-Key` header (see §3). The guard validates active +
   IP-allowed + (optionally) scoped, stamps `last_used_at`, and runs the handler as the owner.
3. **Revoke / delete** — flip `is_active` (immediate — checked every request) or delete the row.

A user may only self-grant scopes flagged `user_grantable`; an admin may grant any registered
scope. No scope ⇒ no scoped action is authorized (deny by default).

## 3. Using a key

### Test that a key works — `GET /api/v1/api-keys/health`
A core endpoint authenticated by the key itself (NOT a JWT). **Any valid, active, IP-allowed
key passes — no scope required** — so a holder can confirm a key is live and see what it can do.

```bash
curl -s https://<instance>/api/v1/api-keys/health \
  -H "X-API-Key: vbwdk_5lqcauP8…your-token…"
```
```jsonc
{
  "ok": true,
  "message": "API key is valid",
  "user_id": "99d1eee9-fe09-47fc-85db-1776fe3f6187",
  "key_prefix": "vbwdk_5lqc",
  "label": "health-test",
  "scopes": [],
  "ip_whitelist": []
}
```
- **401** — missing/blank/unknown/inactive key.
- **403** — caller IP not in the key's `ip_whitelist`.

### Call a scoped endpoint (e.g. CMS content ingestion)
```bash
curl -s -X POST https://<instance>/api/v1/cms/api/posts \
  -H "X-API-Key: vbwdk_…" -H "Content-Type: application/json" \
  -d '{"type":"post","title":"My headline","categories":["News"],"status":"draft"}'
```
The endpoint is guarded by `require_api_key("cms:posts:create")` — the key must carry that
scope (else **403 `Scope not granted`**). The created post is authored as the key's user.

## 4. How a plugin exposes its own scopes + protected endpoints

This is the whole point of the design: **a new scope or consumer needs ZERO core changes.**

### Step 1 — declare the scope on the plugin object
Add an `api_scopes` attribute (same shape as `admin_permissions`). The core scope registry
(`vbwd/services/api_scope_registry.py`) collects it through the injected `plugin_manager` —
it **never imports your plugin module** (mirrors `permission_catalog.py`).

```python
class MyPlugin(BasePlugin):
    # Each scope: key, label, description, and whether a user may self-grant it.
    api_scopes = [
        {
            "key": "myplugin:widgets:create",   # "<plugin>:<resource>:<action>"
            "label": "Create widgets via API",
            "description": "Create a widget owned by the key's user.",
            "user_grantable": True,              # shows on the user Manage-API page
        },
    ]
```
The scope string is **opaque to core** — core only string-matches it against a key's
allow-list. Do not hardcode a plugin term anywhere in `vbwd/` (the agnosticism + vocabulary
oracles enforce this).

### Step 2 — guard the endpoint with the core decorator
```python
from vbwd.middleware.api_key_auth import require_api_key

@my_bp.route("/api/v1/myplugin/api/widgets", methods=["POST"])
@require_api_key("myplugin:widgets:create")
def create_widget_via_api():
    # Liskov: the guard set g.user_id and g.user exactly like require_auth,
    # so g.user_id is the key owner — use it as the author/owner.
    payload = request.get_json() or {}
    return jsonify(my_service.create(payload, user_id=g.user_id)), 201
```
- `require_api_key("scope")` → 401 (no/invalid key) · 403 (IP blocked **or** scope missing).
- `require_api_key()` (no arg) → "any valid key" — used only for the health endpoint; don't
  use it to gate a domain action.
- The guard also exposes the authenticating key as `g.api_key`.
- Keep the handler thin: compose existing services (`create_post`, `upload_image`, …); the API
  layer owns no persistence. See `plugins/cms/src/services/content_ingest_service.py` for the
  reference consumer (`cms:posts:create` + `POST /api/v1/cms/api/posts`).

### Step 3 — that's it
Because scopes are **data declared by plugins** (not code in core), the scope appears
automatically in the create-key UI's scope catalogue (`GET /api/v1/admin/api-keys/scopes`,
and `GET /api/v1/api-keys/scopes` for the user-grantable subset). No core edit, no new UI.

## 5. Endpoint reference

**Core — key management (JWT-authenticated, permission-gated):**
| method | path | gate | purpose |
|---|---|---|---|
| GET | `/api/v1/admin/api-keys/scopes` | `api_keys.manage` | scope catalogue (admin) |
| GET/POST | `/api/v1/admin/users/<id>/api-keys` | `api_keys.manage` | list / create a user's keys |
| POST | `/api/v1/admin/api-keys/<id>/revoke` | `api_keys.manage` | deactivate |
| DELETE | `/api/v1/admin/api-keys/<id>` | `api_keys.manage` | delete |
| GET | `/api/v1/api-keys/scopes` | `manage_api` | user-grantable scopes |
| GET/POST | `/api/v1/api-keys` | `manage_api` | list / create own keys |
| POST | `/api/v1/api-keys/<id>/revoke` | `manage_api` + owner | revoke own |
| DELETE | `/api/v1/api-keys/<id>` | `manage_api` + owner | delete own |

**Core — key-authenticated (`X-API-Key`):**
| method | path | guard | purpose |
|---|---|---|---|
| GET | `/api/v1/api-keys/health` | `require_api_key()` | **test a key** (any valid key) |

**Plugin consumers — key-authenticated:**
| method | path | guard | plugin |
|---|---|---|---|
| POST | `/api/v1/cms/api/posts` | `require_api_key("cms:posts:create")` | cms |

## 6. Security guarantees
- Plaintext is never stored or logged; only sha256(token) + a display prefix.
- Constant-time hash compare on lookup.
- IP whitelist is enforced **before** scope; CIDR via stdlib `ipaddress`; `X-Forwarded-For`
  honoured only when `TRUST_FORWARDED_FOR` is set.
- Revocation is immediate (`is_active` checked every request).
- Owner isolation: user self-service routes touch only the caller's keys and require
  `manage_api` **server-side** (FE gating is UX, not security).
- No privilege escalation: a scope authorizes a plugin endpoint, **not** admin permissions —
  `require_permission(...)` still gates admin routes.
