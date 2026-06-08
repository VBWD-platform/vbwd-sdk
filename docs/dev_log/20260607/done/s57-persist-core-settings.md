# Sprint 57 — Persist core settings (file-backed `var/core/vbwd_settings.json`)

**Status:** READY — 2026-06-07.
**Area:** **core** — `vbwd-backend` only (`vbwd/routes/admin/settings.py` + a new `vbwd/services/core_settings_store.py`). No plugin, no fe change (the Settings → Core tab API is unchanged).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · clean code · **core agnostic** (generic infra; names no plugin domain — oracle stays green) · **NO OVERENGINEERING**. Gate: `bin/pre-commit-check.sh --full` green on `vbwd-backend` (incl. `test_core_agnosticism.py` + `test_core_no_domain_vocabulary.py`).
**Unblocks:** the S46 `core_settings` exchanger (R10) — a fast-follow once this lands.

## Problem (verified 2026-06-07)

`vbwd/routes/admin/settings.py` backs the **Settings → Core** tab (provider name, contact email, website, postal address, bank name/IBAN/BIC) with a **module-level `_settings` dict** — no DB, no file, no hydration:

```python
# In-memory settings store (in production, use database or config service)
_settings = { "provider_name": "", ... "bank_iban": "", "bank_bic": "" }
```

This is a **latent prod bug**, not just an S46 blocker:
- **Restart/redeploy wipes it** → provider name / bank details (used on invoices + emails) silently go blank.
- **Multi-worker inconsistency** → gunicorn runs N workers, each with its own copy; a `PUT` updates only the serving worker, a later `GET` on another worker returns stale/empty.
- **Nothing to export** → S46's `core_settings` exchanger has no durable record.

## Design — file-backed store under the existing `var/` mount

A small generic core service persists the settings as one JSON file at
**`${VBWD_VAR_DIR:-/app/var}/core/vbwd_settings.json`** (the `var/` dir is already host-mounted into the backend, so this survives restarts and is the single source of truth shared by all workers).

### `vbwd/services/core_settings_store.py` (new)
- `DEFAULT_CORE_SETTINGS` — the existing key set (provider_name, contact_email, website_url, other_links, address_street/city/postal_code/country, bank_name/bank_iban/bank_bic). Single source of truth for the schema.
- `_path()` → `os.path.join(os.environ.get("VBWD_VAR_DIR", "/app/var"), "core", "vbwd_settings.json")`.
- `get_core_settings() -> dict` — read the file (if present) and return `{**DEFAULT_CORE_SETTINGS, **file_values}` (defaults fill any missing/new keys; corrupt/missing file → defaults, logged, never raises).
- `update_core_settings(partial: dict) -> dict` — `current = get_core_settings(); current.update({k: v for k, v in partial.items() if k in DEFAULT_CORE_SETTINGS})` (known-keys whitelist preserved); **atomic write** (`os.makedirs(dir, exist_ok=True)` + temp file in the same dir + `os.replace`); return the merged dict. Last-writer-wins is fine (settings edits are rare/serial — no lock; NO OVERENGINEERING).

### `vbwd/routes/admin/settings.py` (rewire)
- Delete the module-level `_settings` dict.
- `GET /api/v1/admin/settings` (`settings.view`) → `{"settings": get_core_settings()}`.
- `PUT /api/v1/admin/settings` (`settings.manage`) → `{"settings": update_core_settings(request.get_json() or {}), "message": ...}`.
- API shape + permissions unchanged → **fe-admin Core Settings tab needs no change.**

### DevOps
- **`.gitignore`:** add `var/core/*.json` (the file holds bank IBAN/BIC — sensitive, per-deployment; never commit). Mirrors `var/plugins/*-config.json`.
- No compose change — the file lives under the existing `${VAR_DIR}:/app/var` mount (same mount the cms prerender + plugin config use).
- Recipes/install: nothing required (defaults apply when the file is absent; the file is created on first PUT).

## TDD plan (tests FIRST)
- **unit** (`tmp_path` + `VBWD_VAR_DIR` monkeypatch): `get_core_settings()` returns defaults when the file is absent; round-trips a written file; merges defaults over a partial file (new keys appear); `update_core_settings()` whitelists known keys (ignores unknown), writes atomically, and a **fresh read sees the value** (persistence-across-"restart" proof); corrupt JSON → defaults (no raise).
- **integration** (Flask client): `PUT /admin/settings` then `GET /admin/settings` returns the saved values; values survive a new app instance pointed at the same `VBWD_VAR_DIR`; `settings.view`/`settings.manage` gating (401/403); a second "worker" (new store call) reads the same file (consistency).
- **oracles:** `test_core_agnosticism.py` + `test_core_no_domain_vocabulary.py` stay green (generic infra; no `from plugins.*`, no banned vocabulary).

## Definition of done
Core settings persist to `${VBWD_VAR_DIR}/core/vbwd_settings.json`: survive restart, are consistent across workers (file is the source of truth), and the Settings → Core API/UI behave identically. `var/core/*.json` git-ignored. `--full` green on `vbwd-backend` + both oracles. **Follow-up (S46):** add the `core_settings` `EntityExchanger` reading/writing via this store.
