# Sprint 58 — Unified `FilesystemManager` for the `${VBWD_VAR_DIR}` (and uploads) tree

**Status:** PLANNED — 2026-06-07. Decisions **D1–D9 PROPOSED** (ratify before 58.0). **D9 adds unified logging** over the `logs/` namespace.
**Area:** core `vbwd-backend` (`vbwd/services/filesystem/`) — a new **agnostic core service** + port, consumed by plugins (ghrm, cms, meinchat, shop, booking, cms-ai) and core (settings, plugin manifests) via DI. **No core→plugin dependency** ([[feedback_core_never_depends_on_plugins]]); the manager knows files, not domains.
**Shape:** umbrella + sub-sprints (the `s48-*` pattern). One keystone (58.0) then independent per-consumer migrations.

## Why (the problem — measured by inventory)

Every subsystem that writes under `${VBWD_VAR_DIR:-/app/var}` (and `/app/uploads`) reinvents file access, inconsistently. Today:

| consumer | path | mechanism | atomic? | traversal guard | perms | lock |
|---|---|---|---|---|---|---|
| Plugin manifests | `plugins/*.json` | `open(w)`+`json.dump` **in-place** | ❌ | ❌ | ❌ | ❌ (3 containers race) |
| Core settings | `core/vbwd_settings.json` | `mkstemp`+`os.replace` | ✅ | ❌ | ❌ | last-writer-wins |
| GHRM private key | `ghrm/auth/github-app.pem` | `open(r)` only | n/a | ❌ (isfile) | ⚠️ external chmod | n/a |
| SEO prerender | `seo/<slug>.html` | `open(w)`+write | ❌ | ⚠️ slug assumed safe | ❌ | ❌ |
| Uploads (cms/shop/booking/meinchat) | `/app/uploads/**` | `makedirs`+`open(wb)` | ❌ | ✅ (cms guard) | ❌ | ❌ |
| cms-ai logs | `logs/`, hardcoded `tmp/log-dev/` | `open(a)` append | ❌ | ❌ | ❌ | ❌ |

**Concrete bugs this causes:** a reader container can see **half-written plugin JSON** during a write (no atomicity, no lock); concurrent SEO publish events **truncate** an HTML file; the GitHub App private key sits **plaintext, world-readable inside the container**; `IFileStorage` is **duplicated** (`vbwd/interfaces/file_storage.py` **and** `plugins/cms/src/services/file_storage.py`); var paths are derived from a **scatter** of `os.environ.get("VBWD_VAR_DIR", "/app/var")` + six `VBWD_*_JSON` env vars with no single source of truth.

## Goal

One **agnostic core `FilesystemManager`** that is the single, safe, testable way to touch the managed tree. Every consumer routes through it; nobody calls `open()` on a var path directly. It centralises **path confinement, atomic-vs-in-place write policy, advisory locking, permissions, optional encryption, and JSON helpers** — once, correctly.

## Engineering requirements (BINDING — restated in every sub-sprint)

**TDD-first** · **DevOps-first** · **SOLID** (the manager is a port with swappable impls; per-namespace policy is open for extension) · **Liskov** · **DI** · **DRY** (kill the duplicate `IFileStorage`) · clean code · **NO OVERENGINEERING** (narrowest manager that absorbs the six consumers — not a VFS). Full readable names ([[feedback_variable_naming]]). **`bin/pre-commit-check.sh` is the quality guard** — `--plugin <touched> --full` / core gate green = "done". No raw SQL is irrelevant here, but: **no behaviour change to served upload URLs or to the bind-mounted manifest contract without an explicit decision.** Core stays agnostic ([[feedback_core_never_depends_on_plugins]]); the manager is consumed via the DI container, exactly like `register_repositories` ([[project_plugin_di_provider_registration]]).

## Architecture

### The managed tree (single source of truth)

The manager owns a set of **roots** and, within each, named **namespaces** with a policy:

```
${VBWD_VAR_DIR:-/app/var}/
├── core/        settings JSON            policy: ATOMIC_REPLACE
├── plugins/     enable/config manifests  policy: INPLACE_LOCKED   (bind-mounted single files — D2)
├── seo/         prerendered HTML         policy: ATOMIC_REPLACE + slug→safe-path
├── secrets/     ghrm pem, bot tokens…    policy: ATOMIC_REPLACE + 0600 + optional encrypt (D4)
├── logs/        unified logging (D9)     policy: APPEND + rotation
│   ├── core/{error,warnings,info,events}.log
│   └── <plugin>/{error,events}.log       (cms, ghrm, email, booking, …)
└── tmp/         scratch                  policy: best-effort
${UPLOADS_BASE_PATH:-/app/uploads}/        (a managed root — D5)
└── uploads/     cms/shop/booking/meinchat blobs  policy: ATOMIC_REPLACE + traversal guard + url_for
```

### Port + service (core, `vbwd/services/filesystem/`)

```python
class IFilesystemManager(Protocol):
    # All paths are (namespace, relative_path); the manager resolves + confines them.
    def read_text(self, ns: str, rel: str) -> str: ...
    def read_bytes(self, ns: str, rel: str) -> bytes: ...
    def write_text(self, ns: str, rel: str, text: str) -> str: ...      # policy-driven write
    def write_bytes(self, ns: str, rel: str, data: bytes) -> str: ...
    def read_json(self, ns: str, rel: str, default=None) -> Any: ...    # corrupt/missing → default
    def write_json(self, ns: str, rel: str, obj: Any) -> str: ...       # dump→fsync→replace
    def append_text(self, ns: str, rel: str, text: str) -> None: ...    # logs
    def delete(self, ns: str, rel: str) -> None: ...
    def exists(self, ns: str, rel: str) -> bool: ...
    def listdir(self, ns: str, rel: str = "") -> list[str]: ...
    def url_for(self, ns: str, rel: str) -> str: ...                    # uploads → public URL
    def resolve(self, ns: str, rel: str) -> str: ...                    # absolute path (for read-only handoff, e.g. ghrm pem)
```

- **`LocalFilesystemManager`** — real impl; per-namespace `NamespacePolicy(write_mode, dir_mode, file_mode, encrypt, base_root, url_base)`.
- **`InMemoryFilesystemManager`** — test impl (supersedes both `InMemoryFileStorage` copies).
- Registered on the core container in `app` setup; plugins resolve `container.filesystem_manager()` and never import a sibling.

### Write policies (the crux — D2)

- **`ATOMIC_REPLACE`** (default) — write to a temp file in the same dir, `flush`+`os.fsync`, `os.replace()`. Crash-safe, no torn reads. Used by core settings (already does this), SEO, secrets, uploads.
- **`INPLACE_LOCKED`** — **for bind-mounted single files** (the plugin manifests): `os.replace` across the bind-mount inode fails with *"Device or resource busy"*, so a temp+rename is impossible. Instead: acquire an **advisory `fcntl.flock`** on the target (works across the 3 bind-mounted containers — same host inode), `open(r+)`, truncate, write, `fsync`, release. A reader takes a shared lock → never sees a half-written manifest. This **fixes the torn-read race** without breaking the bind-mount contract.
- **`APPEND`** — `open(a)` under a short lock for log lines.

### Path confinement (D3 — centralised guard)

Every `(ns, rel)` is validated once: reject absolute paths, `..` segments, NUL bytes; `realpath` must stay within the namespace dir (defeats symlink escape, which the current CMS `startswith` check does not). One implementation replaces the per-consumer (and missing) guards.

### Unified logging (D9) — `LogManager` over the `logs/` namespace

Today logging is scattered: every plugin does `logging.getLogger(__name__)` to stdout (lost when the container rotates), the only on-disk logs are cms-ai's hardcoded files, and a domain event (e.g. `contact_form.received`) leaves **no trace** — which is exactly why the contact-form bug was invisible until traced by hand. D9 adds **one** logging layer, built on the `logs/` namespace, that routes every log line *and* every domain event to a predictable file per scope.

**Layout** (scope = `core` or a plugin id, derived automatically):
```
logs/
├── core/                       # everything under the vbwd.* logger namespace
│   ├── error.log    ERROR+
│   ├── warnings.log WARNING
│   ├── info.log     INFO
│   └── events.log   every EventBus event (global audit trail)
└── <plugin>/                   # cms, ghrm, email, booking, …
    ├── error.log    ERROR+ from plugins.<plugin>.*
    └── events.log   events published by that plugin
```

**Mechanism (one handler + one event subscriber — no per-plugin wiring):**
- A single `VbwdLogRouter` (a `logging.Handler`) is installed on the **root** logger at app boot. For each record it derives **scope** from the logger name (`plugins.<id>.…` → `<id>`; `vbwd.…`/root → `core`) and **stream** from level (ERROR/CRITICAL→`error.log`, WARNING→`warnings.log`, INFO→`info.log`), then writes one **JSON line** via `filesystem_manager.append_text("logs", f"{scope}/{stream}.log", line)`. Plugins keep using plain `logging.getLogger(__name__)` — routing is automatic.
- An `EventLogSubscriber` on the `EventBus` writes every `publish(name, payload)` to `core/events.log` (always) **and** to `<plugin>/events.log` when the event originates inside a plugin (the bus tags the publisher; core-only when unknown). This is the audit stream that makes "the event fired but nothing handled it" visible.
- **Default stream set per scope (matches the requested shape):** `core` → `{error, warnings, info, events}`; each plugin → `{error, events}` (a plugin's INFO/WARNING fold into the core streams by default, keeping per-plugin dirs lean). Both the per-scope min-level and the stream all-list are configurable.
- **Format:** JSON-lines `{ts, level, scope, logger, msg, …extra}` — grep/`jq`-friendly, consistent with the existing structured-WARN telemetry (429 lines).
- **Append-safe** across gunicorn workers via the namespace's `APPEND` policy (O_APPEND + short lock).
- **Rotation/retention:** size-based rotation per file (`max_bytes` + `backups`, `error.log`→`error.log.1`…) plus an optional **TESTING-guarded prune scheduler** (reuse the meinchat retention pattern) capping total age/size — a log must never fill the disk (a DoS). Console handler stays additive in dev.

Logging goes **through the FilesystemManager** (not its own `open()`) so it inherits confinement, the append policy, perms, and the single var-root — and so a plugin can't accidentally write outside `logs/<its-own-scope>/`.

## Open decisions (PROPOSED 2026-06-07)

- **D1 — Manager is agnostic CORE infrastructure.** Port + impls live in `vbwd/services/filesystem/`, DI-exposed; plugins consume via the container. It routes files, not domains → passes the agnosticism oracle (core never imports a plugin). *(Rejected: a shared library each plugin vendors — re-duplicates today's problem.)*
- **D2 — Per-namespace write policy, incl. `INPLACE_LOCKED` for bind-mounted manifests.** A single `ATOMIC_REPLACE` everywhere would reintroduce the *"Device or resource busy"* failure on the bind-mounted plugin JSONs. Policy-per-namespace is the narrowest correct model.
- **D3 — Mandatory path confinement** (realpath-within-namespace, reject `..`/absolute/symlink-escape) on every op.
- **D4 — `secrets/` namespace = `0600` + optional `TokenCipher` encryption** (reuse `vbwd/utils/crypto.py`). GHRM pem migrates here; **external provisioning stays supported** via `resolve()` for a read-only, pre-placed key. Future bot-base/bot-telegram tokens use this namespace too ([[feedback_plugin_baseline_config_files]]).
- **D5 — Uploads stay at `${UPLOADS_BASE_PATH:-/app/uploads}` as a *managed root*, not physically moved under var.** Moving them would break already-served URLs and on-disk data. The manager registers `uploads` as a root with its own `url_base`; a physical consolidation under `var/uploads` is a **separate, opt-in migration**, out of scope here. *(Rejected: relocate now — needless data migration + URL breakage.)*
- **D6 — Delete the duplicate `IFileStorage`.** `plugins/cms/src/services/file_storage.py` and `vbwd/interfaces/file_storage.py` collapse into the manager. CMS/shop/booking/meinchat call the `uploads` namespace; a thin `IFileStorage`-shaped adapter over the manager preserves existing call-sites where cheap (DRY without a big-bang rewrite).
- **D7 — Advisory locking via `fcntl.flock`** (POSIX); a **no-op lock fallback** on platforms without flock (dev single-process) so tests/dev never hang. Cross-container coordination works because the bind-mount shares the host inode.
- **D8 — Var root + namespace paths come from the manager**, replacing the scatter of `VBWD_VAR_DIR` reads and the six `VBWD_*_JSON` env vars. Those env vars are **honoured as per-file overrides** for back-compat (prod compose sets them), but new code asks the manager for `(ns, rel)`.
- **D9 — Unified logging over the `logs/` namespace.** One root `VbwdLogRouter` handler + one `EventLogSubscriber` route every log record (by `logger-name → scope`, `level → stream`) and every domain event to `logs/<scope>/<stream>.log` — `core/{error,warnings,info,events}.log` and `<plugin>/{error,events}.log`. JSON-lines, append-safe, size-rotated, prune-guarded. Plugins keep `getLogger(__name__)`; no per-plugin handler wiring. *(Rejected: each plugin configures its own file handler — re-scatters paths, loses the events stream, and bypasses confinement/rotation. Rejected: a third-party log framework — overkill; stdlib `logging` + the manager suffices.)*

## Security (CRITICAL)

1. **Confinement (D3)** — realpath-within-namespace defeats `../` and symlink escape; the current CMS `startswith` guard is replaced (it passes a symlink that resolves outside).
2. **Secrets (D4)** — `0600`, dir `0700`, optional encryption; tokens never logged; never returned by any API; the GitHub App key stops being world-readable inside the container.
3. **Torn-read elimination (D2)** — locked in-place + atomic-replace mean a reader never observes a partial manifest/HTML/settings file.
4. **Durability** — `fsync` before `replace`; a disk-full write fails cleanly on the temp file, leaving the previous good file intact (no truncation).
5. **No path from user input to the filesystem unmediated** — slugs/filenames pass through `secure`-style normalisation in the manager, not at each call-site.
6. **Logging hygiene (D9)** — logs MUST NOT contain secrets or raw PII: the router applies a redaction pass (token/`Authorization`/password/`smtp_password`-style keys masked) before write, and the `secrets/` values (D4) are never logged. Rotation + the prune scheduler bound total log size so a noisy/abusive path can't fill the disk (a DoS). `logs/<plugin>/` is write-confined to that plugin's scope.

## TDD plan (tests FIRST)

- **Manager unit** (`InMemoryFilesystemManager` + a `tmp_path` `LocalFilesystemManager`):
  - confinement: `..`, absolute, NUL, and a symlink escaping the namespace all raise; legal nested paths pass.
  - `ATOMIC_REPLACE`: a write interrupted before `replace` leaves the old content intact; no temp file left behind.
  - `INPLACE_LOCKED`: target inode is preserved across writes (proves no rename — the bind-mount contract); concurrent writer/reader under flock never yields a torn read (thread test).
  - `write_json/read_json` round-trip; corrupt JSON → `default`.
  - secrets policy: file mode `0600`; encrypted namespace round-trips through `TokenCipher` and the on-disk bytes are ciphertext.
  - `url_for` maps an uploads rel-path to the configured public URL.
- **Unified logging (D9):** the router maps `logging.getLogger("plugins.cms.x").error(...)` → `logs/cms/error.log` and `getLogger("vbwd.y").info(...)` → `logs/core/info.log` (scope+stream derivation); a record at WARNING from a plugin folds to `core/warnings.log` per the default stream-set; an `EventBus.publish("contact_form.received", …)` appends a JSON line to `core/events.log` (and the plugin's `events.log` when attributed); rotation rolls a file at `max_bytes`; the **redaction** pass masks a `password`/token field; concurrent appends from two threads don't interleave a line. Output lines parse as JSON.
- **Per-consumer migration tests** live in each sub-sprint and assert *behaviour-unchanged* (same bytes, same path, same URL) plus the new guarantee (atomic/locked/0600).

## Sub-sprints

| # | Sprint | Scope | Gate |
|---|---|---|---|
| **58.0** | **FilesystemManager core** | port + `Local`/`InMemory` impls, namespace policies, confinement (D3), write modes (D2), JSON/append helpers, flock (D7), DI registration | core `--full` green; manager unit suite green |
| **58.1** | Core settings + plugin manifests | route `core_settings_store` + `frontend_plugins` through the manager (`core`=ATOMIC, `plugins`=INPLACE_LOCKED); honour `VBWD_*_JSON` overrides (D8) | core `--full` green; **torn-read race gone** (concurrency test); manifests byte-identical |
| **58.2** | SEO prerender | `seo_prerender` / `seo_asset_stamp` / `seo_wiring` → `seo` namespace (atomic + slug-safe path) | `--plugin cms --full` green; concurrent-publish no longer truncates |
| **58.3** | Uploads consolidation (D6) | cms/shop/booking/meinchat → `uploads` namespace; **delete** the duplicate `IFileStorage`; keep served URLs identical | `--plugin cms/meinchat/shop/booking --full` green; upload+serve round-trip unchanged |
| **58.4** | Secrets namespace (D4) | `secrets` namespace (0600 + optional encrypt); GHRM pem read via manager (external provisioning still works); ready for bot-base/bot-telegram tokens | `--plugin ghrm --full` green; key no longer world-readable |
| **58.5** | Unified logging (D9) | `VbwdLogRouter` (root handler, scope+stream routing, JSON-lines, redaction, rotation) + `EventLogSubscriber` on the EventBus; install at app boot; per-scope config + TESTING-guarded prune | core `--full` green; logs land under `logs/core/*` + `logs/<plugin>/*`; events.log captures a published event; redaction + rotation covered |
| **58.6** (opt.) | Migrate stragglers | cms-ai's hardcoded `logs/`/`tmp/log-dev/` onto the unified router + `tmp/` scratch via the manager; drop the bespoke logger | `--plugin cms-ai --full` green |

**Order:** 58.0 keystone → then 58.1–58.6 independently (each behind the manager, each re-greens only its own gate). 58.5 depends only on 58.0 (the `logs/` namespace) + the EventBus.

## Why this is not overengineering

The manager absorbs **six existing, already-required** file-access sites into one ~200-line service with a port and an in-memory test double — it adds no capability the system doesn't already use; it removes duplication (`IFileStorage` ×2), centralises a guard most call-sites lack, and fixes three concrete correctness bugs (torn manifest reads, truncated SEO files, world-readable secret). It is **not** a virtual filesystem, not pluggable backends (S3 etc. is explicitly out of scope until a consumer needs it), and it does **not** relocate upload data (D5). The unified logging (D9) is likewise **stdlib `logging` + one handler + one event subscriber** over the existing `logs/` namespace — not a log framework; it replaces today's lost-to-stdout logging and the cms-ai one-off, and adds the missing **events** audit stream (the gap that hid the contact-form failure) for ~one file's worth of code. Core stays agnostic; every consumer change is narrow and behind the new seam.
