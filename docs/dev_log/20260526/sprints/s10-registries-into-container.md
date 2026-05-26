# S10 — Move module-level registries into the DI container as `Singleton` providers

**Source:** review §3.3 → seven module-level mutables across `vbwd/events/` and `vbwd/services/`.
**Risk:** MEDIUM. Touches every plugin that registers against these (subscription, shop, taro, payment plugins). Test infra changes too.
**Outcome:** `line_item_registry`, `deletion_dependency_registry`, `demo_data_registry`, entitlement / lifecycle / subscription read-model / catalog read-model providers all live as `providers.Singleton` on `Container`. No module-level mutable. Plugins register against the container instance (per-app). Tests get a fresh container per test app and cross-test leakage is gone by construction.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md). The single DI sprint that unifies the agnosticism-port surface.

## Baseline (E1)

1. `tests/unit/test_no_module_level_registries.py::test_registries_are_container_singletons`
   — greps `vbwd/events/` and `vbwd/services/` for module-level
   assignment patterns (`^_provider:` / `^line_item_registry =` /
   `^_providers: Dict`), asserts none of them are mutated at runtime
   (each is either absent OR is a non-mutable typed alias). **Today: fails.**
2. `tests/integration/test_registry_no_cross_test_leak.py`
   — run test A that registers a fake handler; run test B that asserts
   no handler is registered; **today the second test fails** because the
   global registry persists.

## Touch-points

- `vbwd/events/line_item_registry.py:237`
- `vbwd/services/deletion_dependency_registry.py:17`
- `vbwd/services/demo_data_registry.py:14-17`
- `vbwd/services/entitlement.py:78`
- `vbwd/services/subscription_lifecycle.py:95`
- `vbwd/services/subscription_read_model.py:50`
- `vbwd/services/catalog_read_model.py:36`
- `vbwd/container.py` (add 7 `Singleton` providers)
- Every plugin's `on_enable` that calls `register_*` → switch to
  `container.<registry>().register(...)`
- All call sites of `resolve_*` → swap to `container.<registry>()`

## Steps (each validated)

1. **Write both Baseline tests.** Red.
2. **For each registry, turn the class into a pure object** (no
   module-level instance). Example:
   ```python
   # vbwd/events/line_item_registry.py
   class LineItemHandlerRegistry:
       def __init__(self):
           self._handlers: list[ILineItemHandler] = []
       def register(self, handler): ...
       def dispatch(self, ...): ...
   # NO line_item_registry = LineItemHandlerRegistry() at module level
   ```
3. **Wire as `Singleton`** in `vbwd/container.py`:
   ```python
   line_item_registry = providers.Singleton(LineItemHandlerRegistry)
   deletion_dependency_registry = providers.Singleton(DeletionDependencyRegistry)
   entitlement_provider = providers.Singleton(NullEntitlementProvider)  # plugins override
   subscription_lifecycle = providers.Singleton(NullSubscriptionLifecycle)
   …
   ```
4. **Replace `resolve_*()` helpers** with shims that call into
   `current_app.container.<name>()`. (Keep the helper names so plugin
   code doesn't churn — §8 no over-engineering of the migration.)
5. **Replace `register_*` helpers similarly** — they now mutate the
   container singleton via `container.<name>().register(...)`. For
   provider-style registries (single impl) the helper becomes
   `container.<name>.override(providers.Singleton(MyImpl))`.
6. **Per-plugin `on_enable`** — for the provider-style registries,
   call `.override(...)`. For collection-style registries, call
   `container.line_item_registry().register(MyHandler())`. `on_disable`
   does the inverse (`reset_override` / `unregister`).
7. **Tests:** delete `tests/.../conftest.py::clear_registries()` hacks
   — no longer needed because each test app has its own container.
8. **Run pre-commit `--full`** — green.

## Acceptance (oracle)

- Both Baseline tests green.
- `rg "^_provider|^_handlers|^_providers|^_read_model" vbwd/services/ vbwd/events/` → empty.
- Parallel pytest (-n auto) is green — proves no cross-test leak.
- Plugin enable→disable→re-enable cycle in a running app leaves no
  stale entries.

## Notes

- This is the right answer to the agent's "drop dependency_injector"
  suggestion: USE the container properly instead of removing it.
- §3 Liskov: null defaults (`NullEntitlementProvider`, etc.) keep the
  same contract as real impls.
- §8: don't add per-request scopes / context-vars — `Singleton`
  per-container is the right granularity (one container per Flask app
  instance, one app instance per process, one per test).
- After this sprint, tests no longer need the
  `clear_*_handlers()` / `clear_demo_data_seeders()` / etc. hooks —
  delete those public APIs at the end of this slice (§7 clean code,
  remove dead code).
