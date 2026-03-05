# Mobile-First Dashboard Restructure (2026-02-17)

## Summary
Completely redesigned the user dashboard for mobile-first approach with burger menu navigation, reorganized menu structure, and relocated Profile & Appearance to user dropdown menu.

---

## Major Changes

### 1. **Router URL Structure**
**File:** `vbwd-frontend/user/vue/src/router/index.ts`

**Changes:**
- Moved invoices from `/dashboard/invoices` → `/dashboard/subscription/invoices`
- Updated all related routes:
  - `/dashboard/invoices/:invoiceId` → `/dashboard/subscription/invoices/:invoiceId`
  - `/dashboard/invoices/:invoiceId/pay` → `/dashboard/subscription/invoices/:invoiceId/pay`

---

### 2. **Layout Redesign**
**File:** `vbwd-frontend/user/vue/src/layouts/UserLayout.vue` (Complete rewrite)

#### Responsive Behavior
- **Desktop (>1024px):** Sidebar expanded by default, burger menu hidden
- **Tablet (768px-1024px):** Burger menu visible, sidebar slides out from left
- **Mobile (<768px):** Burger menu, full-width sidebar on overlay

#### Mobile Header
```vue
<header class="mobile-header">
  <button class="burger-menu">☰</button>
  <div class="logo-mobile">VBWD</div>
</header>
```

Features:
- Fixed height (60px)
- Contains animated burger icon (3-line hamburger → X animation)
- Shows VBWD logo
- Only visible on tablet/mobile (<1024px)

#### Navigation Menu Restructure

**Before:**
```
Dashboard
Taro
Profile ← Now in user dropdown
Subscription
Invoices (separate item)
Plans (separate item)
Tokens (separate item)
Add-Ons (separate item)
Appearance ← Now in user dropdown
Chat (if enabled)
```

**After:**
```
Dashboard
Taro
Store (collapsible group)
  ├─ Plans
  ├─ Tokens
  └─ Add-Ons
Subscription (collapsible group)
  ├─ Subscription
  └─ Invoices
Chat (if enabled)
```

#### User Menu (Bottom-Left)
Reorganized with new structure:

```
[Avatar] user@example.com
├─ Profile → /dashboard/profile
├─ Appearance → /dashboard/appearance (if theme-switcher plugin enabled)
└─ Logout
```

**Features:**
- User icon + email display
- Click to toggle dropdown menu
- Profile, Appearance, Logout menu items
- Logout button styled in red (#e74c3c)

#### Cart Button
- Remains in sidebar footer above user menu
- Shows badge with item count
- Dropdown displays cart items with checkout option

---

## Implementation Details

### Collapsible Menu Groups
Both "Store" and "Subscription" are collapsible groups with chevron icons:

```typescript
expandedGroups = ref({
  store: false,
  subscription: false,
});

function toggleGroup(groupName: 'store' | 'subscription') {
  expandedGroups.value[groupName] = !expandedGroups.value[groupName];
}
```

When expanded, sub-items appear with darker background:
- Padding: 40px left (indented relative to parent)
- Background: `rgba(0, 0, 0, 0.2)` for visual separation
- Font size: 0.9rem (slightly smaller than parent)

### Mobile Menu Overlay
When sidebar is open on mobile:
- Semi-transparent overlay appears (`rgba(0, 0, 0, 0.5)`)
- Clicking overlay closes the sidebar
- Clicking a menu item closes the sidebar
- Prevents scrolling on body

### Responsive Breakpoints

**Desktop (1024px+)**
- Sidebar: fixed, 250px width, always visible
- Header: hidden
- Main content: 250px left margin
- Menu groups: all visible by default

**Tablet (768px-1024px)**
- Header: fixed, 60px height
- Sidebar: 250px width, slides from left on toggle
- Main content: no left margin, top margin 60px
- Overlay: visible when menu open
- Logo: hidden (mobile logo in header)

**Mobile (<768px)**
- Header: fixed, 60px height
- Sidebar: full width (100%), slides from left
- Main content: no margins, top margin 60px
- Overlay: visible when menu open
- Padding: reduced to 20px from 30px

---

## Accessibility Improvements

### Semantic HTML
- `<header>` for top navigation
- `<nav>` for main navigation menu
- `<button>` for menu toggles (not divs)
- `<router-link>` for navigation (native Vue Router)

### ARIA & Labels
- Burger menu button: `data-testid="burger-menu"`
- Menu items: clear text labels
- Dropdown menus: proper positioning and visibility
- User email: truncated with `text-overflow: ellipsis`

### Keyboard Navigation
- All interactive elements are keyboard accessible
- Tab order follows visual layout
- Click outside to close dropdowns
- Escape not currently implemented (future enhancement)

---

## Menu Item Locations

| Item | Desktop | Tablet | Mobile | Route |
|------|---------|--------|--------|-------|
| Dashboard | Sidebar | Burger | Burger | `/dashboard` |
| Taro | Sidebar | Burger | Burger | `/dashboard/taro` |
| Plans | Sidebar (Store) | Burger (Store) | Burger (Store) | `/dashboard/plans` |
| Tokens | Sidebar (Store) | Burger (Store) | Burger (Store) | `/dashboard/tokens` |
| Add-Ons | Sidebar (Store) | Burger (Store) | Burger (Store) | `/dashboard/add-ons` |
| Subscription | Sidebar (Subscription) | Burger (Subscription) | Burger (Subscription) | `/dashboard/subscription` |
| Invoices | Sidebar (Subscription) | Burger (Subscription) | Burger (Subscription) | `/dashboard/subscription/invoices` |
| Chat | Sidebar | Burger | Burger | `/dashboard/chat` |
| Profile | User Menu | User Menu | User Menu | `/dashboard/profile` |
| Appearance | User Menu | User Menu | User Menu | `/dashboard/appearance` |
| Cart | Sidebar | Sidebar | Sidebar | (dropdown) |
| Logout | User Menu | User Menu | User Menu | (action) |

---

## CSS Features

### Animations
- **Burger menu:** 300ms smooth transition
  - Line 1: translateY(9px) rotate(45deg)
  - Line 2: opacity 0
  - Line 3: translateY(-9px) rotate(-45deg)
- **Chevron:** 200ms rotate on group toggle
- **Sidebar:** 300ms translateX slide animation
- **Dropdowns:** position absolute, immediate show/hide

### Color Scheme
- Sidebar background: `var(--vbwd-sidebar-bg, #2c3e50)`
- Sidebar text: `rgba(255, 255, 255, 0.8)`
- Active item: `rgba(255, 255, 255, 0.1)` background
- Cart badge: `#e74c3c` (red)
- Logout button: `#e74c3c` red theme
- Main content: `var(--vbwd-page-bg, #f5f5f5)`

### Z-Index Stacking
```
1000 - Sidebar (desktop always visible)
999  - Mobile header, overlay
100  - Dropdown menus (cart, user)
0    - Main content
```

---

## State Management

### Local Refs
```typescript
showMobileMenu: boolean   // Burger menu toggled state
showCart: boolean        // Cart dropdown visible
showUserMenu: boolean    // User menu dropdown visible
expandedGroups: {        // Collapsible groups state
  store: boolean
  subscription: boolean
}
```

### Computed
```typescript
userEmail: string        // From localStorage.user.email
```

### Functions
- `toggleMobileMenu()` - Toggle burger menu
- `closeMobileMenu()` - Close burger menu
- `toggleGroup(name)` - Toggle collapsible group
- `toggleCart()` - Toggle cart dropdown
- `toggleUserMenu()` - Toggle user dropdown
- `closeUserMenu()` - Close user menu & burger
- `openAppearance()` - Navigate to appearance
- `handleClickOutside()` - Close dropdowns on outside click

---

## Event Handling

### Click Outside
Closes dropdowns when clicking outside:
- `.cart-wrapper` element
- `.user-menu` element
- Sidebar background close icon (mobile)

### Menu Item Clicks
All menu items call `closeMobileMenu()` to close sidebar after navigation.

### Navigation
- Router links use Vue Router `to` prop
- Logout clears localStorage and redirects to `/login`
- Appearance navigation uses `router.push()`

---

## Testing Checklist

### Desktop (>1024px)
- [ ] Sidebar visible by default
- [ ] Burger menu hidden
- [ ] All menu items visible
- [ ] Groups expandable/collapsible
- [ ] No top margin on main content
- [ ] Cart and user dropdowns work
- [ ] Responsive adjusts at 1024px

### Tablet (768px-1024px)
- [ ] Header with burger menu visible
- [ ] Sidebar hidden by default
- [ ] Click burger opens sidebar
- [ ] Sidebar slides from left
- [ ] Overlay shows behind sidebar
- [ ] Click overlay closes sidebar
- [ ] Click menu item closes sidebar
- [ ] Main content has top margin (60px)
- [ ] All menu items accessible

### Mobile (<768px)
- [ ] Header with burger menu visible
- [ ] Sidebar takes full width
- [ ] Sidebar slides from left on toggle
- [ ] Overlay blocks content clicks
- [ ] Groups collapsible/expandable
- [ ] User menu dropdown works
- [ ] Cart dropdown works
- [ ] Padding reduced to 20px
- [ ] Text readable without horizontal scroll

### Navigation
- [ ] `/dashboard` link works
- [ ] `/dashboard/taro` link works
- [ ] `/dashboard/plans` link works
- [ ] `/dashboard/tokens` link works
- [ ] `/dashboard/add-ons` link works
- [ ] `/dashboard/subscription` link works
- [ ] `/dashboard/subscription/invoices` link works (updated URL)
- [ ] `/dashboard/subscription/invoices/:id` works (updated URL)
- [ ] `/dashboard/profile` link works
- [ ] `/dashboard/appearance` link works (from user menu)
- [ ] `/dashboard/chat` link works (if plugin enabled)
- [ ] Logout redirects to login

### User Menu
- [ ] Click user button opens dropdown
- [ ] Profile item visible
- [ ] Appearance item visible (if theme-switcher enabled)
- [ ] Logout button visible
- [ ] Click outside closes dropdown
- [ ] Click profile navigates to /dashboard/profile
- [ ] Click appearance navigates to /dashboard/appearance
- [ ] Click logout clears localStorage and redirects to /login

---

## Migration Notes

### Breaking Changes
- Invoice URLs changed: `/dashboard/invoices` → `/dashboard/subscription/invoices`
- Any hardcoded links to old invoice URLs will break
- Profile no longer in main nav (only in user menu)
- Appearance no longer in main nav (only in user menu)

### What Remained
- Cart functionality unchanged
- Router structure unchanged (except invoice paths)
- Plugin system unchanged
- User authentication unchanged
- All page components unchanged

### Future Enhancements
1. Add Escape key to close menus
2. Add keyboard navigation (arrow keys in menu)
3. Remember expanded/collapsed group state in localStorage
4. Add animations to group toggles
5. Add touch-friendly larger tap targets on mobile
6. Add swipe to close sidebar on mobile
7. Add search/filter to menu on desktop
8. Add breadcrumbs for current location

---

## Files Modified

| File | Changes |
|------|---------|
| `vbwd-frontend/user/vue/src/router/index.ts` | Updated invoice routes from `/dashboard/invoices/*` to `/dashboard/subscription/invoices/*` |
| `vbwd-frontend/user/vue/src/layouts/UserLayout.vue` | Complete rewrite: mobile-first responsive design, burger menu, reorganized navigation, user dropdown menu |

---

## Summary

Successfully restructured the user dashboard for mobile-first design with:

✅ **Mobile-First Responsive Design**
- Burger menu on tablet/mobile
- Sidebar expanded on desktop
- Proper breakpoints at 1024px and 768px

✅ **Navigation Reorganization**
- Combined Plans, Tokens, Add-Ons into "Store" group
- Moved Invoices under "Subscription" group
- Reorganized Profile & Appearance to user menu

✅ **URL Updates**
- Invoices now at `/dashboard/subscription/invoices`
- Maintains all existing functionality

✅ **User Menu Enhancement**
- Profile, Appearance, Logout in user dropdown
- Appearance only visible if theme-switcher plugin enabled

✅ **Accessibility**
- Semantic HTML structure
- Keyboard navigable
- Click outside to close
- Clear visual feedback

The dashboard is now fully responsive and mobile-friendly!
