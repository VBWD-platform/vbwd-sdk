# S5 — Move the 5 subscription model classes core → plugin

**Risk:** HIGH (SQLAlchemy mapper config / boot). **Depends on S4** (the core
invoice FK to `vbwd_subscription`/`vbwd_tarif_plan` must be gone, else moving the
classes can break mapper config for a subscription-free deploy — R4).
**Outcome:** `vbwd/models/` defines no subscription model; the subscription
plugin owns them. Headline "models leave core" lands here.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI ·
DRY · Liskov · clean code · **no overengineering** —
[`_engineering-requirements.md`](_engineering-requirements.md). Gate:
`bin/pre-commit-check.sh --full` green before "done" (DevOps: verify boot with
subscription enabled *and* a disabled/absent smoke — mapper config must hold).

## What moves
`vbwd/models/{subscription,tarif_plan,tarif_plan_category,addon,addon_subscription}.py`
→ `plugins/subscription/subscription/models/`. They reference each other
(subscription→tarif_plan, addon_subscription→addon, category↔tarif_plan assoc,
addon↔tarif_plan assoc) — move as a unit. Table names stay (`vbwd_subscription`
etc.), so any remaining string FKs keep resolving.

## Importers (from the dig — small!)
- **Only** `vbwd/models/__init__.py` imports the 5 from core (lines 8/9/22/23/24
  + `__all__` entries) — remove them.
- `vbwd/models/tarif_plan_category.py` has a TYPE_CHECKING import of TarifPlan —
  moves with the file (fix to relative/local).
- The plugin's `plugins/subscription/subscription/models/__init__.py` currently
  **re-exports from `vbwd.models`** (transition "04b"). Flip it to define
  locally (`from .subscription import Subscription`, …) — this is the planned
  "04c".
- No core module does `from vbwd.models import Subscription/TarifPlan/...`
  (verified empty), so no re-export consumers to chase.

## Steps (each validated)
1. `git mv` the 5 files into the plugin models package (use the plugin repo's
   git; these live in the subscription plugin repo).
2. Fix intra-set imports to the new location (relative imports within the
   package).
3. Update plugin `models/__init__.py` to import from the local files.
4. Remove the 5 from `vbwd/models/__init__.py` + `__all__`.
5. **Ensure the plugin models are imported at app startup** so their tables are
   in `db.metadata` before mapper config / `create_all` (the plugin already
   imports its models via handlers/on_enable + conftest — verify the app boot
   path, not just tests).
6. Repoint `plugins/ghrm/src/bin/populate_ghrm.py` imports `vbwd.models.tarif_plan*`
   → `plugins.subscription.subscription.models` (the S3 dev-seed residual).
7. Validate: app boots (mapper config OK with subscription enabled AND, ideally,
   a smoke with it disabled), full subscription suite, agnostic oracle.

## Acceptance (the slice's oracle, set in S7)
- `import vbwd.models.subscription` raises; `vbwd/models/__init__` exports none
  of the 5; the 6 plugins import none from `vbwd.models.*`.
