# S20 — DRY: extract payment-plugin timestamp + `to_dict()` into `BaseModel` / mixin

**Source:** review §6.1 → `plugins/conekta`, `plugins/mercado_pago`, `plugins/truemoney`, `plugins/toss_payments` (+ likely `promptpay`, `c2p2`) each redefine `created_at`, `updated_at`, and the ISO-format `to_dict()` boilerplate.
**Risk:** LOW. Pure DRY refactor.
**Outcome:** Every plugin model inherits `created_at`, `updated_at`, and an `iso_isoformat()`-using `to_dict()` from a single shared base. Each plugin's models file loses ~30 LOC. Future timestamp-policy changes happen in one place.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/meta/test_no_duplicate_timestamp_columns.py::test_plugin_models_do_not_redeclare_created_at`
   — walks every `plugins/*/.../models.py` (or `models/`), parses with
   `ast`, asserts no `Assign(targets=[Name(id='created_at')])` or
   `Name(id='updated_at')` exists outside the shared base. **Today: fails.**
2. Per-plugin integration test re-runs after refactor — round-trip
   create/update timestamps preserved.

## Touch-points

- `vbwd/models/base.py` (already exports `BaseModel` — verify it has
  `created_at`, `updated_at`, `to_dict()`)
- `plugins/conekta/conekta/models.py:29-58`
- `plugins/mercado_pago/mercado_pago/models.py:28-58`
- `plugins/truemoney/.../models.py`
- `plugins/toss_payments/.../models.py`
- Audit: `promptpay`, `c2p2` — likely same pattern

## Steps (each validated)

1. **Write the meta test.** Red.
2. **Verify `vbwd/models/base.py::BaseModel`** has the right columns +
   a generic `to_dict()` that iso-formats datetimes. If it does, use
   it directly. If not — extract a `TimestampedMixin`:
   ```python
   class TimestampedMixin:
       created_at = db.Column(db.DateTime(timezone=True), nullable=False,
                              default=utcnow)
       updated_at = db.Column(db.DateTime(timezone=True), nullable=False,
                              default=utcnow, onupdate=utcnow)
   ```
3. **Per plugin**, change `class ConektaOrder(db.Model)` →
   `class ConektaOrder(BaseModel)` (or with the mixin). Delete the
   redundant timestamp columns and `to_dict()` overrides — unless the
   override adds plugin-specific fields, in which case keep ONLY the
   plugin-specific bits and call `super().to_dict()`.
4. **Run each plugin's tests** — green (timestamps still set, payloads
   identical).
5. **Re-run the meta test.** Green.

## Acceptance (oracle)

- Meta test green.
- Per-plugin grep — `rg "created_at = .*Column" plugins/` shows zero
  hits outside `vbwd/models/base.py`.
- Pre-commit `--full` green.

## Notes

- Coordinate with [[s19]] (TZ-aware) so the mixin emits aware
  datetimes natively.
- §8 no overengineering: don't introduce a UUIDMixin + AuditMixin +
  SoftDeleteMixin combo speculatively — only the timestamp mixin is
  proven necessary today.
