# Sprint 25b: Backend Static Analysis & Dead Code Cleanup

## Goal
Fix all Black, Flake8, and Mypy errors. Remove dead code accurately — verify each removal doesn't break tests. Target: 0 Black reformats, 0 Flake8 errors, 0 Mypy errors (excluding structural SQLAlchemy/Flask false positives).

## Engineering Principles
- **Accurate dead code removal**: Verify each import/file is truly unused before deleting. Check `grep` for references. Never delete something that might be used at runtime via reflection/DI.
- **No suppression**: Do NOT add `# type: ignore`, `# noqa`, or `# pragma: no cover` to hide problems. Fix properly.
- **No overengineering**: Minimal changes per issue. Don't refactor surrounding code.
- **Preserve behavior**: All 661 unit tests + 76 Stripe tests must pass after every change.

## Current State (Baseline)

| Check | Count | Status |
|-------|-------|--------|
| Black | 35 files need reformatting | FAIL |
| Flake8 | 60 errors (F401, F841, E712, E501) | FAIL |
| Mypy | 100 errors | FAIL |
| Unit tests | 661 passed, 4 skipped | PASS |
| Stripe tests | 76 passed | PASS |
| Dead test | `test_mock_payment_plugin.py` — imports deleted module | BROKEN |

## Testing Approach

```bash
# After each batch of changes, verify:
cd vbwd-backend

# 1. Black
docker compose run --rm -T test black --check src/ tests/

# 2. Flake8
docker compose run --rm -T test flake8 src/ tests/ --max-line-length=120 --extend-ignore=E203,W503

# 3. Mypy
docker compose run --rm -T test mypy src/ --ignore-missing-imports --no-error-summary

# 4. Unit tests (must stay at 661+ passed)
docker compose run --rm -T test pytest tests/unit/ -v --tb=short --ignore=tests/unit/plugins/test_mock_payment_plugin.py

# 5. Stripe plugin tests (must stay at 76 passed)
docker compose run --rm -T test pytest plugins/stripe/tests/ -v --tb=short
```

---

## Phase 1: Black Auto-Format (35 files)

Run `black src/ tests/` inside Docker. This is purely cosmetic (line wrapping, trailing commas).

```bash
docker compose run --rm -T test black src/ tests/
```

**Files affected (35):** Listed below, all are whitespace/formatting only.

src/:
- `src/cli/plugins.py`
- `src/handlers/subscription_cancel_handler.py`
- `src/handlers/checkout_handler.py`
- `src/models/plugin_config.py`
- `src/models/addon_subscription.py`
- `src/plugins/config_store.py`
- `src/plugins/payment_route_helpers.py`
- `src/plugins/json_config_store.py`
- `src/plugins/manager.py`
- `src/app.py`
- `src/repositories/addon_subscription_repository.py`
- `src/repositories/subscription_repository.py`
- `src/repositories/plugin_config_repository.py`
- `src/repositories/invoice_repository.py`
- `src/routes/admin/plugins.py`
- `src/routes/admin/invoices.py`
- `src/routes/admin/users.py`
- `src/routes/user.py`
- `src/services/refund_service.py`
- `src/services/restore_service.py`

tests/:
- `tests/unit/plugins/test_plugin_config_model.py`
- `tests/unit/plugins/test_plugin_discovery.py`
- `tests/unit/plugins/test_plugin_config_schema.py`
- `tests/unit/plugins/test_plugin_config_repository.py`
- `tests/unit/plugins/test_plugin_manager_persistence.py`
- `tests/unit/plugins/test_json_file_plugin_config_store.py`
- `tests/unit/handlers/test_subscription_cancel_handler.py`
- `tests/unit/handlers/test_refund_handler.py`
- `tests/unit/handlers/test_restore_handler.py`
- `tests/unit/routes/test_user_addon_detail.py`
- `tests/unit/routes/test_admin_user_addons.py`
- `tests/unit/routes/test_admin_plugins_routes.py`
- `tests/unit/services/test_restore_service.py`
- `tests/unit/services/test_refund_service.py`
- `tests/integration/test_checkout_endpoint.py`

**Verification:** Run unit tests after to confirm no behavioral change.

---

## Phase 2: Dead Code Removal (F401 unused imports + F841 unused vars + dead test file)

### 2a. Delete dead test file

**`tests/unit/plugins/test_mock_payment_plugin.py`** — imports `src.plugins.providers.mock_payment_plugin` which was deleted in Sprint 21 (providers directory removed). The entire test file is dead. Delete it.

### 2b. Remove unused imports in src/ (F401)

Each import below is verified unused via Flake8. Remove the unused import only (not the entire line if other imports remain).

| File | Unused Import |
|------|--------------|
| `src/events/checkout_events.py:3` | `typing.Optional` |
| `src/events/payment_events.py:4` | `typing.List` |
| `src/handlers/payment_handler.py:3` | `uuid.UUID` |
| `src/models/payment_method.py:3` | `typing.List` |
| `src/plugins/payment_route_helpers.py:7` | `typing.Optional`, `typing.Tuple` |
| `src/repositories/addon_subscription_repository.py:2` | `typing.Optional` |
| `src/repositories/payment_method_repository.py:2` | `typing.Tuple` |
| `src/repositories/token_bundle_purchase_repository.py:2` | `typing.Optional` |
| `src/repositories/token_bundle_repository.py:2` | `typing.Optional` |
| `src/routes/admin/settings.py:4` | `src.extensions.db` |
| `src/services/restore_service.py:13-16` | `InvoiceRepository`, `SubscriptionRepository`, `TokenBundlePurchaseRepository`, `AddOnSubscriptionRepository` — all 4 are imported but the service gets repos from DI container, not direct import |

### 2c. Remove unused imports in tests/ (F401)

| File | Unused Import |
|------|--------------|
| `tests/fixtures/checkout_fixtures.py:2` | `pytest` |
| `tests/integration/test_checkout_addons.py:12` | `os` |
| `tests/integration/test_checkout_endpoint.py:15` | `os` |
| `tests/integration/test_checkout_invoice_total.py:12` | `os` |
| `tests/integration/test_checkout_token_bundles.py:12` | `os` |
| `tests/integration/test_user_frontend_endpoints.py:16` | `typing.Any` |
| `tests/unit/models/test_payment_method.py:6` | `pytest` |
| `tests/unit/plugins/test_payment_route_helpers.py:3` | `uuid.UUID` |
| `tests/unit/plugins/test_plugin_blueprints.py:3` | `unittest.mock.MagicMock` |
| `tests/unit/plugins/test_plugin_config_model.py:2` | `pytest` |
| `tests/unit/plugins/test_plugin_config_repository.py:3` | `unittest.mock.patch` |
| `tests/unit/plugins/test_plugin_config_schema.py:3` | `os` |
| `tests/unit/plugins/test_plugin_discovery.py:5` | `src.plugins.base.BasePlugin`, `src.plugins.base.PluginMetadata` |
| `tests/unit/routes/test_admin_addon_plans.py:4` | `decimal.Decimal` |
| `tests/unit/routes/test_admin_plugins_routes.py:3` | `pytest` |
| `tests/unit/services/test_refund_service.py:2` | `datetime.datetime` |
| `tests/unit/services/test_refund_service.py:3` | `unittest.mock.PropertyMock` |
| `tests/unit/services/test_token_service.py:5` | `src.models.enums.PurchaseStatus` |

### 2d. Remove unused local variables (F841)

| File | Variable |
|------|----------|
| `tests/unit/routes/test_user_addon_detail.py:130` | `user_id` — assigned but never read |
| `tests/unit/routes/test_user_addon_detail.py:245` | `user_id` — assigned but never read |
| `tests/unit/services/test_token_service.py:110` | `result` — assigned but never read |

For the `user_id` cases: the `_setup_mocks` likely returns a tuple and `user_id` is just captured to discard. Replace with `_` or remove the assignment. For `result`: if the call has side effects being tested, replace `result = service.foo()` with just `service.foo()`.

---

## Phase 3: Flake8 Style Fixes (E712, E501)

### 3a. E712 — `== True` / `== False` comparisons (20 occurrences)

SQLAlchemy filter expressions like `.filter(Model.is_active == True)` are intentional — SQLAlchemy overloads `==` to produce SQL `WHERE is_active = TRUE`. These are **NOT bugs**. However, Flake8 flags them.

**Fix:** Use `Model.column.is_(True)` / `Model.column.is_(False)` instead. This is the SQLAlchemy-idiomatic way that avoids Flake8 E712.

| File | Lines | Fix |
|------|-------|-----|
| `src/repositories/country_repository.py` | 29, 38, 47, 57 | `.filter(Country.is_enabled == True)` → `.filter(Country.is_enabled.is_(True))` etc. |
| `src/repositories/payment_method_repository.py` | 41, 74, 94, 110 | Same pattern |
| `src/routes/admin/countries.py` | 57, 65 | Same pattern |
| `src/routes/admin/payment_methods.py` | 108 | Same pattern |
| `tests/integration/test_admin_addons.py` | 197, 312, 380, 438, 460, 511 | These are **assertion** `== True`/`== False` in tests. Change to `assert value is True` / `assert value is False` |
| `tests/integration/test_admin_token_bundles.py` | 213, 376, 398 | Same — assertion fix |

### 3b. E501 — Lines too long (3 occurrences)

| File | Line | Action |
|------|------|--------|
| `src/plugins/manager.py:21` | 124 chars | Wrap line |
| `tests/unit/plugins/test_payment_route_helpers.py:1` | 121 chars | Wrap docstring/import |
| `tests/integration/test_user_subscription_flow.py:14` | 130 chars | Wrap line |

---

## Phase 4: Mypy Type Fixes (100 errors → 0 fixable)

### 4a. Event dataclass `None` defaults without `Optional` (19 errors)

**Pattern:** Dataclass fields like `invoice_id: UUID = None` should be `invoice_id: Optional[UUID] = None`.

| File | Lines | Fix |
|------|-------|-----|
| `src/events/payment_events.py` | 39-41, 83-85, 106, 123-124 | Add `Optional[...]` to 9 fields |
| `src/events/checkout_events.py` | 17-18, 22, 37-39, 52-54 | Add `Optional[...]` to 10 fields |

### 4b. `IEventHandler.handle()` override violations (4 errors)

**Pattern:** Subclass `handle(self, event: PaymentCapturedEvent)` narrows the supertype `handle(self, event: DomainEvent)`. Liskov violation.

| File | Lines | Fix |
|------|-------|-----|
| `src/handlers/payment_handlers.py` | 39, 95, 140, 183 | Accept `DomainEvent` in signature, cast inside method body |

### 4c. `Optional` not handled — `str | None` passed where `str` expected (8 errors)

| File | Lines | Fix |
|------|-------|-----|
| `src/handlers/payment_handlers.py` | 51, 68, 189, 207 | Add `None` guards before calling |
| `src/handlers/restore_handler.py` | 36 | Add `None` guard |
| `src/handlers/password_reset_handler.py` | 83, 120, 144 | Add `None` guards |

### 4d. Flask `app.container` / `app.plugin_manager` attribute errors (8 errors)

Flask's type stubs don't know about custom attributes attached at runtime. Fix with a type-safe accessor pattern or cast.

| File | Lines | Fix |
|------|-------|-----|
| `src/decorators/permissions.py` | 30, 73, 116, 160, 205 | Use `cast()` or `getattr()` with type annotation |
| `src/app.py` | 170, 194-196 | Same pattern |

### 4e. SQLAlchemy `Column[T]` vs `T` assignment mismatches (15 errors)

These are false positives from Mypy not understanding SQLAlchemy's column descriptor protocol. When you assign `model.field = value`, SQLAlchemy handles the Column→value conversion at runtime.

| File | Lines | Fix |
|------|-------|-----|
| `src/models/base.py:15` | `db.Model` not defined | Add `TYPE_CHECKING` import with `from src.extensions import db` |
| `src/models/plugin_config.py:9` | Same | Same pattern |
| `src/models/payment_method.py:248` | Same | Same pattern |
| `src/repositories/plugin_config_repository.py` | 91, 93 | Use `setattr()` or cast |
| `src/repositories/country_repository.py` | 76 | Same |
| `src/routes/admin/countries.py` | 69-70, 98-99 | Same |
| `src/services/auth_service.py` | 66, 68, 94, 104 | Cast `user.id` to `UUID` |
| `src/services/password_reset_service.py` | 78, 86, 140 | Same |

### 4f. Relationship iteration errors (6 errors)

Mypy doesn't understand SQLAlchemy `relationship()` returns an iterable collection at runtime.

| File | Lines | Fix |
|------|-------|-----|
| `src/models/role.py` | 64, 73 | Add `# type: ignore[attr-defined]` — genuine SQLAlchemy limitation |
| `src/models/invoice.py` | 139 | Same |
| `src/models/addon.py` | 90, 92 | Same |
| `src/repositories/role_repository.py` | 33 | Same |
| `src/services/refund_service.py` | 92 | Same |

**Exception to no-suppression rule:** These 7 are genuine SQLAlchemy/Mypy incompatibilities where the runtime behavior is correct. Use `# type: ignore[attr-defined]` with a comment explaining why.

### 4g. Other Mypy fixes

| File | Lines | Error | Fix |
|------|-------|-------|-----|
| `src/sdk/base.py:115` | Exception not derived from BaseException | Fix custom exception class |
| `src/repositories/base.py` | 54-62, 71 | Generic `T` has no `id`/`version` | Add `Protocol` or bound the TypeVar |
| `src/repositories/tax_repository.py:17` | Wrong arg order | Swap constructor arguments |
| `src/cli/_demo_seeder.py` | 131, 143 | `.rowcount` on Result | Cast to `CursorResult` |
| `src/services/feature_guard.py` | 51, 82, 118, 151 | Missing `get_active_subscription` | Add method to `SubscriptionRepository` or fix the method name |
| `src/services/refund_service.py:85` | Missing annotation | Add `: dict[str, str]` |
| `src/services/restore_service.py:74` | Missing annotation | Add `: dict[str, str]` |
| `src/handlers/payment_handler.py` | 79, 121, 164, 176 | Mixed types in dict | Fix annotation and assignments |
| `src/container.py:57` | Missing annotation | Add type annotation for `db_session` |
| `src/routes/subscriptions.py` | 161, 204, 247, 305, 363 | `None` access on Optional | Add `None` guard before `.to_dict()` |
| `src/routes/tarif_plans.py` | 108-109 | Session type mismatch | Cast session |
| `src/routes/health.py:2` | `src` has no `db` | Fix import path |
| `src/app.py:40` | `MockEmailService` vs `EmailService` | Add protocol or make Mock inherit from EmailService |
| `src/utils/redis_client.py:2`, `src/sdk/idempotency_service.py:7` | Missing `types-redis` stubs | Install `types-redis` in Docker or add to requirements |
| `src/routes/admin/subscriptions.py:4` | Missing `types-python-dateutil` | Install stubs or use alternative |

---

## Phase 5: Final Verification

```bash
# Full pre-commit check
cd vbwd-backend && ./bin/pre-commit-check.sh --quick
# Expected: Black ✓, Flake8 ✓, Mypy ✓, 661+ unit tests passed
```

---

## Files Summary

| Category | Files | Changes |
|----------|-------|---------|
| Black auto-format | 35 | Whitespace only |
| Dead code removal (imports) | ~30 | Remove unused imports |
| Dead test file | 1 | Delete `test_mock_payment_plugin.py` |
| E712 SQLAlchemy fixes | 5 src + 2 test | `== True` → `.is_(True)` |
| E712 assertion fixes | 2 test | `== True` → `is True` |
| E501 line length | 3 | Wrap lines |
| Mypy Optional fields | 2 event files | Add `Optional[...]` |
| Mypy type narrowing | ~15 | Add None guards, casts |
| Mypy SQLAlchemy ignores | 7 lines | `# type: ignore[attr-defined]` |
| Mypy stubs | requirements | Add `types-redis`, `types-python-dateutil` |
| Mypy misc | ~10 | Annotations, casts, protocol fixes |
