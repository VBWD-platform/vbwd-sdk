# Plugin System Refactoring - Dynamic Plugin Loader

**Status:** ✅ **COMPLETE**
**Date:** February 15, 2026
**Scope:** User App + Admin App Frontend

---

## Summary

Refactored the frontend plugin system to eliminate hardcoded imports and enable fully dynamic plugin loading. Developers can now work exclusively in the `/plugins` directory without touching core application code.

**Key Achievement:** Plugins are now loaded at runtime based on `plugins.json` configuration, not at build time.

---

## Changes Made

### 1. Created Plugin Loader Utility

**Files Created:**
- `/vbwd-frontend/user/vue/src/utils/pluginLoader.ts`
- `/vbwd-frontend/admin/vue/src/utils/pluginLoader.ts`

**Functionality:**
- Reads `plugins.json` manifest at runtime
- Dynamically imports enabled plugins using `import()`
- Handles multiple export patterns (camelCase, kebab-case, default)
- Provides error handling and graceful fallback
- Returns array of loaded plugin objects

**Key Features:**
- ✅ No build-time coupling to plugin locations
- ✅ Automatic kebab-case to camelCase conversion
- ✅ Flexible export pattern detection
- ✅ Detailed console logging for debugging
- ✅ Non-fatal error handling (skips failed plugins)

### 2. Updated User App (`user/vue/src/main.ts`)

**Removed:**
- 8 hardcoded import statements (lines 8-15)
- Static `availablePlugins` object
- `fetchPluginRegistry()` function with fallback logic

**Added:**
- Single import: `import { loadEnabledPlugins } from '@/utils/pluginLoader'`
- Dynamic plugin loading from `./plugins/plugins.json`
- Automatic plugin registration and activation

**Before:**
```typescript
import { landing1Plugin } from '../../plugins/landing1';
import { checkoutPlugin } from '../../plugins/checkout';
// ... 6 more hardcoded imports
const availablePlugins = { landing1, checkout, ... };
```

**After:**
```typescript
const plugins = await loadEnabledPlugins('./plugins/plugins.json');
for (const plugin of plugins) {
  registry.register(plugin);
}
```

### 3. Updated Admin App (`admin/vue/src/main.ts`)

**Removed:**
- Hardcoded: `import { analyticsWidgetPlugin } from '@plugins/analytics-widget'`
- Static import: `import pluginsRegistry from '@plugins/plugins.json'`
- Manual registration: `registry.register(analyticsWidgetPlugin)`

**Added:**
- Single import: `import { loadEnabledPlugins } from '@/utils/pluginLoader'`
- Dynamic plugin loading from `./plugins/plugins.json`

### 4. Updated Taro Plugin Registration

**File:** `/vbwd-frontend/user/plugins/plugins.json`

**Added Taro to enabled plugins:**
```json
"taro": {
  "enabled": true,
  "version": "1.0.0",
  "installedAt": "2026-02-15T18:00:00.000Z",
  "source": "local"
}
```

**Result:** Taro now loads dynamically without code changes.

---

## Plugin Discovery Mechanism

### How Plugins Are Found

1. **Manifest Reading:** Load `plugins.json` containing all plugins
2. **Filter:** Keep only plugins with `enabled: true`
3. **Dynamic Import:** For each enabled plugin:
   - Path: `./plugins/{name}/index.ts`
   - Convert name to export: `"chat"` → `chatPlugin`, `"analytics-widget"` → `analyticsWidgetPlugin`
4. **Export Detection:** Try multiple patterns:
   - Exact camelCase: `chatPlugin`
   - Kebab-case: `chat-plugin`
   - Default export
   - Any export with `name` property
5. **Registration:** Register all found plugins with PluginRegistry

### Disabling/Removing Plugins

Simply set `enabled: false` in `plugins.json`:
```json
"chat": {
  "enabled": false,  // Plugin won't load
  ...
}
```

To remove a plugin:
1. Delete its directory from `/plugins/{name}/`
2. Delete its entry from `plugins.json`

**No leftover imports!**

---

## Benefits

✅ **Zero Core Code Changes for New Plugins**
- Add plugin to `plugins.json` with `enabled: true`
- Plugin automatically loads at runtime

✅ **Plugin Management is Dynamic**
- Enable/disable without rebuild
- No code duplication between apps
- Single source of truth: `plugins.json`

✅ **Developer Workflow Improvement**
- Plugin developers never touch `src/main.ts`
- Work exclusively in `/plugins/{plugin-name}/`
- Changes take effect on page refresh

✅ **No Dead Code**
- Disabled plugins don't load
- Failed plugins don't break the app
- Old plugin imports can be safely deleted

✅ **Consistent Architecture**
- Both user and admin apps use same pattern
- Reusable loader utility
- Clear plugin interface expectations

---

## Plugin Interface Requirements

All plugins must export a named or default export matching `IPlugin`:

```typescript
// Good ✅
export const myPluginPlugin: IPlugin = { ... };
export const my_plugin: IPlugin = { ... };
export default { name: 'my-plugin', ... };

// Bad ❌
export const plugin = { ... };  // No name property
export { something } = { ... };   // Not recognized as IPlugin
```

---

## File Structure

```
vbwd-frontend/
├── user/
│   ├── plugins/
│   │   ├── plugins.json           ← Control which plugins load
│   │   ├── taro/index.ts          ← Plugin exports taroPlugin
│   │   ├── chat/index.ts          ← Plugin exports chatPlugin
│   │   └── ...
│   └── vue/src/
│       ├── main.ts                ← No hardcoded imports ✅
│       └── utils/pluginLoader.ts  ← Dynamic loader utility
│
└── admin/
    ├── plugins/
    │   ├── plugins.json           ← Control which plugins load
    │   ├── analytics-widget/...   ← Plugin exports analyticsWidgetPlugin
    │   └── ...
    └── vue/src/
        ├── main.ts                ← No hardcoded imports ✅
        └── utils/pluginLoader.ts  ← Dynamic loader utility
```

---

## Testing

### Build Status
✅ User app builds successfully
✅ Admin app builds successfully
✅ No TypeScript errors
✅ All modules transform correctly

### Runtime Behavior
- Plugins load based on `plugins.json`
- Console logs show loaded plugin count
- Disabled plugins are skipped
- Failed plugin loads don't crash app

---

## Migration Checklist

- [x] Create pluginLoader utility for user app
- [x] Create pluginLoader utility for admin app
- [x] Remove hardcoded imports from user/main.ts
- [x] Remove hardcoded imports from admin/main.ts
- [x] Update Taro to appear in user plugins.json
- [x] Update admin app plugin loading
- [x] Verify both apps build without errors
- [x] Test plugin discovery mechanism

---

## Next Steps (Optional)

1. **Auto-Discovery:** Scan `/plugins` directory instead of requiring `plugins.json`
2. **CLI Tool:** Create tool to add/remove plugins (updates `plugins.json`)
3. **Validation:** Schema validation for `plugins.json`
4. **Versioning:** Track plugin versions and check compatibility
5. **Hot Module Replacement:** Reload plugins without page refresh

---

## Backward Compatibility

✅ **100% Compatible**
- All existing plugins work without modification
- Plugin interfaces unchanged
- No breaking changes

---

**Status:** Ready for production
**Last Updated:** 2026-02-15
**Tested:** ✅ Build & Load
