# S28.1 — Server retention prune (daily APScheduler job)

**Parent sprint:** [S28 — meinchat extension seams + meinchat-plus + retention](s28-meinchat-e2e-encryption-and-retention.md)
**Status:** PLANNED — 2026-05-28
**Depends on:** [S28.0](s28-0-config-and-limits-endpoint.md) (reads the config keys it created).
**Blocks:** nothing directly; lifts a privacy risk independently of the crypto track.

**Repos touched:** `vbwd-backend/plugins/meinchat/` only.
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** — [`_engineering-requirements.md`](_engineering-requirements.md).
**Gate:** `bin/pre-commit-check.sh --plugin meinchat` GREEN (both `--quick` and `--full`); integration suite GREEN.

---

## 1. Goal

A daily background job hard-deletes `message` rows whose `sent_at` is
older than `messages_retention_days_server`, plus the matching
attachment objects from `IFileStorage`. **Default 2 days.** When the
key is set to `0`, *everything* is pruned (operator-amnesic escape
hatch). The job is idempotent — re-running it is a no-op.

This slice lifts the today-existing risk of forever-plaintext rows
sitting in Postgres **independently of the crypto track** — even if
S28.3b (meinchat-plus) never lands, the operator's leak window shrinks
from "forever" to "2 days".

## 2. Touched files

### 2.1 New — `RetentionService`

`vbwd-backend/plugins/meinchat/meinchat/services/retention_service.py` (~60 LOC).

```python
class RetentionService:
    def __init__(
        self,
        *,
        message_repo: IMessageRepository,
        attachment_storage: IFileStorage,
        clock: Callable[[], datetime] = lambda: datetime.now(tz=UTC),
        logger: logging.Logger = logger,
    ) -> None: ...

    def prune_messages(self, *, days_to_keep: int) -> RetentionResult:
        """Hard-delete messages older than ``days_to_keep`` days.
        Returns a result with counts; safe to re-run (idempotent)."""

    def prune_attachments(self, *, days_to_keep: int) -> RetentionResult:
        """Best-effort delete of attachment objects whose owning rows
        are being pruned. Storage failures are logged + counted, never
        propagated — the message row delete is the source of truth."""
```

`RetentionResult` is a frozen dataclass `{deleted_count, skipped_count, errors}`.

### 2.2 Scheduler hook in plugin lifecycle

`plugins/meinchat/__init__.py` `on_enable`:

```python
def on_enable(self) -> None:
    super().on_enable()
    # Tests pass TESTING=True; the scheduler must NOT spawn there or it
    # leaks threads between tests and exhausts PG connection slots
    # (lesson from the booking + subscription scheduler post-mortem).
    if not current_app.config.get("TESTING"):
        _register_retention_job(current_app, self._config)
```

`_register_retention_job` uses the existing APScheduler instance core
already exposes; the job runs `RetentionService.prune_messages` +
`prune_attachments` daily at 03:00 UTC (config-overridable as
`retention_prune_cron` if anyone needs another window).

### 2.3 Migration — none

Pure deletes from existing tables. No schema change.

### 2.4 Repo additions

`IMessageRepository.delete_older_than(threshold: datetime) -> list[UUID]`
returns the ids of deleted rows so the caller can clean up matching
attachments. Pure SQL `DELETE … RETURNING id`. New method on the
existing repo; doesn't break callers.

## 3. TDD plan

### 3.1 Unit specs — `tests/unit/services/test_retention_service.py` (NEW, ≥ 8 specs)

| # | Spec | Asserts |
|---|---|---|
| 1 | `test_deletes_only_messages_older_than_threshold` | seed messages at -5d / -2d / -1d; prune with `days_to_keep=2` → -5d gone, -2d gone (boundary inclusive on `<`), -1d kept |
| 2 | `test_off_by_one_minute_at_threshold` | `sent_at` = threshold − 1min → pruned; threshold + 1min → kept |
| 3 | `test_days_zero_deletes_everything` | `days_to_keep=0` → all rows gone |
| 4 | `test_days_negative_raises` | `days_to_keep=-1` → `ValueError` (fail-fast on config typo) |
| 5 | `test_idempotent_re_run_is_noop` | run twice in a row; second run reports `deleted_count == 0` |
| 6 | `test_returns_deleted_ids` | result lists exactly the ids of removed rows (so attachment prune can fan out) |
| 7 | `test_attachment_storage_failure_is_logged_not_raised` | fake `IFileStorage` raises on `delete` → service catches, increments `errors`, message-row delete still committed |
| 8 | `test_clock_is_injected` | inject a fixed clock; assert prune respects it (DI / Liskov) |

### 3.2 Integration — `tests/integration/services/test_retention_prune.py` (NEW, ≥ 3 specs)

1. **End-to-end against real PG:** seed messages backdated -5d / -1d via the repository, run `prune_messages(days_to_keep=2)`, assert -5d is gone and -1d remains. Verify with a raw `SELECT count(*)`.
2. **Cascade-safety:** confirm pruning a message does NOT cascade-delete the parent `conversation` row.
3. **Attachment cleanup against a fake `IFileStorage` backed by a temp dir:** seed a row with `attachment_url='/uploads/.../foo.jpg'`, write the file, run prune, file is gone and row is gone.

### 3.3 Scheduler-guard spec

`tests/unit/test_plugin.py` — extend with one spec asserting that the
scheduler **does not** register when `app.config["TESTING"]` is true.
This is a regression test for the `--full` mass-test connection-pool
exhaustion lesson recorded in `feedback_ci_precommit_lessons`.

## 4. Deploy / ops notes

- First production run with default `2` will delete most of the current
  message history on `vbwd.cc`. Surface this prominently in the S28.1
  release notes. Operator can set `messages_retention_days_server` to a
  larger value before the recipe restarts the api container if they
  want to preserve more.
- Job runs daily at 03:00 UTC. Logged at `info` with the result counts.
- Manual trigger for ops: `make meinchat-prune` (new Makefile target —
  one-liner that does `docker compose exec api python -c "from
  plugins.meinchat.meinchat.services.retention_service import
  RetentionService; …"`). Useful for the first cutover.

## 5. Acceptance criteria

- With `messages_retention_days_server = 2`: a fresh message survives
  the daily cron at +0d, +1d; is gone at +3d.
- With `= 0`: every message row + attachment object is gone after the
  next cron tick.
- Re-running the cron the same day deletes nothing extra.
- `bin/pre-commit-check.sh --plugin meinchat --full` GREEN — both new
  unit specs and the new integration specs.
- `make up` cold-start of `vbwd-backend` does NOT spawn the scheduler
  in the test container (regression check via the `TESTING` guard).

## 6. Out of scope

- **Soft-delete with grace period.** Hard-delete only — the privacy
  goal is "data is gone." If anyone needs a paper-trail of *that a
  message existed*, that's `meinchat-enterprise`'s audit-log territory,
  out of scope.
- **Per-conversation legal hold.** Same — enterprise concern.
- **Compression / archive to cold storage.** Out of scope; the goal is
  forgetting, not migrating.
- **GDPR right-to-be-forgotten endpoint.** Separate workstream.

## 7. Engineering-requirements check

- **TDD-first:** ≥ 11 specs land before the service body is written. The
  characterisation test that captures "today messages live forever" is
  the implicit zero-state for spec #5.
- **DevOps-first:** schema-free (no Alembic). CI cold-start runs the
  full integration matrix against real PG. The `TESTING` guard is part
  of the spec set — guarantees the job doesn't run in CI.
- **SOLID — S:** `RetentionService` does one thing (prune). Scheduler
  registration is in the plugin lifecycle, not the service.
- **SOLID — D:** repo + storage + clock are injected.
- **DRY:** the same service is called by the cron AND the manual
  Makefile target — one home for the prune behaviour.
- **Liskov:** fake `IFileStorage` (in-memory) and a real one (S3 / local
  files) substitute cleanly — the failure-tolerance contract holds for
  both.
- **NO OVERENGINEERING:** one service, one job registration, no plugin
  surface beyond what's already there. No new tables.
- **Core agnostic:** entirely inside `plugins/meinchat/`.
