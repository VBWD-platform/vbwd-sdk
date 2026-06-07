# S48.0 — Fair load harness (seeded user pool + login-once + ramped spawn)

**Status:** PLANNED — 2026-06-03. Parent: [S48](s48-load-capacity-and-resilience.md).
**Area:** `vbwd-platform` (`tests/load/locustfile.py`) + `vbwd-backend` (`flask seed loadtest` — the deferred S30 follow-up).

## Engineering requirements (BINDING)

TDD-first · DevOps-first · DRY · clean code · NO OVERENGINEERING — [`_engineering_requirements.md`](_engineering_requirements.md). Backend gate: `bin/pre-commit-check.sh --quick`. Harness gate: the `loadtest_unit` CI job (S29) stays green; validated by a heavy-load re-dispatch.

## Problem

The load scenario registers a **fresh user in every VU's `on_start`** (`_register(...)`). At 500 VU that is 500 simultaneous **bcrypt** registrations — a thundering herd against the most CPU-expensive endpoint, which is *not* a realistic traffic shape (real traffic is mostly already-authenticated requests reusing a JWT). It dominates the 500-VU collapse (login/register p50 = 19 s) and **confounds** the measurement: we cannot tell how much of the meltdown is the app vs the test self-harming. The default `spawn_rate` also lets the user choose a 1-second herd.

## Goal

Make the harness exercise the **API hot paths**, not the auth herd, so heavy-load numbers reflect the application. Authentication becomes a small, amortized fraction (each VU authenticates once, then makes many requests) — matching production.

## Design

### Backend — `flask seed loadtest [--count N]` (S30 follow-up)
A new seed target (or a `loadtest` pseudo-plugin) that idempotently creates **N deterministic load users** through the user/auth **service layer** (never raw SQL — [[feedback_no_direct_db_for_test_data]]): `loadtest-0@example.com … loadtest-<N-1>@example.com`, password `LoadTest123@`. Idempotent (re-running creates 0). Wired so the heavy-load workflow runs it after `flask seed all`.

### Harness — pool + login-once
- A process-wide `LOADTEST_USERS` pool (size from env, default e.g. 50) of `(email, password)`.
- Authenticated `HttpUser` subclasses get an abstract base whose `on_start` **logs in once** from the pool (round-robin) and sets the bearer; **fail the VU loudly** if login fails (no more proceeding with an empty bearer → the 401 cascade disappears).
- Keep a *small* `register` scenario (low weight) so the register path is still measured — but it is no longer on every VU's critical path.
- Until the backend target ships, the pool can be inlined (50 entries) + a runner-side seed helper.

### Spawn shape
- Document/encourage a **ramped** spawn (e.g. spawn-rate ≤ users/10) for the steady-state capacity test; keep an explicit **spike** preset for thundering-herd testing as a *separate, labeled* scenario, not the default.

## TDD plan

- **Backend unit/integration:** `flask seed loadtest --count 3` creates 3 users via the service; re-run → 0 created (idempotent); users can authenticate.
- **Harness unit** (extend `tests/load/tests/`, requests-mock): the auth base `on_start` calls `POST /auth/login` (not `/register`), sets the bearer on 200, and a login failure marks the VU failed (does not silently continue with `Authorization: ""`). Pool round-robins without collisions.

## Acceptance

- Heavy-load re-dispatch at 100 + 500 VU shows auth latency dramatically reduced (login amortized; no 19 s register herd) and the **401-on-checkout cascade gone**.
- The remaining failures/latency now reflect the *app* (and S48.1's connection limits), giving a trustworthy knee.

## Out of scope

- Pre-minting JWTs to skip login entirely (possible later optimization; login-once is enough and more realistic).
- Multi-region / distributed load generation.
