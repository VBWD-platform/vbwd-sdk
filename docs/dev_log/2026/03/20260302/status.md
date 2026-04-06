# Sprint 02 — GHRM Plugin Implementation Status

**Sprint doc:** `sprints/02-github-repo-manager.md`
**Started:** 2026-03-11

---

## Backend

| Step | Task | Status |
|---|---|---|
| 1 | Failing tests — GithubAccessService | ✅ done (12 tests) |
| 2 | Failing tests — SoftwarePackageService | ✅ done (12 tests) |
| 3 | Models — 4 tables (ghrm_software_package, ghrm_software_sync, ghrm_user_github_access, ghrm_access_log) | ✅ done |
| 4 | MockGithubAppClient | ✅ done |
| 5 | GithubAppClient (real — httpx) | ✅ done |
| 6 | Repositories (4) | ✅ done |
| 7 | GithubAccessService | ✅ done (all tests green) |
| 8 | SoftwarePackageService | ✅ done (all tests green) |
| 9 | Subscription event wiring (on_enable) | ✅ done |
| 10 | Grace period scheduler | ✅ done |
| 11 | Sync endpoint | ✅ done |
| 12 | OAuth endpoints | ✅ done |
| 13 | Public catalogue endpoints | ✅ done |
| 14 | Admin endpoints | ✅ done |
| 15 | bin/populate_ghrm.py + Alembic migration | ✅ done |

## fe-admin

| Step | Task | Status |
|---|---|---|
| 16 | GhrmSoftwareTab.vue (conditional tab on tariff plan edit) | ✅ done |

## fe-user

| Step | Task | Status |
|---|---|---|
| 17 | useGhrmStore + API client | ✅ done |
| 18 | GhrmCategoryIndex + GhrmPackageList | ✅ done |
| 19 | GhrmPackageDetail (6 tabs + related + CTA) | ✅ done |
| 20 | GhrmSearch | ✅ done |
| 21 | GhrmGithubConnectButton + GhrmOAuthCallback | ✅ done |

## E2E

| Step | Task | Status |
|---|---|---|
| 22 | subscribe → OAuth → install token → cancel → grace → revoke | ✅ done |
| 23 | public browse → Get Package → checkout redirect | ✅ done |

---

## Log

- **2026-03-11** — Sprint doc finalised. Status file created. Implementation started.
- **2026-03-11** — Steps 1-4, 6-8 complete. 24/24 unit tests passing in container.
- **2026-03-11** — Steps 5, 9-15 complete. All 17 API routes, Alembic migration, scheduler, real GitHub client, populate script. 24/24 unit tests still green.
- **2026-03-11** — Steps 22-23 complete. E2E: ghrm-lifecycle.spec.ts (6 tests, lifecycle with mocked OAuth/API) + ghrm-catalogue.spec.ts (13 tests, public browse + detail tabs + checkout redirect). All 23 steps done.
- **2026-03-11** — Steps 16-21 complete. fe-admin: extensionRegistry PlanTabSection, PlanForm.vue conditional tabs, ghrm-admin plugin with GhrmSoftwareTab.vue. fe-user: ghrmPlugin, useGhrmStore, ghrmApi, GhrmCategoryIndex, GhrmPackageList, GhrmPackageDetail (6 tabs), GhrmSearch, GhrmGithubConnectButton, GhrmOAuthCallback, GhrmMarkdownRenderer. config.json + admin-config.json added to both plugin roots.
