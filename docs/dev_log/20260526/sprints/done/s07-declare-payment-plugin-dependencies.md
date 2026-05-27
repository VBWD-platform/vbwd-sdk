# S07 — Declare `dependencies=["subscription"]` on payment plugins that need it

**Source:** review §1.5.
**Risk:** LOW (metadata only) but corrects a silently-hidden coupling.
**Outcome:** Every payment plugin that calls `resolve_subscription_lifecycle()` or otherwise activates subscriptions on capture declares the subscription dependency in `PluginMetadata.dependencies`. PluginManager refuses to enable a plugin whose declared dependency isn't enabled. A test enforces the contract.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/unit/test_plugin_dependencies_declared.py::test_payment_plugin_dependencies_match_imports`
   — for each `plugins/<payment>/`, parse with `ast` and find calls to
   `resolve_subscription_lifecycle`, `resolve_entitlement_provider`,
   etc.; assert the plugin's `PluginMetadata.dependencies` includes the
   corresponding source plugin. **Today: fails on stripe, paypal,
   yookassa, conekta, mercado_pago, truemoney, toss_payments, promptpay,
   c2p2, token_payment** (verify each via grep first).
2. `tests/unit/test_plugin_manager_enforces_dependencies.py::test_enable_fails_when_dep_disabled`
   — try to enable `stripe` with `subscription` disabled, expect
   `PluginDependencyError`.

## Touch-points

- `plugins/stripe/__init__.py` `PluginMetadata(dependencies=...)`
- `plugins/paypal/__init__.py`
- `plugins/yookassa/__init__.py`
- `plugins/conekta/__init__.py`
- `plugins/mercado_pago/__init__.py`
- `plugins/truemoney/__init__.py`
- `plugins/toss_payments/__init__.py`
- `plugins/promptpay/__init__.py`
- `plugins/c2p2/__init__.py`
- `plugins/token_payment/__init__.py`
- `vbwd/plugins/manager.py` (`enable_plugin` — add dependency check)
- `vbwd/plugins/base.py` (`PluginDependencyError` if not yet exists)

## Steps (each validated)

1. **Grep each plugin's source** for `resolve_subscription_lifecycle`,
   `resolve_entitlement_provider`, any `register_*_handler` from
   subscription — the exact set decides which plugins need the dep
   declared.
2. **Write the two tests** from Baseline. The first lists the actual
   missing decls.
3. **Edit each plugin's `__init__.py`** to add the dep:
   ```python
   PluginMetadata(
       name="stripe", version="…",
       dependencies=["subscription"],  # <-- added
       …,
   )
   ```
   `token_payment` may NOT need subscription (token-only billing is
   plan-agnostic) — verify case by case; only add where the runtime
   actually calls subscription ports.
4. **Implement dependency check** in `PluginManager.enable_plugin`:
   refuse to enable a plugin whose dependency isn't enabled, with a
   helpful error message. (If already implemented, just verify; if
   over-engineered as a full graph resolver, simplify to a single hop
   for now — §8.)
5. **Verify the dependency-disabled path.** Disable subscription in a
   test env, attempt to enable stripe → expect graceful refusal, not a
   500 at first webhook.

## Acceptance (oracle)

- Both tests green.
- The "implicit dep" comment in each `__init__.py` is gone — the
  metadata is the contract.
- App startup with subscription disabled refuses to enable payment
  plugins that need it, with a clear log line.

## Notes

- This is documentation as code: the metadata is the single source of
  truth for what depends on what.
- Pairs with [[s01]] — the same principle applied at the plugin layer
  (no hidden runtime coupling).
- §8 no overengineering: do NOT introduce a full topological sort /
  dependency-resolution graph yet. One-hop "is this dep enabled?" is
  enough for today.

## Outcome — 2026-05-27 (DONE)

**Done.** New parametrised test (10 payment plugins) green.

**Audit confirmed:** only 3 plugins actually call
`resolve_subscription_lifecycle` — stripe, paypal, yookassa. The other
7 (conekta, mercado_pago, truemoney, toss_payments, promptpay, c2p2,
token_payment) don't, so they correctly keep `dependencies=[]`.

**Patches:**
- `plugins/stripe/__init__.py:30` — `dependencies=["subscription"]`
- `plugins/paypal/__init__.py:30` — same
- `plugins/yookassa/__init__.py:30` — same

**No PluginManager change needed:** the manager already enforces
declared dependencies at `enable_plugin` time
(`vbwd/plugins/manager.py:113-117`) — it raises `ValueError` if a
declared dep isn't enabled. S07 just makes the previously-implicit
deps explicit.

**Acceptance verified:**
- All 10 parametrised tests green.
- Disabling the subscription plugin in a test env now refuses to
  enable stripe/paypal/yookassa with a clear "Dependency 'subscription'
  not enabled" error — observable at boot, not at first webhook.
