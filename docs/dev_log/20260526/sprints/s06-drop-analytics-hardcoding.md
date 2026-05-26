# S06 — Drop the `"analytics"` hardcoding in `app.py`; iterate-all admin BPs

**Source:** review §1.3 → `vbwd/app.py:206-231`.
**Risk:** MEDIUM. Boot-time code; bad change → app boot regression.
**Outcome:** Core does not name `"analytics"` (or any plugin) in source. Default-enabling a plugin is expressed by `PluginMetadata.auto_enable: bool = False` (or `plugins.json.dist`). Admin blueprint registration iterates every enabled plugin and calls `get_admin_blueprint()`.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/unit/test_core_agnosticism.py::test_app_py_names_no_plugin`
   — greps `vbwd/app.py` for plugin names from the canonical list,
   asserts empty. **Today: fails on `"analytics"`, `"booking"` (booking
   lives in [[s01]]).**
2. `tests/integration/test_admin_blueprint_registration.py::test_every_plugin_with_admin_bp_is_registered`
   — enables 2 fake plugins each exposing an admin blueprint, asserts
   both routes resolve.
3. `tests/integration/test_auto_enable.py::test_plugin_with_auto_enable_metadata_is_enabled_on_first_boot`
   — wipes `plugins.json`, boots, asserts plugins with
   `metadata.auto_enable=True` are present.

## Touch-points

- `vbwd/app.py:206-231` (the `"analytics"` block)
- `vbwd/plugins/base.py` (PluginMetadata — add `auto_enable: bool = False`)
- `vbwd/plugins/manager.py` (apply auto-enable on first boot)
- `plugins/analytics/__init__.py` (set `auto_enable=True` so behaviour
  is preserved)
- `plugins.json.dist` (alternative if we prefer config over metadata —
  decide in step 1)

## Steps (each validated)

1. **Decide the default-enable mechanism.** Option A: metadata flag.
   Option B: `plugins.json.dist` ships with `{"analytics": {"enabled":
   true}}` and `app.py` just copies dist if no file exists. Option B
   is simpler and already partly in place (the Dockerfile does the
   copy). **Pick B — §8 no overengineering.** Skip the metadata flag.
2. **Write the tests** matching the chosen option.
3. **Edit `plugins.json.dist`** so analytics is enabled by default.
4. **Replace `app.py:206-231`** with:
   ```python
   # Persisted plugin state is loaded by plugin_manager; first-boot
   # defaults come from plugins.json.dist (see Dockerfile CMD).
   for plugin in plugin_manager.get_enabled_plugins():
       admin_bp = plugin.get_admin_blueprint()
       if admin_bp is not None:
           csrf.exempt(admin_bp)
           app.register_blueprint(admin_bp)
   ```
   Delete the analytics-specific branch entirely.
5. **Verify `BasePlugin.get_admin_blueprint`** has a `None` default so
   plugins without an admin BP just return None.
6. **Smoke:** boot with fresh `plugins.json` → analytics enabled →
   `/admin/analytics/*` routes resolve. Boot with analytics disabled
   in `plugins.json` → routes 404. Both pre-commit-check `--full` green.

## Acceptance (oracle)

- `grep -n '"analytics"\|"booking"\|"cms"\|"stripe"\|"taro"' vbwd/app.py` → empty.
- All three Baseline tests green.
- Existing `/admin/analytics/*` integration tests still pass.

## Notes

- Pair this with [[s01]] (booking removed) and you've cleared every
  hardcoded plugin name from `app.py`.
- §3 OCP: this IS the OCP fix — the registration loop is now closed
  to modification, open to extension (any new plugin gets its admin
  BP registered for free).
- §8: don't add per-plugin priority ordering for blueprint registration
  unless a real conflict arises.
