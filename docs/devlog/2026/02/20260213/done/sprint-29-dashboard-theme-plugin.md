# Sprint 29: Dashboard Color Theme Plugin

## Goal

Create a user frontend plugin that lets users switch the dashboard color theme. The plugin provides preset color themes (default blue, dark, forest green, ocean, sunset) and persists the user's choice in localStorage. It leverages CSS custom properties already defined in `core/src/styles/variables.css` and overrides the hardcoded colors in the user app's layout and views.

## Engineering Principles

- **TDD**: Tests first — write failing tests for theme store, theme provider, theme preset application, and plugin lifecycle before implementation
- **SOLID — SRP**: Theme store manages state + persistence. Theme provider applies CSS variables to DOM. Plugin registers the store and UI. Each has one job
- **SOLID — OCP**: Adding a new theme preset requires only adding an entry to the theme presets array — no modifications to the store, provider, or UI components
- **SOLID — DIP**: Components depend on the theme store abstraction (Pinia), not on direct DOM manipulation or localStorage access
- **SOLID — LSP**: All theme presets conform to the same `ThemePreset` interface — any preset can be applied interchangeably
- **Liskov Substitution**: The theme plugin follows the same `IPlugin` interface as all other plugins — install, activate, deactivate lifecycle is identical
- **DI**: Theme presets are injected as data, not hardcoded in the provider. The store accepts an initial theme from config
- **Clean Code**: Self-documenting names (`applyTheme`, `ThemePreset`, `ThemeProvider`). No magic color values — all named constants
- **DRY**: CSS variables are the single source of truth for colors. Theme presets define only the variables that differ from default. No duplication of color values across components
- **No overengineering**: No server-side theme persistence (localStorage is sufficient for MVP). No custom color picker (presets only). No CSS-in-JS runtime — pure CSS custom properties

## Testing Approach

All tests MUST pass before the sprint is considered complete. Run via:

```bash
# 1. User frontend tests (theme plugin)
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# 2. Core regression (no core changes expected)
cd vbwd-frontend/core && npx vitest run

# 3. Admin regression (no admin code changes expected)
cd vbwd-frontend/admin/vue && npx vitest run

# 4. Full pre-commit check
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --user --unit
```

---

## Architecture

### Current State (Problem)

The user app's dashboard uses **hardcoded hex colors** throughout:

| Element | Color | Location |
|---------|-------|----------|
| Sidebar background | `#2c3e50` | `UserLayout.vue` |
| Primary accent | `#3498db` | `Profile.vue`, buttons, links |
| Button hover | `#2980b9` | Multiple views |
| Page background | `#f5f5f5` | `App.vue`, `UserLayout.vue` |
| Card background | `#ffffff` | `Dashboard.vue`, all views |
| Text headings | `#2c3e50` | Multiple views |
| Success green | `#27ae60` | Status badges |
| Error red | `#e74c3c` | Error messages |

The core library defines CSS variables (`--vbwd-color-primary`, etc.) and even a `.dark` class, but the user app **does not use them** — it uses hardcoded colors.

### Target State (Solution)

1. **Refactor user app to use CSS custom properties** — replace hardcoded hex colors with CSS variables
2. **Create theme plugin** that defines preset themes and applies them by setting CSS variables on `:root`
3. **Add theme selector UI** — a simple dropdown/card grid in a new "Appearance" section accessible from the user profile or sidebar

```
Theme Plugin Architecture
┌─────────────────────────────────────────┐
│ theme-switcher plugin                    │
│                                          │
│ ┌──────────────┐  ┌───────────────────┐ │
│ │ Theme Store   │  │ Theme Presets     │ │
│ │ (Pinia)       │  │                   │ │
│ │               │  │ default (blue)    │ │
│ │ currentTheme  │  │ dark              │ │
│ │ setTheme()    │  │ forest            │ │
│ │ initTheme()   │  │ ocean             │ │
│ │               │  │ sunset            │ │
│ └──────┬───────┘  └───────────────────┘ │
│        │                                 │
│        ▼                                 │
│ ┌──────────────────┐                     │
│ │ applyTheme()     │                     │
│ │ Sets CSS vars    │                     │
│ │ on :root element │                     │
│ └──────────────────┘                     │
│                                          │
│ ┌──────────────────┐                     │
│ │ ThemeSelector.vue │                     │
│ │ Card grid with   │                     │
│ │ theme previews   │                     │
│ └──────────────────┘                     │
└─────────────────────────────────────────┘
```

### CSS Variable Strategy

Replace hardcoded colors with CSS custom properties. The theme plugin sets these on `document.documentElement.style`:

```css
:root {
  /* Layout */
  --vbwd-sidebar-bg: #2c3e50;
  --vbwd-sidebar-text: rgba(255, 255, 255, 0.8);
  --vbwd-sidebar-active-bg: rgba(255, 255, 255, 0.1);
  --vbwd-page-bg: #f5f5f5;
  --vbwd-card-bg: #ffffff;

  /* Brand */
  --vbwd-color-primary: #3498db;
  --vbwd-color-primary-hover: #2980b9;

  /* Text */
  --vbwd-text-heading: #2c3e50;
  --vbwd-text-body: #333;
  --vbwd-text-muted: #666;

  /* Status */
  --vbwd-color-success: #27ae60;
  --vbwd-color-danger: #e74c3c;
  --vbwd-color-warning: #f39c12;

  /* Borders */
  --vbwd-border-color: #ddd;
  --vbwd-border-light: #eee;

  /* Shadows */
  --vbwd-card-shadow: 0 2px 5px rgba(0, 0, 0, 0.05);
}
```

---

## What Already Exists (referenced but not modified)

| File | Provides |
|------|----------|
| `core/src/styles/variables.css` | CSS variables with `.dark` class (core library — NOT used by user app currently) |
| `user/plugins/plugins.json` | Plugin registry (will add theme-switcher entry) |
| `core/src/plugins/PlatformSDK.ts` | `createStore()` for Pinia store creation |

---

## What This Sprint Adds

| Layer | File | Provides |
|-------|------|----------|
| Plugin | `user/plugins/theme-switcher/index.ts` | Plugin entry — registers store, route, translations |
| Plugin | `user/plugins/theme-switcher/presets.ts` | Theme preset definitions (5 themes) |
| Plugin | `user/plugins/theme-switcher/apply-theme.ts` | DOM utility — sets CSS variables on `:root` |
| Plugin | `user/plugins/theme-switcher/ThemeSelectorView.vue` | Theme selection page with preview cards |
| Plugin | `user/plugins/theme-switcher/locales/en.json` | EN translations |
| Plugin | `user/plugins/theme-switcher/locales/de.json` | DE translations |
| Plugin | `user/plugins/theme-switcher/config.json` | Plugin config schema |
| Plugin | `user/plugins/theme-switcher/admin-config.json` | Admin config UI |
| User | `user/vue/src/layouts/UserLayout.vue` | **MODIFY** — replace hardcoded colors with CSS vars |
| User | `user/vue/src/App.vue` | **MODIFY** — replace hardcoded colors with CSS vars |
| User | `user/vue/src/views/Dashboard.vue` | **MODIFY** — replace hardcoded colors with CSS vars |
| User | `user/vue/src/views/Profile.vue` | **MODIFY** — replace hardcoded colors with CSS vars |
| User | `user/vue/src/main.ts` | **MODIFY** — add theme-switcher to available plugins |
| User | `user/plugins/plugins.json` | **MODIFY** — add theme-switcher entry |

---

## Task 1: Theme Presets

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/plugins/theme-switcher/presets.ts` | **NEW** |

### Interface

```typescript
export interface ThemePreset {
  id: string;
  name: string;        // Display name (i18n key)
  description: string; // Description (i18n key)
  colors: Record<string, string>;  // CSS variable → value
  preview: {           // Preview colors for the selector card
    sidebar: string;
    primary: string;
    background: string;
    card: string;
    text: string;
  };
}
```

### Presets

```typescript
export const themePresets: ThemePreset[] = [
  {
    id: 'default',
    name: 'theme.presets.default.name',
    description: 'theme.presets.default.description',
    colors: {
      '--vbwd-sidebar-bg': '#2c3e50',
      '--vbwd-sidebar-text': 'rgba(255, 255, 255, 0.8)',
      '--vbwd-sidebar-active-bg': 'rgba(255, 255, 255, 0.1)',
      '--vbwd-page-bg': '#f5f5f5',
      '--vbwd-card-bg': '#ffffff',
      '--vbwd-color-primary': '#3498db',
      '--vbwd-color-primary-hover': '#2980b9',
      '--vbwd-text-heading': '#2c3e50',
      '--vbwd-text-body': '#333333',
      '--vbwd-text-muted': '#666666',
      '--vbwd-color-success': '#27ae60',
      '--vbwd-color-danger': '#e74c3c',
      '--vbwd-color-warning': '#f39c12',
      '--vbwd-border-color': '#dddddd',
      '--vbwd-border-light': '#eeeeee',
      '--vbwd-card-shadow': '0 2px 5px rgba(0, 0, 0, 0.05)',
    },
    preview: {
      sidebar: '#2c3e50',
      primary: '#3498db',
      background: '#f5f5f5',
      card: '#ffffff',
      text: '#333333',
    }
  },
  {
    id: 'dark',
    name: 'theme.presets.dark.name',
    description: 'theme.presets.dark.description',
    colors: {
      '--vbwd-sidebar-bg': '#1a1a2e',
      '--vbwd-sidebar-text': 'rgba(255, 255, 255, 0.7)',
      '--vbwd-sidebar-active-bg': 'rgba(255, 255, 255, 0.08)',
      '--vbwd-page-bg': '#16213e',
      '--vbwd-card-bg': '#1a1a2e',
      '--vbwd-color-primary': '#60a5fa',
      '--vbwd-color-primary-hover': '#3b82f6',
      '--vbwd-text-heading': '#f3f4f6',
      '--vbwd-text-body': '#d1d5db',
      '--vbwd-text-muted': '#9ca3af',
      '--vbwd-color-success': '#34d399',
      '--vbwd-color-danger': '#f87171',
      '--vbwd-color-warning': '#fbbf24',
      '--vbwd-border-color': '#374151',
      '--vbwd-border-light': '#2d3748',
      '--vbwd-card-shadow': '0 2px 5px rgba(0, 0, 0, 0.3)',
    },
    preview: {
      sidebar: '#1a1a2e',
      primary: '#60a5fa',
      background: '#16213e',
      card: '#1a1a2e',
      text: '#d1d5db',
    }
  },
  {
    id: 'forest',
    name: 'theme.presets.forest.name',
    description: 'theme.presets.forest.description',
    colors: {
      '--vbwd-sidebar-bg': '#1b4332',
      '--vbwd-sidebar-text': 'rgba(255, 255, 255, 0.8)',
      '--vbwd-sidebar-active-bg': 'rgba(255, 255, 255, 0.1)',
      '--vbwd-page-bg': '#f0fdf4',
      '--vbwd-card-bg': '#ffffff',
      '--vbwd-color-primary': '#059669',
      '--vbwd-color-primary-hover': '#047857',
      '--vbwd-text-heading': '#1b4332',
      '--vbwd-text-body': '#374151',
      '--vbwd-text-muted': '#6b7280',
      '--vbwd-color-success': '#10b981',
      '--vbwd-color-danger': '#ef4444',
      '--vbwd-color-warning': '#f59e0b',
      '--vbwd-border-color': '#d1d5db',
      '--vbwd-border-light': '#e5e7eb',
      '--vbwd-card-shadow': '0 2px 5px rgba(0, 0, 0, 0.05)',
    },
    preview: {
      sidebar: '#1b4332',
      primary: '#059669',
      background: '#f0fdf4',
      card: '#ffffff',
      text: '#374151',
    }
  },
  {
    id: 'ocean',
    name: 'theme.presets.ocean.name',
    description: 'theme.presets.ocean.description',
    colors: {
      '--vbwd-sidebar-bg': '#0c4a6e',
      '--vbwd-sidebar-text': 'rgba(255, 255, 255, 0.8)',
      '--vbwd-sidebar-active-bg': 'rgba(255, 255, 255, 0.1)',
      '--vbwd-page-bg': '#f0f9ff',
      '--vbwd-card-bg': '#ffffff',
      '--vbwd-color-primary': '#0284c7',
      '--vbwd-color-primary-hover': '#0369a1',
      '--vbwd-text-heading': '#0c4a6e',
      '--vbwd-text-body': '#334155',
      '--vbwd-text-muted': '#64748b',
      '--vbwd-color-success': '#22c55e',
      '--vbwd-color-danger': '#ef4444',
      '--vbwd-color-warning': '#eab308',
      '--vbwd-border-color': '#cbd5e1',
      '--vbwd-border-light': '#e2e8f0',
      '--vbwd-card-shadow': '0 2px 5px rgba(0, 0, 0, 0.05)',
    },
    preview: {
      sidebar: '#0c4a6e',
      primary: '#0284c7',
      background: '#f0f9ff',
      card: '#ffffff',
      text: '#334155',
    }
  },
  {
    id: 'sunset',
    name: 'theme.presets.sunset.name',
    description: 'theme.presets.sunset.description',
    colors: {
      '--vbwd-sidebar-bg': '#7c2d12',
      '--vbwd-sidebar-text': 'rgba(255, 255, 255, 0.8)',
      '--vbwd-sidebar-active-bg': 'rgba(255, 255, 255, 0.1)',
      '--vbwd-page-bg': '#fff7ed',
      '--vbwd-card-bg': '#ffffff',
      '--vbwd-color-primary': '#ea580c',
      '--vbwd-color-primary-hover': '#c2410c',
      '--vbwd-text-heading': '#7c2d12',
      '--vbwd-text-body': '#44403c',
      '--vbwd-text-muted': '#78716c',
      '--vbwd-color-success': '#16a34a',
      '--vbwd-color-danger': '#dc2626',
      '--vbwd-color-warning': '#d97706',
      '--vbwd-border-color': '#d6d3d1',
      '--vbwd-border-light': '#e7e5e4',
      '--vbwd-card-shadow': '0 2px 5px rgba(0, 0, 0, 0.05)',
    },
    preview: {
      sidebar: '#7c2d12',
      primary: '#ea580c',
      background: '#fff7ed',
      card: '#ffffff',
      text: '#44403c',
    }
  }
];
```

---

## Task 2: Theme Application Utility

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/plugins/theme-switcher/apply-theme.ts` | **NEW** |

### Implementation

```typescript
import type { ThemePreset } from './presets';

/**
 * Apply a theme preset by setting CSS custom properties on :root.
 * Pure function with DOM side effect — easy to test by mocking document.
 */
export function applyTheme(preset: ThemePreset): void {
  const root = document.documentElement;
  for (const [property, value] of Object.entries(preset.colors)) {
    root.style.setProperty(property, value);
  }
}

/**
 * Remove all theme CSS custom properties (reset to stylesheet defaults).
 */
export function clearTheme(preset: ThemePreset): void {
  const root = document.documentElement;
  for (const property of Object.keys(preset.colors)) {
    root.style.removeProperty(property);
  }
}
```

---

## Task 3: Refactor User App — Replace Hardcoded Colors with CSS Variables

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/vue/src/App.vue` | **MODIFY** |
| `vbwd-frontend/user/vue/src/layouts/UserLayout.vue` | **MODIFY** |
| `vbwd-frontend/user/vue/src/views/Dashboard.vue` | **MODIFY** |
| `vbwd-frontend/user/vue/src/views/Profile.vue` | **MODIFY** |

### Strategy

Replace hardcoded hex colors with CSS variables. The variables have **fallback values** matching the current defaults, so the app looks identical without the theme plugin:

```css
/* BEFORE */
.sidebar {
  background-color: #2c3e50;
  color: white;
}

/* AFTER */
.sidebar {
  background-color: var(--vbwd-sidebar-bg, #2c3e50);
  color: var(--vbwd-sidebar-text, rgba(255, 255, 255, 0.8));
}
```

### App.vue Changes

```css
/* BEFORE */
body {
  background-color: #f5f5f5;
  color: #333;
}

/* AFTER */
body {
  background-color: var(--vbwd-page-bg, #f5f5f5);
  color: var(--vbwd-text-body, #333);
}
```

### UserLayout.vue Changes

```css
/* Replace in .sidebar */
background-color: #2c3e50;    → var(--vbwd-sidebar-bg, #2c3e50)
color: white;                 → var(--vbwd-sidebar-text, rgba(255, 255, 255, 0.8))

/* Replace in .nav-item */
color: rgba(255, 255, 255, 0.8); → var(--vbwd-sidebar-text, rgba(255, 255, 255, 0.8))

/* Replace in .nav-item.router-link-active */
background-color: rgba(255, 255, 255, 0.1); → var(--vbwd-sidebar-active-bg, rgba(255, 255, 255, 0.1))

/* Replace in .main-content */
background-color: #f5f5f5;    → var(--vbwd-page-bg, #f5f5f5)
```

### Dashboard.vue Changes

```css
/* Replace in .card */
background: white;            → var(--vbwd-card-bg, #ffffff)
box-shadow: 0 2px 5px ...;   → var(--vbwd-card-shadow, 0 2px 5px rgba(0, 0, 0, 0.05))

/* Replace in .card h3 */
color: #2c3e50;               → var(--vbwd-text-heading, #2c3e50)
border-bottom: 1px solid #eee; → 1px solid var(--vbwd-border-light, #eee)
```

### Profile.vue Changes

```css
/* Replace in .btn.primary */
background-color: #3498db;    → var(--vbwd-color-primary, #3498db)

/* Replace in .btn.primary:hover */
background-color: #2980b9;    → var(--vbwd-color-primary-hover, #2980b9)

/* Replace in input:focus */
border-color: #3498db;        → var(--vbwd-color-primary, #3498db)
box-shadow: 0 0 0 3px rgba(52, 152, 219, 0.2); → 0 0 0 3px color-mix(in srgb, var(--vbwd-color-primary, #3498db) 20%, transparent)
```

**Important**: All replacements use CSS `var()` with the current hardcoded value as fallback — visually identical without the theme plugin active.

---

## Task 4: Theme Selector View

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/plugins/theme-switcher/ThemeSelectorView.vue` | **NEW** |

### Component Design

A page showing theme preset cards in a grid. Each card shows a mini-preview of the theme colors and the theme name. Clicking a card applies the theme instantly.

```html
<template>
  <div class="theme-selector">
    <h2>{{ $t('theme.title') }}</h2>
    <p class="theme-subtitle">{{ $t('theme.subtitle') }}</p>

    <div class="theme-grid">
      <div
        v-for="preset in presets"
        :key="preset.id"
        class="theme-card"
        :class="{ 'theme-card--active': currentTheme === preset.id }"
        @click="selectTheme(preset.id)"
        :data-testid="`theme-${preset.id}`"
      >
        <!-- Mini preview -->
        <div class="theme-preview">
          <div class="preview-sidebar" :style="{ backgroundColor: preset.preview.sidebar }"></div>
          <div class="preview-content" :style="{ backgroundColor: preset.preview.background }">
            <div class="preview-card" :style="{ backgroundColor: preset.preview.card }">
              <div class="preview-heading" :style="{ backgroundColor: preset.preview.primary }"></div>
              <div class="preview-text" :style="{ backgroundColor: preset.preview.text }"></div>
              <div class="preview-text short" :style="{ backgroundColor: preset.preview.text }"></div>
            </div>
          </div>
        </div>

        <!-- Theme info -->
        <div class="theme-info">
          <span class="theme-name">{{ $t(preset.name) }}</span>
          <span v-if="currentTheme === preset.id" class="theme-active-badge">
            {{ $t('theme.active') }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { themePresets } from './presets';
import { applyTheme } from './apply-theme';

const STORAGE_KEY = 'vbwd_theme';

const presets = themePresets;

const currentTheme = computed(() => {
  return localStorage.getItem(STORAGE_KEY) || 'default';
});

function selectTheme(themeId: string) {
  const preset = presets.find(p => p.id === themeId);
  if (!preset) return;

  applyTheme(preset);
  localStorage.setItem(STORAGE_KEY, themeId);
}
</script>
```

### Styles

```css
.theme-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: 20px;
  margin-top: 20px;
}

.theme-card {
  border: 2px solid var(--vbwd-border-color, #ddd);
  border-radius: 8px;
  overflow: hidden;
  cursor: pointer;
  transition: all 0.2s;
}

.theme-card:hover {
  border-color: var(--vbwd-color-primary, #3498db);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.theme-card--active {
  border-color: var(--vbwd-color-primary, #3498db);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--vbwd-color-primary, #3498db) 20%, transparent);
}

.theme-preview {
  display: flex;
  height: 120px;
}

.preview-sidebar {
  width: 30%;
}

.preview-content {
  width: 70%;
  padding: 8px;
  display: flex;
  align-items: flex-start;
}

.preview-card {
  width: 100%;
  padding: 6px;
  border-radius: 4px;
}

.preview-heading {
  height: 6px;
  width: 50%;
  border-radius: 3px;
  margin-bottom: 4px;
  opacity: 0.8;
}

.preview-text {
  height: 4px;
  width: 80%;
  border-radius: 2px;
  margin-bottom: 3px;
  opacity: 0.3;
}

.preview-text.short {
  width: 50%;
}

.theme-info {
  padding: 12px;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.theme-active-badge {
  font-size: 0.75rem;
  padding: 2px 8px;
  background: var(--vbwd-color-primary, #3498db);
  color: white;
  border-radius: 12px;
}
```

---

## Task 5: Plugin Entry + Registration

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/plugins/theme-switcher/index.ts` | **NEW** |
| `vbwd-frontend/user/vue/src/main.ts` | **MODIFY** |
| `vbwd-frontend/user/plugins/plugins.json` | **MODIFY** |

### Plugin Entry

```typescript
import type { IPlugin, IPlatformSDK } from '@vbwd/view-component';
import { themePresets } from './presets';
import { applyTheme } from './apply-theme';

// Import translations (if Sprint 28 is done, use sdk.addTranslations;
// otherwise import directly — both approaches shown)
import en from './locales/en.json';
import de from './locales/de.json';

const STORAGE_KEY = 'vbwd_theme';

export const themeSwitcherPlugin: IPlugin = {
  name: 'theme-switcher',
  version: '1.0.0',
  description: 'Dashboard color theme selector with preset themes',
  _active: false,

  install(sdk: IPlatformSDK) {
    // Register theme selector route (protected — dashboard feature)
    sdk.addRoute({
      path: '/dashboard/appearance',
      name: 'appearance',
      component: () => import('./ThemeSelectorView.vue'),
      meta: { requiresAuth: true }
    });

    // Register translations
    sdk.addTranslations('en', en);
    sdk.addTranslations('de', de);
  },

  activate() {
    this._active = true;
    // Apply saved theme on activation
    const savedThemeId = localStorage.getItem(STORAGE_KEY) || 'default';
    const preset = themePresets.find(p => p.id === savedThemeId);
    if (preset) {
      applyTheme(preset);
    }
  },

  deactivate() {
    this._active = false;
    // Reset to default theme
    const defaultPreset = themePresets.find(p => p.id === 'default');
    if (defaultPreset) {
      applyTheme(defaultPreset);
    }
  }
};
```

### main.ts Changes

```typescript
import { themeSwitcherPlugin } from '../../plugins/theme-switcher';

const availablePlugins: Record<string, IPlugin> = {
  landing1: landing1Plugin,
  checkout: checkoutPlugin,
  'stripe-payment': stripePaymentPlugin,
  'paypal-payment': paypalPaymentPlugin,
  'yookassa-payment': yookassaPaymentPlugin,
  'theme-switcher': themeSwitcherPlugin,  // NEW
};
```

### plugins.json Addition

```json
{
  "theme-switcher": {
    "name": "theme-switcher",
    "version": "1.0.0",
    "description": "Dashboard color theme selector",
    "enabled": true,
    "installed": true
  }
}
```

---

## Task 6: Navigation Link

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/vue/src/layouts/UserLayout.vue` | **MODIFY** (add nav item) |

### Changes

Add an "Appearance" link to the sidebar navigation, after existing items:

```html
<!-- Add after existing nav items -->
<router-link
  v-if="themeSwitcherEnabled"
  to="/dashboard/appearance"
  class="nav-item"
  data-testid="nav-appearance"
>
  {{ $t('nav.appearance') }}
</router-link>
```

The `themeSwitcherEnabled` check uses `inject('pluginRegistry')` to check if the theme-switcher plugin is active — this way the nav item disappears when the plugin is disabled.

```typescript
import { inject, computed } from 'vue';

const pluginRegistry = inject<any>('pluginRegistry');

const themeSwitcherEnabled = computed(() => {
  if (!pluginRegistry) return false;
  const plugin = pluginRegistry.get('theme-switcher');
  return plugin && plugin.status === 'ACTIVE';
});
```

### i18n Key

Add to user app global locale files:

```json
// en.json → nav section
"appearance": "Appearance"

// de.json → nav section
"appearance": "Darstellung"
```

---

## Task 7: Plugin i18n Translations

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/plugins/theme-switcher/locales/en.json` | **NEW** |
| `vbwd-frontend/user/plugins/theme-switcher/locales/de.json` | **NEW** |

### EN Translations

```json
{
  "theme": {
    "title": "Appearance",
    "subtitle": "Choose a color theme for your dashboard",
    "active": "Active",
    "presets": {
      "default": {
        "name": "Default Blue",
        "description": "Classic blue theme with light background"
      },
      "dark": {
        "name": "Dark",
        "description": "Dark theme for reduced eye strain"
      },
      "forest": {
        "name": "Forest Green",
        "description": "Natural green tones inspired by nature"
      },
      "ocean": {
        "name": "Ocean",
        "description": "Deep blue oceanic color palette"
      },
      "sunset": {
        "name": "Sunset",
        "description": "Warm orange and earth tones"
      }
    }
  }
}
```

### DE Translations

```json
{
  "theme": {
    "title": "Darstellung",
    "subtitle": "Wählen Sie ein Farbthema für Ihr Dashboard",
    "active": "Aktiv",
    "presets": {
      "default": {
        "name": "Standard Blau",
        "description": "Klassisches blaues Thema mit hellem Hintergrund"
      },
      "dark": {
        "name": "Dunkel",
        "description": "Dunkles Thema für weniger Augenbelastung"
      },
      "forest": {
        "name": "Waldgrün",
        "description": "Natürliche Grüntöne inspiriert von der Natur"
      },
      "ocean": {
        "name": "Ozean",
        "description": "Tiefblaue ozeanische Farbpalette"
      },
      "sunset": {
        "name": "Sonnenuntergang",
        "description": "Warme Orange- und Erdtöne"
      }
    }
  }
}
```

---

## Task 8: Plugin Config Files

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/plugins/theme-switcher/config.json` | **NEW** |
| `vbwd-frontend/user/plugins/theme-switcher/admin-config.json` | **NEW** |

### config.json

```json
{
  "defaultTheme": {
    "type": "string",
    "default": "default",
    "description": "Default theme applied to new users (default, dark, forest, ocean, sunset)"
  }
}
```

### admin-config.json

```json
{
  "tabs": [
    {
      "id": "general",
      "label": "General",
      "fields": [
        {
          "key": "defaultTheme",
          "label": "Default Theme",
          "component": "select",
          "options": [
            { "value": "default", "label": "Default Blue" },
            { "value": "dark", "label": "Dark" },
            { "value": "forest", "label": "Forest Green" },
            { "value": "ocean", "label": "Ocean" },
            { "value": "sunset", "label": "Sunset" }
          ]
        }
      ]
    }
  ]
}
```

---

## Task 9: Tests

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/vue/tests/unit/plugins/theme-switcher.spec.ts` | **NEW** |
| `vbwd-frontend/user/vue/tests/unit/plugins/theme-presets.spec.ts` | **NEW** |
| `vbwd-frontend/user/vue/tests/unit/plugins/theme-selector.spec.ts` | **NEW** |

### `theme-switcher.spec.ts` — Plugin Lifecycle (~8 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_plugin_name` | `'theme-switcher'` |
| 2 | `test_plugin_version` | `'1.0.0'` |
| 3 | `test_install_adds_route` | `/dashboard/appearance` route registered with `requiresAuth: true` |
| 4 | `test_install_adds_translations` | `sdk.addTranslations` called for `en` and `de` |
| 5 | `test_activate_applies_saved_theme` | localStorage has `'dark'` → `applyTheme` called with dark preset |
| 6 | `test_activate_defaults_to_default` | No localStorage → `applyTheme` called with default preset |
| 7 | `test_deactivate_resets_to_default` | `applyTheme` called with default preset |
| 8 | `test_activate_deactivate_toggles_active` | `_active` toggles |

### `theme-presets.spec.ts` — Preset Data + Apply (~10 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_five_presets_defined` | `themePresets.length === 5` |
| 2 | `test_each_preset_has_id` | All presets have unique `id` |
| 3 | `test_each_preset_has_colors` | All presets have `colors` object |
| 4 | `test_each_preset_has_preview` | All presets have `preview` with 5 color keys |
| 5 | `test_default_preset_sidebar_color` | Default preset sidebar is `#2c3e50` |
| 6 | `test_dark_preset_page_bg` | Dark preset page bg is `#16213e` |
| 7 | `test_applyTheme_sets_css_variables` | After `applyTheme(dark)`, `getPropertyValue('--vbwd-page-bg')` is `#16213e` |
| 8 | `test_applyTheme_sets_all_variables` | All preset color keys set on `:root` |
| 9 | `test_clearTheme_removes_variables` | After `clearTheme()`, variables removed from inline style |
| 10 | `test_preset_colors_consistent_count` | All presets have same number of color entries |

### `theme-selector.spec.ts` — View Component (~8 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_renders_title` | Page title visible |
| 2 | `test_renders_five_theme_cards` | 5 `.theme-card` elements |
| 3 | `test_default_theme_has_active_badge` | Default theme shows "Active" badge |
| 4 | `test_click_theme_applies_it` | Click dark card → `applyTheme` called with dark preset |
| 5 | `test_click_theme_saves_to_localstorage` | `localStorage.setItem('vbwd_theme', 'dark')` |
| 6 | `test_preview_colors_rendered` | Each card has preview with correct sidebar/primary colors |
| 7 | `test_active_card_has_active_class` | Active theme card has `theme-card--active` class |
| 8 | `test_saved_theme_shown_as_active` | localStorage has `'forest'` → forest card is active |

**User frontend test target: 185 → ~211 (+26: 8 lifecycle + 10 presets + 8 selector)**

---

## Implementation Order & Dependencies

```
Task 1: Theme presets (no deps — data only)
Task 2: Apply theme utility (deps: Task 1)
  ↓ (Tasks 1 & 2 can run in parallel)
Task 3: Refactor user app CSS to use variables (no deps — standalone refactoring)
  ↓
Task 4: Theme selector view (deps: Tasks 1, 2)
  ↓
Task 7: Plugin translations (no deps — data only)
  ↓
Task 5: Plugin entry + registration (deps: Tasks 4, 7)
  ↓
Task 6: Navigation link (deps: Task 5)
  ↓
Task 8: Plugin config files (no deps — data only)
  ↓
Task 9: Tests (deps: all above)
```

---

## New Files Summary

```
user/plugins/theme-switcher/
├── index.ts                       ← Plugin entry (route, translations, theme init)
├── presets.ts                     ← 5 theme preset definitions
├── apply-theme.ts                 ← DOM utility for CSS variable application
├── ThemeSelectorView.vue          ← Theme selection page with preview cards
├── locales/
│   ├── en.json                    ← EN translations (theme.*)
│   └── de.json                    ← DE translations (theme.*)
├── config.json                    ← Plugin config schema
└── admin-config.json              ← Admin config UI

user/vue/tests/unit/plugins/
├── theme-switcher.spec.ts         ← Plugin lifecycle tests
├── theme-presets.spec.ts          ← Preset data + apply tests
└── theme-selector.spec.ts         ← View component tests
```

**Modified files:**
- `user/vue/src/App.vue` — replace hardcoded body colors with CSS vars
- `user/vue/src/layouts/UserLayout.vue` — replace hardcoded sidebar/layout colors with CSS vars + add Appearance nav link
- `user/vue/src/views/Dashboard.vue` — replace hardcoded card colors with CSS vars
- `user/vue/src/views/Profile.vue` — replace hardcoded button/input colors with CSS vars
- `user/vue/src/main.ts` — add theme-switcher to available plugins
- `user/plugins/plugins.json` — add theme-switcher entry
- `user/vue/src/i18n/locales/en.json` — add `nav.appearance` key
- `user/vue/src/i18n/locales/de.json` — add `nav.appearance` key

---

## Test Targets

| Suite | Before | After | Delta |
|-------|--------|-------|-------|
| User | 185 | ~211 | +26 (theme lifecycle + presets + selector) |
| Admin | 331 | 331 | 0 (no changes) |
| Core | 300 | 300 | 0 (no changes) |
| Backend | 849 | 849 | 0 (no changes) |
| **Total** | **1665** | **~1691** | **+26** |

## Verification Commands

```bash
# 1. User frontend tests
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# 2. Admin regression
cd vbwd-frontend/admin/vue && npx vitest run

# 3. Core regression
cd vbwd-frontend/core && npx vitest run

# 4. Rebuild containers
cd vbwd-frontend && docker compose up -d --build user-app

# 5. Manual verification — default theme unchanged
# Open http://localhost:8080/dashboard — should look identical to current

# 6. Manual verification — theme selector page
# Navigate to http://localhost:8080/dashboard/appearance
# Should see 5 theme cards with color previews

# 7. Manual verification — apply dark theme
# Click "Dark" card → entire dashboard should switch to dark colors instantly

# 8. Manual verification — persistence
# Refresh page → dark theme should still be active

# 9. Manual verification — default fallback
# Clear localStorage → refresh → default blue theme should appear
```
