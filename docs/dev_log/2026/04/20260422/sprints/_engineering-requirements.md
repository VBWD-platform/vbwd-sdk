# Shared Core Engineering Requirements

Every sprint in `20260422/sprints/` inherits this block. It is
**non-negotiable** per the rules in `CLAUDE.md` and the learned lessons
captured in `MEMORY.md`. A deliverable is not "done" until every item
here is satisfied for the code it touches.

Each individual sprint inlines a short list of *method-specific TDD
checkpoints* that extend §1 below.

---

## 1. TDD-first
- Every new adapter method, service, repository, route handler,
  webhook handler, and Pinia action has its **spec written first**,
  run, watched fail, then implementation follows.
- Backend spec lives next to the implementation:
  - `vbwd-plugin-<name>/tests/unit/` — pytest with `MagicMock()`
    collaborators (no DB).
  - `vbwd-plugin-<name>/tests/integration/` — pytest with the `db`
    fixture (creates + drops test DB per `MEMORY.md` Test Pattern).
- Frontend spec: Vitest `*.spec.ts` co-located with the
  store/component/composable. Playwright E2E in
  `vue/tests/e2e/` for full checkout flow.
- **No "refactor now, test later"**. If a test is hard to write,
  redesign — don't skip.

## 2. DevOps-first
- `bin/pre-commit-check.sh --full` green on the full touched repo set
  before merge. Per `feedback_ci_precommit_lessons.md`:
  - Always `bash -n <script>` after editing any shell script —
    a stray `fi` breaks **all** CI jobs.
  - Vitest filter: `plugins/<name>/` (the plugin ID path), **never**
    a deep `tests/unit/` path. Include-pattern needs `**`.
  - ESLint is always project-wide (`npm run lint`), never scoped
    with `npx eslint plugins/<name>/`.
  - Mypy excludes `tests/`, disables `import-untyped`, and runs
    non-blocking for `--plugin` mode.
  - Skip tests gracefully when a plugin has no test files — check
    dir existence + `find .py` count before invoking pytest.
  - Plugin CI installs **all** plugins (vue-tsc needs full project).
  - Never delete `package-lock.json` on CI — it causes type
    mismatches.
  - New plugin repos cloned by other CI workflows must be public.
- **Alembic migrations only** for any schema change — never raw SQL
  (`feedback_migrations_only.md`).
- **No `# noqa`, `# type: ignore`, or any suppression** without
  explicit user approval (`feedback_no_noqa_without_permission.md`).
  Fix the root cause.
- **No `npm install` on the host** in bind-mounted `vbwd-fe-core`
  (`feedback_no_host_npm_install_in_bindmounts.md`). Native binaries
  (esbuild) get polluted and containers crash on restart.
- **Local vs prod compose never mixed**: demo instances live in
  `vbwd-demo-instances/instances/local/<name>/` for dev and
  `instances/<name>/` for prod (scp'd to VPS by CI) — never edit the
  prod files for local use
  (`feedback_never_mix_local_and_prod_compose.md`).
- Dockerfile changes (e.g., system libs for PDF rendering) ship in
  the same PR with a `docker-compose up --build` verification.

## 3. SOLID

### S — Single responsibility
- Adapter classes speak the gateway API **only**. They know nothing
  about VBWD's `Invoice`, `Order`, `User`, or event dispatcher.
- Service classes map VBWD domain ↔ gateway DTOs.
- Route handlers are thin — input validation + service call + DTO
  serialisation. No business logic.

### O — Open / closed
- New payment methods, currencies, and regions added via config or
  enum extension, not by editing the adapter.
- Webhook event types added by registering a handler, not by
  switching inside one function.

### L — Liskov substitution
- Every `IPaymentAdapter` implementation must honour every
  postcondition of the base interface. A successful `capture()`
  return ⇒ payment record persisted + invoice state transitioned +
  event emitted. A subclass must never weaken this contract.
- Per `MEMORY.md` Plugin Class Template: `initialize(config)` must
  call `super().initialize(merged_config)`; overriding without the
  `super()` call breaks the Liskov contract of `BasePlugin`.
- Mocks in tests must also satisfy the LSP — a `MagicMock()`
  standing in for a repository must behave like the real interface,
  including raising the expected exceptions.

### I — Interface segregation
- Public VBWD `PaymentResult` / `PaymentIntent` DTOs stay narrow —
  only the 4-6 fields the client uses. Method-specific metadata
  (e.g., Klarna `authorization_token`, Mercado Pago `preference_id`)
  stays internal.
- Admin config DTOs and user-facing config DTOs are separate — don't
  fatten one response with admin-only values.

### D — Dependency inversion
- See §5.

## 4. DRY
- One HTTP client factory per plugin. When a third plugin needs the
  exact same pattern, promote — not before.
- IBAN / CLABE / tax-id validation is written once per concern and
  exposed as a callable; frontends call backend validation endpoints
  rather than duplicating logic.
- Shared helpers (blob download, currency format, date format)
  stay in `vbwd-fe-core` **only** once a third consumer appears.
  Two copies is fine; three is the promotion trigger.
- Zero copy-paste between plugins. The plugin template lives in
  `MEMORY.md` — extend it, don't clone.

## 5. Dependency injection
- Backend services receive collaborators through constructor DI —
  never via module-level singletons.
  Example: `KlarnaService(klarna_adapter, order_repo, invoice_repo,
  event_dispatcher)`.
- Webhook handlers receive their adapter + dispatcher via DI.
- `PdfService(template_env)` from Sprint 28 — the Jinja env is
  injected so tests can pass a `DictLoader`.
- Frontend: Pinia stores stay singleton, but any composable that
  calls an API takes the `sdk` / `api` client as an argument (for
  testability).

## 6. Clean code
- Full, pronounceable names per `feedback_variable_naming.md`:
  - `createKlarnaSession`, not `createKS`.
  - `sepaDirectDebitMandate`, not `sddm`.
  - `cancellationGracePeriodHours`, not `cgph`.
  - No single-letter variables, no cryptic abbreviations.
- Functions < 30 lines where possible. One level of abstraction per
  function. No flag arguments (`reschedule(booking, notify=True)` ✗,
  two methods ✓).
- **Zero "what" comments** — identifiers already say what. Only
  write a comment when the **why** is non-obvious: a regulatory rule,
  a subtle invariant, a vendor-API quirk.
- No references to tickets or current callers in comments ("used by
  the Klarna flow", "added for issue #123") — those belong in the
  PR description.
- `black` / `isort` / `flake8` / `mypy` on backend;
  `eslint` / `prettier` on frontend; all gated in pre-commit.

## 7. No over-engineering
- No generic "BNPL adapter framework" — Klarna only; Afterpay /
  Affirm become separate plugins if/when needed.
- No "multi-PSP routing layer" — VBWD core already picks the adapter
  per order based on configured methods.
- No retries, backoff, or circuit-breakers beyond what the vendor
  SDK already provides. A single retry on 5xx with 3 s wait is
  enough for v1.
- No admin analytics dashboards unless a real merchant asked for
  them. Ship the basic transaction list first.
- No feature flags for half-done features. If it isn't ready, it
  isn't in the diff.
- Don't design for hypothetical future requirements. Three similar
  lines is better than a premature abstraction.

## 8. Drop deprecated
- **Delete, don't comment out.** Any code this sprint replaces is
  removed in the same commit. No `// @deprecated`, no
  `# removed` headstones. Git history is the audit log.
- Per `feedback_no_temp_branches.md`: commit + push to `main` in the
  standalone plugin repo; never leave work on a temp branch.
- Per `feedback_work_in_sdk_dirs.md`: work in SDK plugin directories
  (the path PyCharm / the submodule is synced to), never in `/tmp`.
- Unused i18n keys, unused CSS classes, dead routes — **deleted**,
  not flagged deprecated.

## Gate

A deliverable is accepted when:
1. Specs were authored first and are now green
   (see each sprint's *method-specific TDD checkpoints*).
2. `bin/pre-commit-check.sh --full` passes on every touched repo.
3. No rule in this document is violated in the diff.
4. No deprecated code left behind.
5. The demo instance boots cleanly with the new plugin enabled and
   the advertised happy path works end-to-end.

---

## Plugin structure contract (reminder)

Every new plugin in these sprints follows the convention from
`MEMORY.md`:

```
vbwd-plugin-<name>/
├── <name>/__init__.py           # Plugin class (MUST be defined here,
│                                # not re-exported)
├── <name>/<name>/                # plugin-id source dir
│   ├── adapters/                 # gateway-API client
│   ├── services/                 # VBWD ↔ gateway mapping
│   ├── repositories/             # data access
│   ├── models/                   # SQLAlchemy models
│   ├── routes.py                 # Flask Blueprint
│   └── utils/                    # helpers
├── tests/unit/, tests/integration/
├── alembic/versions/<ts>_<desc>.py
├── populate_db.py                # idempotent demo data
├── plugins.json patch            # enabled: true
└── config.json patch             # default config
```

fe-user + fe-admin plugins use **named exports** per the
`fe-user Plugin Export Convention` in `MEMORY.md`:

```ts
export const xPlugin: IPlugin = {
  name: 'x',
  version: '1.0.0',
  install(sdk) { /* routes, stores, i18n */ },
  activate() {},
  deactivate() {},
};
```

---

## Lessons carried forward

See also:
- `MEMORY.md` — single-source index of all learned-lesson feedback
  files.
- `feedback_plugins_always_in_own_repos.md` — never commit plugin
  code into core repos.
- `feedback_entity_navigation.md` — detail views for entities
  (transactions, mandates) use canonical routes, never inline
  modals.
- `feedback_plugin_source_dir.md` — new plugins use the plugin-id
  source dir (`<name>/<name>/`), not `src/`.
