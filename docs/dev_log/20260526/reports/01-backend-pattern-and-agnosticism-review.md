# Backend Pattern & Agnosticism Review — 2026-05-26

**Scope:** `vbwd-backend/` (core `vbwd/` + all plugins under `plugins/`)
**Lens:** TDD · SOLID · DRY · Clean Code · No Over-Engineering · Liskov · DI · DIP · DevOps-first · **Agnosticism (core⇄plugin)**
**Method:** 4 parallel review agents (agnosticism / SOLID-DI / TDD-DRY-clean / DevOps), then spot-verified the headline findings by direct grep.
**Engineering-requirements anchor:** `docs/dev_log/20260525/sprints/_engineering-requirements.md` and CLAUDE.md "Core engineering requirements (BINDING)".

---

## 0. Verdict at a glance

The architecture is sound on paper — clean port/adapter interfaces for entitlement, subscription lifecycle, line-item handlers, deletion dependencies, catalog read model, payment route helpers. Sprint 11 successfully removed subscription from core models. But the audit found **9 critical / high issues that violate the very rules these interfaces were created to enforce**, plus systemic DI hygiene and DRY rot in the plugin tree.

| Pillar | Result |
|---|---|
| **Agnosticism (core)** | ❌ Two hard `from plugins.*` imports in core. Two hardcoded plugin names in `app.py`. |
| **DIP / DI hygiene** | ❌ Routes construct repos with `db.session` inline instead of pulling from container; multiple plugins never register their repos with the container at all. |
| **TDD** | ⚠️ 18 core repositories have **zero** unit tests; 7 core services untested; 4 silently skipped tests with no follow-up. |
| **DRY** | ⚠️ Timestamps + `to_dict()` reimplemented in 4+ payment-plugin models; payment-route boilerplate duplicated across ~9 providers. |
| **Clean code** | ⚠️ Multiple route functions 95-127 LOC; bare `except Exception: pass`; magic numbers. |
| **No over-engineering** | ⚠️ Optional-method "fat" `ILineItemHandler`; a couple of registries that today have one implementation. (Note: `dependency_injector` itself is justified — the agent's call to rip it out is too aggressive given the plugin model. Disagreed with.) |
| **Liskov** | ⚠️ Some payment SDK adapters return `success=False` for unsupported ops instead of raising — silent contract drift. |
| **DevOps-first** | ❌ **6 plugin migration dirs missing from `alembic.ini` version_locations** — `alembic upgrade heads` silently skips them. Migrations run inline in `CMD` before gunicorn (no init container). Health endpoint doesn't probe DB/Redis. |

---

## 1. CRITICAL — Agnosticism violations (verified by grep)

### 1.1 `vbwd/scheduler.py:15-22` imports the booking plugin directly

```python
from plugins.booking.booking.repositories.booking_repository import (
    BookingRepository,
)
from plugins.booking.booking.repositories.resource_repository import (
    ResourceRepository,
)
from plugins.booking.booking.services.booking_completion_service import (
    BookingCompletionService,
)
```

The whole file (and `app.py:323-325`'s `start_booking_scheduler(app)`) treats booking as a privileged citizen of core. The try/except guard around the import softens the symptom but does not fix the violation — core still names a plugin module.

**Fix:** Introduce `IBackgroundJobScheduler` in `vbwd/interfaces/` (mirror of `ISubscriptionLifecycle`). Booking plugin registers its scheduler in `on_enable` via `register_background_job_scheduler(...)`. Core's startup calls `resolve_background_job_scheduler()` — no-op when nothing is registered. Rename `vbwd/scheduler.py` → `vbwd/background_jobs.py` (or move into the booking plugin entirely; the booking-completion job is a booking concern, not a core concern).

### 1.2 `vbwd/routes/admin/access.py:440-441` imports CMS plugin models

```python
from plugins.cms.src.models.cms_page import CmsPage
from plugins.cms.src.models.cms_layout_widget import CmsLayoutWidget
```

A core admin route (`GET /api/v1/admin/access/user-levels/<level_id>/content`) reaches into the CMS plugin's ORM models. Disable CMS → core route 500s on import.

**Fix:** Define an `IAccessLevelContentProvider` port in core (returns a list of `{kind, id, title, slug}` records). CMS plugin registers its provider in `on_enable`. Other content-bearing plugins (shop, taro, etc.) can register too without core touching them.

### 1.3 `vbwd/app.py:206-231` hardcodes the `"analytics"` plugin

```python
# Load persisted state from DB; default-enable analytics on first run
…
plugin_manager.enable_plugin("analytics")
…
analytics_plugin = None
for plugin in plugin_manager.get_all_plugins():
    if plugin.metadata.name == "analytics":
        analytics_plugin = plugin
…
# Register analytics admin blueprint from plugin (for /admin/analytics routes)
if analytics_plugin:
    admin_bp = analytics_plugin.get_admin_blueprint()
    if admin_bp: ...
```

Two distinct sins in one stretch:
1. Default-enabling a specific plugin by name → make `PluginMetadata.auto_enable: bool = False` or read from `config.json`.
2. Special-casing `get_admin_blueprint()` only for `"analytics"` → iterate **every** plugin and call `get_admin_blueprint()`; the method already exists on `BasePlugin`, so registration should be plugin-agnostic.

### 1.4 `vbwd/app.py:323-325` starts a "booking" scheduler from core

```python
if not app.config.get("TESTING"):
    from vbwd.scheduler import start_booking_scheduler
    start_booking_scheduler(app)
```

Companion to 1.1. Same fix: lifecycle hook on `BasePlugin` (`on_app_started(app)` or `register_background_jobs(scheduler)`) and core just iterates plugins.

### 1.5 Plugin-to-plugin deps not declared in `PluginMetadata.dependencies`

Payment plugins (`stripe`, `paypal`, `yookassa`, plus likely `conekta`, `mercado_pago`, `truemoney`, `toss_payments`, `promptpay`, `c2p2`, `token_payment`) call `resolve_subscription_lifecycle()` at webhook time but declare `dependencies=[]`. Per CLAUDE.md's "Core never depends on plugins; plugin→plugin deps must be declared":

> plugin→plugin deps (taro→subscription, meinchat→subscription) are fine but declared in `PluginMetadata.dependencies`.

Each payment plugin that activates subscriptions on capture must add `dependencies=["subscription"]`. Token-only checkout plugins can keep `[]`.

### 1.6 Acknowledged D4 residuals (Sprint 11 / S8 deferred — do NOT re-fix)

- `vbwd/routes/admin/access.py:24` — `analytics.view` permission listed in core (Sprint 11/S8 deferral).
- `vbwd/models/user_access_level.py:46-56` — `linked_plan_slug` column + docstring mentioning "subscription plugin". String slug is minimal coupling; acceptable.
- Invoice `subscription_*` metadata fields, `/deletion-info subscription_count`, `/dashboard/{tokens,subscription/invoices}` routes, `subscription.*` permission names — all per Sprint 11 lock decisions.

---

## 2. CRITICAL — DevOps-first failures (verified)

### 2.1 `alembic.ini` `version_locations` is missing 6 plugin migration dirs

Lists 9 dirs (`taro`, `cms`, `ghrm`, `booking`, `chat`, `shop`, `discount`, `meinchat`, `subscription`). Actually have migrations:

```
booking, c2p2, chat, cms, conekta, discount, ghrm, meinchat,
mercado_pago, promptpay, shop, subscription, taro, toss_payments, truemoney
```

**Missing:** `c2p2`, `conekta`, `mercado_pago`, `promptpay`, `toss_payments`, `truemoney` — every non-Stripe/PayPal payment provider.

**Consequence:** Any environment with these plugins enabled runs an under-migrated DB. Webhook hits → "relation does not exist" → 500 → silent payment loss. This is the worst CI bug in the audit because it bypasses every test that doesn't actually exercise the plugin tables.

**Fix:** Append the 6 missing dirs to the `version_locations` line. While there, consider switching to `recursive_version_locations = true` and dropping the explicit list — it scales as plugins are added.

### 2.2 Migrations run synchronously in `CMD` before gunicorn boots

`container/python/Dockerfile:27`:
```dockerfile
CMD ["sh", "-c", "...alembic upgrade heads && gunicorn ..."]
```

If a migration hangs or errors, the container never becomes healthy and there's no rollback path — the previous good container has already been replaced.

**Fix:** Move `alembic upgrade heads` out of `CMD`. Options: (a) `docker compose run --rm vbwd_backend alembic upgrade heads` as a pre-step in the deploy script; (b) a one-shot init container; (c) a `migrate` service in compose with `depends_on` from `vbwd_backend`. Keep gunicorn's `CMD` to just `gunicorn`.

### 2.3 `Makefile.server:67` runs `alembic upgrade head` (singular)

Should be `heads` (plural) — core + each plugin have separate revision heads. Singular `head` is undefined when multiple heads exist and will fail or silently underapply.

### 2.4 Health endpoint `/api/v1/health` (`vbwd/app.py:255-258`) returns 200 unconditionally

No DB or Redis probe. Kubernetes / load balancer will route to a broken container. Add a `/ready` that does `SELECT 1` and `redis.ping()` and returns 503 on failure; keep `/health` as a liveness check.

### 2.5 Secret defaults baked into compose

`docker-compose.yaml:10-11` and `docker-compose.server.yaml:27`:
```yaml
FLASK_SECRET_KEY=${FLASK_SECRET_KEY:-dev-secret-key-change-in-production}
JWT_SECRET_KEY=${JWT_SECRET_KEY:-dev-jwt-secret-change-in-production}
```

A missing env var in prod silently produces a known-insecure key. Replace the `:-default` with the mandatory form `${VBWD_FLASK_SECRET:?VBWD_FLASK_SECRET is required}`.

### 2.6 `vbwd-backend/.env` committed

`.env` is in `.gitignore` but tracked — `git rm --cached vbwd-backend/.env` and confirm in CI that the file is absent before allowing merge.

### 2.7 `vbwd_backend` service missing `restart: always` in `docker-compose.server.yaml`

Every other prod service has it. A single backend crash = manual recovery.

### 2.8 CI plugin clone loop has no error handling

`.github/workflows/tests.yml:87-89` — `git clone` failures don't `exit 1`. CI reports green even when plugins are missing. Wrap each clone in `|| exit 1` (or build a `requires.txt`-style manifest and fail fast on any failure).

---

## 3. HIGH — DI / DIP discipline

### 3.1 Routes construct services inline instead of pulling from the container

`vbwd/routes/auth.py:56-57` (and ~8 sites across `auth.py`, `user.py`, `invoices.py`):
```python
user_repo = UserRepository(db.session)
auth_service = AuthService(user_repository=user_repo)
```

A `Container` exists for a reason. Pull `current_app.container.auth_service()`. The current pattern means swapping repos for test doubles requires monkeypatching `db.session`, and DI configuration in `container.py` is effectively dead code for the routes.

### 3.2 Several plugins never register their repositories with the DI container

Confirmed missing for **shop, booking, meinchat** (CLAUDE.md memory `project_plugin_di_provider_registration.md` records the same kind of bug took down checkout in 2026-03-27). Subscription plugin does it correctly — use it as the reference:

```python
def on_enable(self):
    container = getattr(current_app, "container", None)
    if container is None:
        return
    container.shop_product_repository = providers.Factory(
        ProductRepository, session=container.db_session
    )
    ...
```

### 3.3 Module-level mutable registries used as a DI substitute

`vbwd/events/line_item_registry.py:237`, `vbwd/services/deletion_dependency_registry.py:17`, `vbwd/services/demo_data_registry.py:14`, `vbwd/services/entitlement.py:78`, `vbwd/services/subscription_lifecycle.py:95`, `vbwd/services/subscription_read_model.py:50`, `vbwd/services/catalog_read_model.py:36` — all module-level mutables, no lock. Plugin `on_enable` mutates them; tests `clear_*` them. Race-prone under parallel test execution; leaks between tests if a plugin's `on_disable` doesn't unregister.

**Fix (preferred):** Move them into `Container` as `providers.Singleton(LineItemHandlerRegistry)` etc. Plugins register against the container instance, not a module global. Tests get a fresh container per test app and no cross-talk.
**Fix (minimum):** Add `threading.RLock` and matching `unregister_*` functions called from `on_disable`.

### 3.4 Plugin handlers receive raw `db.session` and build repos inline

`plugins/booking/__init__.py:118-121`:
```python
handler = BookingPaymentHandler(
    session=db.session,
    booking_repository=BookingRepository(db.session),
    resource_repository=ResourceRepository(db.session),
)
```

Same anti-pattern as 3.1 inside plugins. Once 3.2 is fixed, this turns into `container.booking_repository()`.

---

## 4. HIGH — LSP / OCP / ISP

### 4.1 LSP: payment SDK adapters return `success=False` for unsupported ops

`plugins/mercado_pago/mercado_pago/sdk_adapter.py:63-77` (and Conekta has the same pattern):
```python
def capture_payment(self, payment_intent_id, idempotency_key=None) -> SDKResponse:
    return SDKResponse(success=False, error="Mercado Pago captures on user redirect; ...")
def release_authorization(self, payment_intent_id) -> SDKResponse:
    return SDKResponse(success=False, error="Mercado Pago preferences do not support release")
```

The `ISDKAdapter` contract says `capture_payment` performs a capture. Returning `success=False` for "I structurally cannot do this" is a soft failure that callers will treat as a transient error — retry storms, spurious refunds. Define `UnsupportedOperationError` and raise it; let the route translate that to a 4xx/5xx as appropriate. Better still: split the interface (see ISP below).

### 4.2 ISP: `ILineItemHandler` is fat

Core 4 abstract methods + 3 optional methods (`resolve_catalog_item_id`, `is_recurring_line_item`, `recurring_billing_spec`). Split:
- `ILineItemHandler` (the 4 mandatory ops)
- `ICatalogMappedLineItem` (mixin: `resolve_catalog_item_id`)
- `IRecurringLineItem` (mixin: `is_recurring_line_item` + `recurring_billing_spec`)

Same prescription fits SDK adapters: a base `IPaymentSDKAdapter` with the universal ops, plus `ICapturableSDKAdapter` for providers that actually support deferred capture/release. The OCP "if Stripe / if PayPal" branches in payment helpers disappear automatically.

### 4.3 OCP: `PasswordResetHandler.handle()` does `isinstance` branching

`vbwd/handlers/password_reset_handler.py:54-59` — split into `PasswordResetRequestHandler` + `PasswordResetExecuteHandler`. Trivial refactor, removes the one-handler-many-events smell.

---

## 5. HIGH — TDD discipline

### 5.1 18 core repositories have zero unit tests

There is **no `vbwd-backend/tests/unit/repositories/` directory**. Repos covered only via HTTP-level integration tests:

```
country_repository, currency_repository, feature_usage_repository,
invoice_line_item_repository, invoice_repository, password_reset_repository,
payment_method_repository, plugin_config_repository, role_repository, tax_repository,
token_bundle_purchase_repository, token_bundle_repository, token_repository,
user_details_repository, user_repository  (+ 3 more)
```

Repository tests are cheap, fast, and catch query-shape regressions integration tests miss. This is the single biggest TDD gap.

### 5.2 7 core services untested

`activity_logger.py`, `catalog_read_model.py`, `deletion_dependency_registry.py`, `demo_data_registry.py`, `entitlement.py`, `subscription_lifecycle.py`, `subscription_read_model.py`. These are exactly the agnosticism-port surfaces — they MUST have unit tests against their interfaces (null-default behavior, register/resolve, double-register, register-during-test cleanup).

### 5.3 Silently skipped tests

`tests/unit/routes/test_rate_limiting.py:31, 75, 94, 123` — 4 tests skipped with `"Rate limiting not reliably testable in unit test environment"`. Either mock Redis (the right answer) or move to integration. As-is it's coverage theatre.

### 5.4 Plaintext-token TODOs in `plugins/ghrm/src/services/github_access_service.py:98, 199`

`# TODO: encrypt in production` for OAuth + deploy tokens. **Don't ship until encrypted.** Add the test that asserts stored tokens are not plain (and add a model-level encrypted-column wrapper).

### 5.5 `vbwd/utils/datetime_utils.py:10` — `TODO: migrate to timezone-aware datetimes`

Touches every model with timestamps. Add the regression tests first, then migrate.

---

## 6. MEDIUM — DRY

### 6.1 Timestamp + `to_dict()` duplicated in every payment plugin's models

`plugins/conekta/conekta/models.py:29-58`, `plugins/mercado_pago/mercado_pago/models.py:28-58` (and almost certainly `truemoney`, `toss_payments`, `promptpay`, `c2p2`). Each re-declares:

```python
created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
updated_at = Column(..., onupdate=lambda: datetime.now(timezone.utc))
def to_dict(self): ...  # same isoformat dance
```

Core already exports `BaseModel`. Either inherit from it directly or extract a `PluginTimestampedModel` mixin. ~40 LOC × ~5 plugins = 200 LOC + 5 places to forget when the timestamp policy changes.

### 6.2 Payment-route boilerplate duplicated across providers

Frontend-URL derivation (`Origin` / `Referer` / iOS deep-link), error envelope, metadata extraction (invoice_id, user_id), webhook signature plumbing — all reimplemented in `stripe`, `paypal`, `conekta`, `yookassa`, `mercado_pago`, `truemoney`, `toss_payments`, `promptpay`. Add to `vbwd/plugins/payment_route_helpers.py`:

```python
def build_redirect_urls(provider: str, request) -> tuple[str, str]: ...
def payment_error(reason: str, status: int = 500): ...
def extract_invoice_context(request) -> InvoiceContext: ...
```

### 6.3 Pagination boilerplate in every admin list route

`vbwd/routes/admin/{invoices,users,payment_methods}.py` each parse `limit` / `offset` with the same `min(int(...), 100)` dance. Extract `parse_pagination_params(request)` into `vbwd/utils/pagination.py`.

---

## 7. MEDIUM — Clean code

### 7.1 Oversized route handlers (refactor into services)

| File | Function | LOC |
|---|---|---|
| `vbwd/routes/admin/users.py:197` | `update_user` | **127** |
| `vbwd/routes/admin/users.py:19` | `create_user` | **111** |
| `vbwd/routes/admin/payment_methods.py:38` | `create_payment_method` | **95** |
| `vbwd/routes/admin/invoices.py:280` | `refund_invoice` | 81 |
| `plugins/stripe/stripe/routes.py:380` | `_handle_refund_updated` | 75 |

Routes should be transport, not logic. Push each into a service method, leave route at ~15 LOC for validation + dispatch + serialization.

### 7.2 Silent excepts

- `vbwd/plugins/config_schema.py:62` — `except Exception: continue` swallowing config-load failures.
- `vbwd/models/invoice_line_item.py:56` — `except Exception: return None` with no log.
- `vbwd/routes/admin/users.py:107` — `except Exception: pass` for optional event dispatch.

Narrow each to the specific exception, log at `debug` (optional path) or `warning` (unexpected).

### 7.3 Magic numbers

`int(line_item.unit_price * 100)` for Stripe cents (multiple sites), `min(limit, 100)` for max page size (every list route), implicit transaction timeouts. Pull into named constants in `vbwd/config.py` or per-plugin `constants.py`.

---

## 8. MEDIUM — No over-engineering

Honest accounting: most of the architecture is *not* over-engineered — the registry/port pattern earns its keep because plugins are real and out-of-tree.

What I would still trim:

- **`PluginManager` has unused methods** — `initialize_plugin`, `enable_plugin`, `disable_plugin`. Remove or wire to the admin enable/disable endpoint properly.
- **Single-implementation interfaces** — `ISubscriptionReadModel`, `ICatalogReadModel` today have exactly one implementer each (the subscription plugin). Keep the interface (extensibility is the whole point of the architecture) but stop hand-rolling a null-object fallback that duplicates the no-op default — pick one of the two patterns.
- **`EmailService.send_welcome_email` / `send_invoice` etc.** — these are concrete methods on a service whose `send_template()` already generalises the work. Drop the named methods; let callers compose.

I'm **disagreeing** with one earlier suggestion: don't rip out `dependency_injector`. With multiple plugins each owning repos that need wiring at runtime, the declarative container is the *least* engineered solution that works. The fix is "use it correctly everywhere" (sections 3.1-3.4), not "remove it".

---

## 9. Prioritised action list

**Block release until done (security / correctness):**
1. §1.1, §1.2 — remove `from plugins.*` imports from `vbwd/` (port + register pattern). [Critical]
2. §2.1 — add the 6 missing plugin migration paths to `alembic.ini`. [Critical, one-line fix]
3. §2.2 — move `alembic upgrade heads` out of the container `CMD`. [Critical]
4. §2.3 — `head` → `heads` in `Makefile.server:67`. [One-line fix]
5. §2.5 — replace `:-default` secret fallbacks with required-form `${…:?…}`. [Critical, security]
6. §2.6 — `git rm --cached vbwd-backend/.env`. [Security]
7. §5.4 — ship `ghrm` token encryption before any production enable. [Security]

**Next sprint (architecture hygiene):**
8. §1.3, §1.4 — remove hardcoded `"analytics"` / `"booking"` from `app.py`; add `auto_enable` metadata flag + plugin-iterating admin-blueprint registration.
9. §1.5 — declare `dependencies=["subscription"]` on every payment plugin that calls `resolve_subscription_lifecycle()`.
10. §3.1, §3.2 — routes pull from container; shop / booking / meinchat register their repos in `on_enable`.
11. §3.3 — move shared registries into `Container` as `Singleton` providers (or add `RLock` + `unregister_*`).
12. §4.1, §4.2 — raise `UnsupportedOperationError` from SDK adapters; split `ILineItemHandler` and `IPaymentSDKAdapter`.
13. §2.4 — real `/api/v1/ready` with DB+Redis probe.
14. §2.7 — `restart: always` on `vbwd_backend` in `docker-compose.server.yaml`.
15. §2.8 — fail-fast plugin clone in CI.

**Background quality (no specific deadline):**
16. §5.1 — write repository unit tests (start with `user_repository`, `invoice_repository`, `token_repository`).
17. §5.2 — service unit tests for the agnosticism ports.
18. §5.3 — mock Redis in rate-limit unit tests (kill `@pytest.mark.skip`).
19. §6.1, §6.2, §6.3 — extract shared base model + payment-route helpers + pagination util.
20. §7.1 — refactor 5 oversized route handlers into services.
21. §7.2, §7.3 — narrow excepts; magic numbers → constants.
22. §8 — drop `PluginManager` dead methods; collapse `EmailService` named-template helpers.

---

## 10. Files referenced

Core hot-spots:
- `vbwd-backend/vbwd/scheduler.py:15-22`
- `vbwd-backend/vbwd/routes/admin/access.py:440-441`
- `vbwd-backend/vbwd/app.py:206-231, 323-325, 255-258`
- `vbwd-backend/alembic.ini` (`version_locations`)
- `vbwd-backend/container/python/Dockerfile:27`
- `vbwd-backend/Makefile.server:67`
- `vbwd-backend/docker-compose.yaml:10-11`
- `vbwd-backend/docker-compose.server.yaml:27`
- `vbwd-backend/vbwd/handlers/password_reset_handler.py:54-59`
- `vbwd-backend/vbwd/events/line_item_registry.py:86-112, 210-227, 237`
- `vbwd-backend/vbwd/services/{entitlement,subscription_lifecycle,subscription_read_model,catalog_read_model,deletion_dependency_registry,demo_data_registry}.py`
- `vbwd-backend/vbwd/routes/{auth,user,invoices}.py` (inline `Repo(db.session)`)
- `vbwd-backend/vbwd/routes/admin/{users,invoices,payment_methods}.py` (oversized handlers + pagination dup)

Plugins:
- `plugins/{shop,booking,meinchat}/__init__.py` (`on_enable` missing DI registration)
- `plugins/{stripe,paypal,yookassa,conekta,mercado_pago,truemoney,toss_payments,promptpay,c2p2,token_payment}/__init__.py` (missing `dependencies=["subscription"]`)
- `plugins/mercado_pago/mercado_pago/sdk_adapter.py:63-77` (LSP)
- `plugins/{conekta,mercado_pago,truemoney,toss_payments}/.../models.py` (timestamp dup)
- `plugins/ghrm/src/services/github_access_service.py:98, 199` (plaintext tokens TODO)
