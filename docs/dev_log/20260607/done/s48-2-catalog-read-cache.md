# S48.2 — Catalog read cache (Redis) for the read-mostly hot paths

**Status:** PLANNED — 2026-06-03. Parent: [S48](s48-load-capacity-and-resilience.md).
**Area:** `vbwd-backend` `plugins/subscription` (tarif-plans / addons) + core token-bundles routes; uses **Redis (already in the stack)**.

## Engineering requirements (BINDING)

TDD-first · SOLID (cache behind an interface) · DI · DRY · clean code · NO OVERENGINEERING — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: `bin/pre-commit-check.sh --plugin subscription --full` + core `--quick` green; validated by a heavy-load re-dispatch. **Core stays agnostic** — caching helper is generic; the subscription plugin wires its own keys.

## Problem (from the load profile)

The heaviest traffic is read-mostly catalogue data that changes rarely:

| endpoint | reqs @ 100 VU | nature |
|---|---:|---|
| `GET /tarif-plans` | 2138 (most traffic) | plan list + pricing |
| `GET /addons` | 1336 | addon list |
| `GET /token-bundles` | 710 | bundle list |

Every one of these hits Postgres on every request. Postgres is the resource that **saturates first** under load (S48.1). Caching read-mostly catalogue data offloads the bulk of traffic from the DB, raising the throughput ceiling and flattening the tail — for data that an admin edits maybe a few times a day.

## Goal

Serve catalogue reads from Redis with correct, simple invalidation, so the dominant traffic no longer touches Postgres on the hot path — without serving stale data after an admin edit.

## Design (SOLID, narrow)

- **Generic cache port** (core): a small `ICacheStore` (`get/set/delete(prefix)`) with a `RedisCacheStore` impl using the existing Redis connection, and an `InMemoryCacheStore` for unit tests. DI-provided; no business code talks to Redis directly.
- **Cache the resolved responses** for `tarif-plans` (list), `addons` (list), `token-bundles` (list), keyed by the inputs that vary the output (`currency`, `country`, `category` query params) — so per-currency results are cached independently. Short TTL (e.g. 60–300 s) as a safety net.
- **Event-based invalidation (preferred over TTL-only):** on any admin write to a plan/addon/bundle (create/update/delete/activate), publish an invalidation that clears the relevant cache prefix. The subscription plugin already emits/handles domain events — hook invalidation there so an edit is reflected immediately, with TTL as backstop.
- **Detail route** (`/tarif-plans/<slug>`): cache only **after** S48.5 makes it return 200 (don't cache a 400); cache per `(slug, currency, country)`.
- Cache **only successful 2xx**; never cache auth-dependent or per-user data (this sprint is public catalogue only).

## TDD plan

- **Unit (InMemoryCacheStore):** second identical catalogue request is served from cache (repo/DB not hit twice); different `currency` → distinct cache entry; an admin write event clears the prefix → next read repopulates; TTL expiry repopulates.
- **Unit:** non-2xx responses are not cached.
- **Integration:** end-to-end list → edit (admin) → list reflects the edit immediately (invalidation), and an unrelated edit doesn't clear the wrong key.

## Acceptance

- `--plugin subscription --full` + core `--quick` green; agnosticism oracles green (cache port is generic).
- Heavy-load re-dispatch: catalogue endpoints show markedly lower DB load / tighter tail; aggregate throughput ceiling rises vs the S48.1 baseline.
- Manual: admin edits a plan → public list shows it without waiting for TTL.

## Out of scope

- Caching authed/per-user responses (dashboard, invoices) — different correctness profile; revisit only if proven hot after S48.1/S48.3.
- A full HTTP/CDN edge-cache layer (deployment concern).
