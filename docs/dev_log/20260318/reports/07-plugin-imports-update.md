# Plugin Imports Update: src. → vbwd.

**Date:** 2026-03-18
**Status:** Done

---

## Summary

Updated all 10 backend plugin repositories to use `from vbwd.` imports instead of `from src.`. This aligns plugins with the core backend rename (`src/` → `vbwd/`) completed in Phase 1 of the metapackage sprint. Frontend plugins required no changes — they import from `vbwd-view-component` (TypeScript), not from the Python backend.

---

## Root Cause

The core backend directory was renamed from `src/` to `vbwd/` and all imports inside the core were updated. However, the 10 backend plugin repos on GitHub still had `from src.` imports. This caused CI failures:

```
WARNING  vbwd.plugins.manager:manager.py:245 Failed to import module 'plugins.analytics': No module named 'src'
WARNING  vbwd.plugins.manager:manager.py:245 Failed to import module 'plugins.chat': No module named 'src'
...
```

---

## Changes Per Plugin

| Plugin | Repo | Files Changed | Import Updates |
|--------|------|---------------|----------------|
| analytics | `vbwd-plugin-analytics` | 5 | 20 |
| chat | `vbwd-plugin-chat` | 5 | 7 |
| cms | `vbwd-plugin-cms` | 14 | 30 |
| email | `vbwd-plugin-email` | 9 | 22 (+new all-events Mailpit test) |
| ghrm | `vbwd-plugin-ghrm` | 14 | 35 |
| mailchimp | `vbwd-plugin-mailchimp` | 1 | 1 |
| paypal | `vbwd-plugin-paypal` | 9 | 35 |
| stripe | `vbwd-plugin-stripe` | 10 | 56 |
| taro | `vbwd-plugin-taro` | 16 | 41 |
| yookassa | `vbwd-plugin-yookassa` | 9 | 33 |
| **Total** | **10 repos** | **92 files** | **280 import references** |

## Frontend Plugins — No Changes

All 15 frontend plugins (10 fe-user, 5 fe-admin) are TypeScript/Vue and import from `vbwd-view-component`, not from the Python backend. No updates needed.

---

## What Was Updated

Three types of references in each plugin's `.py` files:

```python
# Import statements
from src.models import User        →  from vbwd.models import User
import src.config                  →  import vbwd.config

# mocker.patch strings in tests
mocker.patch("src.middleware.auth.AuthService", ...)
→ mocker.patch("vbwd.middleware.auth.AuthService", ...)
```

---

## CI Impact

The platform CI (`vbwd-platform/.github/workflows/ci.yml`) previously included a `sed` patch step to fix imports after cloning. This step is now redundant (the repos are already updated) but remains as a safety net.

---

## Commits

| Repo | Commit | Branch |
|------|--------|--------|
| `vbwd-plugin-analytics` | `2183aea` | main |
| `vbwd-plugin-chat` | `6323210` | main |
| `vbwd-plugin-cms` | `0eee96a` | main |
| `vbwd-plugin-email` | `1a3f6ef` | main |
| `vbwd-plugin-ghrm` | `d53f960` | main |
| `vbwd-plugin-mailchimp` | `5310805` | main |
| `vbwd-plugin-paypal` | `6d2264d` | main |
| `vbwd-plugin-stripe` | `13f8382` | main |
| `vbwd-plugin-taro` | `59bb02d` | main |
| `vbwd-plugin-yookassa` | `9cc5676` | main |
