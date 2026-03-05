# Sprint 28 Report: Plugin i18n System

## Summary

Extended the plugin system so each plugin can bundle its own i18n translations. Translations are merged into vue-i18n at install time via `sdk.addTranslations(locale, messages)`. Removed plugin-specific keys from the global locale files (en.json/de.json) and moved them into per-plugin `locales/` directories.

## Changes

### Core Library (`vbwd-frontend/core/`)

| File | Change |
|------|--------|
| `src/plugins/types.ts` | Added `translations?` to `IPlugin`, `addTranslations()`/`getTranslations()` to `IPlatformSDK` |
| `src/plugins/PlatformSDK.ts` | Added i18n constructor param, `addTranslations()` merges into vue-i18n via `mergeLocaleMessage()`, `getTranslations()` returns collected map |
| `src/utils/deep-merge.ts` | New utility for recursive object merge (arrays/primitives replaced, plain objects merged) |
| `src/index.ts` | Re-exported `deepMerge` |

### User Plugins (`vbwd-frontend/user/plugins/`)

| Plugin | Files Added |
|--------|------------|
| landing1 | `locales/en.json`, `locales/de.json` |
| checkout | `locales/en.json`, `locales/de.json` |
| stripe-payment | `locales/en.json`, `locales/de.json` |
| paypal-payment | `locales/en.json`, `locales/de.json` |
| yookassa-payment | `locales/en.json`, `locales/de.json` |

Each plugin's `index.ts` updated to import locales and call `sdk.addTranslations('en', en)` / `sdk.addTranslations('de', de)` in `install()`.

### Global Locale Files

| File | Change |
|------|--------|
| `user/vue/src/i18n/locales/en.json` | Removed `landing1`, `checkout`, `stripe`, `paypal`, `yookassa` top-level keys |
| `user/vue/src/i18n/locales/de.json` | Same removals |

### Entry Point

| File | Change |
|------|--------|
| `user/vue/src/main.ts` | Changed `new PlatformSDK()` to `new PlatformSDK(i18n)` |

## Tests Added

| File | Tests | Description |
|------|-------|-------------|
| `core/tests/utils/deep-merge.spec.ts` | 8 | Deep merge utility (nested, arrays, edge cases) |
| `core/tests/unit/plugins/PlatformSDKTranslations.spec.ts` | 8 | SDK addTranslations/getTranslations, i18n merging |
| `user/vue/tests/unit/plugins/plugin-i18n.spec.ts` | 10 | End-to-end plugin i18n (all 5 plugins, locale keys verified) |

**Total new tests: 26**

## Test Results

| Suite | Before | After |
|-------|--------|-------|
| Core | 300 | 316 (+16) |
| User | 210 | 220 (+10) |
| Admin | 331 | 331 |

## Key Decisions

1. **Collect-only mode**: PlatformSDK works without i18n instance (stores translations internally). This enables testing without a real vue-i18n setup.
2. **Deep merge**: Plugin translations that share namespace keys are merged recursively, not overwritten.
3. **No lazy loading**: All plugin translations are loaded eagerly at install time. Sufficient for current scale (~30 keys per plugin).
