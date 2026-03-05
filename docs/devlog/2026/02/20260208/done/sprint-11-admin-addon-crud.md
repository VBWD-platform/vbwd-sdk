# Sprint 11 — Admin Add-On CRUD Management

**Priority:** HIGH
**Goal:** Replace the placeholder Add-Ons admin page with a fully functional CRUD interface for managing add-ons (list, create, edit, delete, activate/deactivate).

**Principles:** TDD-first, SOLID (SRP, OCP, LSP, ISP, DIP), DRY, Clean Code, Liskov Substitution, No Overengineering

---

## Plugin System Context

Add-ons exist **outside** the plugin system — they are a core domain entity (like Plans, Subscriptions, Invoices). This sprint adds the missing admin UI for the core `AddOn` model. For reference, the plugin system architecture is documented below since both systems coexist in the platform.

### Backend Plugin Lifecycle

```
DISCOVERED → register_plugin() → REGISTERED → initialize_plugin() → INITIALIZED
     ↕                                                                    ↕
  (auto-discovery                                              enable_plugin()
   on app startup)                                                    ↕
                                                               ENABLED ↔ DISABLED
                                                            (disable_plugin())
```

**Status Enum:** `DISCOVERED → REGISTERED → INITIALIZED → ENABLED ↔ DISABLED | ERROR`

**Lifecycle Hooks (BasePlugin):**

| Method | Trigger | Purpose |
|--------|---------|---------|
| `__init__()` | Plugin file discovered | Instance created |
| `initialize(config)` | `PluginManager.initialize_plugin()` | Store config, set INITIALIZED |
| `on_enable()` | `PluginManager.enable_plugin()` | Plugin-specific activation logic |
| `on_disable()` | `PluginManager.disable_plugin()` | Plugin-specific cleanup logic |
| `get_blueprint()` | App startup (dynamic route registration) | Return Flask Blueprint or None |
| `get_url_prefix()` | App startup (dynamic route registration) | Return URL prefix or None |

**App Startup Sequence (`app.py`):**
1. Create `PluginManager` with `PluginConfigRepository` (DB persistence)
2. `plugin_manager.discover("src.plugins.providers")` — auto-scan for `BasePlugin` subclasses
3. `plugin_manager.load_persisted_state()` — restore enabled plugins from `plugin_config` DB table
4. Default: enable `analytics` plugin if nothing in DB
5. Loop `plugin_manager.get_plugin_blueprints()` — register all enabled plugin routes

**Database Persistence (`plugin_config` table):**
- `plugin_name` (unique), `status` ("enabled"/"disabled"), `config` (JSONB), `enabled_at`, `disabled_at`
- `enable_plugin()` → `config_repo.save(name, "enabled", config)`
- `disable_plugin()` → `config_repo.save(name, "disabled", config)`
- `load_persisted_state()` → reads DB, re-enables previously enabled plugins on restart

### CLI Commands

```bash
# Inside backend container:
cd vbwd-backend && make shell

flask plugins list              # List all plugins with status
flask plugins enable <name>     # Enable plugin (persists to DB)
flask plugins disable <name>    # Disable plugin (persists to DB)
```

**Output example:**
```
$ flask plugins list
analytics (1.0.0) — ENABLED
mock-payment (1.0.0) — INITIALIZED
```

### Adding a New Plugin (Zero app.py Changes)

```python
# 1. Create: src/plugins/providers/my_plugin.py
class MyPlugin(BasePlugin):
    @property
    def metadata(self):
        return PluginMetadata(name="my-plugin", version="1.0.0", ...)

    def on_enable(self): ...
    def on_disable(self): ...
    def get_blueprint(self): return my_bp  # optional
    def get_url_prefix(self): return "/api/v1/plugins/my-plugin"  # optional

# 2. Restart app → auto-discovered, status: INITIALIZED
# 3. flask plugins enable my-plugin → status: ENABLED, persisted to DB
# 4. Restart → restored from DB, still ENABLED
```

### Frontend Plugin System

```typescript
// PluginRegistry + PlatformSDK initialized in admin main.ts
const registry = new PluginRegistry();
const sdk = new PlatformSDK(app, router, pinia);

// Plugin lifecycle: register → install → activate ↔ deactivate
registry.register(myPlugin);
await registry.installAll(sdk);    // Calls plugin.install(sdk)
await registry.activate('name');   // Calls plugin.activate()
await registry.deactivate('name'); // Calls plugin.deactivate()

// SDK capabilities available to plugins:
sdk.addRoute({ path, name, component });  // Inject Vue Router route
sdk.createStore('name', storeOptions);     // Create Pinia store
sdk.addWidget('dashboard', component);     // Add dashboard widget
```

### Existing Plugins

| Plugin | Type | Status | Routes |
|--------|------|--------|--------|
| `analytics` | Backend + Frontend | ENABLED by default | `GET /api/v1/plugins/analytics/active-sessions` |
| `mock-payment` | Backend only | INITIALIZED | Payment provider interface |
| `analytics-widget` | Frontend only | Active | Dashboard widget via PlatformSDK |

---

## Overview

### Current State

The admin Add-Ons page (`/admin/add-ons`) is a placeholder:
- Two empty tabs with "Tab 1 content coming soon..." text
- No Pinia store for addon state management
- No form for creating or editing add-ons
- No routes for create/edit pages
- i18n has only 5 placeholder keys

### Target State

Full CRUD matching the Plans pattern (Plans.vue + PlanForm.vue + planAdmin.ts):
- **List view**: Table with name, slug, price, billing period, status, actions — with search, sort, pagination
- **Create/Edit form**: Shared AddonForm.vue with all addon fields (name, slug, description, price, currency, billing_period, config, is_active, sort_order)
- **Actions**: Create, edit, delete (with confirmation), activate, deactivate
- **Store**: Pinia store with full CRUD actions mirroring `planAdmin.ts`
- **Routes**: `/admin/add-ons`, `/admin/add-ons/new`, `/admin/add-ons/:id/edit`
- **i18n**: Complete keys in all 8 languages

### Backend API (Already Complete)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/admin/addons/?page=1&per_page=20&include_inactive=true` | List with pagination |
| `POST` | `/api/v1/admin/addons/` | Create (auto-slug if not provided) |
| `GET` | `/api/v1/admin/addons/<id>` | Get by ID |
| `GET` | `/api/v1/admin/addons/slug/<slug>` | Get by slug |
| `PUT` | `/api/v1/admin/addons/<id>` | Update |
| `DELETE` | `/api/v1/admin/addons/<id>` | Delete |
| `POST` | `/api/v1/admin/addons/<id>/activate` | Activate |
| `POST` | `/api/v1/admin/addons/<id>/deactivate` | Deactivate |

### AddOn Model Fields

```
id, name, slug, description, price, currency, billing_period, config (JSONB),
is_active, is_recurring (computed), sort_order, created_at, updated_at
```

---

## Sprint Breakdown

### Sub-sprint 11a: Addon Store (TDD)

**Goal:** Create `addons.ts` Pinia store mirroring `planAdmin.ts` pattern.

#### 11a.1 Unit Tests (RED)

**File:** `vbwd-frontend/admin/vue/tests/unit/stores/addons.spec.ts`

```
Tests to write FIRST:

test_fetch_addons_populates_state
  - Mock API GET /admin/addons returns { items: [addon1, addon2], total: 2 }
  - store.addons has 2 items, store.total === 2

test_fetch_addons_sets_loading_state
  - During fetch: store.loading === true
  - After fetch: store.loading === false

test_fetch_addons_handles_error
  - Mock API rejects with "Network Error"
  - store.error === "Network Error"

test_fetch_addon_by_id
  - Mock API GET /admin/addons/<id> returns { addon: addonData }
  - store.selectedAddon matches addonData

test_create_addon
  - Mock API POST /admin/addons returns { addon: newAddon }
  - Resolves without error

test_create_addon_validation_error
  - Mock API POST rejects with 400 "Name is required"
  - store.error set

test_update_addon
  - Mock API PUT /admin/addons/<id> returns { addon: updatedAddon }
  - Resolves without error

test_delete_addon
  - Mock API DELETE /admin/addons/<id> returns 200
  - Resolves without error

test_activate_addon
  - Mock API POST /admin/addons/<id>/activate returns { addon: activated }
  - Resolves without error

test_deactivate_addon
  - Mock API POST /admin/addons/<id>/deactivate returns { addon: deactivated }
  - Resolves without error

test_reset_clears_state
  - Store has addons and error
  - store.reset() clears all state
```

#### 11a.2 Implementation (GREEN)

**File:** `vbwd-frontend/admin/vue/src/stores/addons.ts`

```typescript
import { defineStore } from 'pinia';
import { api } from '../api';

export interface AdminAddon {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  price: string;
  currency: string;
  billing_period: string;
  config: Record<string, unknown>;
  is_active: boolean;
  is_recurring: boolean;
  sort_order: number;
  created_at: string | null;
  updated_at: string | null;
}

export interface CreateAddonData {
  name: string;
  slug?: string;
  description?: string;
  price: number;
  currency?: string;
  billing_period: string;
  config?: Record<string, unknown>;
  is_active?: boolean;
  sort_order?: number;
}

export const useAddonStore = defineStore('addons', {
  state: () => ({
    addons: [] as AdminAddon[],
    selectedAddon: null as AdminAddon | null,
    total: 0,
    loading: false,
    error: null as string | null
  }),

  actions: {
    async fetchAddons(page = 1, perPage = 20, includeInactive = true) {
      this.loading = true;
      this.error = null;
      try {
        const response = await api.get('/admin/addons/', {
          params: { page, per_page: perPage, include_inactive: includeInactive }
        }) as { items: AdminAddon[]; total: number };
        this.addons = response.items;
        this.total = response.total;
        return response;
      } catch (error) {
        this.error = (error as Error).message || 'Failed to fetch add-ons';
        throw error;
      } finally {
        this.loading = false;
      }
    },

    async fetchAddon(addonId: string): Promise<AdminAddon> {
      this.loading = true;
      this.error = null;
      try {
        const response = await api.get(`/admin/addons/${addonId}`) as { addon: AdminAddon };
        this.selectedAddon = response.addon;
        return response.addon;
      } catch (error) {
        this.error = (error as Error).message || 'Failed to fetch add-on';
        throw error;
      } finally {
        this.loading = false;
      }
    },

    async createAddon(data: CreateAddonData) {
      this.loading = true;
      this.error = null;
      try {
        const response = await api.post('/admin/addons/', data);
        return response;
      } catch (error) {
        this.error = (error as Error).message || 'Failed to create add-on';
        throw error;
      } finally {
        this.loading = false;
      }
    },

    async updateAddon(addonId: string, data: Partial<CreateAddonData>) {
      this.loading = true;
      this.error = null;
      try {
        const response = await api.put(`/admin/addons/${addonId}`, data);
        return response;
      } catch (error) {
        this.error = (error as Error).message || 'Failed to update add-on';
        throw error;
      } finally {
        this.loading = false;
      }
    },

    async deleteAddon(addonId: string) {
      this.loading = true;
      this.error = null;
      try {
        const response = await api.delete(`/admin/addons/${addonId}`);
        return response;
      } catch (error) {
        this.error = (error as Error).message || 'Failed to delete add-on';
        throw error;
      } finally {
        this.loading = false;
      }
    },

    async activateAddon(addonId: string) {
      this.loading = true;
      this.error = null;
      try {
        const response = await api.post(`/admin/addons/${addonId}/activate`);
        return response;
      } catch (error) {
        this.error = (error as Error).message || 'Failed to activate add-on';
        throw error;
      } finally {
        this.loading = false;
      }
    },

    async deactivateAddon(addonId: string) {
      this.loading = true;
      this.error = null;
      try {
        const response = await api.post(`/admin/addons/${addonId}/deactivate`);
        return response;
      } catch (error) {
        this.error = (error as Error).message || 'Failed to deactivate add-on';
        throw error;
      } finally {
        this.loading = false;
      }
    },

    reset() {
      this.addons = [];
      this.selectedAddon = null;
      this.total = 0;
      this.error = null;
      this.loading = false;
    }
  }
});
```

Pattern: Mirrors `planAdmin.ts` exactly (SRP — store only manages state, OCP — easy to add new actions, DIP — depends on api abstraction not fetch).

#### 11a.3 Verify

```bash
cd vbwd-frontend/admin/vue && npx vitest run tests/unit/stores/addons.spec.ts
```

---

### Sub-sprint 11b: AddOns List View (TDD)

**Goal:** Replace placeholder AddOns.vue with a proper list table following Plans.vue pattern.

#### 11b.1 Unit Tests (RED)

**File:** `vbwd-frontend/admin/vue/tests/unit/views/addons.spec.ts`

```
Tests to write FIRST:

test_renders_addons_table_with_data
  - Mock store with 2 addons
  - [data-testid="addons-table"] visible with 2 rows

test_shows_loading_spinner
  - store.loading = true
  - [data-testid="loading-spinner"] visible

test_shows_error_message
  - store.error = "Failed to fetch"
  - [data-testid="error-message"] visible with text

test_shows_empty_state
  - store.addons = []
  - [data-testid="empty-state"] visible

test_create_button_navigates_to_new
  - Click [data-testid="create-addon-button"]
  - router.push called with '/admin/add-ons/new'

test_row_click_navigates_to_edit
  - Click addon row
  - router.push called with '/admin/add-ons/<id>/edit'

test_search_filters_addons
  - Type in [data-testid="search-input"]
  - Table rows filter by name

test_activate_deactivate_toggle
  - Addon is_active = true → click deactivate → store.deactivateAddon called
  - Addon is_active = false → click activate → store.activateAddon called

test_delete_button_calls_store
  - Click delete button on addon row
  - store.deleteAddon called with addon ID

test_include_inactive_checkbox
  - Toggle [data-testid="include-inactive"]
  - store.fetchAddons called with updated param

test_table_columns_correct
  - Table headers: Name, Slug, Price, Billing Period, Status, Actions

test_sort_by_name
  - Click Name header
  - Addons sorted alphabetically
```

#### 11b.2 Implementation (GREEN)

**File:** `vbwd-frontend/admin/vue/src/views/AddOns.vue` — replace placeholder entirely

Key structure (follows Plans.vue):
- Header: title + create button
- Filters: search input + include-inactive checkbox
- States: loading, error, empty
- Table: name, slug, price, billing period, status badge, actions (activate/deactivate, delete)
- Row click navigates to edit
- Sorting on columns

#### 11b.3 Verify

```bash
cd vbwd-frontend/admin/vue && npx vitest run tests/unit/views/addons.spec.ts
```

---

### Sub-sprint 11c: AddonForm View (TDD)

**Goal:** Create AddonForm.vue for create/edit following PlanForm.vue pattern.

#### 11c.1 Unit Tests (RED)

**File:** `vbwd-frontend/admin/vue/tests/unit/views/addon-form.spec.ts`

```
Tests to write FIRST:

test_renders_create_form_title
  - Route has no id param
  - [data-testid="form-title"] shows "Create Add-On"

test_renders_edit_form_title
  - Route has id param
  - Fetches addon from store
  - [data-testid="form-title"] shows "Edit Add-On"

test_populates_form_in_edit_mode
  - Store returns addon with name, price, etc.
  - Form fields pre-populated

test_validates_required_name
  - Submit with empty name
  - [data-testid="validation-error"] shows name required

test_validates_required_price
  - Submit with no price
  - [data-testid="validation-error"] shows price required

test_validates_required_billing_period
  - Submit with empty billing_period
  - [data-testid="validation-error"] shows billing period required

test_submit_create_calls_store
  - Fill form with valid data, submit
  - store.createAddon called with form data
  - Navigates back to /admin/add-ons

test_submit_edit_calls_store
  - In edit mode, modify fields, submit
  - store.updateAddon called with addon ID and data
  - Navigates back to /admin/add-ons

test_cancel_navigates_back
  - Click cancel
  - router.push('/admin/add-ons')

test_back_button_navigates
  - Click back arrow
  - router.push('/admin/add-ons')

test_activate_button_in_edit_mode
  - Addon is_active = false
  - [data-testid="activate-button"] visible
  - Click → store.activateAddon called

test_deactivate_button_in_edit_mode
  - Addon is_active = true
  - [data-testid="deactivate-button"] visible
  - Click → store.deactivateAddon called

test_delete_button_in_edit_mode
  - Click [data-testid="delete-button"]
  - store.deleteAddon called
  - Navigates to /admin/add-ons

test_shows_loading_in_edit_mode
  - store.loading = true in edit mode
  - [data-testid="loading-spinner"] visible

test_shows_fetch_error
  - store.fetchAddon rejects
  - [data-testid="error-message"] visible

test_description_textarea
  - Enter description text
  - formData.description updated

test_config_json_textarea
  - Enter valid JSON in config field
  - formData.config parsed correctly

test_sort_order_input
  - Enter sort order number
  - formData.sort_order updated

test_slug_auto_generated_on_create
  - Enter name "Premium Support"
  - Slug hint shows "premium-support" (auto-generated by backend)
```

#### 11c.2 Implementation (GREEN)

**File:** `vbwd-frontend/admin/vue/src/views/AddonForm.vue`

Form fields:
- **Name** (text input, required)
- **Slug** (text input, optional — auto-generated from name by backend if empty)
- **Description** (textarea, optional)
- **Price** (number input, required, step=0.01, min=0)
- **Currency** (select: EUR, USD, GBP — default EUR)
- **Billing Period** (select: monthly, yearly, one_time)
- **Config** (textarea for JSON, optional)
- **Sort Order** (number input, default 0)

Actions (edit mode):
- Activate / Deactivate toggle
- Delete with confirmation
- Save / Cancel

Pattern: Mirrors PlanForm.vue structure exactly (LSP — AddonForm behaves like PlanForm from user's perspective, DRY — same form/button/error CSS classes).

#### 11c.3 Verify

```bash
cd vbwd-frontend/admin/vue && npx vitest run tests/unit/views/addon-form.spec.ts
```

---

### Sub-sprint 11d: Router + Navigation

**Goal:** Add routes for addon create/edit pages.

#### 11d.1 Changes

**File:** `vbwd-frontend/admin/vue/src/router/index.ts`

Add after the existing `add-ons` route:

```typescript
{
  path: 'add-ons/new',
  name: 'addon-new',
  component: () => import('@/views/AddonForm.vue')
},
{
  path: 'add-ons/:id/edit',
  name: 'addon-edit',
  component: () => import('@/views/AddonForm.vue')
}
```

No test needed — route registration is tested implicitly via view navigation tests.

---

### Sub-sprint 11e: i18n Keys

**Goal:** Add comprehensive addon CRUD keys to all 8 admin languages.

#### 11e.1 EN Keys to Add/Replace

Replace `addOns` section in `en.json`:

```json
{
  "addOns": {
    "title": "Add-Ons",
    "createAddon": "Create Add-On",
    "editAddon": "Edit Add-On",
    "createFirstAddon": "Create your first add-on",
    "backToAddons": "Back to Add-Ons",
    "name": "Name",
    "slug": "Slug",
    "slugHint": "Auto-generated from name if left empty",
    "description": "Description",
    "price": "Price",
    "currency": "Currency",
    "billingPeriod": "Billing Period",
    "config": "Configuration (JSON)",
    "configHint": "Optional JSON configuration for flexible parameters",
    "sortOrder": "Sort Order",
    "subscribers": "Subscriptions",
    "includeInactive": "Show inactive",
    "monthly": "Monthly",
    "yearly": "Yearly",
    "oneTime": "One-Time",
    "enterName": "Enter add-on name",
    "enterDescription": "Enter description",
    "enterConfig": "{ \"key\": \"value\" }",
    "nameRequired": "Name is required",
    "priceRequired": "Price is required",
    "priceInvalid": "Price must be a non-negative number",
    "billingPeriodRequired": "Billing period is required",
    "updateAddon": "Save Changes",
    "deleteAddon": "Delete Add-On",
    "confirmDelete": "Are you sure you want to delete this add-on?",
    "activateAddon": "Activate",
    "deactivateAddon": "Deactivate",
    "loadingAddon": "Loading add-on...",
    "failedToLoadAddon": "Failed to load add-on",
    "failedToSaveAddon": "Failed to save add-on",
    "failedToDeleteAddon": "Failed to delete add-on"
  }
}
```

#### 11e.2 Translate to DE, FR, ES, RU, ZH, JA, TH

Use same key structure. Example DE:

```json
{
  "addOns": {
    "title": "Add-Ons",
    "createAddon": "Add-On erstellen",
    "editAddon": "Add-On bearbeiten",
    "createFirstAddon": "Erstellen Sie Ihr erstes Add-On",
    "backToAddons": "Zurueck zu Add-Ons",
    "name": "Name",
    "slug": "Slug",
    "slugHint": "Wird automatisch aus dem Namen generiert, wenn leer",
    "description": "Beschreibung",
    "price": "Preis",
    "currency": "Waehrung",
    "billingPeriod": "Abrechnungszeitraum",
    "config": "Konfiguration (JSON)",
    "configHint": "Optionale JSON-Konfiguration fuer flexible Parameter",
    "sortOrder": "Sortierreihenfolge",
    "subscribers": "Abonnements",
    "includeInactive": "Inaktive anzeigen",
    "monthly": "Monatlich",
    "yearly": "Jaehrlich",
    "oneTime": "Einmalig",
    "enterName": "Add-On-Name eingeben",
    "enterDescription": "Beschreibung eingeben",
    "enterConfig": "{ \"key\": \"value\" }",
    "nameRequired": "Name ist erforderlich",
    "priceRequired": "Preis ist erforderlich",
    "priceInvalid": "Preis muss eine nicht-negative Zahl sein",
    "billingPeriodRequired": "Abrechnungszeitraum ist erforderlich",
    "updateAddon": "Aenderungen speichern",
    "deleteAddon": "Add-On loeschen",
    "confirmDelete": "Sind Sie sicher, dass Sie dieses Add-On loeschen moechten?",
    "activateAddon": "Aktivieren",
    "deactivateAddon": "Deaktivieren",
    "loadingAddon": "Add-On wird geladen...",
    "failedToLoadAddon": "Add-On konnte nicht geladen werden",
    "failedToSaveAddon": "Add-On konnte nicht gespeichert werden",
    "failedToDeleteAddon": "Add-On konnte nicht geloescht werden"
  }
}
```

Rule: All 8 languages must have identical key structure (previous bug: key mismatch between EN/DE).

---

### Sub-sprint 11f: E2E Tests

**Goal:** Add Playwright E2E tests for admin addon CRUD flow.

#### 11f.1 Test Plan

**File:** `vbwd-frontend/admin/vue/tests/e2e/admin-addons-crud.spec.ts`

```
Tests:

test_addon_list_page_loads
  - Navigate to /admin/add-ons
  - Table or empty state visible

test_create_addon_flow
  - Click "Create Add-On"
  - Fill form: name="Test Addon", price=9.99, billing_period=monthly
  - Submit
  - Redirected to add-ons list
  - New addon appears in table

test_edit_addon_flow
  - Click on addon row
  - Form pre-populated with addon data
  - Change name
  - Submit
  - Redirected to list with updated name

test_activate_deactivate_addon
  - Deactivate an active addon
  - Status changes to inactive
  - Activate again
  - Status changes to active

test_delete_addon
  - Click delete on an addon
  - Confirm deletion
  - Addon removed from list

test_search_addons
  - Type in search input
  - Table filters to matching addons

test_validation_errors
  - Try to submit empty form
  - Validation error messages appear
```

---

## TDD Execution Order

| Step | Type | Sub-sprint | Description | Status |
|------|------|------------|-------------|--------|
| 1 | Unit (RED) | 11a | Write addon store tests — 11 tests fail | [ ] |
| 2 | Code (GREEN) | 11a | Create `addons.ts` store — tests pass | [ ] |
| 3 | Verify | 11a | `npx vitest run` — store tests green | [ ] |
| 4 | Unit (RED) | 11b | Write AddOns list view tests — 12 tests fail | [ ] |
| 5 | Code (GREEN) | 11b | Replace AddOns.vue placeholder — tests pass | [ ] |
| 6 | Verify | 11b | `npx vitest run` — list view tests green | [ ] |
| 7 | Unit (RED) | 11c | Write AddonForm tests — 18 tests fail | [ ] |
| 8 | Code (GREEN) | 11c | Create AddonForm.vue — tests pass | [ ] |
| 9 | Verify | 11c | `npx vitest run` — form tests green | [ ] |
| 10 | Routes | 11d | Add router entries for addon-new and addon-edit | [ ] |
| 11 | i18n | 11e | Replace addOns keys in all 8 languages (verify key count matches) | [ ] |
| 12 | E2E | 11f | Write and run Playwright E2E tests | [ ] |
| 13 | Verify | ALL | `cd vbwd-frontend && make test` — zero regressions | [ ] |
| 14 | Verify | ALL | Pre-commit check passes | [ ] |

---

## File Plan

### New Files

| File | Purpose | Sub-sprint |
|------|---------|------------|
| `admin/vue/src/stores/addons.ts` | Pinia store for addon CRUD | 11a |
| `admin/vue/src/views/AddonForm.vue` | Create/edit form view | 11c |
| `admin/vue/tests/unit/stores/addons.spec.ts` | Store unit tests (~11 tests) | 11a |
| `admin/vue/tests/unit/views/addons.spec.ts` | List view unit tests (~12 tests) | 11b |
| `admin/vue/tests/unit/views/addon-form.spec.ts` | Form view unit tests (~18 tests) | 11c |
| `admin/vue/tests/e2e/admin-addons-crud.spec.ts` | E2E CRUD tests (~7 tests) | 11f |

### Modified Files

| File | Change | Sub-sprint |
|------|--------|------------|
| `admin/vue/src/views/AddOns.vue` | Replace placeholder with full list view | 11b |
| `admin/vue/src/router/index.ts` | Add addon-new and addon-edit routes | 11d |
| `admin/vue/src/i18n/locales/en.json` | Replace addOns section (~35 keys) | 11e |
| `admin/vue/src/i18n/locales/de.json` | Replace addOns section (~35 keys) | 11e |
| `admin/vue/src/i18n/locales/fr.json` | Replace addOns section (~35 keys) | 11e |
| `admin/vue/src/i18n/locales/es.json` | Replace addOns section (~35 keys) | 11e |
| `admin/vue/src/i18n/locales/ru.json` | Replace addOns section (~35 keys) | 11e |
| `admin/vue/src/i18n/locales/zh.json` | Replace addOns section (~35 keys) | 11e |
| `admin/vue/src/i18n/locales/ja.json` | Replace addOns section (~35 keys) | 11e |
| `admin/vue/src/i18n/locales/th.json` | Replace addOns section (~35 keys) | 11e |

---

## Definition of Done

- [ ] Pinia addon store with fetch, create, update, delete, activate, deactivate actions
- [ ] AddOns.vue list view with table, search, sort, status badges, actions
- [ ] AddonForm.vue with all addon fields, validation, create/edit modes
- [ ] Routes: `/admin/add-ons/new` and `/admin/add-ons/:id/edit` registered
- [ ] i18n: ~35 addon CRUD keys in all 8 languages (matching key structure)
- [ ] ~11 store unit tests pass
- [ ] ~12 list view unit tests pass
- [ ] ~18 form view unit tests pass
- [ ] ~7 E2E tests pass
- [ ] All existing tests pass (no regressions)
- [ ] Pre-commit check passes

---

## Principles Applied

| Principle | Application |
|-----------|-------------|
| **TDD** | Tests written first (RED) at every sub-sprint, then implementation (GREEN) |
| **SRP** | Store manages state only. View renders only. Form handles input only. Router handles navigation only. |
| **OCP** | AddOns.vue is open for new columns/actions without modifying core structure |
| **LSP** | AddonForm behaves identically to PlanForm from user perspective — same UX pattern, same button positions, same error handling |
| **ISP** | Store exposes specific actions (fetchAddons, createAddon, etc.) — consumers only depend on what they need |
| **DIP** | Views depend on store abstraction, store depends on api abstraction — no direct fetch() in components |
| **DRY** | Reuse Plans.vue CSS patterns, shared status-badge classes, same form layout structure. `formatPrice()` reused from Plans.vue |
| **Liskov** | AdminAddon interface is substitutable where plan-like entities are expected (same price/name/status shape) |
| **Clean Code** | Descriptive test names, small focused functions, consistent data-testid naming (`addon-*`), no magic numbers |
| **No Overengineering** | No abstract base store. No generic CRUD factory. No inline editing. No drag-and-drop reorder. Simple table + form pattern that works. |
