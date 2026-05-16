# Sprints — 2026-05-16 — Admin User Creation: "Invalid status: active"

**Trigger:** Creating a user from the admin backoffice
(`POST /api/v1/admin/users/` with body
`{email, password, status: "active", role: "ADMIN"}`) returns
`400 {"error": "Invalid status: active"}`. Reproducible on **prod**.

**Class:** Core API contract bug — case mismatch between the frontend
enum vocabulary (lowercase: `active`, `pending`, `suspended`) and the
backend `UserStatus` / `UserRole` enums (uppercase: `ACTIVE`, …). Role
only works by accident because `UserCreate.vue` happens to send `ADMIN`
uppercase; status is always sent lowercase and always fails.

**Scope note (core vs plugin):** This is a defect in vbwd **core**
(`vbwd-backend/vbwd/`), not plugin functionality, so a core change is
correct here. The "core is agnostic, only plugins are gnostic" rule
forbids adding *plugin* behaviour to core — it does not forbid fixing a
core API contract bug.

## Sprint index

| # | Sprint | Failure class | Effort |
| --- | --- | --- | --- |
| [01](./01-admin-user-status-case-insensitive.md) | Admin user create/update rejects lowercase `status`/`role` | API contract / enum coercion | S |

## Engineering requirements (binding)

Inherited from
[`../../20260422/sprints/_engineering-requirements.md`](../../20260422/sprints/_engineering-requirements.md).
Highlights this sprint leans on:

- **TDD-first** — the failing pytest (lowercase `"active"` → 400) and
  the failing Playwright e2e (create-user flow) are written and watched
  fail *before* the enum fix.
- **DRY** — the fix is a single `CaseInsensitiveEnum` mixin applied to
  both `UserStatus` and `UserRole`; it repairs all 5 call sites
  (`users.py:60,67,233,239,355`) without editing any of them. No
  per-route `.upper()` sprinkling.
- **SOLID / SRP** — case-normalization is one concern, owned by one
  mixin in `vbwd/models/enums.py`. Route handlers keep their single
  responsibility (HTTP I/O), unchanged.
- **Liskov** — `CaseInsensitiveEnum` is a drop-in `enum.Enum`
  substitute: `UserStatus("active") is UserStatus.ACTIVE`, identity and
  membership semantics preserved; existing uppercase callers and DB
  round-trips are unaffected.
- **Clean code / variable naming** — full readable names
  (`raw_status`, `normalized_value`), per
  `feedback_variable_naming.md`. No `# noqa` / `# type: ignore`
  (`feedback_no_noqa_without_permission.md`).
- **No raw SQL / no migration** — enum *values* on disk are unchanged
  (still uppercase); only Python-side parsing becomes tolerant. No
  Alembic change needed (`feedback_migrations_only.md` — N/A, no schema
  change).
- **Show diff → confirm → push** to `main` of `vbwd-backend` and
  `vbwd-fe-admin` standalone repos; no temp branches
  (`feedback_no_temp_branches.md`).
