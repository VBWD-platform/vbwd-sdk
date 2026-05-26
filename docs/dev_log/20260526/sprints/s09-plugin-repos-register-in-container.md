# S09 — Plugins register their repositories with the DI container on `on_enable`

**Source:** review §3.2 → `plugins/shop`, `plugins/booking`, `plugins/meinchat` (subscription is the reference; other plugins need spot-checks).
**Risk:** HIGH. Memory [[project_plugin_di_provider_registration]] records the 2026-03-27 checkout outage caused by exactly this bug class.
**Outcome:** Every plugin that owns repositories registers them on `container` in `on_enable` and removes them in `on_disable`. A static test enforces the contract per plugin.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/unit/test_plugin_di_registration.py::test_plugin_repos_registered_in_container`
   — for each plugin, parse `plugins/<name>/<name>/repositories/`,
   compute the expected provider name (`<plugin>_<repo_snake>`),
   enable the plugin in a test app, assert `container.<provider>()`
   resolves and returns the expected type. **Today: fails on shop,
   booking, meinchat (+ likely others).**
2. `tests/unit/test_plugin_di_registration.py::test_plugin_repos_unregistered_on_disable`
   — disable a plugin, assert the provider attribute is gone.

## Touch-points

- `plugins/shop/__init__.py` (`on_enable` / `on_disable`)
- `plugins/booking/__init__.py` (same)
- `plugins/meinchat/__init__.py` (same)
- Audit: `chat`, `ghrm`, `taro`, `cms`, `discount`, `c2p2`, every
  payment plugin
- Reference impl: `plugins/subscription/__init__.py::on_enable`

## Steps (each validated)

1. **Write the contract tests** with one plugin (shop) parameterised
   in. They fail.
2. **Extract the registration helper** to `vbwd/plugins/di_helpers.py`:
   ```python
   def register_repositories(container, repos: dict[str, type]):
       for name, repo_cls in repos.items():
           setattr(container, name, providers.Factory(repo_cls, session=container.db_session))

   def unregister_repositories(container, names: list[str]):
       for name in names:
           if hasattr(container, name):
               delattr(container, name)
   ```
   §5 DRY — one home for the wiring boilerplate.
3. **Implement in shop:**
   ```python
   def on_enable(self):
       super().on_enable()
       container = getattr(current_app, "container", None)
       if container is None:
           return
       register_repositories(container, {
           "shop_product_repository": ProductRepository,
           "shop_order_repository": OrderRepository,
           "shop_warehouse_repository": WarehouseRepository,
       })

   def on_disable(self):
       container = getattr(current_app, "container", None)
       if container is not None:
           unregister_repositories(container, [
               "shop_product_repository",
               "shop_order_repository",
               "shop_warehouse_repository",
           ])
       super().on_disable()
   ```
4. **Implement in booking, meinchat** — same shape.
5. **Audit the other plugins.** For each, check whether its routes
   construct repos inline (the smell from §3.4). If yes, register +
   refactor route to resolve from container.
6. **Re-run the parametrised test across every plugin** — green.

## Acceptance (oracle)

- Both unit tests green for every plugin in the suite.
- `grep -rn "Repository(db\.session)" plugins/` → empty in plugin route
  files (instances remaining ONLY in service-factory bodies inside
  service files where db.session was explicitly passed for testability
  — those are fine; routes are the target).
- Re-enable a plugin in a running app: the registered providers reappear.

## Notes

- This unblocks [[s08]] for plugin routes (they couldn't resolve from
  the container before because providers weren't registered).
- §8 no overengineering: don't introduce auto-discovery via decorators
  / metaclasses — explicit dict is fine and greppable.
- Subscription plugin already does it correctly — use as the reference
  for code review.
