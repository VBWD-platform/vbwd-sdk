# Missing i18n Translations Fix (2026-02-17)

## Summary
Fixed missing navigation translations that were blocking the mobile-first dashboard from displaying navigation items properly. Added `nav.store` to core language files and `nav.taro` to Taro plugin language files.

---

## Issue
The mobile-first dashboard navigation had two missing translation keys:
- `nav.store` - Referenced in core UserLayout.vue navigation group
- `nav.taro` - Referenced in Taro plugin route

Without these translations, the navigation labels displayed as empty strings, breaking the UI.

---

## Root Cause
**Architecture Distinction Not Initially Followed:**
- `nav.store` is a **core navigation item** (plugin-agnostic) → should be in **core language files**
- `nav.taro` is a **plugin-specific navigation item** → should be in **plugin language files**

The core principle: **Core is plugin-agnostic; plugins handle plugin-specific translations.**

---

## Solution

### 1. Core Translations (Plugin-Agnostic)
**Files Modified:**
- `vbwd-frontend/user/vue/src/i18n/locales/en.json`
- `vbwd-frontend/user/vue/src/i18n/locales/de.json`

**Changes:**
Added to `nav` section:
```json
"nav": {
  "dashboard": "Dashboard",
  "profile": "Profile",
  "subscription": "Subscription",
  "invoices": "Invoices",
  "plans": "Plans",
  "tokens": "Tokens",
  "addons": "Add-ons",
  "appearance": "Appearance",
  "chat": "Chat",
  "store": "Store"  // Added
}
```

**German Translation:**
```json
"store": "Shop"  // German equivalent for Store
```

### 2. Plugin Translations (Taro-Specific)
**Files Modified:**
- `vbwd-frontend/user/plugins/taro/locales/en.json`
- `vbwd-frontend/user/plugins/taro/locales/de.json`

**Changes:**
Added new `nav` section at top level:
```json
{
  "nav": {
    "taro": "Taro"
  },
  "taro": {
    // ... existing translations
  },
  "oracle": {
    // ... existing translations
  },
  "common": {
    // ... existing translations
  }
}
```

**German Translation:**
```json
"nav": {
  "taro": "Tarot"
}
```

---

## Architecture Principles Applied

### Core vs Plugin Scope
| Aspect | Core | Plugin |
|--------|------|--------|
| Location | `vbwd-frontend/user/vue/src/i18n/locales/` | `vbwd-frontend/user/plugins/{plugin-name}/locales/` |
| Content | Navigation items, common UI terms | Feature-specific text, plugin labels |
| Plugin-Agnostic | Yes ✓ | No (plugin-specific) |
| Dependencies | None | None (self-contained) |
| Scope | Available to entire app | Loaded per plugin activation |

### Translation Hierarchy
1. **Core Translations** load first (framework/app level)
2. **Plugin Translations** load on plugin installation (via `sdk.addTranslations()`)
3. Plugins can override core keys if needed, but shouldn't for nav items

### Key Learning
The distinction is crucial for:
- **Maintainability**: Core doesn't need plugin knowledge
- **Modularity**: Plugins are independent, transferable units
- **Flexibility**: Same core works with different plugin combinations
- **Clarity**: Clear ownership of translation strings

---

## How the Navigation Works Now

### Desktop (>1024px)
```
Sidebar (250px fixed)
├── Dashboard
├── Store (nav.store - core translation) ✓
│   ├── Plans
│   ├── Tokens
│   └── Add-ons
├── Subscription (nav.subscription - core translation)
│   ├── Subscription Details
│   └── Invoices
├── Taro (nav.taro - plugin translation) ✓
└── User Menu
    ├── Profile
    ├── Appearance
    └── Logout
```

### Tablet/Mobile (<1024px)
```
Mobile Header (60px)
├── Burger Menu
│   ├── Store ✓
│   ├── Subscription ✓
│   └── Taro ✓
└── User Dropdown
    ├── Profile
    ├── Appearance
    └── Logout
```

---

## Verification

### Files Changed
1. ✅ `/vbwd-frontend/user/vue/src/i18n/locales/en.json` - Added `nav.store`
2. ✅ `/vbwd-frontend/user/vue/src/i18n/locales/de.json` - Added `nav.store` (German: "Shop")
3. ✅ `/vbwd-frontend/user/plugins/taro/locales/en.json` - Added `nav.taro`
4. ✅ `/vbwd-frontend/user/plugins/taro/locales/de.json` - Added `nav.taro` (German: "Tarot")

### Translation Keys Added

**Core (plugin-agnostic):**
- `nav.store` → "Store" (English), "Shop" (German)

**Plugin (Taro-specific):**
- `nav.taro` → "Taro" (English), "Tarot" (German)

---

## Testing Checklist

### English (en) Locale
- [x] `nav.store` resolves to "Store" in core nav group
- [x] `nav.taro` resolves to "Taro" in Taro plugin nav
- [x] Navigation displays correctly on desktop, tablet, mobile

### German (de) Locale
- [x] `nav.store` resolves to "Shop" in core nav group
- [x] `nav.taro` resolves to "Tarot" in Taro plugin nav
- [x] Navigation displays correctly on desktop, tablet, mobile

### Plugin Loading
- [x] Core translations available immediately
- [x] Plugin translations loaded when Taro plugin installs
- [x] No translation key conflicts or collisions
- [x] No console warnings about missing translations

---

## Related Components
- **`UserLayout.vue`** - Uses `{{ $t('nav.store') }}` and `{{ $t('nav.taro') }}`
- **Mobile Menu** - Displays navigation groups with proper labels
- **User Dropdown** - Remains in sidebar/header with Profile, Appearance, Logout

---

## Summary

✅ **Mobile-First Dashboard Translations Complete**

The dashboard now displays all navigation items with proper translations:
- **Core navigation** (`nav.store`) properly scoped in core language files
- **Plugin navigation** (`nav.taro`) properly scoped in plugin language files
- **Architecture principle maintained**: Core is plugin-agnostic, plugins are self-contained
- **Both languages supported**: English and German translations in place
- **No missing translation warnings** in console

Implementation follows vbwd-sdk plugin architecture standards: clear separation of concerns between core and plugin-specific code/configuration.
