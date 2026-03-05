# Mobile Header Display Fix (2026-02-17)

## Issue
Mobile header (burger menu + logo) was displaying on desktop when it should only appear on tablet/mobile (<1024px).

## Root Cause
The template had an always-true class binding:
```vue
<header class="mobile-header" :class="{ 'mobile-header-visible': true }">
```

This forced the header to always have the `.mobile-header-visible` class, overriding the CSS `display: none` on desktop.

---

## Solution

### Change Made
**File:** `vbwd-frontend/user/vue/src/layouts/UserLayout.vue`

**Removed:**
```vue
<header class="mobile-header" :class="{ 'mobile-header-visible': true }">
```

**Changed to:**
```vue
<header class="mobile-header">
```

Also removed the now-unused `.mobile-header-visible` CSS class rule.

---

## How It Works Now

### CSS Control (Default - Desktop)
```css
.mobile-header {
  display: none;  /* Hidden on desktop by default */
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  height: 60px;
  ...
}
```

### CSS Control (Tablet/Mobile - <1024px)
```css
@media (max-width: 1024px) {
  .mobile-header {
    display: flex;  /* Show on tablet/mobile */
  }

  .burger-menu {
    display: flex;
  }
  ...
}
```

### CSS Control (Mobile - <768px)
```css
@media (max-width: 768px) {
  /* Additional mobile-specific adjustments */
}
```

---

## Display Behavior

| Screen Size | Display | Content |
|------------|---------|---------|
| **Desktop (>1024px)** | Hidden | - Sidebar expanded (250px) <br>- No header <br>- Main content full width after sidebar |
| **Tablet (768px-1024px)** | Visible | - Fixed header (60px) <br>- Burger menu (hamburger icon) <br>- Logo <br>- Sidebar collapsible |
| **Mobile (<768px)** | Visible | - Fixed header (60px) <br>- Burger menu <br>- Logo <br>- Full-width sidebar on overlay |

---

## Browser Caching Note

If the header still appears on desktop after deployment:
1. **Hard refresh** the page: `Ctrl+Shift+R` (Windows/Linux) or `Cmd+Shift+R` (Mac)
2. **Clear browser cache** and reload
3. **Open DevTools** and check CSS:
   - `.mobile-header` should show `display: none` on desktop
   - Should show `display: flex` on tablet/mobile

---

## Testing Checklist

### Desktop (>1024px)
- [ ] No mobile header visible
- [ ] Sidebar (250px) visible on left
- [ ] No burger menu button
- [ ] Main content extends full width (minus sidebar)
- [ ] No unwanted spacing at top

### Tablet (768px-1024px)
- [ ] Mobile header (60px) visible at top
- [ ] Burger menu button visible and functional
- [ ] VBWD logo in header
- [ ] Sidebar hidden by default
- [ ] Click burger opens sidebar
- [ ] Main content has 60px top margin

### Mobile (<768px)
- [ ] Mobile header visible (60px)
- [ ] Burger menu animated (3-line to X)
- [ ] Logo visible in header
- [ ] Sidebar full-width on click
- [ ] Overlay visible behind sidebar
- [ ] No horizontal scroll
- [ ] Layout responsive and readable

---

## CSS Specificity

The fix works because:
1. **Default state** (desktop): `.mobile-header { display: none; }` - specificity: 1
2. **Media query override** (tablet/mobile): `@media (max-width: 1024px) { .mobile-header { display: flex; } }` - specificity: 1 + media query

Media queries don't increase specificity but they override based on viewport size, which is the intended behavior.

---

## Complete Header Visibility Logic

```
┌─ Desktop (>1024px)
│  ├─ .mobile-header: display: none ✓
│  ├─ .burger-menu: display: none ✓
│  └─ .sidebar: width: 250px, position: fixed (always visible) ✓
│
├─ Tablet (768px-1024px)
│  ├─ .mobile-header: display: flex ✓ (from media query)
│  ├─ .burger-menu: display: flex ✓ (from media query)
│  └─ .sidebar: transform: translateX(-100%), shows on click ✓
│
└─ Mobile (<768px)
   ├─ .mobile-header: display: flex ✓ (from media query)
   ├─ .burger-menu: display: flex ✓ (from media query)
   └─ .sidebar: width: 100%, full-screen overlay ✓
```

---

## Summary

✅ **Mobile Header Display Fixed**

The mobile header now correctly:
- **Hides on desktop** (>1024px) - no header shown
- **Shows on tablet** (768px-1024px) - burger menu header visible
- **Shows on mobile** (<768px) - burger menu header visible, full-width sidebar

The fix removes the template class binding that forced the header to always be visible, allowing pure CSS media queries to control the display behavior based on viewport size.

**Implementation:** Changed 1 line of template code (removed always-true class binding)
**Result:** Header visibility now properly controlled by media queries
