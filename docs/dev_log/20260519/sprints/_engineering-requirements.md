# Shared Engineering Requirements — Subscription Extraction (Direction A)

Every sprint in `20260519/sprints/` **inherits, in full**,
[`../../20260422/sprints/_engineering-requirements.md`](../../20260422/sprints/_engineering-requirements.md)
(TDD-first · DevOps-first · SOLID · DRY · DI · Clean code). That block is
non-negotiable per `CLAUDE.md` and `MEMORY.md`. Read it first; it is not
repeated here.

This file adds the **extraction-specific checkpoints** that extend §1 (TDD)
and §3 (SOLID) for the specific hazard of moving a live feature out of core.

---

## E1 — Characterisation tests before any move (extends §1)

Moving code that already runs in production is **refactoring, not greenfield**.
Therefore, for every unit of code a sprint relocates:

1. If a test already exists, run it green **on core** first and record the
   command + result in the sprint's "Baseline" section.
2. If no test exists, the sprint's **first commit** is a *characterisation
   test* pinning current observable behaviour (HTTP status + body, emitted
   event name + payload, DB rows written, rendered template bytes). It must
   pass against the *unmoved* code.
3. The same test, unchanged, must pass after the move. A test that needed
   editing to pass post-move is a behaviour change — stop, get sign-off.

"Watched it fail" for extraction means: temporarily break the moved wiring,
see the characterisation test go red, restore, see it green.

## E2 — No behaviour change in a move sprint (extends §3-L / Liskov)

A relocation sprint changes **where** code lives, never **what** it does.
The Liskov contract here is between *old call site* and *new call site*:
same inputs ⇒ same outputs, same side-effects, same exceptions. Any
intended behaviour change is a **separate** follow-up sprint with its own
RED test. Mixed "move + improve" commits are rejected in review.

## E3 — Agnosticism is the acceptance oracle (extends §3-O/D)

The definition of done for the programme is **falsifiable**: a backend +
fe-user + fe-admin install with the subscription plugins **disabled** must
have, provably:

- zero `vbwd_subscription*` / `vbwd_tarif_plan*` / `vbwd_addon*` tables
  created by core migrations;
- zero subscription routes registered, zero subscription nav items,
  zero `subscription.*` permission strings evaluated by core;
- zero subscription identifiers resolvable from core packages
  (`import vbwd.models.subscription` ⇒ `ModuleNotFoundError` after Phase 1);
- no `subscription`/`tarif`/`plan` strings in the rendered core i18n bundles.

Each sprint states which slice of this oracle it makes pass. Sprint 09
automates the whole oracle in CI as the programme's exit gate.

## E4 — Migration discipline (extends §2)

- Subscription schema changes ship as **plugin** Alembic migrations under
  `vbwd-backend/plugins/subscription/migrations/versions/`, registered in
  `alembic.ini` `version_locations` — never in core
  (`feedback_plugin_migrations_in_plugin.md`).
- The detach from the monolithic `20260403_1612_vbwd_all_tables.py` is a
  **data-preserving** migration: tables are *adopted* by the plugin's
  Alembic branch (stamp/branch), not dropped-and-recreated. A
  drop+recreate that loses prod rows is a failed sprint.
- Demo/test data flows through the plugin's service/repository layer, never
  raw SQL (`feedback_no_direct_db_for_test_data.md`).

## E5 — Plugins live in their own repos (extends §2)

Subscription plugin code is moved **into the standalone plugin repos**
(`vbwd-backend/plugins/subscription`, `vbwd-fe-user/plugins/subscription`,
`vbwd-fe-admin/plugins/subscription-admin`), never left in core
(`feedback_plugins_always_in_own_repos.md`). Commits go directly to the
plugin repo's `main` (`feedback_no_temp_branches.md`); work happens in the
SDK plugin dirs, never `/tmp` (`feedback_work_in_sdk_dirs.md`).

## E6 — Extension points over hardcoding (extends §3-O)

Where core currently hardcodes subscription (nav groups, user-edit tabs,
access-level columns, line-item resolution), the fix is a **generic
extension point** the plugin registers into — mirroring the patterns
already in the codebase: `userNavRegistry`, `accessLevelFormFields`,
`extensionRegistry`, the line-item handler registry, `planDetailTabRegistry`.
Adding a second hardcoded branch instead of an extension point fails review.
