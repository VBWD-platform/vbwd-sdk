# Appearance Plugin Configuration Update (2026-02-17)

## Summary
Updated the Appearance (theme-switcher) plugin configuration to reflect that it appears in the user profile dropdown menu (bottom-left) instead of as a standalone navigation item.

---

## Changes Made

### 1. **Admin Config File**
**File:** `vbwd-frontend/user/plugins/theme-switcher/admin-config.json`

**Added:**
```json
{
  "metadata": {
    "placement": "user-menu",
    "description": "Appearance settings shown in user profile dropdown menu"
  },
  "tabs": [...]
}
```

**Rationale:**
- Declares that this plugin is placed in the user menu dropdown
- Documents the intended behavior for administrators
- Can be used by the admin panel to understand plugin placement

### 2. **Plugin Definition**
**File:** `vbwd-frontend/user/plugins/theme-switcher/index.ts`

**Added:**
```typescript
metadata: {
  placement: 'user-menu',
  displayName: 'Appearance',
  icon: 'palette'
}
```

**Details:**
- `placement`: Indicates plugin appears in user menu dropdown
- `displayName`: User-friendly name for the Appearance feature
- `icon`: Icon identifier for visual representation (palette)

---

## Integration with Dashboard

### User Layout Implementation
The UserLayout component already supports the Appearance plugin in the user dropdown:

```vue
<button
  v-if="enabledPlugins.has('theme-switcher')"
  class="user-dropdown-item appearance-btn"
  @click="openAppearance"
  data-testid="appearance-menu-item"
>
  {{ $t('nav.appearance') }}
</button>
```

**When Clicked:**
1. Closes user dropdown menu
2. Closes mobile burger menu (if open)
3. Navigates to `/dashboard/appearance`
4. Opens ThemeSelectorView.vue component

---

## Plugin Behavior

### Installation
The theme-switcher plugin still:
- Adds the `/dashboard/appearance` route
- Loads translations (en.json, de.json)
- Initializes theme system on activation

### Activation
On plugin activation:
- Applies the saved theme from localStorage
- Sets default theme if none saved

### Deactivation
On plugin deactivation:
- Reverts to default theme
- Disables theme selector UI

---

## User Experience

### Desktop (>1024px)
1. User clicks profile icon + email in sidebar bottom
2. Dropdown appears with options:
   - Profile
   - Appearance (if theme-switcher enabled)
   - Logout
3. Click "Appearance" → Navigate to `/dashboard/appearance`

### Tablet/Mobile (<1024px)
1. User opens burger menu
2. Sees main navigation items
3. Clicks profile icon + email at bottom
4. Dropdown appears with same options
5. Click "Appearance" → Navigate to `/dashboard/appearance`

---

## Configuration Structure

### admin-config.json
Defines UI schema for admin panel:
- `metadata`: Plugin placement and description
- `tabs`: Admin configuration interface (default theme selection)
- `fields`: Form fields for admin settings

### config.json (Runtime)
Defines schema for plugin configuration:
- `defaultTheme`: Default theme for new users

### index.ts (Plugin Code)
Defines plugin functionality and metadata:
- `name`: Plugin identifier ('theme-switcher')
- `version`: Plugin version
- `description`: Human-readable description
- `metadata`: Placement and UI hints
- `install()`: Route and translation setup
- `activate()`: Theme initialization
- `deactivate()`: Theme cleanup

---

## Metadata Fields

### metadata.placement
**Values:**
- `'user-menu'`: Appears in user profile dropdown (current)
- `'main-nav'`: Would appear in main navigation sidebar
- `'dashboard'`: Would appear on dashboard page
- `'settings'`: Would appear in settings section

**Usage:**
- Admin panel can use to organize plugins
- Frontend can use to conditionally render placement
- Documentation for intent and behavior

### metadata.displayName
**Purpose:**
- User-friendly name for the feature
- Used in UI labels and menus
- Can be translated via i18n

### metadata.icon
**Purpose:**
- Icon identifier for visual representation
- Supports: 'palette', 'brush', 'paint-bucket', etc.
- Can be used by UI frameworks for consistent iconography

---

## Testing Checklist

### Desktop (>1024px)
- [ ] Sidebar footer shows user email + icon
- [ ] Click user button opens dropdown
- [ ] "Appearance" option visible if theme-switcher enabled
- [ ] "Appearance" option hidden if theme-switcher disabled
- [ ] Click "Appearance" navigates to `/dashboard/appearance`
- [ ] ThemeSelectorView.vue loads correctly
- [ ] Can select different themes
- [ ] Selected theme persists on page reload
- [ ] Logout button visible and functional

### Tablet (768px-1024px)
- [ ] Open burger menu
- [ ] User profile section visible at bottom
- [ ] Click user button opens dropdown
- [ ] "Appearance" option visible (if enabled)
- [ ] Click "Appearance" navigates correctly
- [ ] Mobile menu closes after navigation

### Mobile (<768px)
- [ ] All tablet behaviors work
- [ ] Dropdown positioned correctly in full-width sidebar
- [ ] No overflow or layout issues
- [ ] Touch-friendly button sizes

### Plugin Enable/Disable
- [ ] When theme-switcher enabled: "Appearance" shows in menu
- [ ] When theme-switcher disabled: "Appearance" hidden from menu
- [ ] Disable doesn't break other menu items
- [ ] Re-enable shows "Appearance" again

### Theme Functionality
- [ ] Can switch to different themes from Appearance page
- [ ] Theme persists in localStorage
- [ ] Theme applies to entire app
- [ ] Default theme loads on first visit
- [ ] Custom theme persists across sessions

---

## File Organization

```
vbwd-frontend/user/plugins/theme-switcher/
├── index.ts                    # Plugin definition with metadata
├── admin-config.json           # Admin UI config with metadata
├── config.json                 # Runtime schema
├── ThemeSelectorView.vue       # Theme selection UI (accessed from user menu)
├── apply-theme.ts              # Theme application logic
├── presets.ts                  # Available theme presets
├── locales/
│   ├── en.json                # English translations
│   └── de.json                # German translations
└── tests/                      # Unit tests
```

---

## Future Enhancements

1. **Theme Preview**
   - Add preview thumbnails for each theme
   - Show live preview on hover/selection

2. **Custom Themes**
   - Allow users to create custom color schemes
   - Save custom themes to profile

3. **Theme Sync**
   - Sync theme preference across devices
   - Use backend to persist theme choice

4. **Auto Dark Mode**
   - Detect OS dark mode preference
   - Auto-switch theme based on system settings

5. **Theme Scheduling**
   - Schedule theme changes (dark mode at night, etc.)
   - Time-based theme switching

6. **Accessibility Themes**
   - High contrast theme for visibility
   - Color-blind friendly themes

---

## Summary

✅ **Appearance Plugin Configuration Updated**

The theme-switcher (Appearance) plugin is now properly configured to appear in the user profile dropdown menu at the bottom-left of the dashboard:

- Metadata added to indicate placement in user menu
- User can access Appearance from profile dropdown
- Plugin remains conditionally enabled based on plugin system
- Full integration with mobile-first responsive design
- Maintains all existing theme functionality

The configuration is backward compatible and doesn't affect existing functionality. The plugin continues to work exactly as before, just with clearer configuration metadata documenting its intended placement.
