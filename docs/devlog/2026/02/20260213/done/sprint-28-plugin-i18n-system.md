# Sprint 28: Plugin i18n System — Bundled Translations

## Goal

Extend the frontend plugin system so that each plugin can bundle its own i18n translations inside its plugin folder. Translations are merged into the app's `vue-i18n` instance at plugin install time via a new `PlatformSDK.addTranslations()` method. Move existing plugin translations from the monolithic `en.json`/`de.json` locale files into the respective plugin folders.

## Engineering Principles

- **TDD**: Tests first — write failing tests for `addTranslations()`, `IPlugin.translations`, merge logic, and per-plugin locale files before implementation
- **SOLID — SRP**: `PlatformSDK` collects translations. Merge utility handles deep-merge logic. Plugin provides translations via a simple property. Each has one job
- **SOLID — OCP**: New plugins can add translations for any locale without modifying the core i18n setup or any existing locale files. The system is open for extension
- **SOLID — ISP**: `translations` is an optional property on `IPlugin` — plugins without translations (payment views that use parent keys) are not forced to implement it
- **SOLID — DIP**: Plugin install depends on the `IPlatformSDK.addTranslations()` abstraction, not on the concrete `vue-i18n` instance. The SDK handles the bridge
- **Liskov Substitution**: Any `IPlugin` with or without `translations` installs identically — the registry treats them the same
- **DI**: The `vue-i18n` instance is injected into `PlatformSDK` at app bootstrap, not imported globally by plugins
- **Clean Code**: Self-documenting, minimal comments. Translation keys are namespaced by plugin name to prevent collisions
- **DRY**: Each plugin owns its translations — no duplication between plugin folder and global locale files. Deep-merge utility is shared across all plugins
- **No overengineering**: No lazy-loading of translations, no remote translation fetching, no translation compilation step — simple JSON files merged at install time
- **No backward compatibility**: Remove plugin-specific keys from global locale files after moving them to plugins. No shims

## Testing Approach

All tests MUST pass before the sprint is considered complete. Run via:

```bash
# 1. Core library tests (new SDK i18n methods)
cd vbwd-frontend/core && npx vitest run

# 2. User frontend tests (plugin translation integration)
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# 3. Admin regression (no admin code changes expected)
cd vbwd-frontend/admin/vue && npx vitest run

# 4. Full pre-commit check
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --user --unit
```

---

## Architecture

### Current State (Problem)

Plugin translations live in monolithic global locale files:

```
user/vue/src/i18n/locales/en.json  ← 609 keys, including landing1.*, checkout.*, stripe.*, paypal.*, yookassa.*
user/vue/src/i18n/locales/de.json  ← Same structure in German
```

**Problems:**
1. Adding a new plugin requires editing global locale files — violates OCP
2. Removing a plugin leaves orphan translation keys — no cleanup mechanism
3. Plugin translations are not co-located with plugin code — hard to maintain
4. No mechanism for third-party plugins to provide translations

### Target State (Solution)

Each plugin bundles its own translations in a `locales/` folder:

```
user/plugins/landing1/
├── index.ts
├── Landing1View.vue
├── locales/
│   ├── en.json           ← { "landing1": { "title": "Choose Your Plan", ... } }
│   └── de.json           ← { "landing1": { "title": "Wählen Sie Ihren Plan", ... } }
├── config.json
└── admin-config.json

user/plugins/checkout/
├── index.ts
├── PublicCheckoutView.vue
├── locales/
│   ├── en.json           ← { "checkout": { "title": "Checkout", ... } }
│   └── de.json           ← { "checkout": { "title": "Kasse", ... } }
└── ...
```

At plugin install time, translations are deep-merged into the `vue-i18n` instance:

```
Plugin.install(sdk)
  → sdk.addTranslations('en', { landing1: { title: "Choose Your Plan" } })
  → sdk.addTranslations('de', { landing1: { title: "Wählen Sie Ihren Plan" } })
  → vue-i18n mergeLocaleMessage('en', { landing1: { ... } })
```

### Translation Merge Flow

```
App Bootstrap (main.ts)
  │
  ├── Create vue-i18n with base messages (common, nav, dashboard, etc.)
  │   └── Only NON-plugin keys remain in global locale files
  │
  ├── Create PlatformSDK(i18nInstance)  ← NEW: pass i18n to SDK
  │
  ├── For each enabled plugin:
  │   └── registry.install(pluginName, sdk)
  │       └── plugin.install(sdk)
  │           ├── sdk.addRoute(...)          (existing)
  │           ├── sdk.addTranslations(...)   (NEW)
  │           │   └── i18n.global.mergeLocaleMessage(locale, messages)
  │           └── ...
  │
  └── App mounts with all translations available
```

---

## What Already Exists (NO changes needed)

| File | Provides |
|------|----------|
| `core/src/plugins/PluginRegistry.ts` | Plugin lifecycle management (register, install, activate) |
| `user/vue/src/i18n/index.ts` | vue-i18n instance with `legacy: false` |
| `user/vue/src/i18n/locales/en.json` | All EN translations (will be trimmed, not deleted) |
| `user/vue/src/i18n/locales/de.json` | All DE translations (will be trimmed, not deleted) |

---

## What This Sprint Changes

| Layer | File | Change |
|-------|------|--------|
| Core | `core/src/plugins/types.ts` | **MODIFY** — add optional `translations` property to `IPlugin` |
| Core | `core/src/plugins/PlatformSDK.ts` | **MODIFY** — add `addTranslations()` method + i18n instance injection |
| Core | `core/src/plugins/types.ts` | **MODIFY** — add `addTranslations()` to `IPlatformSDK` interface |
| Core | `core/src/utils/deep-merge.ts` | **NEW** — deep-merge utility for translation objects |
| User | `user/plugins/landing1/locales/en.json` | **NEW** — landing1 EN translations (moved from global) |
| User | `user/plugins/landing1/locales/de.json` | **NEW** — landing1 DE translations (moved from global) |
| User | `user/plugins/landing1/index.ts` | **MODIFY** — add translations in `install()` |
| User | `user/plugins/checkout/locales/en.json` | **NEW** — checkout EN translations |
| User | `user/plugins/checkout/locales/de.json` | **NEW** — checkout DE translations |
| User | `user/plugins/checkout/index.ts` | **MODIFY** — add translations in `install()` |
| User | `user/plugins/stripe-payment/locales/en.json` | **NEW** — stripe EN translations |
| User | `user/plugins/stripe-payment/locales/de.json` | **NEW** — stripe DE translations |
| User | `user/plugins/stripe-payment/index.ts` | **MODIFY** — add translations in `install()` |
| User | `user/plugins/paypal-payment/locales/en.json` | **NEW** — paypal EN translations |
| User | `user/plugins/paypal-payment/locales/de.json` | **NEW** — paypal DE translations |
| User | `user/plugins/paypal-payment/index.ts` | **MODIFY** — add translations in `install()` |
| User | `user/plugins/yookassa-payment/locales/en.json` | **NEW** — yookassa EN translations |
| User | `user/plugins/yookassa-payment/locales/de.json` | **NEW** — yookassa DE translations |
| User | `user/plugins/yookassa-payment/index.ts` | **MODIFY** — add translations in `install()` |
| User | `user/vue/src/i18n/locales/en.json` | **MODIFY** — remove plugin-specific keys |
| User | `user/vue/src/i18n/locales/de.json` | **MODIFY** — remove plugin-specific keys |
| User | `user/vue/src/main.ts` | **MODIFY** — pass i18n instance to PlatformSDK |

---

## Task 1: Extend Core Plugin Interfaces

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/core/src/plugins/types.ts` | **MODIFY** |

### Changes to `IPlugin`

Add optional `translations` property:

```typescript
export interface IPlugin {
  name: string;
  version: string;
  description?: string;
  author?: string;
  homepage?: string;
  keywords?: string[];
  dependencies?: string[] | Record<string, string>;

  // NEW: Plugin-bundled translations
  // Key = locale code (e.g. 'en', 'de'), Value = translation messages object
  translations?: Record<string, Record<string, unknown>>;

  install(sdk: IPlatformSDK): void | Promise<void>;
  activate(): void | Promise<void>;
  deactivate(): void | Promise<void>;
  uninstall?(): void | Promise<void>;
  _active: boolean;
}
```

### Changes to `IPlatformSDK`

Add `addTranslations()` method:

```typescript
export interface IPlatformSDK {
  api: IApiClient;
  events: IEventBus;
  addRoute(route: IRouteConfig): void;
  getRoutes(): IRouteConfig[];
  addComponent(name: string, component: unknown): void;
  removeComponent(name: string): void;
  getComponents(): Record<string, unknown>;
  createStore(id: string, options: unknown): unknown;
  getStores(): Record<string, unknown>;

  // NEW: Merge translations into the app's i18n instance
  addTranslations(locale: string, messages: Record<string, unknown>): void;
  getTranslations(): Record<string, Record<string, unknown>>;
}
```

---

## Task 2: Extend PlatformSDK Implementation

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/core/src/plugins/PlatformSDK.ts` | **MODIFY** |
| `vbwd-frontend/core/src/utils/deep-merge.ts` | **NEW** |

### PlatformSDK Changes

Add i18n integration:

```typescript
import type { I18n } from 'vue-i18n';
import { deepMerge } from '../utils/deep-merge';

export class PlatformSDK implements IPlatformSDK {
  private routes: IRouteConfig[] = [];
  private components: Record<string, unknown> = {};
  private stores: Record<string, unknown> = {};
  private translations: Record<string, Record<string, unknown>> = {};
  private i18n: I18n | null = null;

  constructor(i18n?: I18n) {
    this.i18n = i18n || null;
  }

  // ... existing methods unchanged ...

  addTranslations(locale: string, messages: Record<string, unknown>): void {
    // Collect translations (used by getTranslations() for testing/inspection)
    if (!this.translations[locale]) {
      this.translations[locale] = {};
    }
    this.translations[locale] = deepMerge(this.translations[locale], messages);

    // If i18n instance available, merge immediately
    if (this.i18n) {
      this.i18n.global.mergeLocaleMessage(locale, messages);
    }
  }

  getTranslations(): Record<string, Record<string, unknown>> {
    return { ...this.translations };
  }
}
```

### `deep-merge.ts` — Utility

```typescript
/**
 * Deep-merge two objects. Source values override target values.
 * Only merges plain objects recursively; arrays and primitives are replaced.
 */
export function deepMerge(
  target: Record<string, unknown>,
  source: Record<string, unknown>
): Record<string, unknown> {
  const result = { ...target };
  for (const key of Object.keys(source)) {
    const targetVal = target[key];
    const sourceVal = source[key];
    if (
      isPlainObject(targetVal) &&
      isPlainObject(sourceVal)
    ) {
      result[key] = deepMerge(
        targetVal as Record<string, unknown>,
        sourceVal as Record<string, unknown>
      );
    } else {
      result[key] = sourceVal;
    }
  }
  return result;
}

function isPlainObject(val: unknown): val is Record<string, unknown> {
  return typeof val === 'object' && val !== null && !Array.isArray(val);
}
```

---

## Task 3: Create Per-Plugin Locale Files

### Files

Move existing translations from global locale files into plugin-local `locales/` folders.

| Plugin | Source Keys | New File |
|--------|-----------|----------|
| landing1 | `landing1.*` | `user/plugins/landing1/locales/en.json`, `de.json` |
| checkout | `checkout.*` | `user/plugins/checkout/locales/en.json`, `de.json` |
| stripe-payment | `stripe.*` | `user/plugins/stripe-payment/locales/en.json`, `de.json` |
| paypal-payment | `paypal.*` | `user/plugins/paypal-payment/locales/en.json`, `de.json` |
| yookassa-payment | `yookassa.*` | `user/plugins/yookassa-payment/locales/en.json`, `de.json` |

### Example: `landing1/locales/en.json`

```json
{
  "landing1": {
    "title": "Choose Your Plan",
    "subtitle": "Select the perfect plan for your needs",
    "choosePlan": "Choose Plan",
    "loading": "Loading plans...",
    "error": "Failed to load plans. Please try again.",
    "retry": "Retry",
    "empty": "No plans available at the moment.",
    "perMonth": "/month",
    "perYear": "/year",
    "oneTime": "One-time"
  }
}
```

### Example: `landing1/locales/de.json`

```json
{
  "landing1": {
    "title": "Wählen Sie Ihren Plan",
    "subtitle": "Wählen Sie den perfekten Plan für Ihre Bedürfnisse",
    "choosePlan": "Plan wählen",
    "loading": "Pläne werden geladen...",
    "error": "Pläne konnten nicht geladen werden. Bitte versuchen Sie es erneut.",
    "retry": "Erneut versuchen",
    "empty": "Derzeit sind keine Pläne verfügbar.",
    "perMonth": "/Monat",
    "perYear": "/Jahr",
    "oneTime": "Einmalig"
  }
}
```

**Same pattern for all 5 plugins — extract their namespace keys from the global files.**

---

## Task 4: Update Plugin Install Hooks

### Files
| Plugin | File | Action |
|--------|------|--------|
| landing1 | `user/plugins/landing1/index.ts` | **MODIFY** |
| checkout | `user/plugins/checkout/index.ts` | **MODIFY** |
| stripe-payment | `user/plugins/stripe-payment/index.ts` | **MODIFY** |
| paypal-payment | `user/plugins/paypal-payment/index.ts` | **MODIFY** |
| yookassa-payment | `user/plugins/yookassa-payment/index.ts` | **MODIFY** |

### Example: landing1 Plugin

```typescript
import type { IPlugin, IPlatformSDK } from '@vbwd/view-component';
import en from './locales/en.json';
import de from './locales/de.json';

export const landing1Plugin: IPlugin = {
  name: 'landing1',
  version: '1.0.0',
  description: 'Public landing page with tariff plan selection',
  _active: false,

  install(sdk: IPlatformSDK) {
    // Register route (existing)
    sdk.addRoute({
      path: '/landing1',
      name: 'landing1',
      component: () => import('./Landing1View.vue'),
      meta: { requiresAuth: false }
    });

    // NEW: Register translations
    sdk.addTranslations('en', en);
    sdk.addTranslations('de', de);
  },

  activate() { this._active = true; },
  deactivate() { this._active = false; }
};
```

**Same pattern for all 5 plugins.** Each imports its own `locales/en.json` and `locales/de.json` and calls `sdk.addTranslations()` during install.

---

## Task 5: Trim Global Locale Files

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/vue/src/i18n/locales/en.json` | **MODIFY** — remove plugin keys |
| `vbwd-frontend/user/vue/src/i18n/locales/de.json` | **MODIFY** — remove plugin keys |

### Keys to Remove

Remove the following top-level keys from both `en.json` and `de.json`:

- `landing1` (all keys — moved to `landing1/locales/`)
- `checkout` (all keys — moved to `checkout/locales/`)
- `stripe` (all keys — moved to `stripe-payment/locales/`)
- `paypal` (all keys — moved to `paypal-payment/locales/`)
- `yookassa` (all keys — moved to `yookassa-payment/locales/`)

### Keys That Stay

These are NOT plugin-specific — they're core app translations:

- `common` — shared labels (loading, save, cancel, etc.)
- `nav` — sidebar navigation
- `dashboard` — dashboard view
- `profile` — profile view
- `subscription` — subscription management
- `plans` — plan listing (authenticated)
- `tokens` — token bundles
- `addons` — add-ons
- `invoices` — invoice management
- `login` — login page
- `components` — shared UI components
- `planDetail` — plan detail view
- `tokenBundleDetail` — token bundle detail
- `addonInfo` — add-on info
- `notFound` — 404 page

---

## Task 6: Update main.ts — Pass i18n to PlatformSDK

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/vue/src/main.ts` | **MODIFY** |

### Changes

Pass the `i18n` instance to `PlatformSDK` constructor:

```typescript
// BEFORE:
const sdk = new PlatformSDK();

// AFTER:
import { i18n } from './i18n';
const sdk = new PlatformSDK(i18n);
```

This is a one-line change in the bootstrap function. The i18n instance is already created before plugin initialization.

---

## Task 7: Tests

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/core/tests/plugins/PlatformSDK.spec.ts` | **MODIFY** — add translation tests |
| `vbwd-frontend/core/tests/utils/deep-merge.spec.ts` | **NEW** |
| `vbwd-frontend/user/vue/tests/unit/plugins/plugin-i18n.spec.ts` | **NEW** |

### PlatformSDK Translation Tests (~8 tests)

Add to existing `PlatformSDK.spec.ts`:

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_addTranslations_stores_messages` | `sdk.getTranslations()['en']` contains added messages |
| 2 | `test_addTranslations_multiple_locales` | EN and DE both stored |
| 3 | `test_addTranslations_deep_merges` | Two calls with nested keys merge correctly |
| 4 | `test_addTranslations_no_overwrite_existing` | Adding `{ a: { b: 1 } }` then `{ a: { c: 2 } }` preserves both `b` and `c` |
| 5 | `test_addTranslations_calls_i18n_merge` | `i18n.global.mergeLocaleMessage` called with correct args |
| 6 | `test_addTranslations_works_without_i18n` | No error when i18n not provided (collects only) |
| 7 | `test_getTranslations_returns_copy` | Mutating returned object doesn't affect internal state |
| 8 | `test_constructor_accepts_i18n` | `new PlatformSDK(mockI18n)` stores instance |

### Deep Merge Tests (~8 tests)

New file `core/tests/utils/deep-merge.spec.ts`:

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_merges_flat_objects` | `{ a: 1 }` + `{ b: 2 }` → `{ a: 1, b: 2 }` |
| 2 | `test_deep_merges_nested` | `{ a: { b: 1 } }` + `{ a: { c: 2 } }` → `{ a: { b: 1, c: 2 } }` |
| 3 | `test_source_overrides_target` | `{ a: 1 }` + `{ a: 2 }` → `{ a: 2 }` |
| 4 | `test_arrays_replaced_not_merged` | `{ a: [1] }` + `{ a: [2, 3] }` → `{ a: [2, 3] }` |
| 5 | `test_handles_empty_source` | `{ a: 1 }` + `{}` → `{ a: 1 }` |
| 6 | `test_handles_empty_target` | `{}` + `{ a: 1 }` → `{ a: 1 }` |
| 7 | `test_does_not_mutate_inputs` | Original objects unchanged after merge |
| 8 | `test_three_levels_deep` | Nested 3 levels deep merges correctly |

### Plugin i18n Integration Tests (~10 tests)

New file `user/vue/tests/unit/plugins/plugin-i18n.spec.ts`:

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_landing1_provides_en_translations` | Plugin install adds `landing1.*` keys to EN |
| 2 | `test_landing1_provides_de_translations` | Plugin install adds `landing1.*` keys to DE |
| 3 | `test_checkout_provides_translations` | Checkout plugin adds `checkout.*` keys |
| 4 | `test_stripe_provides_translations` | Stripe plugin adds `stripe.*` keys |
| 5 | `test_paypal_provides_translations` | PayPal plugin adds `paypal.*` keys |
| 6 | `test_yookassa_provides_translations` | YooKassa plugin adds `yookassa.*` keys |
| 7 | `test_translations_available_after_install` | After `installAll()`, `$t('landing1.title')` resolves |
| 8 | `test_global_locale_no_plugin_keys` | Global `en.json` does NOT contain `landing1`, `checkout`, etc. |
| 9 | `test_multiple_plugins_no_collision` | Installing landing1 + checkout doesn't overwrite each other's keys |
| 10 | `test_plugin_without_translations_works` | Plugin without `addTranslations` call installs without error |

**Test targets:**
- Core: 300 → ~316 (+16: 8 SDK + 8 deep-merge)
- User: 185 → ~195 (+10: plugin i18n integration)
- Admin: 331 → 331 (0 — no changes)

---

## Implementation Order & Dependencies

```
Task 1: Extend core interfaces (types.ts) — no deps
  ↓
Task 2: Extend PlatformSDK + deep-merge utility (deps: Task 1)
  ↓
Task 3: Create per-plugin locale files (no deps — can run parallel with Task 2)
  ↓
Task 4: Update plugin install hooks (deps: Tasks 2, 3)
  ↓
Task 5: Trim global locale files (deps: Task 4 — must verify translations still work)
  ↓
Task 6: Update main.ts — pass i18n to SDK (deps: Task 2)
  ↓
Task 7: Tests (deps: all above)
```

---

## New Files Summary

**Per-plugin locale files (10 files):**
```
user/plugins/landing1/locales/en.json
user/plugins/landing1/locales/de.json
user/plugins/checkout/locales/en.json
user/plugins/checkout/locales/de.json
user/plugins/stripe-payment/locales/en.json
user/plugins/stripe-payment/locales/de.json
user/plugins/paypal-payment/locales/en.json
user/plugins/paypal-payment/locales/de.json
user/plugins/yookassa-payment/locales/en.json
user/plugins/yookassa-payment/locales/de.json
```

**Core utility (1 file):**
```
core/src/utils/deep-merge.ts
```

**Tests (2 new files + 1 modified):**
```
core/tests/utils/deep-merge.spec.ts            ← NEW
user/vue/tests/unit/plugins/plugin-i18n.spec.ts ← NEW
core/tests/plugins/PlatformSDK.spec.ts          ← MODIFY (add translation tests)
```

**Modified files (9):**
- `core/src/plugins/types.ts` — add `translations` to `IPlugin`, `addTranslations` to `IPlatformSDK`
- `core/src/plugins/PlatformSDK.ts` — implement `addTranslations()`, accept i18n in constructor
- `user/plugins/landing1/index.ts` — call `sdk.addTranslations()`
- `user/plugins/checkout/index.ts` — call `sdk.addTranslations()`
- `user/plugins/stripe-payment/index.ts` — call `sdk.addTranslations()`
- `user/plugins/paypal-payment/index.ts` — call `sdk.addTranslations()`
- `user/plugins/yookassa-payment/index.ts` — call `sdk.addTranslations()`
- `user/vue/src/i18n/locales/en.json` — remove plugin keys
- `user/vue/src/i18n/locales/de.json` — remove plugin keys
- `user/vue/src/main.ts` — pass `i18n` to `PlatformSDK`

---

## Test Targets

| Suite | Before | After | Delta |
|-------|--------|-------|-------|
| Core | 300 | ~316 | +16 (SDK translations + deep-merge) |
| User | 185 | ~195 | +10 (plugin i18n integration) |
| Admin | 331 | 331 | 0 (no changes) |
| Backend | 849 | 849 | 0 (no changes) |
| **Total** | **1665** | **~1691** | **+26** |

## Verification Commands

```bash
# 1. Core tests (new SDK methods + deep-merge)
cd vbwd-frontend/core && npx vitest run

# 2. User frontend tests (plugin translations)
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# 3. Admin regression
cd vbwd-frontend/admin/vue && npx vitest run

# 4. Rebuild containers
cd vbwd-frontend && docker compose up -d --build user-app

# 5. Manual verification — landing1 still renders translated text
# Open http://localhost:8080/landing1 — titles and labels should display correctly

# 6. Manual verification — switch locale
# Set localStorage 'user_locale' to 'de', reload — German text should appear

# 7. Verify global locale files no longer have plugin keys
# grep -c '"landing1"' user/vue/src/i18n/locales/en.json
# Expected: 0
```
