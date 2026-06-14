# S89 — Heavy-load data-exchange: CLI · UI · API import/export speed at 100k → 1M rows

**Status:** PLANNED — 2026-06-14
**Repos:** `vbwd-platform` (workflow + Locust/bench harness + thresholds) · `vbwd-backend` (core data-exchange affordances: row-cap config, streaming export, bulk test-data generator).
**Track:** independent. Continuation of the heavy-load line — supersedes nothing; it adds a *second* load profile dedicated to data-exchange throughput.
**Depends on:**
- The unified data-exchange framework (exists): core `vbwd/services/data_exchange/`, admin routes `vbwd/routes/admin/data_exchange.py`, CLI `vbwd/cli/data_exchange.py`, fe-admin unified Import/Export view.
- S30 affordances (`flask seed [plugin|all]`, `GET /api/v1/_routes`, `GET /api/v1/_seed_status`) — done.
- S29 heavy-load harness (`vbwd-platform/.github/workflows/heavy-load.yml` + `tests/load/`) — done.
- The per-plugin exchangers shipped by S46 / S61–S64 for the four entities under test.

**Prior art:** [S29 heavy-load harness](../../20260530/done/s30-heavy-load-harness-fixes.md) · [S30 load-test affordances](../../20260530/done/s30-load-test-code-affordances.md) · [report 12](../../20260530/reports/12-s29-heavy-load-harness-complete.md) · [report 13](../../20260530/reports/13-heavy-load-validated-engine-speed.md).

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** (the row-cap config + streaming + bulk generator are core; nothing reads a plugin entity) · **NO OVERENGINEERING** (narrowest change that makes the measurement runnable and meaningful) — [`_engineering_requirements.md`](_engineering_requirements.md). Test data is generated **through services / repository bulk-insert APIs, never raw SQL** ([[feedback_no_direct_db_for_test_data]]); schema changes (none expected) would be Alembic-only.
**Gate:** `bin/pre-commit-check.sh --full` green on `vbwd-backend`; the new `data-exchange` load profile completes end-to-end in CI for **Tier 1** (the smallest tier) and **fails only on a real signal** (a measured budget breach or a backend error), never on harness drift. The full Tier-2/Tier-3 sweep is **manual workflow_dispatch** (cost-gated), not on every push.

---

## 1. Goal

Measure — reproducibly, in CI, and on one dashboard — **how fast import and
export are across all three operator surfaces** (CLI, REST API, fe-admin UI)
for four bulk entities, at three dataset scales. Every number is attributable
to a surface × operation × entity × scale cell, so a regression in any one of
them is visible in the next run, not discovered in production by a customer
trying to import their catalogue.

This is a *measurement* sprint first. The code we add to `vbwd-backend` is only
what the measurement **requires to run at all**: today a 100k or 1M export/import
is impossible because `DEFAULT_ROW_CAP = 10000` rejects it, and the export path
materialises every row + the whole JSON string in memory before returning. Those
two are the load-bearing blockers; we fix exactly them and stop.

### Entities under test (real exchanger keys)

| User-facing name | Exchanger `entity_key` | Plugin | csv? |
|---|---|---|---|
| Products | `shop_products` | `shop` | yes |
| Bookings | `bookings` | `booking` | json |
| Tarif plans | `subscription_plans` | `subscription` | json |
| Add-ons | `subscription_addons` | `subscription` | json |

### Dataset scale tiers (as requested)

| Tier | products | bookings | tarif plans | addons | When it runs |
|---|---|---|---|---|---|
| **T1** | 100 000 | 10 000 | 10 000 | 10 000 | CI gate (every dispatch) + the CI smoke |
| **T2** | 100 000 | 100 000 | 100 000 | 100 000 | manual sweep |
| **T3** | 1 000 000 | 1 000 000 | 1 000 000 | 1 000 000 | **DEFERRED — out of scope this sprint** (see below) |

> T1 mirrors the exact mix the request named (products already at 100k while the
> rest sit at 10k). T2 lifts everything to 100k. The tiers are a single
> `tier` workflow input so an operator dials the ambition (and the cost) up or down.
>
> **Decision (2026-06-14):** this sprint **caps at T2 (100k)**. T3 (1M × 4 = 4M
> rows) is left **defined but deferred** to a follow-up — generating + holding 4M
> rows on the standard CI runner is a separate infra question (disk/RAM, possibly a
> self-hosted runner), and T2's attribution data is expected to already reveal
> where each surface breaks. The `tier` input keeps a `t3` slot so the follow-up is
> a config + capacity decision, not a code change. We measure at T2 first, then
> decide whether 1M is worth the runner cost.

---

## 2. The measurement matrix

For each **tier**, for each of the **4 entities**, for each **surface** (CLI /
API / UI), for each **operation** (export / import) we capture two layers of
metric: **headline** (the comparable numbers) and **attribution** (where the time
and memory actually went). The whole point of the attribution layer is to answer
*"what is the bottleneck"* — without it a slow cell only tells you it's slow, not
why.

### 2.1 Headline metrics (the comparable numbers)

- **wall-clock seconds** — the operator-perceived total.
- **rows/sec** — throughput; the one number comparable across scales and surfaces.
- **peak RSS of the api/worker process** — does it stream or does it climb with N?
- **payload bytes** on the wire / on disk — artefact size, and bytes/row.
- **outcome** — `ok | row-cap-rejected | error | timeout | oom`.

### 2.2 Attribution metrics (where the time + memory go — the bottleneck finder)

Each cell's wall-clock is decomposed into stages that sum to the total, so a
regression or a slow scale-up points at one stage, not at "the whole thing":

**Time, broken down by stage**
- **DB time** — total seconds in SQL, and split into **read/query** vs
  **insert/update** vs **commit/flush**. Captured via a SQLAlchemy
  `before_cursor_execute`/`after_cursor_execute` timing hook active only under the
  load env flag (no prod overhead).
- **query count** and **rows-per-query** — the N+1 detector. A 1M upsert doing 1M
  individual `SELECT … WHERE natural_key=?` probes is *the* expected bottleneck;
  this is how we prove it.
- **serialisation / deserialisation time** — Python `dict`→JSON (export) and
  JSON→`dict` + model-mapping (import), isolated from DB time.
- **transport time** — for API/UI: time on the wire (request upload + response
  download), separated from server compute via server-side timing.
- **app/overhead time** — wall-clock minus the accounted stages (GC pauses,
  Python object churn, framework overhead); a large residual is itself a signal.

**Memory + resource pressure**
- **peak RSS** *and* whether it grows with N (streaming works) or linearly
  (materialisation bottleneck).
- **GC**: collection count + total GC pause time during the op (Python `gc` stats)
  — large object graphs at 1M show up here.
- **DB connection / transaction duration** — longest single transaction and
  longest lock-wait (from `pg_stat_activity` / `pg_locks` sampled during the op);
  surfaces the "one giant transaction holds a lock for 40s" failure mode.
- **CPU%** of the api/worker vs **DB CPU%** — tells us whether the ceiling is
  app-side (serialisation/GC) or DB-side (index/IO).

**Surface-specific bottleneck signals**
- **API/UI**: HTTP status + whether the **60s admin proxy cut**
  ([[project_fe_admin_plugin_runtime_manifests]]) or `client_max_body_size`
  fired (413/504), and TTFB vs total (did streaming start early or buffer?).
- **CLI**: file write throughput (MB/s to `--outfile`) vs compute, so a slow
  disk doesn't masquerade as a slow exporter.
- **DB-side artefacts after the op**: table + index size on disk, and whether an
  `ANALYZE`/autovacuum was triggered (affects the *next* operation's plan).

> **How the split is captured (NO OVERENGINEERING):** all of the above is
> read from facilities that already exist — a SQLAlchemy event hook (already the
> idiom in the codebase), `resource.getrusage` / `tracemalloc` for memory, `gc`
> module stats, `psutil` for CPU, and two cheap Postgres catalog queries
> (`pg_stat_activity`, `pg_stat_statements` if available, `pg_total_relation_size`)
> sampled by the bench. No APM agent, no new infra. The hook + sampler live in the
> harness / behind the load env flag, **off in production**.

That is 4 × 3 × 2 = **24 cells per tier**, each carrying the headline + attribution
fields. The harness emits them as one `results.json` and renders (a) a grouped bar
chart of rows/sec by surface × entity (reusing `tests/load/chart/`), **(b) a
stacked stage-breakdown bar per cell** (db-read / db-write / commit / serialise /
transport / overhead) so the bottleneck stage is visible at a glance, plus a
Markdown table in the job summary.

**Import is measured twice per cell** — once into an **empty** table (pure
insert) and once **re-importing the same envelope** (upsert-by-natural-key, the
realistic "customer re-uploads their corrected sheet" path). The attribution split
is what makes this pair informative: cold insert should be DB-write-bound, upsert
should be DB-read-bound (the per-row natural-key probe), and the stacked chart
proves which — turning "upsert is slower" into "upsert spends 80% in N lookup
queries", an actionable finding.

---

## 3. What is broken / missing today (the obstacles the run will hit)

Verified against current source:

1. **`DEFAULT_ROW_CAP = 10000`** (`base_model_exchanger.py`) — every exchanger
   raises `RowCapExceededError` past 10k rows. Export returns
   `ROW_CAP_STATUS`; CLI `_fail`s. **Tier 1 already exceeds it for products.**
   Without a configurable cap there is *nothing to measure* above 10k.
2. **Export materialises everything in memory.** `exchanger.export(selector).rows`
   builds the full row list, then the API `jsonify`s the whole envelope and the
   CLI `json.dumps(...)`s the whole string. At 1M rows this is hundreds of MB of
   Python objects + an equal-size string — likely OOM on a CI runner, and at best
   a misleading "speed" number dominated by GC.
3. **Import reads the whole file into one request body / one transaction.** The
   API import and the per-row upsert lookups are untested at 1M; transaction size
   and lock duration are unknown.
4. **No bulk generator at this scale.** `flask seed` produces *demo* volumes;
   `cli/test_data.py` seeds a handful of rows. There is no supported way to
   manufacture 1M products through the service/repository layer.
5. **No nginx body-size / timeout headroom** for a multi-hundred-MB import upload
   on the API and UI surfaces — the 60s admin proxy cut ([[project_fe_admin_plugin_runtime_manifests]])
   and `client_max_body_size` will both bite. The harness must surface these as
   *real findings*, not crash on them.

---

## 4. Slices

Ordered so each lands independently and the harness can lean on the prior one.
Backend slices are core-only and gate-green in isolation; harness slices live in
`vbwd-platform`.

### Slice 0 — Configurable row cap (backend, core)

**File:** `vbwd-backend/vbwd/services/data_exchange/base_model_exchanger.py`.

`DEFAULT_ROW_CAP` stays 10000 as the **safe default** (a stray "export
everything" from the UI should still be protected). Make it overridable per
process via an env var read once at construction — e.g.
`VBWD_DATA_EXCHANGE_ROW_CAP` (int; `0`/unset → keep 10000). The exchangers and
the registry already pass `row_cap` through; this only changes the **source of
the default**, not the contract.

- The load harness exports `VBWD_DATA_EXCHANGE_ROW_CAP=2000000` for the run.
- Production is untouched (var unset → 10000).

**TDD (write first):** `tests/unit/services/data_exchange/test_row_cap_config.py`
— (a) unset env → cap is 10000 and 10001 rows raise `RowCapExceededError`;
(b) env=`500000` → 10001 rows pass, 500001 raise; (c) env=`0` / garbage →
falls back to 10000 (no crash). Liskov: the override is behaviour-preserving for
the default path.

> **NO OVERENGINEERING note:** we do *not* build a per-request cap override in the
> API body, a per-tenant config table, or a UI control. One env var the harness
> sets is the entire need today.

### Slice 1 — Streaming / chunked export, NDJSON artefact (backend, core)

The headline blocker for honest 100k numbers. Export must not hold N rows + N
bytes in memory at once.

- Add a **chunked iterator** path to `BaseModelExchanger` (`iter_export(selector,
  *, chunk_size, include_pii) -> Iterator[list[dict]]`) that pages the underlying
  query (keyset/`yield_per`) instead of `.all()`. The existing `export()` stays
  (small entities, the UI default) and is reimplemented on top of the iterator
  (DRY) — it just drains the iterator into a list, so its contract is unchanged
  (**Liskov**).
- **Artefact format: NDJSON** (decided 2026-06-14) — one JSON object per line, the
  rows streamed line-by-line. The **first line is the envelope header**
  (`{vbwd_export, version, instance, entity_key, format:"ndjson"}` with no `rows`),
  each subsequent line is one row. This preserves the envelope's provenance
  metadata while making both export and import strictly streaming and O(1) in
  memory. A new `ndjson` value joins the existing `json`/`csv`/`zip` formats.
- The **CLI `export --format ndjson`** writes the header line then streams each
  `iter_export` chunk to the `--outfile` handle. The **API `export`** with
  `format=ndjson` returns a Flask streaming response (`stream_with_context`,
  `Content-Type: application/x-ndjson`) so peak RSS is bounded by `chunk_size`, not
  by total rows. The existing buffered `json` envelope stays as the default for
  small/UI exports.
- The **import side learns NDJSON**: a streaming reader parses the header line,
  then applies rows in `chunk_size` batches (each batch its own flush) — so import
  is also bounded-memory and never builds the full list. This is the *added work*
  NDJSON costs us, and it is in scope (it is what makes the import measurement
  honest at 100k).
- `chunk_size` a named module constant (e.g. 5000), no magic number.

**TDD (write first):** `iter_export` yields all rows in `chunk_size` batches and
the concatenation equals the old `export().rows`; peak-objects stay bounded
(assert the iterator never builds the full list — e.g. patch the query to count
`yield_per` pages); **NDJSON round-trip**: `export --format ndjson` → `import`
reproduces the rows byte-for-byte equal to the buffered-JSON round-trip (parity
across formats); a malformed NDJSON line is reported with its line number, not a
silent skip; the header line is required and validated.

> Scope guard: this slice makes **both** export and import bounded-memory for the
> NDJSON path (NDJSON's line framing makes streaming import tractable — unlike a
> single giant JSON object). The legacy buffered JSON/CSV paths are unchanged; if
> a *buffered* 100k import strains memory in the run, that is a **measured
> finding** for the report, not a reason to rewrite the legacy path here.

### Slice 2 — Bulk test-data generator (backend, core CLI)

A supported, idempotent way to manufacture the tiers **through the
service/repository layer** ([[feedback_no_direct_db_for_test_data]]) — no raw SQL.

- New command: `flask data-exchange bulk-seed <entity> --count N [--reset]`.
- It resolves the entity's exchanger/repository and inserts `N` rows via the
  repository's bulk-insert API (`bulk_save_objects` / `bulk_insert_mappings`
  *through the repo*, in batches), generating deterministic synthetic rows
  (slug = `loadtest-<entity>-<i>`, valid required fields, valid FKs — e.g. each
  product points at one seeded category; bookings at one seeded resource).
- Idempotent: re-running with the same N is a no-op upsert; `--reset` drops the
  load-test rows first (matched by the `loadtest-` slug prefix only — never
  touches real/demo data).
- Reports inserted/skipped counts + exit code for the harness.

**Why a CLI, not the API:** seeding 1M rows over HTTP would itself be the thing
under test and would dominate setup time; the generator must be *fast and
out-of-band* so the measured export/import numbers are clean.

**TDD (write first):** `bulk-seed shop_products --count 1000` → 1000 rows exist
via the repo, all with `loadtest-` slugs and a valid category FK; re-run → still
1000 (idempotent); `--reset` → load-test rows gone, any non-`loadtest-` row
untouched; an unknown entity exits non-zero with a clear message. Batches commit
incrementally (assert no single 1M transaction).

### Slice 2b — Server-side stage timing (backend, core; load-env-gated)

The bottleneck attribution (§2.2) needs the *server's* view of where time went —
the client clock can only see total + transport. Add a lightweight, **load-env-gated**
(`VBWD_DATA_EXCHANGE_PROFILE=1`, off in prod) timing collector:

- A SQLAlchemy `before/after_cursor_execute` hook accumulates per-operation
  **DB time**, **query count**, and a coarse read/write/commit split (by statement
  verb). Reset per request/CLI-invocation.
- Export/import wrap their **serialise/deserialise** spans with the same collector.
- The numbers are returned to the harness without scraping logs: the API export/
  import responses carry a `Server-Timing` header (standard, cheap) **and** the
  collector totals in a trailing `_profile` field of the import JSON result; the
  CLI prints a `--profile-json` one-liner to stderr. The bench reads these directly.

This is the only backend code that the attribution layer needs; it is inert unless
the env flag is set. **TDD:** with the flag off, zero overhead and no header; with
it on, an export of K rows reports query_count ≥ 1, db_seconds > 0, serialise_seconds
> 0, and the stage sum is within ε of the measured total. Liskov: the export/import
contracts (status, body, envelope) are byte-identical with the flag on or off — the
profile data is purely additive.

### Slice 3 — `data-exchange` load profile in the harness (`vbwd-platform`)

Add a **third profile** to `heavy-load.yml` (`profile: data-exchange`) alongside
`default` and `plugins`, plus a new bench module `tests/load/data_exchange_bench.py`.

This profile is **not a Locust VU swarm** — it is a serial, instrumented bench
(import/export are throughput operations, not concurrency operations). The
existing Locust harness measures *request concurrency*; this one measures
*single-operation throughput*. New inputs:

- `tier` (choice: `t1`, `t2`; default `t1`. A `t3` slot is reserved but rejected
  with a clear "deferred — needs a capacity decision" message this sprint),
- `entities` (default `all` = the four; or a comma list),
- `surfaces` (default `all` = cli,api,ui),
- per-op budgets: `fail_export_rows_per_sec_min`, `fail_import_rows_per_sec_min`,
  `fail_max_seconds` (breach → job fails on a *real* signal).

Per cell the bench:
1. **CLI** — `docker compose exec -T api flask data-exchange export <key> --all --format ndjson -o /tmp/x.ndjson` (time it, stat the file), then `… import <key> /tmp/x.ndjson` (cold), then again (upsert).
2. **API** — `POST /api/v1/admin/data-exchange/<key>/export` with `format=ndjson` (stream to disk), then `/import` (multipart, NDJSON) cold + upsert, with the admin bearer.
3. **UI** — drive the fe-admin unified Import/Export view with **Playwright** (click Export → capture download timing; upload the file → capture the completion signal). UI is the operator-honest path: it includes nginx, the 60s admin proxy cut, and the browser. The UI cell is allowed to **record a timeout as the result** (a genuine "the UI can't do 1M" finding) rather than fail the job.

Between cells the bench **truncates the load-test rows** (via Slice 2 `--reset`)
so each measurement starts from a known state; re-import (upsert) runs against the
just-imported set.

**Pre-flight (reuse S30 affordances):** assert `GET /api/v1/_routes` lists the
export/import routes and `GET /api/v1/_seed_status` shows the four plugins seeded,
**before** any timing — fail-fast on harness/route drift, exactly the S29 lesson.

### Slice 4 — Results aggregation, chart, thresholds (`vbwd-platform`)

- Emit `results.json`: one record per cell carrying **both** layers from §2 —
  headline `{tier, entity, surface, op, variant(cold|upsert), rows, seconds,
  rows_per_sec, peak_rss_mb, bytes, outcome}` **and** attribution
  `{db_seconds:{read,write,commit}, query_count, rows_per_query,
  serialise_seconds, transport_seconds, overhead_seconds, gc_pause_seconds,
  gc_collections, longest_txn_seconds, longest_lock_wait_seconds, app_cpu_pct,
  db_cpu_pct, table_bytes, index_bytes, proxy_cut(bool), body_size_rejected(bool)}`.
- Extend `tests/load/thresholds.py` (or a sibling) to classify each cell:
  `ok | slow(budget breach) | error | row-cap-rejected | timeout | oom` and decide
  the job exit code (any `error`, or any `slow` on a *non-UI* surface, fails;
  `timeout` on UI at T3 is allowed/annotated). Same "say *why* it failed"
  discipline as S29's threshold module — **and now "say *which stage*"**: a `slow`
  classification names the dominant stage (e.g. `slow:db-read (87%)`) from the
  attribution split, so the failure message is already a diagnosis.
- **Bottleneck rollup:** a small summariser that, across all cells, ranks the
  dominant stage per cell and flags the recurring ceiling (e.g. "import is
  db-read-bound on every entity at T2+ → N+1 natural-key probe"). This is the
  artefact that answers the sprint's headline question.
- Reuse `tests/load/chart/` to render (a) a grouped bar chart (rows/sec by
  surface × entity, faceted by tier) and **(b) a stacked stage-breakdown bar per
  cell** (db-read / db-write / commit / serialise / transport / overhead) into the
  job summary + an artefact; attach the Markdown matrix table to
  `$GITHUB_STEP_SUMMARY`.

---

## 5. Out of scope (named, so the next reader knows it was a choice)

- **T3 / 1M rows (4M total).** Capped at T2 (100k) this sprint by decision
  (2026-06-14). The `t3` input slot is reserved but rejected with a "deferred"
  message; running 1M is a follow-up gated on a runner-capacity decision (the T2
  attribution data informs whether it's worth the cost).
- **Streaming import for the *legacy* buffered JSON/CSV paths.** The **NDJSON**
  path is bounded-memory on both ends in this sprint (Slice 1). Retrofitting the
  old single-object JSON import to stream is out of scope — if a buffered 100k
  import strains memory in the run, it's a *measured finding*, and NDJSON is the
  recommended path anyway.
- **nginx body-size / proxy-timeout tuning for prod.** The run will *surface*
  these limits as findings (a 100k import may hit `client_max_body_size` and the
  60s admin cut). Raising them in the prod compose is a deliberate,
  separately-reviewed change, not this sprint.
- **Concurrency of import/export** (N operators importing at once). This sprint is
  single-operation throughput; concurrent exchange is a different question.
- **The other exchangers** (cms_*, ghrm_*, orders, etc.). Four entities as
  requested; the harness is parameterised by `entities` so adding more later is a
  config change, not code.
- **Per-tenant / per-request cap overrides, a cap UI control.** One env var.

---

## 6. Acceptance / Definition of Done

1. `bin/pre-commit-check.sh --full` green on `vbwd-backend` (Slices 0–2b + their
   tests). No new lint suppressions ([[feedback_no_noqa_without_permission]]).
2. `flask data-exchange bulk-seed shop_products --count 100000` completes
   in-container through the repo layer (no raw SQL), idempotent + `--reset`-clean.
3. With `VBWD_DATA_EXCHANGE_ROW_CAP` set, a 100k `shop_products` **NDJSON export**
   completes via CLI **and** API with bounded peak RSS (streamed), and the
   artefact re-imports (streaming) byte-for-byte equal.
4. With `VBWD_DATA_EXCHANGE_PROFILE=1`, an export/import returns the stage-timing
   split (`Server-Timing` + `_profile`) and the stage sum is within ε of the
   measured total — i.e. the bottleneck attribution is real, not estimated.
5. The `data-exchange` profile of `heavy-load.yml` runs **Tier 1** end-to-end in
   CI and produces `results.json` (headline **+ attribution**) + the rows/sec chart
   + the **stacked stage-breakdown chart** + the summary table, **failing only on a
   real signal** (budget breach / backend error) with a failure message that names
   the dominant stage — never on harness drift; proven by one green dispatch and
   the S29-style pre-flight contract check.
6. A **manual** T2 dispatch is documented (inputs + expected cost/runtime) in the
   completion report, with the measured matrix + bottleneck rollup attached. Cells
   that legitimately exceed a surface's capability (e.g. UI 100k import timing out)
   are recorded as `timeout`/`row-cap-rejected`/`error`/`oom` **with the number**,
   not hidden.
7. Completion report `docs/dev_log/20260613/reports/NN-s89-heavy-load-data-exchange.md`
   with: the as-built deviations, the full T1 **and** T2 matrices, and a
   "where it breaks and why" narrative driven by the attribution data (which
   surface dies first at which scale, and the **dominant stage** — row cap, db-read
   N+1, serialise/GC, transaction size, proxy timeout, or body size). Explicit note
   on whether the data justifies the deferred T3 (1M) follow-up.

---

## 7. Decisions made (2026-06-14) + remaining risks

**Resolved:**
- **Scale ceiling = T2 (100k).** T3 (1M × 4 = 4M rows) is deferred — the standard
  CI runner's disk/RAM for 4M rows is a separate capacity decision, and T2's
  attribution data is expected to already pinpoint each surface's ceiling. The
  follow-up reuses the reserved `t3` slot; no code change to enable it later.
- **Streamed artefact = NDJSON** (header line + one row per line). Both export and
  the new streaming import are bounded-memory on this path; round-trip parity vs
  the buffered JSON path is the hard test.
- **Server-side timing collector = in scope (Slice 2b).** Client-side inference
  was rejected — it can't cleanly separate serialise time from DB time, which is
  the crux of attribution.

**Remaining risks (resolve in TDD or escalate):**
- **Upsert-by-natural-key cost at 100k.** If the per-row lookup is O(N) index
  probes, upsert rows/sec may be 10–100× slower than cold insert. That is exactly
  what the db-read attribution split is built to *prove*; remediation (batched
  natural-key resolution) is a follow-up, not a pre-optimisation here.
- **UI download/upload timing under Playwright** at 100k (tens of MB) — the browser
  may be the bottleneck, not the backend. The bench labels UI numbers as
  "operator-perceived (incl. browser + nginx)", distinct from API numbers.
- **`pg_stat_statements` availability** on the CI Postgres image is not guaranteed.
  Attribution treats it as best-effort: the SQLAlchemy hook + catalog queries are
  the primary source; statement-level stats are an *enrichment* the bench skips
  (with a logged note) if the extension is absent — never a hard dependency.
```
