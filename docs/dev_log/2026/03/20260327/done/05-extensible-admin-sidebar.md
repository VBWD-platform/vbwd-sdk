# Sprint 05 — Extensible Admin Sidebar (Section Slot System)

**Status:** Pending approval
**Date:** 2026-03-28
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Goal

Make ALL core sidebar sections (Sales, Settings, and future sections) extensible from plugins. Plugins can inject items into any core section, add new sections, hide core items, and inject custom components (banners, badges). Core stays fully agnostic.

---

## Problem

Currently:
- Core sidebar hardcodes nav items (Users, Invoices in Sales; Settings, Payment Methods in Settings)
- Plugins can only add **new sections** (`navSections`) or **inject into Settings** (`settingsItems`)
- If a plugin wants to add "Subscriptions" to Sales, it must create a separate section — or core must be edited (gnostic)
- No mechanism to hide/reorder core items or inject non-link elements (badges, banners)

---

## Design

### Section Slot System

Core defines **named slots** (sections with IDs). Plugins inject items into slots by ID.

```typescript
// Plugin developer API — simple and declarative
extensionRegistry.register('subscription-admin', {
  // Inject items into existing core sections
  sectionItems: {
    sales: [
      { label: 'Subscriptions', to: '/admin/subscriptions', position: 'before:invoices' },
    ],
  },
  // New standalone sections (existing behavior)
  navSections: [
    { id: 'tarifs', label: 'Tarifs', items: [...] },
  ],
  // Inject into Settings (existing behavior, now via sectionItems too)
  sectionItems: {
    settings: [
      { label: 'Email Templates', to: '/admin/email/templates' },
    ],
  },
  // Hide core items (e.g., remove Payment Methods if not needed)
  hiddenItems: ['/admin/payment-methods'],
  // Inject custom component into a section (banner, badge, etc.)
  sectionComponents: {
    dashboard: [{ component: AnalyticsWidget, position: 'after' }],
  },
});
```

### Core Section IDs

| Section ID | Core items | Description |
|-----------|-----------|-------------|
| `dashboard` | Dashboard link | Top-level, not expandable |
| `sales` | Users, Invoices | Revenue-related |
| `settings` | Settings, Payment Methods | Admin config |

Plugins can target any ID. Unknown IDs create new sections automatically.

### AdminSidebar.vue Changes

Instead of hardcoding items, the sidebar reads from a unified section model:

```typescript
const sidebarSections = computed(() => {
  const core = [
    {
      id: 'sales',
      label: t('nav.sales'),
      items: [
        { label: t('nav.users'), to: '/admin/users', id: 'users' },
        { label: t('nav.invoices'), to: '/admin/invoices', id: 'invoices' },
      ],
    },
    {
      id: 'settings',
      label: t('nav.settings'),
      items: [
        { label: t('nav.settings'), to: '/admin/settings', id: 'settings' },
        { label: t('nav.paymentMethods'), to: '/admin/payment-methods', id: 'payment-methods' },
      ],
    },
  ];
  // Merge plugin items, filter hidden, add plugin sections
  return extensionRegistry.buildSidebar(core);
});
```

---

## Interface Changes

### 3-Level Navigation Model

The sidebar supports up to 3 levels of nesting:

```
Level 0 — Section header (collapsible):   Sales, Settings, Bookings
Level 1 — Nav item (link or parent):      Users, Invoices, Plans, Resources
Level 2 — Sub-item (nested under L1):     Agoda, Booking.com, Airbnb
```

**Example — Booking plugin with integrations (future):**

```
▼ Bookings                          ← Level 0 (section)
    Dashboard                       ← Level 1 (link)
    All Bookings                    ← Level 1 (link)
    Resources                       ← Level 1 (link)
  ▶ Integrations                    ← Level 1 (expandable parent)
      Agoda                         ← Level 2 (link)
      Booking.com                   ← Level 2 (link)
      Airbnb                        ← Level 2 (link)
```

**Example — Sales with subscription plugin:**

```
▼ Sales                             ← Level 0
    Users                           ← Level 1
    Subscriptions                   ← Level 1 (injected by plugin)
    Invoices                        ← Level 1
```

Level 2 is optional — items only render children if `children` array is present and non-empty.

### ExtensionRegistry additions

```typescript
interface NavItemWithPosition extends NavItem {
  /** Optional ID for targeting by other plugins */
  id?: string;
  /** Position hint: 'before:invoices', 'after:users', 'start', 'end' (default: 'end') */
  position?: string;
  /** Optional children — renders as expandable sub-group (Level 2) */
  children?: NavItem[];
}

interface SectionComponent {
  component: Component;
  position?: 'before' | 'after';  // before/after the items list
}

interface AdminExtension {
  // Existing
  navSections?: NavSection[];
  settingsItems?: NavItem[];           // deprecated — use sectionItems.settings
  userDetailsSections?: Component[];
  planTabSections?: PlanTabSection[];

  // New
  sectionItems?: Record<string, NavItemWithPosition[]>;  // inject into core sections by ID
  hiddenItems?: string[];              // hide items by route path
  sectionComponents?: Record<string, SectionComponent[]>; // inject components into sections
}
```

### ExtensionRegistry new methods

```typescript
/** Build complete sidebar model — merges core + plugin items */
buildSidebar(coreSections: NavSection[]): NavSection[]

/** Get items injected into a specific core section */
getSectionItems(sectionId: string): NavItemWithPosition[]

/** Get items to hide */
getHiddenItems(): string[]

/** Get components injected into a section */
getSectionComponents(sectionId: string): SectionComponent[]
```

---

## Steps

| # | Where | What | Tests first |
|---|-------|------|-------------|
| 1 | `vue/src/plugins/extensionRegistry.ts` | Add `NavItemWithPosition`, `SectionComponent` interfaces | `vue/tests/unit/plugins/extension-registry.spec.ts` |
| 2 | `vue/src/plugins/extensionRegistry.ts` | Add `sectionItems`, `hiddenItems`, `sectionComponents` to `AdminExtension` | Same test file |
| 3 | `vue/src/plugins/extensionRegistry.ts` | Implement `buildSidebar()`, `getSectionItems()`, `getHiddenItems()`, `getSectionComponents()` | Same test file |
| 4 | `vue/src/layouts/AdminSidebar.vue` | Refactor: replace hardcoded sections with `buildSidebar()` computed | `vue/tests/unit/layouts/admin-sidebar-sections.spec.ts` |
| 5 | `vue/src/layouts/AdminSidebar.vue` | Render `sectionComponents` (banners, widgets) in sections | Same test file |
| 6 | `vue/src/layouts/AdminSidebar.vue` | Filter out `hiddenItems` from rendered nav | Same test file |
| 7 | `plugins/subscription-admin/index.ts` | Use `sectionItems.sales` instead of standalone `navSections` for Subscriptions | — |
| 8 | All | Run `pre-commit-check.sh --full` | — |

---

## Test Cases (TDD)

### ExtensionRegistry (`vue/tests/unit/plugins/extension-registry.spec.ts`)

```
Registration:
  - test_register_stores_extension
  - test_unregister_removes_extension
  - test_clear_removes_all

getSectionItems:
  - test_returns_items_for_matching_section_id
  - test_returns_empty_array_when_no_items
  - test_merges_items_from_multiple_plugins
  - test_preserves_position_hints

getHiddenItems:
  - test_returns_hidden_paths
  - test_returns_empty_when_no_hidden
  - test_merges_hidden_from_multiple_plugins

getSectionComponents:
  - test_returns_components_for_section
  - test_returns_empty_when_no_components

buildSidebar:
  - test_returns_core_sections_when_no_plugins
  - test_injects_items_into_matching_core_section
  - test_position_end_appends_to_section
  - test_position_before_inserts_before_target
  - test_position_after_inserts_after_target
  - test_position_start_prepends_to_section
  - test_filters_hidden_items_from_core_sections
  - test_appends_plugin_nav_sections_after_core
  - test_does_not_modify_original_core_array
  - test_unknown_section_id_ignored (doesn't crash)
  - test_preserves_children_on_injected_items (Level 2)
  - test_preserves_children_on_nav_section_items (Level 2)
```

### AdminSidebar (`vue/tests/unit/layouts/admin-sidebar-sections.spec.ts`)

```
Rendering:
  - test_renders_core_sections_with_default_items
  - test_renders_plugin_injected_items_in_sales
  - test_hides_items_marked_as_hidden
  - test_renders_plugin_standalone_sections
  - test_renders_section_components (banner/widget)
  - test_section_is_expandable
  - test_active_section_highlighted_for_plugin_routes

Level 2 (children):
  - test_renders_level2_children_under_parent_item
  - test_level2_children_toggleable_independently
  - test_level2_children_not_rendered_when_empty
  - test_level2_parent_with_to_is_clickable_link
  - test_level2_parent_without_to_is_toggle_only
```

### Playwright E2E — Plugin Nav Items (`vue/tests/e2e/admin-sidebar-plugin-nav.spec.ts`)

Tests run against live dev server with mocked API. Verify that when a plugin is enabled, its sidebar items appear, are clickable, and navigate to the correct page with correct content.

```
Subscription-admin plugin:
  - test_sidebar_shows_subscriptions_item_in_sales_section
      → expand Sales, see "Subscriptions" link
      → click it, URL is /admin/subscriptions
      → page heading contains "Subscriptions"
  - test_sidebar_shows_tarifs_section_with_plans_and_addons
      → see "Tarifs" section in sidebar
      → expand, see "Plans" and "Add-Ons" links
  - test_plans_link_opens_plans_page
      → click "Plans" in sidebar
      → URL is /admin/plans
      → page contains plans table or heading "Plans"
  - test_addons_link_opens_addons_page
      → click "Add-Ons" in sidebar
      → URL is /admin/add-ons
      → page contains add-ons table or heading "Add-Ons"
  - test_subscriptions_link_opens_subscriptions_page
      → click "Subscriptions" in sidebar
      → URL is /admin/subscriptions
      → page contains subscriptions table or heading "Subscriptions"

Booking plugin:
  - test_sidebar_shows_bookings_section
      → see "Bookings" section in sidebar
      → expand, see "Dashboard", "All Bookings", "Resources"
  - test_bookings_link_opens_booking_list
      → click "All Bookings"
      → URL is /admin/booking/list
      → page contains bookings table
  - test_resources_link_opens_resource_list
      → click "Resources"
      → URL is /admin/booking/resources
      → page contains resources table

CMS plugin:
  - test_sidebar_shows_cms_section
      → see CMS-related section in sidebar
  - test_cms_pages_link_opens_pages_list
      → click CMS pages link
      → correct URL and page heading

Core sections (always present):
  - test_sidebar_shows_sales_with_users_and_invoices
      → "Sales" section visible
      → contains "Users" and "Invoices"
  - test_users_link_navigates_to_users_page
      → click "Users" → URL /admin/users → heading "Users"
  - test_invoices_link_navigates_to_invoices_page
      → click "Invoices" → URL /admin/invoices → heading "Invoices"
  - test_sidebar_shows_settings_section
      → "Settings" section visible with core items
  - test_settings_link_navigates_to_settings_page
      → click "Settings" → URL /admin/settings

Hidden items:
  - test_hidden_item_not_visible_in_sidebar
      → register a plugin with hiddenItems: ['/admin/payment-methods']
      → "Payment Methods" should NOT appear in sidebar

Active state:
  - test_active_section_highlighted_when_on_plugin_page
      → navigate to /admin/subscriptions
      → Sales section header has active/expanded class
  - test_active_item_highlighted_in_sidebar
      → navigate to /admin/plans
      → "Plans" link has router-link-active class

Level 2 (children — future-ready, test with mock plugin):
  - test_level2_parent_shows_expand_chevron
      → register plugin with item that has children
      → parent item shows expand arrow
  - test_level2_children_visible_after_expand
      → click expand on parent
      → children links visible with indentation
  - test_level2_child_link_navigates_to_correct_page
      → click a Level 2 child link
      → URL matches child's `to` path
```

### Step update for Playwright

| # | Where | What | Tests first |
|---|-------|------|-------------|
| 9 | `vue/tests/e2e/admin-sidebar-plugin-nav.spec.ts` | Playwright E2E tests for plugin nav items | Write tests, then verify against implementation |
| 10 | All | Run `npx playwright test` + `pre-commit-check.sh --full` | — |

---

## Plugin Developer API (examples)

### Add "Subscriptions" to Sales section

```typescript
extensionRegistry.register('subscription-admin', {
  sectionItems: {
    sales: [
      { label: 'Subscriptions', to: '/admin/subscriptions' },
    ],
  },
  navSections: [
    {
      id: 'tarifs',
      label: 'Tarifs',
      items: [
        { label: 'Plans', to: '/admin/plans' },
        { label: 'Add-Ons', to: '/admin/add-ons' },
      ],
    },
  ],
});
```

### Add "CMS Pages" to Settings

```typescript
extensionRegistry.register('cms-admin', {
  sectionItems: {
    settings: [
      { label: 'CMS Pages', to: '/admin/cms/pages' },
      { label: 'Routing Rules', to: '/admin/cms/routing-rules' },
    ],
  },
});
```

### Hide Payment Methods (e.g., free-tier install)

```typescript
extensionRegistry.register('free-tier', {
  hiddenItems: ['/admin/payment-methods'],
});
```

### Inject analytics banner into dashboard

```typescript
extensionRegistry.register('analytics', {
  sectionComponents: {
    dashboard: [{ component: MiniStatsBanner, position: 'after' }],
  },
});
```

### Level 2 — Add expandable sub-group (e.g., booking integrations)

```typescript
extensionRegistry.register('booking', {
  navSections: [
    {
      id: 'bookings',
      label: 'Bookings',
      items: [
        { label: 'Dashboard', to: '/admin/booking' },
        { label: 'All Bookings', to: '/admin/booking/list' },
        { label: 'Resources', to: '/admin/booking/resources' },
        {
          label: 'Integrations',
          to: '/admin/booking/integrations',
          children: [
            { label: 'Agoda', to: '/admin/booking/integrations/agoda' },
            { label: 'Booking.com', to: '/admin/booking/integrations/bookingcom' },
            { label: 'Airbnb', to: '/admin/booking/integrations/airbnb' },
          ],
        },
      ],
    },
  ],
});
```

Level 2 items render as an indented expandable sub-list under the parent Level 1 item. The parent `to` is optional — if present, clicking the label navigates; the chevron toggles children visibility.

---

## Acceptance Criteria

- ALL core sidebar sections (Sales, Settings) are built via `buildSidebar()`
- Plugins inject items via `sectionItems` with position control
- Plugins can hide any core item via `hiddenItems`
- Plugins can inject components (banners) via `sectionComponents`
- subscription-admin uses `sectionItems.sales` for "Subscriptions"
- Core `AdminSidebar.vue` has zero hardcoded plugin references
- Existing plugin nav sections (`navSections`) continue to work
- Existing `settingsItems` continues to work (backward compat)
- **Playwright E2E**: Every plugin-registered nav item is clickable, navigates to correct URL, and page shows correct heading/content
- **Playwright E2E**: Core items (Users, Invoices, Settings) remain visible and functional
- **Playwright E2E**: Hidden items do not appear in sidebar
- **Playwright E2E**: Active state highlights correct section when on a plugin page
- `pre-commit-check.sh --full` passes
- `npx playwright test vue/tests/e2e/admin-sidebar-plugin-nav.spec.ts` passes

---

## Scope — fe-user

The same pattern should be applied to fe-user's `UserLayout.vue` in a follow-up sprint. The Store section (Plans, Tokens, Add-Ons) and Subscription section should become extensible slots. Not in this sprint's scope.

---

## Pre-commit Checks

```bash
./bin/pre-commit-check.sh --full
```

---

## i18n — All Supported Languages

Every plugin that registers sidebar labels, page headings, or UI text must provide translations for all 8 core-supported languages:

| Code | Language |
|------|----------|
| `en` | English |
| `de` | Deutsch |
| `es` | Español |
| `fr` | Français |
| `ja` | 日本語 |
| `ru` | Русский |
| `th` | ไทย |
| `zh` | 中文 |

**Requirements:**
- `subscription-admin` plugin must have `locales/{en,de,es,fr,ja,ru,th,zh}.json` with nav labels ("Subscriptions", "Plans", "Add-Ons", "Tarifs")
- Plugin `install()` must call `sdk.addTranslations(lang, {...})` for all 8 languages
- `sectionItems` and `navSections` labels should use i18n keys via `$t()`, not hardcoded strings
- Follow the pattern of existing plugins (e.g., booking's `index.ts` calls `sdk.addTranslations` for each language)

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before implementation |
| **Open/Closed** | New plugin capabilities without modifying core sidebar code |
| **DI** | Plugins inject via registry, core reads from registry |
| **DRY** | Single `buildSidebar()` method replaces scattered section logic |
| **No over-engineering** | Position hints are optional (default: 'end') |
| **Meaningful names** | `sectionItems`, `hiddenItems`, `buildSidebar` — self-documenting |
| **i18n** | All UI text in 8 languages: en, de, es, fr, ja, ru, th, zh |
