# Sprint 03: Complete I18n for All Plugins

**Date:** 2026-03-21
**Status:** Planned
**Repos:** All fe-admin and fe-user plugin repos

---

## Problem

The platform supports 8 languages (en, de, es, fr, ja, ru, th, zh) in core apps and most fe-user plugins. However several plugins have incomplete or missing translations:

### Current Status

| Plugin | Repo | Locales | Languages | $t() | Status |
|--------|------|---------|-----------|------|--------|
| **booking** (admin) | fe-admin | Empty | 0 | No | All hardcoded |
| **booking** (user) | fe-user | Empty | 0 | No | All hardcoded |
| **ghrm-admin** | fe-admin | None | 0 | No | All hardcoded |
| **taro-admin** | fe-admin | None | 0 | No | All hardcoded |
| **analytics-widget** | fe-admin | None | 0 | No | All hardcoded |
| **email-admin** | fe-admin | en only | 1 | Partial | Needs 7 languages |
| **cms** (user) | fe-user | en only | 1 | Yes | Needs 7 languages |
| **ghrm** (user) | fe-user | en only | 1 | Yes | Needs 7 languages |
| **cms-admin** | fe-admin | 8 langs | 8 | Yes | Complete |
| **checkout** (user) | fe-user | 8 langs | 8 | Yes | Complete |
| **chat** (user) | fe-user | 8 langs | 8 | Yes | Complete |
| **landing1** (user) | fe-user | 8 langs | 8 | Yes | Complete |
| **stripe-payment** | fe-user | 8 langs | 8 | Yes | Complete |
| **paypal-payment** | fe-user | 8 langs | 8 | Yes | Complete |
| **yookassa-payment** | fe-user | 8 langs | 8 | Yes | Complete |
| **taro** (user) | fe-user | 8 langs | 8 | Yes | Complete |
| **theme-switcher** | fe-user | 8 langs | 8 | Yes | Complete |

### Target

All 17 plugins fully translated in 8 languages, all strings using `$t()`.

---

## Languages

All plugins must support these 8 languages (matching core apps):

| Code | Language |
|------|----------|
| en | English |
| de | German (Deutsch) |
| es | Spanish (Español) |
| fr | French (Français) |
| ja | Japanese (日本語) |
| ru | Russian (Русский) |
| th | Thai (ไทย) |
| zh | Chinese Simplified (中文) |

---

## Work Breakdown

### Phase 1: Booking plugins (highest priority — most hardcoded strings)

#### 1a. Booking Admin (fe-admin) — ~240 strings

**Files to modify:**
- `ResourceList.vue` — 96 strings
- `ResourceForm.vue` — 50 strings
- `SchemaEditor.vue` — 30 strings
- `CategoryEditor.vue` — 20 strings
- `BookingDashboard.vue` — 10 strings
- `BookingList.vue` — 10 strings
- `BookingDetail.vue` — 25 strings
- `index.ts` — nav labels

**Locale key structure:**
```json
{
  "booking": {
    "nav": {
      "dashboard": "Dashboard",
      "allBookings": "All Bookings",
      "resources": "Resources"
    },
    "resources": {
      "title": "Resources & Categories",
      "tabs": { "resources": "Resources", "categories": "Categories", "schemas": "Schemas" },
      "newResource": "+ New Resource",
      "search": "Search resources...",
      "table": { "name": "Name", "schema": "Schema", "capacity": "Capacity", ... },
      ...
    },
    "schemas": { ... },
    "categories": { ... },
    "dashboard": { ... },
    "bookings": { ... },
    "common": { "save": "Save", "cancel": "Cancel", "delete": "Delete", ... }
  }
}
```

**Steps:**
1. Create `locales/en.json` with all strings extracted
2. Replace all hardcoded strings in 7 Vue files with `$t('booking.xxx')`
3. Register translations in `index.ts` via `sdk.addTranslations()`
4. Create de.json, es.json, fr.json, ja.json, ru.json, th.json, zh.json

#### 1b. Booking User (fe-user) — ~60 strings

**Files to modify:**
- `BookingCatalogue.vue` — 15 strings
- `BookingResourceDetail.vue` — 20 strings
- `BookingForm.vue` — 20 strings
- `MyBookings.vue` — 10 strings

**Steps:** Same as 1a.

---

### Phase 2: GHRM + CMS (already use $t() but only en.json)

#### 2a. CMS User (fe-user) — expand to 8 languages

Already uses `$t()`. Just need to create 7 new locale files by translating the existing `en.json`.

#### 2b. GHRM User (fe-user) — expand to 8 languages

Same — translate `en.json` into 7 languages.

---

### Phase 3: Admin plugins without any i18n

#### 3a. GHRM Admin (fe-admin)

- Create `locales/` directory
- Extract hardcoded strings, replace with `$t()`
- Create 8 locale files

#### 3b. Taro Admin (fe-admin)

Same pattern.

#### 3c. Analytics Widget (fe-admin)

Same pattern (fewer strings — it's a small widget).

#### 3d. Email Admin (fe-admin) — expand from en-only to 8 languages

Already has en.json + partial $t() usage. Add 7 languages.

---

## Translation Pattern (how plugins register translations)

```typescript
// index.ts
import en from './locales/en.json';
import de from './locales/de.json';
import es from './locales/es.json';
import fr from './locales/fr.json';
import ja from './locales/ja.json';
import ru from './locales/ru.json';
import th from './locales/th.json';
import zh from './locales/zh.json';

export const myPlugin: IPlugin = {
  install(sdk: IPlatformSDK) {
    sdk.addTranslations('en', en);
    sdk.addTranslations('de', de);
    sdk.addTranslations('es', es);
    sdk.addTranslations('fr', fr);
    sdk.addTranslations('ja', ja);
    sdk.addTranslations('ru', ru);
    sdk.addTranslations('th', th);
    sdk.addTranslations('zh', zh);
    // ... routes
  }
};
```

**In templates:**
```vue
<h2>{{ $t('booking.resources.title') }}</h2>
<button>{{ $t('booking.common.save') }}</button>
```

---

## Implementation Order

| Step | Plugin | Strings | New Files |
|------|--------|---------|-----------|
| 1 | booking admin (fe-admin) | ~240 | 8 locale files + 7 Vue edits |
| 2 | booking user (fe-user) | ~60 | 8 locale files + 4 Vue edits |
| 3 | cms user (fe-user) | ~0 (translate existing) | 7 locale files |
| 4 | ghrm user (fe-user) | ~0 (translate existing) | 7 locale files |
| 5 | ghrm-admin (fe-admin) | ~80 | 8 locale files + Vue edits |
| 6 | taro-admin (fe-admin) | ~40 | 8 locale files + Vue edits |
| 7 | analytics-widget (fe-admin) | ~15 | 8 locale files + Vue edits |
| 8 | email-admin (fe-admin) | ~0 (translate existing) | 7 locale files |
| **Total** | | **~435** | **62 locale files** |

---

## Acceptance Criteria

1. All 17 plugins have `locales/` with 8 language files
2. Zero hardcoded user-facing strings in Vue templates (all use `$t()`)
3. Plugin `index.ts` registers translations via `sdk.addTranslations()`
4. Switching language in admin/user settings reflects in all plugin UI
5. No English fallback visible when a non-English language is selected
