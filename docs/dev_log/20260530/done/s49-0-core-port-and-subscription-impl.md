# Sprint 49.0 — GHRM→subscription entitlement read (declared plugin dependency)

**Parent:** [s49-ghrm-collaborator-lifecycle.md](s49-ghrm-collaborator-lifecycle.md) · **Decision:** D1 (revised) · supersedes O3
**Status:** READY · **Area:** `plugins/subscription` (one read method) + `plugins/ghrm` (declare dep + one narrow port + composition-root adapter)
**Depends on:** nothing (first slice). **Blocks:** S49.3 (connect-time entitlement resolution).

> **Revision note (2026-06-04):** the original draft added `active_plan_ids` to the **core** port `vbwd/services/subscription_read_model.py`. That is rejected — **core must name no plugin domain.** A core port that exists *solely* to broker plan/entitlement data from one plugin (subscription) to another (ghrm), with **no core consumer**, is a plugin↔plugin contract squatting in core. The correct seam is a **declared plugin→plugin dependency**: ghrm is meaningless without plans (the taro→subscription precedent), so it may hard-depend on subscription and read entitlements from a **subscription-owned** port. **Zero core change.**

## Engineering requirements (BINDING)
TDD-first · SOLID · **Liskov** · DI · DRY · clean code · **NO OVERENGINEERING** (narrowest change). Guard: `--plugin subscription --full` + `--plugin ghrm --full` green. **Core is untouched** — `git diff vbwd/` is empty for this slice; the core-agnosticism oracle stays green by construction. See [`_engineering_requirements.md`](_engineering_requirements.md).

## Goal
Give GHRM a DI-clean way to ask "which tariff plans is this user actively entitled to **right now**?" — used only at GitHub-connect time (events handle ongoing changes). The answer comes from the **subscription plugin's own** read surface, reached because GHRM **declares a dependency** on subscription. Core mediates nothing.

## Why not the core port (the rejected design)
- The core file `subscription_read_model.py` is itself slated to leave core (it names a plugin domain and only core admin surfaces consume the *existing* methods). Adding `active_plan_ids` — which **no core surface uses** — would deepen exactly the leak we are removing.
- GHRM↔subscription is a textbook **plugin→plugin dependency**, which the platform explicitly allows when declared in `PluginMetadata.dependencies` (cf. taro→subscription, meinchat→subscription). The agnosticism oracle bans `from plugins.*` in **core only**; plugin→plugin imports are fine when declared.

## Scope (narrowest change)
Add exactly one read method on the subscription side; declare the dep; give ghrm one narrow port + a one-place adapter. Do **not** add reconcile jobs, extra query surface, or route the read through core.

### 1. Subscription plugin — the entitlement read (plugin-owned)
- **Repo accessor (data access stays in the repo — DRY):** add
  `find_active_by_user_list(user_id) -> List[Subscription]` to
  `plugins/subscription/subscription/repositories/subscription_repository.py`
  (status in `{ACTIVE, TRIALING}` — matching the existing `find_active_by_user` predicate; the existing one returns a single `Optional`, so a list accessor is the missing piece, not a duplicate query).
- **Read method:** add to the existing plugin-owned `SubscriptionReadModel`
  (`plugins/subscription/subscription/services/subscription_read_model.py`):
  `active_plan_ids(user_id) -> List[UUID]` → distinct `tarif_plan_id`s of the user's active subscriptions (dedup, order-insensitive).
- No core import, no core registration change. (`SubscriptionReadModel` is stateless and already instantiated freely, e.g. `__init__.py:211`.)

### 2. GHRM — declare the dependency
- `plugins/ghrm/__init__.py`: `PluginMetadata(... dependencies=["subscription"], ...)` (was `[]`). The plugin manager now enables ghrm only when subscription is enabled, so the import below is always satisfiable at runtime.

### 3. GHRM — own the abstraction it needs (DIP), adapt at the composition root
- **Port (ghrm-owned):** `plugins/ghrm/src/services/ports.py`
  ```python
  class ISubscriptionEntitlements(Protocol):
      def active_plan_ids(self, user_id: UUID) -> List[UUID]: ...
  ```
  The `GithubAccessService` depends on **this** narrow port (constructor-injected) — never on the subscription concrete class. Unit tests stub it; subscription is **not** imported in ghrm unit tests.
- **Adapter (single place subscription is imported):** in the ghrm composition root
  `plugins/ghrm/__init__.py:_make_access_service`, build an adapter that wraps the subscription read model:
  ```python
  from plugins.subscription.subscription.services.subscription_read_model import SubscriptionReadModel
  class _SubscriptionEntitlementsAdapter:        # satisfies ISubscriptionEntitlements
      def active_plan_ids(self, user_id): return SubscriptionReadModel().active_plan_ids(user_id)
  ```
  This is the **only** `from plugins.subscription...` import in ghrm; it is legitimate because the dependency is declared.

> **Catalog reads (out of scope here):** ghrm also reads core's `catalog_read_model` today (`routes.py`, `software_package_repository.py`). Those keep working unchanged in S49 — repointing them off the core catalog port folds into the separate "domain vocabulary leaves core" extraction sprint. Once both reads move to subscription-owned ports, core's catalog/subscription read ports lose their last consumer and can be deleted there. **Do not** repoint catalog in this slice (no overengineering; keep S49 focused and low-risk).

## TDD plan (tests FIRST)
- **Subscription unit** (MagicMock repo): user with two active subs on plans A,B + one cancelled on C → `{A,B}` (deduped, order-insensitive); no active subs → `[]`.
- **Subscription integration** (`db`): seed active + expired subscriptions for a user → `active_plan_ids` returns only the active plan ids; `find_active_by_user_list` filters ACTIVE+TRIALING only.
- **GHRM unit:** `GithubAccessService` with a **stubbed `ISubscriptionEntitlements`** → entitlement resolution uses the port (no subscription import in the test); empty entitlements ⇒ no membership created (covered fully in S49.3).
- **GHRM dependency:** `GhrmPlugin().metadata.dependencies == ["subscription"]`.
- **Core untouched:** `git diff --quiet vbwd/` for this slice; `tests/unit/test_core_agnosticism.py` still green (no new core file/method).

## Implementation steps
1. Write the failing subscription unit + integration tests for `active_plan_ids` / `find_active_by_user_list`.
2. Add the repo accessor + read method in the subscription plugin → subscription tests green.
3. Add the ghrm-owned `ISubscriptionEntitlements` port; declare `dependencies=["subscription"]`; build the adapter in `_make_access_service`.
4. Run both gates (`--plugin subscription --full`, `--plugin ghrm --full`); confirm `vbwd/` has no diff.

## Definition of done
`active_plan_ids` exists on the **subscription** plugin's read model with a correct, tested impl; ghrm declares `dependencies=["subscription"]` and depends on its **own** `ISubscriptionEntitlements` port with subscription wired only at the composition root; **no core change** (`vbwd/` diff empty, oracle green); subscription + ghrm `--full` green; no catalog reads touched.