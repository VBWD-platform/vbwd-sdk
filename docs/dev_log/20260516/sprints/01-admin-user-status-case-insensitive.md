# Sprint 01 — Admin user create/update rejects lowercase `status` / `role`

**Status:** IMPLEMENTED & VERIFIED — 2026-05-16
**Result:** RED→GREEN done. Backend: `CaseInsensitiveEnum` mixin added,
`UserStatus`/`UserRole` inherit it, **0** `users.py` call sites edited.
Unit/route tests green; full backend suite **747 passed, 4 skipped**;
`make lint` ALL CHECKS PASSED. Frontend: `UserCreate.vue` sends
canonical UPPERCASE; Playwright `admin-user-create-status.spec.ts`
**2 passed** against the live 8081 stack (POST now 201, body
`status:ACTIVE role:ADMIN`); ESLint 0 errors. Pre-existing out-of-scope
finding: the shared `navigateViaNavbar` e2e helper is broken (navbar
refactored into dropdown groups) — logged as a follow-up; new spec
navigates by URL to stay decoupled.
**Repos:** `vbwd-backend` (core fix + pytest), `vbwd-fe-admin` (Playwright e2e)
**Engineering requirements:** [`../../20260422/sprints/_engineering-requirements.md`](../../20260422/sprints/_engineering-requirements.md) — binding.
**Severity:** High — admin user creation is broken in production for every status value except none-supplied.

---

## 1. Failure analysis (root cause, not symptom)

### Observed

```
POST http://localhost:8081/api/v1/admin/users/
body: {email:"test@dev.vbwd.cc", password:"soempassword123", status:"active", role:"ADMIN"}
→ 400 BAD REQUEST  {"error": "Invalid status: active"}
```

Reproducible on prod.

### Backend: the strict enum lookup

`vbwd-backend/vbwd/routes/admin/users.py` — `create_user()`:

```python
# Parse status
status_str = data.get("status", "ACTIVE")
try:
    status = UserStatus(status_str)          # UserStatus("active") → ValueError
except ValueError:
    return jsonify({"error": f"Invalid status: {status_str}"}), 400

# Parse role
role_str = data.get("role", "USER")
try:
    role = UserRole(role_str)
except ValueError:
    return jsonify({"error": f"Invalid role: {role_str}"}), 400
```

`vbwd-backend/vbwd/models/enums.py`:

```python
class UserStatus(enum.Enum):
    PENDING   = "PENDING"
    ACTIVE    = "ACTIVE"
    SUSPENDED = "SUSPENDED"
    DELETED   = "DELETED"

class UserRole(enum.Enum):
    SUPER_ADMIN = "SUPER_ADMIN"
    ADMIN       = "ADMIN"
    USER        = "USER"
    VENDOR      = "VENDOR"
```

`enum.Enum.__call__` does a **value-equality** lookup. `UserStatus("active")`
≠ `"ACTIVE"` → `ValueError` → 400. There is no normalization layer
anywhere between the route and the enum.

### Frontend: the vocabulary it actually sends

`vbwd-fe-admin/vue/src/views/UserCreate.vue`:

```html
<select id="status" v-model="formData.status">
  <option value="active">…</option>      <!-- lowercase -->
  <option value="pending">…</option>
  <option value="suspended">…</option>
</select>
<select id="role" v-model="formData.role">
  <option value="USER">…</option>        <!-- UPPERCASE -->
  <option value="ADMIN">…</option>
  <option value="VENDOR">…</option>
  <option value="SUPER_ADMIN">…</option>
</select>
```

```ts
// UserCreate.vue
const formData = ref<FormData>({ status: 'active', role: 'USER', … });
```

So **`status` is always lowercase** (always 400) and **`role` is
uppercase** (works only by coincidence — the contract is unspecified
and fragile). The same brittle `EnumCls(raw)` pattern is duplicated at
**five** call sites in `users.py`:

| Line | Context |
| --- | --- |
| 60  | `create_user` — status |
| 67  | `create_user` — role |
| 233 | `update_user` — status |
| 239 | `update_user` — role |
| 355 | role update via roles[0] |

A per-route `.upper()` patch would (a) violate DRY across 5 sites and
(b) leave the next call site to regress. The correct fix is to make the
enums themselves case-insensitive at the parse boundary while keeping
their canonical UPPERCASE values (DB columns, serialization, existing
uppercase callers all unchanged).

### Decision: fix the enum, not the routes

- **DRY / SRP:** one `CaseInsensitiveEnum` mixin owns
  "string → member" tolerance. Both `UserStatus` and `UserRole` mix it
  in. Zero route edits → all 5 sites fixed at once.
- **Liskov:** `UserStatus("active") is UserStatus.ACTIVE` (identity
  preserved via the `enum._missing_` hook, which returns the *existing*
  member — it does not create a new one). `UserStatus("ACTIVE")`,
  `UserStatus(UserStatus.ACTIVE)`, `in` checks, DB enum round-trips, and
  JSON serialization (`.value` still `"ACTIVE"`) are all unchanged. Any
  code that currently accepts a `UserStatus` keeps working verbatim.
- **No schema/migration:** persisted values stay UPPERCASE. Pure
  Python-side parsing change. `feedback_migrations_only.md` is N/A (no
  DDL).
- **Frontend hardening (defensive, secondary):** also align
  `UserCreate.vue` to send the canonical UPPERCASE `status` so the wire
  contract is unambiguous going forward. Backend tolerance is the
  primary fix (covers prod + any other client, e.g. fe-user, API
  scripts); the FE change is belt-and-suspenders, gated by its own
  Playwright e2e.

## 2. Scope

**In:**
- `vbwd-backend/vbwd/models/enums.py`: add `CaseInsensitiveEnum` mixin
  via the `_missing_` classmethod hook; apply to `UserStatus` and
  `UserRole`.
- `vbwd-backend` pytest: unit tests for the mixin + a route-level test
  for `POST /api/v1/admin/users/` with lowercase `status`.
- `vbwd-fe-admin` Playwright e2e: a spec that drives the real
  create-user UI (status `active`, role `ADMIN`) and asserts success
  (redirect + user visible), following existing e2e conventions.
- `UserCreate.vue`: normalize `status` to the canonical UPPERCASE value
  on submit (small, covered by the e2e).

**Out:**
- Changing enum *values* / any Alembic migration.
- Editing the 5 `users.py` call sites (the whole point: they need no
  change).
- Refactoring `update_user` beyond what the new tests cover.
- fe-user changes (not in the reported flow; backend fix already covers
  it — note as follow-up if a fe-user form has the same mismatch).
- Touching unrelated routes/plugins.

## 3. TDD checkpoints (red → green → refactor)

### Pre-flight: capture baseline (RED, real bug)

```bash
cd vbwd-backend
make up
# Reproduce the reported 400 against a running stack, or jump to the
# pytest below which encodes the same failure deterministically.
```

### TDD cycle 1 — enum mixin unit test

**Red:** `vbwd-backend/tests/unit/models/test_enums_case_insensitive.py`
(new), written first, run, watched fail (mixin does not exist yet):

```python
import pytest
from vbwd.models.enums import UserStatus, UserRole

@pytest.mark.parametrize("raw,expected", [
    ("active",  UserStatus.ACTIVE),
    ("ACTIVE",  UserStatus.ACTIVE),
    ("Active",  UserStatus.ACTIVE),
    ("pending", UserStatus.PENDING),
])
def test_user_status_is_case_insensitive(raw, expected):
    assert UserStatus(raw) is expected           # identity → Liskov

@pytest.mark.parametrize("raw,expected", [
    ("admin",       UserRole.ADMIN),
    ("ADMIN",       UserRole.ADMIN),
    ("super_admin", UserRole.SUPER_ADMIN),
])
def test_user_role_is_case_insensitive(raw, expected):
    assert UserRole(raw) is expected

def test_unknown_value_still_raises_valueerror():
    with pytest.raises(ValueError):
        UserStatus("not-a-status")

def test_canonical_value_unchanged_for_db_and_json():
    assert UserStatus.ACTIVE.value == "ACTIVE"   # no schema/serialization drift

def test_passing_member_through_is_idempotent():
    assert UserStatus(UserStatus.ACTIVE) is UserStatus.ACTIVE
```

**Green:** add the mixin (illustrative — implement against the tests):

```python
class CaseInsensitiveEnum(enum.Enum):
    """Enum whose value lookup tolerates any string casing.

    Canonical member values stay UPPERCASE (DB column + JSON contract);
    only the *parse* boundary is case-insensitive. Returning an existing
    member from `_missing_` preserves identity, so `Cls("active") is
    Cls.ACTIVE` — a true Liskov substitute for `enum.Enum`.
    """

    @classmethod
    def _missing_(cls, value):
        if isinstance(value, str):
            normalized_value = value.strip().upper()
            for member in cls:
                if member.value == normalized_value:
                    return member
        return None  # → enum raises ValueError, preserving error contract


class UserStatus(CaseInsensitiveEnum):
    PENDING = "PENDING"
    ACTIVE = "ACTIVE"
    SUSPENDED = "SUSPENDED"
    DELETED = "DELETED"


class UserRole(CaseInsensitiveEnum):
    SUPER_ADMIN = "SUPER_ADMIN"
    ADMIN = "ADMIN"
    USER = "USER"
    VENDOR = "VENDOR"
```

**Refactor:** confirm no other enum in `enums.py` regresses; keep
unrelated enums on `enum.Enum` unless they have the same boundary need.

### TDD cycle 2 — route-level pytest (the actual reported bug)

**Red:** new test asserting the reported request now succeeds:

```python
def test_create_user_accepts_lowercase_status(admin_client):
    resp = admin_client.post("/api/v1/admin/users/", json={
        "email": "test@dev.vbwd.cc",
        "password": "soempassword123",
        "status": "active",
        "role": "ADMIN",
    })
    assert resp.status_code == 201
    assert resp.get_json()["status"] in ("ACTIVE", "active")
```

Mirror the existing admin-route test setup/fixtures in
`vbwd-backend/tests/` (auth/admin client). Watch it fail with the exact
`400 Invalid status: active` before cycle 1's mixin is wired, then green
after.

### TDD cycle 3 — Playwright e2e (fe-admin, full UI flow)

**Red first.** Add
`vbwd-fe-admin/vue/tests/e2e/admin-user-create-status.spec.ts`
following the conventions already used in
`vue/tests/e2e/admin-user-crud-flow.spec.ts`:

- auth via `helpers/auth.ts` `loginAsAdmin(page)`
  (`admin@example.com` / `AdminPass123@`);
- navigate via `navigateViaNavbar(page, 'users')` →
  `waitForView(page, 'users-view')`;
- `[data-testid="create-user-button"]` →
  `[data-testid="user-create-view"]`;
- fill `#email`, `#password`, `#status` (`selectOption('active')`),
  `#role` (`selectOption('ADMIN')`);
- `[data-testid="submit-button"]`;
- **assert:** no `Invalid status` error surface; URL redirects to
  `/admin/users/:id` or list; created email is visible after search.

Run against a live stack (real backend, not mocked — this is a
contract bug, mocking the API would hide it):

```bash
cd vbwd-fe-admin/vue
E2E_BASE_URL=http://localhost:8081 npx playwright test admin-user-create-status.spec.ts
```

Watch it fail (400 surfaces as the form error) → apply backend fix →
green. Then add the `UserCreate.vue` UPPERCASE-on-submit normalization
and keep the e2e green (defensive layer, now contract-explicit).

## 4. Files touched

| Repo | File | Change |
| --- | --- | --- |
| vbwd-backend | `vbwd/models/enums.py` | add `CaseInsensitiveEnum`; `UserStatus`/`UserRole` inherit it |
| vbwd-backend | `tests/unit/models/test_enums_case_insensitive.py` | new — mixin unit tests |
| vbwd-backend | `tests/.../test_admin_users_*.py` | new/extended — lowercase-status route test |
| vbwd-fe-admin | `vue/tests/e2e/admin-user-create-status.spec.ts` | new — e2e for the reported flow |
| vbwd-fe-admin | `vue/src/views/UserCreate.vue` | normalize `status` to UPPERCASE on submit (defensive) |

`vbwd-backend/vbwd/routes/admin/users.py` — **unchanged** (the fix is
intentionally invisible to all 5 call sites).

## 5. Verification gate (must pass before push)

```bash
# Backend
cd vbwd-backend
docker compose run --rm test python -m pytest tests/unit/models/test_enums_case_insensitive.py -v
docker compose run --rm test python -m pytest tests/ -k admin_users -v
make lint            # black / flake8 / mypy — no new # noqa / # type: ignore

# Frontend e2e (live backend on 8081)
cd vbwd-fe-admin/vue
npm run lint
E2E_BASE_URL=http://localhost:8081 npx playwright test admin-user-create-status.spec.ts
npx playwright test admin-user-crud-flow.spec.ts   # regression: existing flow still green
```

All green → show diffs → on confirmation push directly to `main` of
`vbwd-backend` and `vbwd-fe-admin` (no temp branches).

## 6. Definition of done

- [x] `UserStatus("active")` / `UserRole("admin")` resolve, identity
      preserved; unknown values still raise `ValueError`.
- [x] Canonical `.value` still UPPERCASE — no DB/JSON drift, no
      migration.
- [x] Reported request `{status:"active", role:"ADMIN"}` → `201`.
- [x] New pytest (unit + route) green; full backend suite 747 passed.
- [x] New Playwright spec green against the live backend (2 passed).
      Note: `admin-user-crud-flow.spec.ts` is **pre-existing red** due to
      unrelated navbar-helper rot (see §7) — not a regression from this
      sprint; the new spec deliberately avoids that helper.
- [x] `UserCreate.vue` submits canonical UPPERCASE `status`.
- [x] `make lint` clean (ALL CHECKS PASSED); ESLint 0 errors; no
      suppression comments added.
- [ ] Diffs reviewed, pushed to `main` of both repos. *(awaiting user
      confirmation — no commit/push performed yet.)*

## 7. Follow-ups (not this sprint)

- Audit `vbwd-fe-user` for the same lowercase/uppercase enum mismatch
  on any user-facing form; the backend fix already protects it, but the
  wire contract should be made explicit there too.
- Consider a tiny shared FE enum-constants module so FE and BE
  vocabularies can't silently diverge again.
