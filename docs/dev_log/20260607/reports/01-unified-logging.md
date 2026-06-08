# Report 01 — Unified Logging (S58.5 / D9)

**Date:** 2026-06-08
**Sprint:** [S58 — Unified `FilesystemManager` + logging](../sprints/s58-unified-var-filesystem-manager.md), sub-sprint 58.5 (+ 58.6 cms-ai migration, taro `print` cleanup).
**Status:** ✅ shipped & green (core `--full` Part A/B; boot TESTING-guarded). **Not committed** (standing rule).
**Dev guide:** [`vbwd-backend/docs/developer/unified-logging.md`](../../../../vbwd-backend/docs/developer/unified-logging.md).

## Why

Logging was scattered and lossy:
- Every plugin did `logging.getLogger(__name__)` to **stdout**, lost on container rotation; the only on-disk logs were cms-ai's bespoke `RotatingFileHandler` (writing a **cwd-relative `core.log`** + a hardcoded `/app/var/tmp/log-dev/fs_out.log`).
- Domain events left **no trace**. This is precisely why the contact-form failure (report context: the `contact_form.received` event fired but no email template existed, so the handler silently no-op'd) was invisible until traced by hand. There was no audit stream to show "event published → nothing handled it."
- ~5–10 `print()` calls in taro swallowed real diagnostics (LLM errors, token-deduction failures) to stdout.

Goal: **one** logging layer, on disk, structured, with a domain-event audit trail — and it must never crash the app.

## Design (D9)

The layer rides the `logs/` namespace of the S58 `FilesystemManager`, so it inherits path confinement, the append/rotation policy, perms, and a single var-root. Two pieces, installed once at boot:

1. **`VbwdLogRouter`** — a single `logging.Handler` on the **root** logger. Per record it derives:
   - **scope** from the logger name: `plugins.<id>.…` → `<id>`; `vbwd.…` / root / third-party → `core`.
   - **stream** from the level: ERROR/CRITICAL → `error`, WARNING → `warnings`, INFO → `info`; below INFO dropped.
   - writes one **redacted JSON line** via `filesystem_manager.append_with_rotation("logs", "<scope>/<stream>.log", …)`.
2. **`EventLogSubscriber`** — subscribed to all EventBus publishes; mirrors each to `logs/core/events.log` (the global audit), plus `logs/<plugin>/events.log` when the event is attributable.

### On-disk layout
```
${VBWD_VAR_DIR}/logs/
├── core/{error,warnings,info,events}.log     # vbwd.* + anything non-plugin
└── <plugin>/{error,events}.log               # cms, ghrm, email, booking, taro, …
```

### Per-scope allowlist + "folding"
Default: `core` → `{error,warnings,info}`; each plugin → `{error}` only. A record whose `(scope, stream)` isn't allowed is **redirected to the `core` file for that stream** — but the JSON keeps the original `scope`/`logger`, so attribution survives. This keeps per-plugin dirs lean (`error` + `events`) while still capturing plugin WARNING/INFO (in `core/warnings.log` / `core/info.log`). The allowlist + min-level + rotation limits are all configurable via `LoggingConfig`.

### Line format
```json
{"ts":1749312000.12,"level":"ERROR","scope":"cms","stream":"error","logger":"plugins.cms.src.services.contact_form_service","msg":"send failed","slug":"contact"}
```
Structured context is attached via `extra={"vbwd_extra": {...}}` (merged + redacted).

### Events stream
Every `EventBus.publish(name, payload)` → one JSON line in `core/events.log`:
```json
{"ts":1749312000.5,"event":"contact_form.received","payload":{"recipient_email":"a@b.c","fields":[...]}}
```
Per-plugin attribution is **best-effort** (the bus exposes no publisher identity): an event is attributed only on a reliable signal — a namespaced name `plugins.<id>.…`, or an explicit `_origin`/`origin_plugin` key in the payload. No stack-walking. Un-attributable events stay core-only. **This is the stream that would have made the contact-form bug obvious at a glance.**

### Secret redaction (always on)
Before any write, keys whose lower-cased name contains `password`/`passwd`/`secret`/`token`/`authorization`/`api_key`/`apikey`/`private_key`/`smtp_password`/`client_secret`/`access_token` are masked to `"***"`, recursively through nested dicts/lists, on both log extras and event payloads. The original objects are untouched. (The actual secret *files* live in the `secrets/` namespace and are never logged.)

### Rotation
Size-based per file: at `max_bytes` (default 10 MiB) a file rolls `error.log → error.log.1 → … → .<backups>` (default 5), under an exclusive lock on a sidecar `<file>.lock` so concurrent gunicorn workers never double-rotate. Overridable via `LOG_MAX_BYTES`/`LOG_BACKUPS` (Flask config) or `VBWD_LOG_MAX_BYTES`/`VBWD_LOG_BACKUPS` (env).

### Resilience & boot
`emit()` wraps the whole path in try/except and degrades to **stderr**; the subscriber is equally defensive. Boot wiring (`vbwd/app.py::_install_unified_logging`) is **TESTING-guarded** (not attached under pytest, so the suite isn't polluted and doesn't write `/app/var/logs`; the console handler stays) and best-effort (an unwritable `logs` root still boots).

## Files

| file | role |
|---|---|
| `vbwd/services/logging/router.py` | `VbwdLogRouter` — root handler (scope/stream routing, JSON, rotation) |
| `vbwd/services/logging/subscriber.py` | `EventLogSubscriber` — EventBus → `events.log` |
| `vbwd/services/logging/redaction.py` | `redact()` — recursive secret masking |
| `vbwd/services/logging/config.py` | `LoggingConfig` — allowlist, level band, rotation |
| `vbwd/app.py::_install_unified_logging` | TESTING-guarded boot wiring |
| `vbwd/services/filesystem/{ports,local,memory}.py` | `append_with_rotation` (58.0/58.5) backing the writes |

Tests: `tests/unit/services/logging/` (25 — routing, redaction, rotation, resilience, boot-guard), driven directly with a `tmp_path`/in-memory manager (never via the guarded boot path).

## Adoption audit (post-ship)

- **84 modules** (23 core + 61 plugin) already use `logging.getLogger(__name__)` → **auto-routed**, zero changes. No module uses a non-`__name__` literal logger name (so scope routing works everywhere).
- **cms-ai** (own `RotatingFileHandler` + hardcoded `/app/var/tmp/log-dev`) — migrated in **58.6**: `LoggerService` is now a thin stdlib wrapper named `plugins.cms-ai.*` (so it scopes to `cms-ai`, not `core`); no bespoke handlers, no stray files.
- **taro** — **10 `print()`** diagnostics (services/routes + `handlers.py`, incl. token-deduction-failure and LLM-error sinks) swapped to `logger.exception/warning`, so they now land in `logs/taro/error.log`. Legitimate `bin/` CLI prints left as-is.

After 58.6 + taro, **nothing in the app path bypasses** the unified logging.

## Known limitations / follow-ups

- **Per-plugin event attribution** is best-effort (no bus publisher identity). If full attribution is wanted, the EventBus would need to tag the publisher at `publish()`.
- **DEBUG is dropped** on disk by default (router min-level INFO) — intentional; raise via `LoggingConfig` if needed.
- **cms-ai vendored-tree lint debt** — `--plugin cms-ai` flake8 is red from 645 pre-existing violations in the vendored `loopai` tree (gitignored, never linted); 58.6's own code is clean. Cleaning that tree is a separate task.
- A central **prune/retention scheduler** (TESTING-guarded, meinchat-style) was deferred; size rotation is in place, which bounds per-file growth.

## How to use (quick)

```python
import logging
logger = logging.getLogger(__name__)
logger.error("checkout failed: %s", err)                       # → logs/<scope>/error.log
logger.info("published", extra={"vbwd_extra": {"slug": s}})    # → logs/<scope or core>/info.log
```
Read with `jq`: `jq -c 'select(.event=="contact_form.received")' /app/var/logs/core/events.log`.
Full reference: the developer guide linked above.
