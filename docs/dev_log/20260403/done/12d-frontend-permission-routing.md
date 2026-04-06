# Sprint 12d — Frontend: Permission-Aware Routing

**Status:** Pending
**Date:** 2026-04-03
**Principles:** TDD · SOLID · DI · Liskov · DRY · Clean Code · No over-engineering
**Parent:** [12 — Admin Access Levels](12-admin-access-levels.md)

---

## Goal

Frontend router guards check permissions before rendering admin views. Sidebar nav items hidden when user lacks permission. 403 page for denied access.

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Create `usePermissions` composable — `hasPermission(perm)`, `hasAnyPermission(perms)`, `userPermissions` | Unit tests |
| 2 | Update auth store to load and cache user permissions from login response | Store tests |
| 3 | Create `ForbiddenView.vue` — 403 page | — |
| 4 | Add `meta.requiredPermission` to admin routes | — |
| 5 | Router guard: check `requiredPermission` meta, redirect to 403 if denied | Integration tests |
| 6 | Update `AdminSidebar.vue`: filter nav items by `requiredPermission` | Unit tests |
| 7 | Update `extensionRegistry`: add `requiredPermission` to `NavItemWithPosition` | Type tests |
| 8 | Update shop-admin plugin: add `requiredPermission` to routes + nav items | — |
| 9 | Update booking-admin plugin: same | — |
| 10 | Update subscription-admin plugin: same | — |
| 11 | Update cms-admin plugin: same | — |
| 12 | Update all remaining admin plugins: same | — |
| 13 | `pre-commit-check.sh --full` (fe-admin) | — |

---

## Key Design

### usePermissions composable
```typescript
export function usePermissions() {
  const authStore = useAuthStore();

  const userPermissions = computed<string[]>(() =>
    authStore.user?.permissions ?? []
  );

  function hasPermission(permission: string): boolean {
    if (userPermissions.value.includes('*')) return true;
    if (userPermissions.value.includes(permission)) return true;
    // Wildcard matching: "shop.*" matches "shop.products.view"
    return userPermissions.value.some(p =>
      p.endsWith('.*') && permission.startsWith(p.slice(0, -1))
    );
  }

  function hasAnyPermission(permissions: string[]): boolean {
    return permissions.some(p => hasPermission(p));
  }

  return { userPermissions, hasPermission, hasAnyPermission };
}
```

### Route meta
```typescript
sdk.addRoute({
  path: 'shop/products',
  name: 'shop-products',
  component: () => import('./src/views/Products.vue'),
  meta: { requiredPermission: 'shop.products.view' },
});
```

### Sidebar nav with permission
```typescript
extensionRegistry.register('shop-admin', {
  sectionItems: {
    sales: [{
      label: 'Shop',
      to: '/admin/shop/products',
      id: 'shop',
      requiredPermission: 'shop.products.view',
      children: [
        { label: 'Products', to: '/admin/shop/products', requiredPermission: 'shop.products.view' },
        { label: 'Orders', to: '/admin/shop/orders', requiredPermission: 'shop.orders.view' },
      ],
    }],
  },
});
```

---

## Pre-commit Validation

```bash
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
```
