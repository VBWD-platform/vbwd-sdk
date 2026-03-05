# Sprint 29 Report: Dashboard Color Theme Plugin

## Summary

Created a new `theme-switcher` user plugin that allows users to change the dashboard color theme. Ships with 5 preset themes (Default Blue, Dark, Forest Green, Ocean, Sunset). Theme selection persists in localStorage and is restored on plugin activation. All existing CSS was refactored to use CSS custom properties with fallbacks, ensuring zero visual regression when the plugin is disabled.

## Changes

### New Plugin (`user/plugins/theme-switcher/`)

| File | Description |
|------|-------------|
| `index.ts` | Plugin entry: registers `/dashboard/appearance` route, adds translations, applies saved theme on activate |
| `presets.ts` | `ThemePreset` interface + 5 preset objects with 16 CSS variable values each + preview colors |
| `apply-theme.ts` | `applyTheme()` sets CSS variables on `document.documentElement`; `clearTheme()` removes them |
| `ThemeSelectorView.vue` | Grid of theme preview cards with miniature sidebar/content/card mockup, active badge, click to apply |
| `locales/en.json` | English translations for theme UI (title, subtitle, active badge, 5 preset names/descriptions) |
| `locales/de.json` | German translations |
| `config.json` | Plugin config schema |
| `admin-config.json` | Admin config UI definition |

### CSS Variable Refactoring

All hardcoded colors in user app views were converted to CSS custom properties with fallbacks:

| File | Variables Introduced |
|------|---------------------|
| `App.vue` | `--vbwd-page-bg`, `--vbwd-text-body` |
| `UserLayout.vue` | `--vbwd-sidebar-bg`, `--vbwd-sidebar-text`, `--vbwd-sidebar-active-bg`, `--vbwd-color-primary`, `--vbwd-color-primary-hover` |
| `Dashboard.vue` | `--vbwd-text-heading`, `--vbwd-card-bg`, `--vbwd-card-shadow`, `--vbwd-border-color`, `--vbwd-border-light`, `--vbwd-color-primary`, `--vbwd-text-muted`, `--vbwd-color-success`, `--vbwd-color-danger` |
| `Profile.vue` | Same variable set for form inputs, cards, headings, buttons, toasts |

### CSS Variables (16 total)

| Variable | Default Value | Purpose |
|----------|---------------|---------|
| `--vbwd-sidebar-bg` | `#2c3e50` | Sidebar background |
| `--vbwd-sidebar-text` | `rgba(255,255,255,0.8)` | Sidebar text |
| `--vbwd-sidebar-active-bg` | `rgba(255,255,255,0.1)` | Sidebar active item |
| `--vbwd-page-bg` | `#f5f5f5` | Page background |
| `--vbwd-card-bg` | `#ffffff` | Card background |
| `--vbwd-color-primary` | `#3498db` | Primary accent |
| `--vbwd-color-primary-hover` | `#2980b9` | Primary hover |
| `--vbwd-text-heading` | `#2c3e50` | Headings |
| `--vbwd-text-body` | `#333333` | Body text |
| `--vbwd-text-muted` | `#666666` | Muted/secondary text |
| `--vbwd-color-success` | `#27ae60` | Success states |
| `--vbwd-color-danger` | `#e74c3c` | Danger/error states |
| `--vbwd-color-warning` | `#f39c12` | Warning states |
| `--vbwd-border-color` | `#dddddd` | Default borders |
| `--vbwd-border-light` | `#eeeeee` | Light borders |
| `--vbwd-card-shadow` | `0 2px 5px rgba(0,0,0,0.05)` | Card shadow |

### Navigation & i18n

| File | Change |
|------|--------|
| `UserLayout.vue` | Added Appearance nav link (`/dashboard/appearance`) |
| `en.json` | Added `nav.appearance: "Appearance"` |
| `de.json` | Added `nav.appearance: "Darstellung"` |
| `main.ts` | Imported and registered `themeSwitcherPlugin` |

## Tests Added

| File | Tests | Description |
|------|-------|-------------|
| `theme-presets.spec.ts` | 21 | Preset data validation (required fields, CSS vars, unique ids, i18n keys) |
| `theme-apply.spec.ts` | 7 | applyTheme/clearTheme DOM manipulation |
| `theme-switcher.spec.ts` | 8 | Full plugin lifecycle (register, install, activate, deactivate, localStorage persistence) |

**Total new tests: 36**

## Test Results

| Suite | Before | After |
|-------|--------|-------|
| Core | 316 | 316 |
| User | 220 | 256 (+36) |
| Admin | 331 | 331 |

## 5 Theme Presets

1. **Default Blue** — Classic light theme with `#2c3e50` sidebar, `#3498db` primary
2. **Dark** — Dark backgrounds (`#1a1a2e`/`#16213e`), blue accents (`#60a5fa`)
3. **Forest Green** — Nature-inspired greens (`#1b4332` sidebar, `#059669` primary)
4. **Ocean** — Deep blue palette (`#0c4a6e` sidebar, `#0284c7` primary)
5. **Sunset** — Warm earth tones (`#7c2d12` sidebar, `#ea580c` primary)
