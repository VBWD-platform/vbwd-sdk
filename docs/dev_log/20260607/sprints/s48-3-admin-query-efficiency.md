# S48.3 — Admin list query efficiency (joins, indexes, pagination counts)

**Status:** PLANNED — 2026-06-03. Parent: [S48](s48-load-capacity-and-resilience.md).
**Area:** `vbwd-backend` `plugins/subscription` (`admin_subscriptions`) + core `vbwd/routes/admin/invoices.py` + repositories; Alembic indexes.

## Engineering requirements (BINDING)

TDD-first · SOLID · DRY · clean code · NO OVERENGINEERING — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: `--plugin subscription --full` + core `--full` green; validated by a heavy-load re-dispatch. **Schema changes via Alembic only** ([[feedback_migrations_only]]); plugin migrations live in the plugin ([[feedback_plugin_migrations_in_plugin]]).

## Problem (from the load profile)

Admin list views are the **slowest endpoints even at low load** and degrade most under it:

| endpoint | p50 @ 50 VU | p50 @ 100 VU | p99 @ 100 VU |
|---|---:|---:|---:|
| `GET /admin/subscriptions` | 120 ms | 130 ms | 810 ms |
| `GET /admin/invoices` | 77 ms | 92 ms | 450 ms |

They are ~10× slower than catalogue reads (9 ms) because they do multi-table **joins + pagination with a total count**. Under contention they hold DB connections longer, worsening the pool pressure S48.1 addresses. (These are admin-only, low-RPS endpoints — so this is tail/efficiency hygiene, not the top capacity lever; sequenced after S48.1/S48.2.)

## Goal

Bring admin list latency down (target p50 well under the catalogue's order of magnitude, p99 under ~250 ms at 100 VU) by removing N+1 queries, adding the indexes the filters/sorts actually need, and making pagination totals cheap.

## Design (measure → fix)

1. **Profile first.** With `flask seed all` data scaled up (enough rows to be representative — seed via service, [[feedback_no_direct_db_for_test_data]]), capture the SQL each route emits (SQLAlchemy echo / `EXPLAIN ANALYZE`). Confirm the actual cost: N+1 lazy loads vs missing index vs `COUNT(*)`.
2. **N+1 → eager load.** If the serializer triggers per-row lazy loads (plan, user, line items), use `selectinload`/`joinedload` in the repository query so the list is O(1) queries.
3. **Indexes (Alembic).** Add indexes for the columns the admin filters/sorts on (`status`, `user_id`, `plan_id`, `created_at`) where missing — confirmed by the EXPLAIN, not guessed. Plugin migrations in `plugins/subscription/migrations/`.
4. **Cheap pagination totals.** `COUNT(*)` over a growing table is a common tail cost. Options (pick the narrowest that fits the UI): keyset/seek pagination, an approximate count for large offsets, or a cached/periodic count — only if EXPLAIN shows the count is the cost.

## TDD plan

- **Unit/integration:** the list repository emits a bounded number of queries regardless of page size (N+1 guard — assert query count via a SQLAlchemy event counter).
- **Migration test:** new indexes up/down/up; queries use them (EXPLAIN in an integration check or a documented manual step).
- **Integration:** admin list returns the same data + total as before (no behavioural regression) — pure performance change.

## Acceptance

- Query-count guard green (no N+1); `--plugin subscription --full` + core `--full` green.
- Heavy-load re-dispatch (100 VU): `/admin/{subscriptions,invoices}` p50/p99 materially lower than the pre-S48.3 baseline; no behavioural diff in responses.

## Out of scope

- Denormalised read models / materialised views (overengineering unless EXPLAIN proves the join itself is irreducible).
- Caching admin lists (per-admin, mutable — not a good cache target).
