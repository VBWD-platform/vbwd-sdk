# S48.00 — Measurement & charting tool (capacity sweep → XY charts)

**Status:** BUILT — 2026-06-06 (tool + tests + workflow wiring landed; pending a heavy-load re-dispatch to validate end-to-end). Parent: [S48](s48-load-capacity-and-resilience.md).
**Area:** `vbwd-platform` — a new `tests/load/chart/` package (sweep runner + parser + plotter). Wraps the **existing** Locust harness (`tests/load/locustfile.py`); does **not** change the harness or the app.

## Engineering requirements (BINDING)

**TDD-first · DevOps-first · SOLID · DI · DRY · clean code · NO OVERENGINEERING** (narrowest change that satisfies the requirement) — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: a new `loadchart_unit` test set green under `bin/pre-commit-check.sh --quick` (pure parse/transform/plot functions, no live stack). The tool is the *instrument* behind the parent's **measure-driven** rule ("fix one proven bottleneck, re-measure, repeat") — every other S48 sub-sprint is validated by re-running this and comparing curves.

## Problem

Capacity work today is judged from **one Locust HTML report per ad-hoc run** ([report 13](../reports/13-heavy-load-validated-engine-speed.md), the 100-VU and 500-VU runs). To find the **knee** — the load at which latency turns up — and to prove a sub-sprint moved it, we read three disconnected reports by eye and eyeball a table:

| load | throughput | p50 | p95 | p99 | error% |
|---|---:|---:|---:|---:|---:|
| 50 VU | 37 req/s | 9 ms | 88 ms | 330 ms | 6.1% |
| 100 VU | 73 req/s | 9 ms | 110 ms | 380 ms | 6.1% |
| 500 VU | 139 req/s | 660 ms | 9 200 ms | 19 000 ms | 51% |

There is no reproducible artifact that **plots** response time against load, no automated sweep across VU levels, and no way to see the DB-pressure dimension at all. "Where is the knee?" and "did S48.1 push it right?" are answered impressionistically.

## Goal

A small Python tool that **sweeps** the existing load harness across a list of load levels, collects each run's stats (plus an optional Postgres query-rate sample), and emits **3–4 XY charts** + a tidy `sweep.csv`. Re-runnable before/after any capacity sub-sprint to show the curve move. Each axis independently selectable **linear / log10 / ln**, because latency-vs-load is often only legible on a log axis.

## Design

A package at `vbwd-platform/tests/load/chart/`, three thin layers (each a pure unit + one I/O edge), driven by one CLI:

```
python -m tests.load.chart.sweep \
  --host http://localhost:5000 \
  --users 10,25,50,100,200,500 \
  --spawn-rate-ratio 0.1 --run-time 2m \
  --scenarios all \
  --pg-dsn postgresql://vbwd:...@localhost:5432/vbwd \   # optional → enables DB-QPS dim
  --out ./load-charts/
```

### 1. Sweep runner — `sweep.py` (I/O edge, kept thin)
- For each level in `--users`, shells out to the **same headless Locust command the CI workflow uses** (`locust -f tests/load/locustfile.py --headless --users N --spawn-rate N*ratio --run-time T --csv <tmp> --html <tmp>`). DRY: build the argv from one shared helper, not a second copy of the command. Spawn-rate defaults to `users × ratio` (ramped, per [S48.0](s48-0-fair-load-harness.md)), not a herd.
- If `--pg-dsn` is given, sample `pg_stat_database` (`xact_commit + xact_rollback`, and `tup_returned`/`tup_fetched`) **immediately before and after** each run; `delta / run_seconds` = **DB transactions·sec⁻¹** (the "density of DB requests per second" dimension). No DB writes — read-only counters. If absent, the DB-QPS chart is simply skipped (degrade gracefully, log why).
- Writes one **`sweep.csv`** (one row per level) and keeps each run's raw Locust CSVs under `--out/runs/<N>/` for audit. The sweep is fully resumable from `sweep.csv` — **plotting never requires re-running the load** (split measurement from rendering, so chart tweaks are free).

### 2. Parser — `parse.py` (pure, the TDD core)
- `parse_locust_stats(csv_text) -> RunStats` reads Locust's `*_stats.csv` "Aggregated" row → `{rps, p50, p95, p99, error_pct, request_count, fail_count}`.
- `parse_history(csv_text) -> list[Sample]` reads `*_stats_history.csv` (timestamped `user_count`, RPS, p50/p95/p99) for the intra-run scatter (RPS-vs-latency from a single ramped run).
- `load_sweep(csv_text) -> list[SweepPoint]` reads our own `sweep.csv` back. All three are pure string→dataclass, fixture-tested.

### 3. Plotter — `plot.py` (pure transform + one savefig edge)
- `Axis = {field, scale}` where `scale ∈ {linear, log10, ln}`; `apply_scale(values, scale)` is a pure, unit-tested transform (guards `≤0` for log → drop/clip with a logged warning).
- `render_chart(points, x: Axis, y: Axis, series?, out_path)` builds one matplotlib figure (Agg backend — headless, no display) and saves a PNG.
- The CLI emits the **default chart set**:
  1. **Throughput → latency:** X = RPS, Y = p95 (and p50, p99 as series) — the classic capacity curve; the knee is where Y turns up.
  2. **Concurrent users → latency:** X = users, Y = p50/p95/p99 — answers "how many users until it hurts".
  3. **DB tx·s⁻¹ → latency:** X = DB-QPS, Y = p95 — shows whether latency tracks DB pressure (motivates S48.2 cache / S48.4 pgbouncer). *(skipped without `--pg-dsn`)*
  4. **Load → error%:** X = users, Y = error% — where it starts shedding/failing.
  Default scales: X linear, Y **log10** for latency charts (latency spans 9 ms → 19 000 ms); `--xscale`/`--yscale` (per-chart `--scale chart=throughput:x=log10,y=ln`) override.

### Dependencies
`matplotlib` only (Agg). Parse with the **stdlib `csv`** module — no pandas (NO OVERENGINEERING). Pin in `tests/load/requirements-chart.txt`; the tool is dev/CI-only, never shipped to the app image.

## TDD plan

- **`parse.py` (unit, fixtures):** committed sample `*_stats.csv` / `*_stats_history.csv` snippets (incl. the "Aggregated" row, a 0-request row, a malformed row) → correct `RunStats`/`Sample`; round-trip `sweep.csv` write→`load_sweep`.
- **`plot.py` (unit):** `apply_scale` for linear/log10/ln incl. the `≤0` guard; `render_chart` writes a non-empty PNG and the figure carries the expected axis labels, scale (`ax.get_xscale()`), and one line per series — all on the Agg backend, no live stack.
- **`sweep.py` (unit, mocked):** the argv builder produces the same flags as the CI command for a given level (shared-helper DRY check); the `pg_stat_database` delta math (`(after−before)/seconds`) with a fake sampler; missing `--pg-dsn` → DB chart skipped, not crashed.
- **No live-stack test in the gate** — the end-to-end sweep is validated by an actual heavy-load re-dispatch (it *is* the heavy-load deliverable), not by `--quick`.

## Acceptance

- `python -m tests.load.chart.sweep --users 10,50,100 …` against a local stack produces `load-charts/{sweep.csv, throughput-latency.png, users-latency.png, errors.png}` (+ `db-latency.png` when `--pg-dsn` set), reproducing the report-13 numbers as a curve.
- Re-running after **S48.1** visibly **moves the knee right** / flattens the 500-VU tail on the same axes — the before/after PNGs are the sub-sprint's proof artifact.
- Each axis switches linear↔log10↔ln from the CLI; `loadchart_unit` is green under `bin/pre-commit-check.sh --quick`.
- `tests/load/README.md` gains a "Charting a sweep" section (sweep command, the chart set, how to read the knee).

## Out of scope

- Changing `locustfile.py`, scenarios, or thresholds (that is [S48.0](s48-0-fair-load-harness.md)).
- Live dashboards / Grafana / time-series DB ingestion — this is a batch tool that emits static PNGs + a CSV.
- Statistical curve-fitting / automatic knee-detection (read it off the chart for now; auto-detect is a possible later add).
- Wiring the sweep into the CI workflow as a gate (it stays a manual capacity-run tool; CI keeps the single-level smoke from S48.4).