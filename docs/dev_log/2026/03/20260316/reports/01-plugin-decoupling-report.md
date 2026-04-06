# Report 01 — Plugin Decoupling: Standalone Repos, Agnostic Core, CI/Dev-Install Automation

**Date:** 2026-03-16
**Scope:** Backend, fe-user, fe-admin — plugin git tracking removal, CI plugin install step, dev-install-ce.sh automation, backend core test suite made plugin-agnostic

---

## Summary

Completed full decoupling of all plugins from their host repos (`vbwd-backend`, `vbwd-fe-user`, `vbwd-fe-admin`). Each plugin now lives exclusively in its own standalone GitHub repo under the VBWD-platform org. Plugins are installed at CI time (git clone) and during local dev setup (dev-install-ce.sh). The backend core test suite was refactored to use only `DemoPlugin` — fully agnostic. Fixed all CI failures that caused this session (paypal flake8, stripe test field/mock errors, CMS/email files committed to wrong repo, analytics delegation stub breaking backend CI).

---

## 1. CI Failures Fixed (Pre-Decoupling)

### vbwd-plugin-paypal — flake8 violations

| File | Error | Fix |
|------|-------|-----|
| `__init__.py` | F401 unused `BasePlugin` import | Removed |
| `sdk_adapter.py` | E741 ambiguous variable name `l` (×2) | Renamed to `link` in both generator expressions |
| `tests/conftest.py` | F401 unused `MagicMock` | Removed |
| `tests/test_recurring.py` | F401 unused `Decimal`, `PropertyMock`, `PluginConfigEntry`, `InvoiceStatus` | Removed |
| `tests/test_routes.py` | F401 unused `patch`, `PluginConfigEntry` | Removed |
| `tests/test_sdk_adapter.py` | F401 unused `SDKResponse` | Removed |
| `tests/test_webhook.py` | F401 unused `PluginConfigEntry` | Removed |

### vbwd-plugin-stripe — test failures

Two test bugs in `tests/test_payment_e2e.py`:

1. **Wrong field name**: Handler sets `subscription.started_at` but test asserted `sub.starts_at`.
   - **Fix:** Added `sub.started_at = None` to `_make_subscription` helper; changed assertion to `assert sub.started_at`.

2. **Wrong mock method**: `test_previous_subscription_cancelled` mocked `find_active_by_user` but the handler calls `find_active_by_user_in_category` (only for `is_single` categories).
   - **Fix:** Added `is_single = True` on the mock category; switched mock to `find_active_by_user_in_category.return_value = [old_sub]`.

### vbwd-fe-user — TypeScript TS6133

- `plugins/ghrm/src/views/GhrmPackageDetail.vue`: Unused `import GhrmBreadcrumb` — removed.

### CMS + Email files committed to wrong repo

Two commits had been made to `vbwd-backend` with files belonging to `vbwd-plugin-cms` and `vbwd-plugin-email`. Reverted both commits from `vbwd-backend`; applied the fixes to the correct standalone repos cloned in `/tmp`.

- **vbwd-plugin-cms** (16 files): E501, E712 (`== True` → `is True`), E741 (`l` → `layout`/`item`), F401, F541, F811, F841
- **vbwd-plugin-email** (4 files): E402 (`# noqa` moved to `from` line), E501, F401

Local cms repo synced via `git stash → git pull --rebase → resolve blank-line conflict → git rebase --continue → git stash drop → git push`.

---

## 2. Plugin Decoupling — Backend

### Git tracking removed

All 10 plugin directories removed from `vbwd-backend` git tracking with `git rm -r --cached`:

```
plugins/analytics  plugins/chat  plugins/cms    plugins/email
plugins/ghrm       plugins/mailchimp  plugins/paypal  plugins/stripe
plugins/taro       plugins/yookassa
```

Added to `.gitignore`:
```
plugins/analytics/
plugins/chat/
...
```

`plugins/demoplugin/` remains tracked — it is the canonical example plugin used by agnostic core tests.

### CI — tests.yml

Added **Install plugins** step before unit tests:

```yaml
- name: Install plugins
  run: |
    for plugin in analytics chat cms email ghrm mailchimp paypal stripe taro yookassa; do
      git clone --depth=1 https://github.com/VBWD-platform/vbwd-plugin-${plugin}.git plugins/${plugin}
    done
```

---

## 3. Backend Core Tests — Made Plugin-Agnostic

### test_analytics_plugin.py — Deleted

This file was a delegation stub (`from plugins.analytics.tests.test_plugin import *`). Tests belong in `vbwd-plugin-analytics`, not the core backend. Deleted.

### test_plugin_blueprints.py — Refactored

Removed `TestAnalyticsPluginBlueprint` class entirely. Replaced all `AnalyticsPlugin` usage with `DemoPlugin`:

```python
from plugins.demoplugin import DemoPlugin

plugin = DemoPlugin()
plugin_manager.register_plugin(plugin)
plugin_manager.initialize_plugin("backend-demo-plugin")
plugin_manager.enable_plugin("backend-demo-plugin")

blueprints = plugin_manager.get_plugin_blueprints()
bp, prefix = blueprints[0]
assert bp.name == "demo_plugin"
assert prefix == "/api/v1/backend-demo-plugin"
```

### test_plugin_discovery.py — Refactored

- Removed `test_discovers_analytics_plugin` (plugin-gnostic)
- Changed `assert count >= 2` → `assert count >= 1` (only `demoplugin` guaranteed)
- Replaced `AnalyticsPlugin` with `DemoPlugin` in `test_skips_already_registered_plugins`

---

## 4. Plugin Decoupling — fe-user

### git tracking

Plugin dirs were already in `.gitignore` (from a prior sprint). No git-tracked plugin files existed; only `plugins/.gitkeep`, `plugins/config.json`, `plugins/plugins.json` are tracked.

### CI — plugin-tests.yml

Added **Install plugin** step to matrix job (clones only the specific plugin under test):

```yaml
- name: Install plugin
  run: |
    git clone --depth=1 https://github.com/VBWD-platform/vbwd-fe-user-plugin-${{ matrix.plugin }}.git plugins/${{ matrix.plugin }}
```

---

## 5. Plugin Decoupling — fe-admin

### CI — plugin-tests.yml

Same pattern as fe-user:

```yaml
- name: Install plugin
  run: |
    git clone --depth=1 https://github.com/VBWD-platform/vbwd-fe-admin-plugin-${{ matrix.plugin }}.git plugins/${{ matrix.plugin }}
```

---

## 6. dev-install-ce.sh — Plugin Clone Automation

Three new install blocks added:

| Step | What | Plugins |
|------|------|---------|
| Step 1.5 | Backend plugins | analytics, chat, cms, email, ghrm, mailchimp, paypal, stripe, taro, yookassa |
| After Step 2b | fe-user plugins | chat, checkout, cms, ghrm, landing1, paypal-payment, stripe-payment, taro, theme-switcher, yookassa-payment |
| After Step 2c | fe-admin plugins | analytics-widget, cms-admin, email-admin, ghrm-admin, taro-admin |

Each block: pulls if already installed, clones with `--depth=1` if not.

---

## 7. Commits

| Repo | Commit | Description |
|------|--------|-------------|
| `vbwd-backend` | `0642e2b` | chore: remove plugin dirs from git tracking; install via CI and dev-install |
| `vbwd-fe-user` | `8f7e829` | chore: clone plugin from standalone repo before running plugin tests in CI |
| `vbwd-fe-admin` | `4e609e4` | chore: clone plugin from standalone repo before running plugin tests in CI |
| `vbwd-sdk` | `a435988` | feat(dev-install): clone backend plugins in Step 1.5 |
| `vbwd-sdk` | `259d7da` | feat(dev-install): clone fe-user and fe-admin plugins during setup |

---

## Architecture Principle Enforced

> **vbwd core is agnostic — only plugins are gnostic.**

- Core repos (`vbwd-backend`, `vbwd-fe-user`, `vbwd-fe-admin`) contain zero plugin code in git.
- Plugin code lives exclusively in standalone repos (`vbwd-plugin-*`, `vbwd-fe-user-plugin-*`, `vbwd-fe-admin-plugin-*`).
- Core test suites test the plugin infrastructure only (manager, config store, discovery, blueprints) using the `demoplugin` fixture — never importing from specific plugins.
- Plugins are installed at runtime: via CI (git clone in workflow) or locally (dev-install-ce.sh).
