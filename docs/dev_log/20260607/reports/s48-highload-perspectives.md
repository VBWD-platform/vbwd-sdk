# Report — S48 High-Load Perspectives (capacity & cost planning)

**Date:** 2026-06-08
**Companion to:** [report 02 — S48 load capacity implemented](02-s48-load-capacity-implemented.md), [S48.4 — pgbouncer + prod-sized load env](../sprints/s48-4-pgbouncer-and-load-env.md).
**Purpose:** translate "N concurrent users" (esp. a mobile app) into real load, size the hardware, estimate hosting cost across load tiers, and mark where the architecture must evolve.

> **Health warning.** The per-instance capacity figures below are *planning estimates* anchored to the **measured ~250 rps on a contended 2-vCPU GitHub CI runner** (which ran the app **+** Postgres **+** Redis **+** the load generator co-located — so the app had well under 2 dedicated cores). Real per-instance numbers require the **S48.4** dedicated-box measurement. Treat costs as order-of-magnitude (self-managed on Hetzner; managed cloud is typically 3–5× more).

---

## 1. "Concurrent users" is not requests/sec

A mobile-app user does **not** hammer the API — they fire a request every N seconds (open app, scroll, check status, occasional action). Concurrent users → rps is bridged by **think-time**:

| think-time per user | rps from 10,000 users |
|---|---|
| 1 req / 60 s (light) | ~170 rps |
| 1 req / 30 s (typical) | ~330 rps |
| 1 req / 10 s (chatty) | ~1,000 rps |
| 1 req / 3 s (very active) | ~3,300 rps |

For comparison, the **load test's VUs fire every ~1.5 s** — 15–40× more aggressively than a real mobile user. So **one Locust VU ≈ 15–40 real mobile users** by request rate, and the measured ~350-VU comfortable zone on the tiny CI box already corresponds to **~5,000–14,000 real mobile users**.

**Two more factors decide everything:**
- **Read/write mix.** Mobile apps are read-heavy (browse, status). Catalog reads are **Redis-cached (S48.2) and edge/CDN-cacheable** → they barely touch the app/DB. The real ceiling is the **write/authed slice** (checkout, token spend, dashboard) — usually 10–20 % of mobile traffic. Sizing below is conservative: it sizes the app fleet against **total** rps, treating the cache offload as safety headroom.
- **Connection model.** If the app uses **SSE / push / long-lived connections** (e.g. meinchat notifications), 10k concurrent is a **connection-count** problem, and the sync `gthread` gunicorn model is poor at many idle connections — that needs a **dedicated async/realtime tier**, sized by connection count, not rps.

---

## 2. Capacity & cost by load tier

Planning assumptions: **typical think-time 1 req / 30 s** (the main `rps` column; the *chatty* 1 req/10 s case is ~3×). **~400 rps per dedicated 4-vCPU app instance** (conservative vs the 250 rps measured on 2 *shared* cores). DB separated from app at ≥1k users. Catalog behind Redis + Cloudflare. Costs ≈ EUR/month, **self-managed on Hetzner**.

| Concurrent users | rps (typical / chatty) | Topology | Hardware (Hetzner, approx) | ≈ €/mo | Notes / risk |
|---|---|---|---|---|---|
| **50** | ~2 / ~5 | single all-in-one box (app+DB+Redis via compose) | 1× CX32 (4 vCPU, 8 GB) | **€5–10** | This is essentially today's demo box. Trivial. |
| **100** | ~3 / ~10 | single all-in-one box | 1× CX32 (4 vCPU, 8 GB) | **€7–12** | + Cloudflare free CDN on catalog. |
| **500** | ~17 / ~50 | single modest box; app+DB co-located | 1× CPX31 (4 vCPU, 8 GB) | **€15–25** | Comfortable. Cache catalog. |
| **1,000** | ~33 / ~100 | start splitting DB out | app 1× CX42 + DB 1× CCX23 (4 ded. vCPU, 16 GB) + Redis on app box | **€35–55** | + pgbouncer. Single instance still fine on real HW. |
| **10,000** | ~330 / ~1,000 | **horizontal app + dedicated DB + replica** (the S48.4 target, §3) | nginx LB (CX22) · 2–3× app (CPX31, 4 vCPU) · DB primary CCX33 (8 vCPU, 32 GB) + 1 read replica · Redis (CX22) · pgbouncer · Cloudflare | **€120–220** | Write path + DB connections are the constraint; pgbouncer essential. SSE → add a small async tier. |
| **100,000** | ~3,300 / ~10,000 | **app fleet + DB primary + multiple replicas + Redis cluster + heavy CDN** | LB(s) · 8–14× app (CPX41/CCX23) · DB primary CCX53 (32 vCPU, 128 GB) + 2–3 read replicas · pgbouncer · Redis cluster · aggressive edge cache | **€800–2,000** | Single write-primary becomes the ceiling; offload reads to replicas, writes need batching/queues. Hyperscaler managed ≈ 3–5×. |
| **1,000,000** | ~33,000 / ~100,000 | **distributed**: autoscaling fleet, partitioned/sharded or distributed DB, queue-based writes, multi-region CDN, dedicated realtime tier | dozens–hundreds of app nodes · Postgres + Citus/partitioning (or Vitess/Cockroach) · Redis cluster · Kafka/queue · multi-CDN · observability/SRE | **€5,000–25,000+** (self-managed) / **€30k–100k+** (managed) | A different architecture *and* an SRE team. The sync-Python + single-primary design must evolve (see §4). Cost is workload-dominated, not a single number. |

**Reading the table:** up to ~1,000 concurrent users this is a **one- or two-box** problem (€10–55/mo). **10,000 concurrent ≈ €120–220/mo** of small Hetzner boxes — very affordable, and the topology in §3 is the S48.4 deliverable. The cost curve stays gentle until ~100k, where the **single write-primary** and the **runtime model** start to bind; ≥1M is a distributed-systems + team problem, not a hosting-plan choice.

---

## 3. Target topology (the S48.4 deliverable — sizes the 10k tier)

```
                         Cloudflare / CDN  (caches public catalog, static)
                                 │
                          ┌──────▼──────┐
                          │   nginx LB  │   (TLS, routing, rate-limit at edge)
                          └──────┬──────┘
              ┌──────────────────┼──────────────────┐
        ┌─────▼─────┐      ┌─────▼─────┐      ┌─────▼─────┐
        │  app #1   │      │  app #2   │ ...  │  app #N   │   stateless (JWT auth,
        │ gunicorn  │      │ gunicorn  │      │ gunicorn  │   no server session)
        └─────┬─────┘      └─────┬─────┘      └─────┬─────┘
              └──────────────────┼──────────────────┘
                          ┌──────▼──────┐
                          │  pgbouncer  │   (transaction-mode conn multiplexing)
                          └──────┬──────┘
                 writes ┌────────┴────────┐ reads
                 ┌──────▼──────┐   ┌───────▼───────┐
                 │  Postgres   │──▶│ read replica(s)│   (catalog/dashboard reads)
                 │  PRIMARY    │   └────────────────┘
                 └─────────────┘
                          ▲
                   ┌──────┴──────┐
                   │    Redis    │   (catalog cache S48.2, sessions/limits)
                   └─────────────┘

  (optional) ┌───────────────────────┐
             │ realtime/SSE tier (async)│  ← only if the mobile app uses push/SSE;
             └───────────────────────┘     sized by connection count, NOT rps
```

Why it scales: the **app is stateless** (JWT, no server session) → add instances linearly behind the LB. **pgbouncer** lets the whole fleet share one Postgres without the `too many clients` wall (S48.1). **read replicas** absorb the read-heavy mobile traffic; **Redis + CDN** keep catalog off the DB entirely. The only inherently-serial resource is the **write primary**.

---

## 4. Where the architecture must evolve (the inflection points)

1. **~1k–10k users — horizontal app + pgbouncer + 1 replica.** Pure ops; no code change. (S48.4.)
2. **~10k–100k — replicas for all reads, Redis cluster, edge cache, write-path tuning.** The app barely changes; the DB topology does. Watch the **write primary** (checkout, token spend) and **connection count** if SSE.
3. **~100k–1M — the single write-primary binds.** You need **write sharding / table partitioning** (Citus, or app-level partitioning by tenant/user), **queue-based write absorption** (accept → enqueue → async apply for non-critical writes), and possibly a **distributed DB**. This is where the **sync-Python + GIL + single-DB** design genuinely starts to cost you, and where moving hot write paths to async services (or another runtime) becomes a real, *measured* decision — not the premature "rewrite to Laravel" of earlier discussions, but a targeted hot-path call backed by load data.
4. **Realtime (any scale).** SSE/push for many concurrent users is a **separate async tier** from day one — never run 10k+ idle long-lived connections through `gthread`.

---

## 5. Practical takeaways

- **10,000 concurrent mobile users is affordable and not exotic** — at typical think-time it's ~330 rps, mostly cacheable reads, served by **~€150/mo** of small Hetzner boxes in the §3 topology. It is *not* a one-2-core-box job and *not* a tuning problem; it's the **stateless-app × horizontal-instances + pgbouncer + read replica + CDN** architecture.
- **S48 was the prerequisite, not the scale story.** It made a *single instance* honest and efficient (no self-inflicted 500s, ~2× throughput, graceful shed). Horizontal scale is what turns one good instance into 10k-user capacity.
- **Get real numbers before sizing money.** The figures here are anchored to a 2-core CI runner. **S48.4** (a dedicated, horizontally-scaled load env) is the next step: measure **per-instance rps on real hardware**, then size the fleet — and report capacity in **real-mobile-user terms** (rps ÷ think-time), not VUs.
- **Re-confirm the read/write mix and whether the mobile app uses SSE** — those two facts move every number in §2 more than any tuning will.

> Cost figures are approximate (Hetzner self-managed, 2025-era pricing) and order-of-magnitude; validate against current Hetzner Cloud/dedicated pricing and your actual read/write mix before committing budget.
