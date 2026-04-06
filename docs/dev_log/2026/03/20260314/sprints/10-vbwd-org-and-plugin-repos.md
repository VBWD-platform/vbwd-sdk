# Sprint 10 — VBWD GitHub Organization, Plugin Repos & Developer Docs

**Status:** Pending approval
**Scope:** GitHub organization setup, repo transfers, per-plugin developer documentation, public plugin repositories

---

## Overview

This sprint has four phases:

| Phase | Goal |
|-------|------|
| A | Create the **VBWD** GitHub organization via `gh` CLI |
| B | Transfer the four core repos into the VBWD org |
| C | Write developer docs (`docs/developer/`) for every plugin across all three projects |
| D | Create a public GitHub repository for each plugin under the VBWD org |

Every step that touches GitHub requires explicit user consent before execution.

---

## Phase A — Create VBWD Organization

### Step A1 — Verify GitHub auth
```bash
gh auth status
```
Expected: `dantweb` account, active token.

### Step A2 — Create the organization (requires user consent)
```bash
gh api /user/orgs \
  --method POST \
  -f login="vbwd" \
  -f profile_name="VBWD" \
  -f visibility="public"
```
> **Consent required.** Organization name `vbwd` (or alternative if taken — `vbwd-sdk`, `vbwdsdk`).

**Fallback:** If `vbwd` is taken, check availability:
```bash
gh api /orgs/vbwd 2>&1 | grep -c '"login"'
# Returns 1 if org exists and is claimed by another user
```

---

## Phase B — Transfer Core Repos to VBWD Org

Each transfer preserves stars, issues, pull requests, and contributors.
GitHub automatically redirects from old URL to new URL.
Submodule references in `vbwd-fe-user` and `vbwd-fe-admin` will need updating after transfer.

### Step B1 — Transfer vbwd-backend (requires user consent)
```bash
gh api /repos/dantweb/vbwd-backend/transfer \
  --method POST \
  -f new_owner="vbwd"
```

### Step B2 — Transfer vbwd-fe-core (requires user consent)
```bash
gh api /repos/dantweb/vbwd-fe-core/transfer \
  --method POST \
  -f new_owner="vbwd"
```

### Step B3 — Transfer vbwd-fe-admin (requires user consent)
```bash
gh api /repos/dantweb/vbwd-fe-admin/transfer \
  --method POST \
  -f new_owner="vbwd"
```

### Step B4 — Transfer vbwd-fe-user (requires user consent)
```bash
gh api /repos/dantweb/vbwd-fe-user/transfer \
  --method POST \
  -f new_owner="vbwd"
```

### Step B5 — Update submodule remotes in vbwd-fe-user and vbwd-fe-admin

After transfer, update the submodule URL pointing to `vbwd-fe-core`:

```bash
# vbwd-fe-user
cd vbwd-fe-user
git submodule set-url vbwd-fe-core https://github.com/vbwd/vbwd-fe-core.git
git add .gitmodules && git commit -m "chore: update vbwd-fe-core submodule to VBWD org"

# vbwd-fe-admin
cd vbwd-fe-admin
git submodule set-url vbwd-fe-core https://github.com/vbwd/vbwd-fe-core.git
git add .gitmodules && git commit -m "chore: update vbwd-fe-core submodule to VBWD org"
```

### Step B6 — Update local git remotes
```bash
cd vbwd-backend  && git remote set-url origin https://github.com/vbwd/vbwd-backend.git
cd vbwd-fe-core  && git remote set-url origin https://github.com/vbwd/vbwd-fe-core.git
cd vbwd-fe-admin && git remote set-url origin https://github.com/vbwd/vbwd-fe-admin.git
cd vbwd-fe-user  && git remote set-url origin https://github.com/vbwd/vbwd-fe-user.git
```

---

## Phase C — Developer Documentation

Create `docs/developer/` in each repo with a README per plugin.
Each README covers: purpose, install/enable steps, config keys, API endpoints, architecture diagram, and extension guide.

### Plugins to document

#### vbwd-backend/plugins/
| Plugin | Description |
|--------|-------------|
| `analytics` | Request/event analytics for admin dashboard |
| `chat` | LLM-powered AI chat with token billing |
| `cms` | CMS pages, categories, images, layouts |
| `demoplugin` | Minimal reference implementation |
| `email` | Email templates, SMTP sender, event-driven delivery |
| `ghrm` | GitHub Release Manager — private package marketplace |
| `mailchimp` | Mandrill/Mailchimp email sender backend |
| `paypal` | PayPal payment SDK adapter and webhooks |
| `stripe` | Stripe payment SDK adapter and webhooks |
| `taro` | Tarot card reading with AI interpretations |
| `yookassa` | YooKassa payment SDK adapter and auto-renewal |

#### vbwd-fe-user/plugins/
| Plugin | Description |
|--------|-------------|
| `chat` | Chat UI — view, input, message, session |
| `checkout` | Checkout flow with billing address and payment method routing |
| `cms` | CMS page rendering with widget slots |
| `ghrm` | Package catalogue, detail page, GitHub OAuth |
| `landing1` | Marketing landing page + embed widget |
| `paypal-payment` | PayPal redirect/success/cancel views |
| `stripe-payment` | Stripe redirect/success/cancel views |
| `taro` | Tarot card reading UI |
| `theme-switcher` | Light/dark/system theme selector |
| `yookassa-payment` | YooKassa redirect/success/cancel views |

#### vbwd-fe-admin/plugins/
| Plugin | Description |
|--------|-------------|
| `analytics-widget` | Dashboard analytics chart widget |
| `cms-admin` | CMS pages/categories/layouts/widgets/styles admin |
| `email-admin` | Email template list and editor (HTML/Text/Preview) |
| `ghrm-admin` | GHRM package management tab in admin |
| `taro-admin` | Tarot session section in user detail |

### Step C1 — Create docs/developer/ directory structure

```
vbwd-backend/docs/developer/
  analytics.md
  chat.md
  cms.md
  demoplugin.md
  email.md
  ghrm.md
  mailchimp.md
  paypal.md
  stripe.md
  taro.md
  yookassa.md

vbwd-fe-user/docs/developer/
  chat.md
  checkout.md
  cms.md
  ghrm.md
  landing1.md
  paypal-payment.md
  stripe-payment.md
  taro.md
  theme-switcher.md
  yookassa-payment.md

vbwd-fe-admin/docs/developer/
  analytics-widget.md
  cms-admin.md
  email-admin.md
  ghrm-admin.md
  taro-admin.md
```

### Step C2 — Backend plugin doc template

Each `docs/developer/<plugin>.md`:

```markdown
# Plugin: <name>

## Purpose
One-paragraph description.

## Installation
1. Add to `plugins/plugins.json` with `"enabled": true`
2. Add config block to `plugins/config.json` (see Config section)
3. Run Alembic migration (if applicable): `flask db upgrade`

## Configuration
| Key | Type | Default | Description |
|-----|------|---------|-------------|

## API Endpoints
| Method | Path | Auth | Description |
|--------|------|------|-------------|

## Events Emitted
| Event class | When |
|-------------|------|

## Events Consumed
| Event class | Handler |
|-------------|---------|

## Architecture
<file tree of plugin directory>

## Extending
How to add new routes / hook into events.
```

### Step C3 — Frontend plugin doc template

Each `docs/developer/<plugin>.md`:

```markdown
# Plugin: <name>

## Purpose
One-paragraph description.

## Installation
The plugin self-registers in `plugins/plugins.json`.
It is loaded by `vue/src/main.ts` via `pluginLoader`.

## Routes Added
| Path | Component | Auth required |
|------|-----------|---------------|

## Stores
| Store | State keys | Actions |
|-------|-----------|---------|

## i18n Keys
Translations live in `plugins/<name>/locales/`.

## Config
`plugins/<name>/config.json` — user-facing enabled/disabled flag.
`plugins/<name>/admin-config.json` — admin panel settings schema.

## Architecture
<file tree>
```

---

## Phase D — Public Plugin Repositories in VBWD Org

Each plugin gets a standalone public GitHub repo so it can be published, starred, forked, and versioned independently.

### Naming convention
`vbwd-plugin-<name>` — e.g. `vbwd-plugin-ghrm`, `vbwd-plugin-stripe`

### Plugin repos to create (requires user consent per batch)

#### Backend plugins
```bash
for plugin in analytics chat cms email ghrm mailchimp paypal stripe taro yookassa; do
  gh repo create vbwd/vbwd-plugin-$plugin \
    --public \
    --description "vbwd backend plugin: $plugin" \
    --add-readme
done
```

#### fe-user plugins
```bash
for plugin in chat checkout cms ghrm landing1 paypal-payment stripe-payment taro theme-switcher yookassa-payment; do
  gh repo create vbwd/vbwd-fe-plugin-$plugin \
    --public \
    --description "vbwd fe-user plugin: $plugin" \
    --add-readme
done
```

#### fe-admin plugins
```bash
for plugin in analytics-widget cms-admin email-admin ghrm-admin taro-admin; do
  gh repo create vbwd/vbwd-admin-plugin-$plugin \
    --public \
    --description "vbwd fe-admin plugin: $plugin" \
    --add-readme
done
```

### Step D2 — Populate each plugin repo

For each plugin repo, push the plugin source directory as the repo root:

```bash
# Example for vbwd-plugin-ghrm (backend)
cd /tmp
git clone https://github.com/vbwd/vbwd-plugin-ghrm.git
cp -r /path/to/vbwd-backend/plugins/ghrm/. vbwd-plugin-ghrm/
cd vbwd-plugin-ghrm
git add . && git commit -m "initial: publish ghrm plugin source"
git push origin main
```

### Step D3 — Link plugin repos from main project README

Update each monorepo `README.md` with a plugin directory table linking to org repos.

---

## Checklist

### Phase A
- [ ] A1: Confirm `gh auth status`
- [ ] A2: Create VBWD org (user consent)

### Phase B
- [ ] B1: Transfer vbwd-backend (user consent)
- [ ] B2: Transfer vbwd-fe-core (user consent)
- [ ] B3: Transfer vbwd-fe-admin (user consent)
- [ ] B4: Transfer vbwd-fe-user (user consent)
- [ ] B5: Update submodule URLs
- [ ] B6: Update local git remotes

### Phase C
- [ ] C1: Create `docs/developer/` structure in all 3 repos
- [ ] C2: Write backend plugin docs (11 files)
- [ ] C3: Write fe-user plugin docs (10 files)
- [ ] C4: Write fe-admin plugin docs (5 files)

### Phase D
- [ ] D1: Create backend plugin repos in VBWD org (user consent)
- [ ] D2: Create fe-user plugin repos in VBWD org (user consent)
- [ ] D3: Create fe-admin plugin repos in VBWD org (user consent)
- [ ] D4: Populate each plugin repo with source
- [ ] D5: Link repos from monorepo READMEs

---

## Notes

- **Org name availability**: `vbwd` may be taken on GitHub. Fallback options: `vbwd-sdk`, `vbwdsdk`, `vbwd-platform`. Check before creating.
- **Submodule compatibility**: After transferring `vbwd-fe-core`, both `vbwd-fe-user` and `vbwd-fe-admin` reference it as a submodule — update `.gitmodules` before the CI breaks.
- **demoplugin**: Not included in Phase D (reference implementation, not a distributable plugin).
- **CORS after org transfer**: CI/CD environment variables referencing old repo URLs (e.g. in `docker-compose.server.yaml`) will need updating after transfer.
- **Plugin versioning**: Each plugin repo should eventually get semantic versioning tags matching the version field in `config.json` / `__init__.py`.

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | For Phase C (docs), verify each doc renders correctly in GitHub preview before marking done. |
| **SOLID** | Each plugin repo contains only its own source — no cross-plugin imports. |
| **DI** | Not applicable — no code changes in this sprint. |
| **DRY** | Docs use a shared template (defined in sprint steps C2/C3). |
| **Clean code** | Docs: accurate, no broken links, no placeholder text left in. |
| **No over-engineering** | Plugin repos start minimal (source + README). CI/CD added in a later sprint. |
| **Drop deprecated** | Use `gh api` (current CLI) not legacy `hub` commands. |

---

## Pre-commit Checks

This sprint modifies **only documentation and GitHub org setup** — no application code changes.

Verify each phase with `gh`:
```bash
# Phase A — confirm org created
gh api /orgs/vbwd --jq '.login'

# Phase B — confirm repo transferred
gh repo view vbwd/vbwd-backend --json nameWithOwner

# Phase C — docs: confirm files exist in each repo
ls vbwd-backend/docs/developer/
ls vbwd-fe-user/docs/developer/
ls vbwd-fe-admin/docs/developer/

# Phase D — confirm plugin repos created
gh repo list vbwd --limit 50 --json name --jq '.[].name'
```

If any application code changes are made as part of Phase C README generation, run the appropriate pre-commit check:
```bash
# fe-user
./bin/pre-commit-check.sh --style

# fe-admin
./bin/pre-commit-check.sh --style

# backend
./bin/pre-commit-check.sh --lint
```
