# Sprint 10 Report — VBWD GitHub Organization, Plugin Repos & Developer Docs

**Date:** 2026-03-15 / 2026-03-16
**Sprint:** 10

---

## Summary

Sprint 10 established the VBWD GitHub organization (`VBWD-platform`), transferred all core repositories, created 25 standalone public plugin repositories, and authored developer documentation for every plugin across all three projects.

---

## Phase A — GitHub Organization

| Step | Result |
|------|--------|
| A1: `gh auth status` | `dantweb` account confirmed |
| A2: Create org | `VBWD-platform` created via GitHub web UI (API endpoint not available for user accounts) |

**Note:** `POST /user/orgs` returns 404 for regular GitHub accounts — org creation requires the GitHub web UI.

---

## Phase B — Core Repo Transfers

All four core repositories transferred from `dantweb` → `VBWD-platform`. GitHub automatically sets up redirects from old URLs.

| Repo | Old URL | New URL |
|------|---------|---------|
| vbwd-backend | `github.com/dantweb/vbwd-backend` | `github.com/VBWD-platform/vbwd-backend` |
| vbwd-fe-core | `github.com/dantweb/vbwd-fe-core` | `github.com/VBWD-platform/vbwd-fe-core` |
| vbwd-fe-admin | `github.com/dantweb/vbwd-fe-admin` | `github.com/VBWD-platform/vbwd-fe-admin` |
| vbwd-fe-user | `github.com/dantweb/vbwd-fe-user` | `github.com/VBWD-platform/vbwd-fe-user` |
| vbwd-sdk | `github.com/dantweb/vbwd-sdk` | `github.com/VBWD-platform/vbwd-sdk` |

**Submodule URLs updated:**
- `vbwd-fe-user/.gitmodules` — `vbwd-fe-core` URL updated to `VBWD-platform`
- `vbwd-fe-admin/.gitmodules` — `vbwd-fe-core` URL updated to `VBWD-platform`
- Both committed and pushed.

**Local git remotes updated** for all 4 core repos via `git remote set-url origin`.

---

## Phase C — Developer Documentation

26 developer docs written across all three projects:

### vbwd-backend (11 files)
| File | Plugin |
|------|--------|
| `docs/developer/analytics.md` | analytics |
| `docs/developer/chat.md` | chat |
| `docs/developer/cms.md` | cms |
| `docs/developer/demoplugin.md` | demoplugin |
| `docs/developer/email.md` | email |
| `docs/developer/ghrm.md` | ghrm |
| `docs/developer/mailchimp.md` | mailchimp |
| `docs/developer/paypal.md` | paypal |
| `docs/developer/stripe.md` | stripe |
| `docs/developer/taro.md` | taro |
| `docs/developer/yookassa.md` | yookassa |

### vbwd-fe-user (10 files)
| File | Plugin |
|------|--------|
| `docs/developer/chat.md` | chat |
| `docs/developer/checkout.md` | checkout |
| `docs/developer/cms.md` | cms |
| `docs/developer/ghrm.md` | ghrm |
| `docs/developer/landing1.md` | landing1 |
| `docs/developer/paypal-payment.md` | paypal-payment |
| `docs/developer/stripe-payment.md` | stripe-payment |
| `docs/developer/taro.md` | taro |
| `docs/developer/theme-switcher.md` | theme-switcher |
| `docs/developer/yookassa-payment.md` | yookassa-payment |

### vbwd-fe-admin (5 files)
| File | Plugin |
|------|--------|
| `docs/developer/analytics-widget.md` | analytics-widget |
| `docs/developer/cms-admin.md` | cms-admin |
| `docs/developer/email-admin.md` | email-admin |
| `docs/developer/ghrm-admin.md` | ghrm-admin |
| `docs/developer/taro-admin.md` | taro-admin |

---

## Phase D — Public Plugin Repositories

25 standalone public repos created under `VBWD-platform` and populated with developer docs as README.

### Naming convention
- Backend plugins: `vbwd-plugin-<name>`
- fe-user plugins: `vbwd-fe-user-plugin-<name>`
- fe-admin plugins: `vbwd-fe-admin-plugin-<name>`

### Backend plugin repos (10)
| Repo | URL |
|------|-----|
| vbwd-plugin-analytics | `github.com/VBWD-platform/vbwd-plugin-analytics` |
| vbwd-plugin-chat | `github.com/VBWD-platform/vbwd-plugin-chat` |
| vbwd-plugin-cms | `github.com/VBWD-platform/vbwd-plugin-cms` |
| vbwd-plugin-email | `github.com/VBWD-platform/vbwd-plugin-email` |
| vbwd-plugin-ghrm | `github.com/VBWD-platform/vbwd-plugin-ghrm` |
| vbwd-plugin-mailchimp | `github.com/VBWD-platform/vbwd-plugin-mailchimp` |
| vbwd-plugin-paypal | `github.com/VBWD-platform/vbwd-plugin-paypal` |
| vbwd-plugin-stripe | `github.com/VBWD-platform/vbwd-plugin-stripe` |
| vbwd-plugin-taro | `github.com/VBWD-platform/vbwd-plugin-taro` |
| vbwd-plugin-yookassa | `github.com/VBWD-platform/vbwd-plugin-yookassa` |

### fe-user plugin repos (10)
| Repo | URL |
|------|-----|
| vbwd-fe-user-plugin-chat | `github.com/VBWD-platform/vbwd-fe-user-plugin-chat` |
| vbwd-fe-user-plugin-checkout | `github.com/VBWD-platform/vbwd-fe-user-plugin-checkout` |
| vbwd-fe-user-plugin-cms | `github.com/VBWD-platform/vbwd-fe-user-plugin-cms` |
| vbwd-fe-user-plugin-ghrm | `github.com/VBWD-platform/vbwd-fe-user-plugin-ghrm` |
| vbwd-fe-user-plugin-landing1 | `github.com/VBWD-platform/vbwd-fe-user-plugin-landing1` |
| vbwd-fe-user-plugin-paypal-payment | `github.com/VBWD-platform/vbwd-fe-user-plugin-paypal-payment` |
| vbwd-fe-user-plugin-stripe-payment | `github.com/VBWD-platform/vbwd-fe-user-plugin-stripe-payment` |
| vbwd-fe-user-plugin-taro | `github.com/VBWD-platform/vbwd-fe-user-plugin-taro` |
| vbwd-fe-user-plugin-theme-switcher | `github.com/VBWD-platform/vbwd-fe-user-plugin-theme-switcher` |
| vbwd-fe-user-plugin-yookassa-payment | `github.com/VBWD-platform/vbwd-fe-user-plugin-yookassa-payment` |

### fe-admin plugin repos (5)
| Repo | URL |
|------|-----|
| vbwd-fe-admin-plugin-analytics-widget | `github.com/VBWD-platform/vbwd-fe-admin-plugin-analytics-widget` |
| vbwd-fe-admin-plugin-cms-admin | `github.com/VBWD-platform/vbwd-fe-admin-plugin-cms-admin` |
| vbwd-fe-admin-plugin-email-admin | `github.com/VBWD-platform/vbwd-fe-admin-plugin-email-admin` |
| vbwd-fe-admin-plugin-ghrm-admin | `github.com/VBWD-platform/vbwd-fe-admin-plugin-ghrm-admin` |
| vbwd-fe-admin-plugin-taro-admin | `github.com/VBWD-platform/vbwd-fe-admin-plugin-taro-admin` |

**Note:** Initial naming used `vbwd-fe-plugin-X` and `vbwd-admin-plugin-X`. All 15 repos renamed via `PATCH /repos/{owner}/{repo}` to the correct convention before population.

---

## D5 — README Plugin Directory Tables

Plugin directory tables added to all three core repo READMEs, linking to their respective VBWD-platform plugin repos.

---

## Post-Sprint Updates

### Installation scripts
- `recipes/dev-install-ce.sh`: all 4 repo URLs updated from `dantweb` → `VBWD-platform`

### GitHub Actions
- `vbwd-fe-user` and `vbwd-fe-admin` CI workflows use `submodules: recursive` — picks up updated `.gitmodules` automatically, no workflow changes needed
- `vbwd-backend` CI workflow operates only on its own checkout, no org references

### GHRM populate script
- `plugins/ghrm/src/bin/populate_ghrm.py`: all VBWD-platform plugin entries updated to `github_owner: "VBWD-platform"` with corrected `github_repo` names matching the plugin repo naming convention

---

## Issues Encountered

| Issue | Resolution |
|-------|-----------|
| `POST /user/orgs` returns 404 | Org creation requires GitHub web UI; user created `VBWD-platform` manually |
| Wrong initial repo naming (`vbwd-fe-plugin-X`, `vbwd-admin-plugin-X`) | All 15 repos renamed via `PATCH /repos/{owner}/{repo}` before population |
| `ghrm-admin.md` written to wrong path | Copied to correct path `vbwd-sdk-2/vbwd-fe-admin/docs/developer/` |
