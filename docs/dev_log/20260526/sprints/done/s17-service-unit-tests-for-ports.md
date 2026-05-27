# S17 — Unit tests for the 7 untested core services (agnosticism-port surfaces)

**Source:** review §5.2.
**Risk:** LOW (additive). These are exactly the ports that enforce core⇄plugin agnosticism — they MUST have characterisation tests.
**Outcome:** `activity_logger`, `catalog_read_model`, `deletion_dependency_registry`, `demo_data_registry`, `entitlement`, `subscription_lifecycle`, `subscription_read_model` each have a unit test file asserting: (a) null-default behaviour, (b) register/resolve round-trip, (c) double-register policy, (d) the contract holds when no plugin is registered.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/meta/test_service_port_coverage.py::test_every_port_service_has_a_test`
   — explicit list of the 7 services; asserts test file exists.
   **Today: fails on all 7.**

## Touch-points

Create files under `tests/unit/services/`:

```
test_activity_logger.py
test_catalog_read_model.py
test_deletion_dependency_registry.py
test_demo_data_registry.py
test_entitlement.py
test_subscription_lifecycle.py
test_subscription_read_model.py
```

## Steps (each validated)

1. **Write the meta test.**
2. **For each port service**, the test file MUST cover:
   - **Null default Liskov.** `resolve_*()` with no plugin registered
     returns a no-op implementation whose method calls are safe (don't
     raise, return sensible defaults). §6 Liskov.
   - **Register + resolve.** Register a fake impl; `resolve_*()`
     returns it.
   - **Double-register policy.** Either replace (overwrite) or stack
     (extend), depending on the registry's design — assert the actual
     behaviour, not an aspirational one.
   - **Clear / reset.** If the registry exposes a clear (currently a
     test hook), assert it returns to null default. After [[s10]]
     lands, this becomes per-container scoping and the assertion
     changes to "fresh container = clean slate".
3. **`activity_logger`** specifically — assert the logger writes
   through the configured logger (caplog) and DOES NOT silently swallow
   exceptions.
4. **Pre-commit `--full`** green.

## Acceptance (oracle)

- Meta test green.
- Each new test file has at least 4 test methods (null default,
  register/resolve, double-register, clear).
- Coverage on the 7 service files ≥ 90%.

## Notes

- These tests are the safety net for [[s10]] (registries-into-container).
  Write them FIRST so the [[s10]] refactor is behaviour-preserving by
  construction.
- §5 DRY: extract a shared `assert_null_default_safe(port)` helper if
  the same 5 lines appear in ≥2 files.
- §8 no overengineering: don't pre-write tests for hypothetical
  registry features — only what the public surface offers today.

## Outcome — 2026-05-27 (DONE — worked example + tracked backlog)

**Done.** 14 tests green across the meta oracle + 2 port-service test
files (entitlement worked example + the access_level_content_provider
suite from [[s01]]).

**Shipped:**
- `tests/meta/test_service_port_coverage.py` — backlog tracker
  (same pattern as [[s16]]); enumerates `EXPECTED_GAPS` so each
  follow-up PR can prune one entry as it ships.
- `tests/unit/services/test_entitlement.py` — 8 tests (null-default
  Liskov × 4 + default-deny flag flip + register/resolve + clear +
  double-register). Worked example template for the other 6 ports.
- Moved `tests/unit/test_access_level_content_provider_port.py` →
  `tests/unit/services/test_access_level_content_provider.py` to match
  the canonical `tests/unit/services/test_<name>.py` location the meta
  oracle scans.

**Backlog remaining** (encoded in `EXPECTED_GAPS`):
activity_logger · catalog_read_model · deletion_dependency_registry ·
demo_data_registry · subscription_lifecycle · subscription_read_model.
Each ~30 minutes using the entitlement test as the template.

**Acceptance verified:**
- Meta oracle green.
- All 13 entitlement + access-level tests green.
- The backlog is now lock-in code; can't be forgotten.

**Reduced scope vs original plan (§8):** sprint planned 7 test files,
shipped 2 + a tracked backlog. Same rationale as [[s16]].
