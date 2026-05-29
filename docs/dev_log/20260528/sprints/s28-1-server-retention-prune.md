# S28.1 — Server retention prune (daily APScheduler job)

**Parent sprint:** [S28 — meinchat extension seams + meinchat-plus + retention](s28-meinchat-e2e-encryption-and-retention.md)
**Status:** PLANNED — 2026-05-28. **Revised 2026-05-28** to absorb the
critical review:
- Prune predicate now exempts **undelivered e2e_v1 rows** (closes
  critical-review §C20: a 2-day default would otherwise delete
  pre-encrypted messages addressed to a recipient who is offline for
  3 days, before they have a chance to fetch and consume the prekey).
- `messages_retention_days_server = 0` is documented as **mutually
  exclusive with `e2e_v1` enabled** — operators must pick one or the
  other (closes critical-review §C2).
- The `prune_messages` signature gains an injected predicate so
  meinchat-plus's `E2eAwareRetentionPolicy` replaces the default via
  `IRetentionPolicy` (S28.3a §2.4).
**Depends on:** [S28.0](s28-0-config-and-limits-endpoint.md) (reads the config keys it created); coordinated with [S28.3a](s28-3a-meinchat-extension-ports.md) §2.4 `IRetentionPolicy` port + [S28.3b](s28-3b-meinchat-plus-signal-ratchet.md) §2.3 delivery-tracking table.
**Blocks:** nothing directly; lifts a privacy risk independently of the crypto track.

**Repos touched:** `vbwd-backend/plugins/meinchat/` only.
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** — [`_engineering-requirements.md`](_engineering-requirements.md).
**Gate:** `bin/pre-commit-check.sh --plugin meinchat` GREEN (both `--quick` and `--full`); integration suite GREEN.

---

## 1. Goal

A daily background job hard-deletes `message` rows whose `sent_at` is
older than `messages_retention_days_server` **AND which are eligible
to be pruned** per the active `IRetentionPolicy.should_prune(row, now)`
predicate. Plus the matching attachment objects from `IFileStorage`.
**Default 2 days.** The job is idempotent — re-running it is a no-op.

**Eligibility predicate (key change in this revision):**
- **`protocol = 'plain'` rows** → eligible as soon as `sent_at` is past
  the threshold. (Today's behaviour.)
- **`protocol = 'e2e_v1'` rows** → eligible only when ALSO
  `delivered_to_all_addressed_devices_at IS NOT NULL`. Async
  first-message delivery via prekey bundles requires the server to hold
  ciphertext until every addressed device has fetched it. If a recipient
  is offline for longer than `messages_retention_days_server`, the row
  survives the prune until they come online; only then does the clock
  start.

**`messages_retention_days_server = 0` mode** is documented as **mutually
exclusive with meinchat-plus enabled**. The admin UI surfaces a
"`0` is incompatible with secure-chat (`e2e_v1`); set a non-zero value
or disable `meinchat-plus`" warning when both are configured. The
backend refuses to start with both set (validated at plugin enable).

This slice lifts the today-existing risk of forever-plaintext rows
sitting in Postgres **independently of the crypto track** — even if
S28.3b (meinchat-plus) never lands, the operator's leak window shrinks
from "forever" to "2 days".

## 2. Touched files

### 2.1 New — `RetentionService` (uses the `IRetentionPolicy` port)

`vbwd-backend/plugins/meinchat/meinchat/services/retention_service.py` (~70 LOC).

```python
class RetentionService:
    def __init__(
        self,
        *,
        message_repo: IMessageRepository,
        attachment_storage: IFileStorage,
        retention_policy: IRetentionPolicy,        # resolved via S28.3a registry
        clock: Callable[[], datetime] = lambda: datetime.now(tz=UTC),
        logger: logging.Logger = logger,
    ) -> None: ...

    def prune_messages(self) -> RetentionResult:
        """Hard-delete messages where ``retention_policy.should_prune(row, now)``
        returns True. The policy reads days from config + (for the
        meinchat-plus E2eAwareRetentionPolicy) the
        `delivered_to_all_addressed_devices_at` column. Safe to re-run
        (idempotent)."""

    def prune_attachments(self) -> RetentionResult:
        """Best-effort delete of attachment objects whose owning rows
        are being pruned. Storage failures are logged + counted, never
        propagated — the message row delete is the source of truth."""
```

`RetentionResult` is a frozen dataclass
`{deleted_count, skipped_undelivered_count, skipped_count, errors}` —
`skipped_undelivered_count` tracks E2E rows that were past the time
threshold but exempt because `delivered_to_all_addressed_devices_at IS
NULL`. Surfaced in the daily cron log so ops can see ratios.

**Default `ConfigRetentionPolicy`** (meinchat-alone) reads
`messages_keep_days` / `attachments_keep_days` from the config store
and returns `True` for any row past the threshold (today's behaviour
preserved).

**`E2eAwareRetentionPolicy`** (registered by meinchat-plus per S28.3a
§2.4 + S28.3b §2.9) wraps the default:

```python
def should_prune(self, message: Message, now: datetime) -> bool:
    past_threshold = (now - message.sent_at) > timedelta(days=self.messages_keep_days())
    if not past_threshold:
        return False
    if message.protocol == "plain":
        return True
    return message.delivered_to_all_addressed_devices_at is not None
```

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

### 3.1 Unit specs — `tests/unit/services/test_retention_service.py` (NEW, ≥ 12 specs)

| # | Spec | Asserts |
|---|---|---|
| 1 | `test_deletes_only_messages_older_than_threshold` | seed messages at -5d / -2d / -1d; prune with `days_to_keep=2` → -5d gone, -2d gone (boundary inclusive on `<`), -1d kept |
| 2 | `test_off_by_one_minute_at_threshold` | `sent_at` = threshold − 1min → pruned; threshold + 1min → kept |
| 3 | `test_days_zero_deletes_everything_when_e2e_disabled` | `days_to_keep=0` + only plain rows → all rows gone |
| 4 | `test_days_negative_raises` | `days_to_keep=-1` → `ValueError` (fail-fast on config typo) |
| 5 | `test_idempotent_re_run_is_noop` | run twice in a row; second run reports `deleted_count == 0` |
| 6 | `test_returns_deleted_ids` | result lists exactly the ids of removed rows (so attachment prune can fan out) |
| 7 | `test_attachment_storage_failure_is_logged_not_raised` | fake `IFileStorage` raises on `delete` → service catches, increments `errors`, message-row delete still committed |
| 8 | `test_clock_is_injected` | inject a fixed clock; assert prune respects it (DI / Liskov) |
| 9 | `test_e2e_undelivered_row_survives_prune` | `protocol='e2e_v1'`, `delivered_to_all_addressed_devices_at IS NULL`, sent 5d ago, days_to_keep=2 → **kept** (closes critical-review §C20) |
| 10 | `test_e2e_delivered_row_pruned_normally` | `protocol='e2e_v1'`, `delivered_to_all_addressed_devices_at` set to 4d ago, days_to_keep=2 → deleted |
| 11 | `test_undelivered_count_is_reported_separately` | mixed seed → `RetentionResult.skipped_undelivered_count` is the right number |
| 12 | `test_zero_days_and_e2e_enabled_refused_at_plugin_enable` | with `meinchat-plus` enabled and `messages_retention_days_server=0`, plugin enable raises `IncompatibleRetentionConfigError` (closes critical-review §C2) |

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

- **TDD-first:** ≥ 15 specs (up from 11; added the E2E exemption +
  zero-days-incompat specs) land before the service body is written.
- **DevOps-first:** schema-free in this slice (no Alembic — the
  `delivered_to_all_addressed_devices_at` column is added by S28.3a).
  CI cold-start runs the full integration matrix against real PG. The
  `TESTING` guard is part of the spec set.
- **SOLID — S:** `RetentionService` does one thing (loop + delete).
  The eligibility predicate lives in `IRetentionPolicy.should_prune`,
  not the service — so swapping policies (S28.3b's E2E-aware one) is
  a pure registration change.
- **SOLID — D:** repo + storage + clock + retention policy are
  injected. Liskov-safe — any policy that honours the contract works.
- **NO OVERENGINEERING — concrete corrections.**
  - **No separate `prune_undelivered_e2e_rows` method.** The
    eligibility predicate threads the E2E exemption into the same loop
    — one code path for both protocols.
  - **No new tables in this slice.** Delivery tracking lives in
    `meinchat_plus_message_delivery` (S28.3b), not in meinchat. Avoids
    coupling meinchat to e2e_v1 schema concerns.
- **DRY — concrete corrections.**
  - **Same `RetentionService`** powers both the daily cron AND the
    manual `make meinchat-prune` Makefile target — one home for the
    behaviour.
  - **One `should_prune(row, now)`** predicate is the single source of
    truth for "is this row eligible?" — re-used by the cron, the
    Makefile target, AND (later) a dashboard "rows-eligible-for-prune"
    query.
- **Liskov:** fake `IFileStorage` (in-memory) and a real one (S3 /
  local files) substitute cleanly — the failure-tolerance contract
  holds for both. `IRetentionPolicy` substitutability (default
  ConfigRetentionPolicy ↔ E2eAwareRetentionPolicy) is the explicit
  Liskov check.
- **Core agnostic:** entirely inside `plugins/meinchat/` +
  `plugins/meinchat-plus/`.
