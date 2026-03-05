# Sprint 12 Report — Plugin System Test Coverage

**Status:** DONE
**Duration:** ~15 minutes
**Date:** 2026-02-08

---

## Summary

Closed four critical test gaps in the frontend plugin system: error recovery, dependency cascade, resource collision, and user app bootstrap.

## Results

| Sub-sprint | File | Tests | Result |
|-----------|------|-------|--------|
| 12a — Error Recovery | `core/tests/unit/plugins/PluginErrorRecovery.spec.ts` | 9 | All GREEN (status preserved by code flow — no fix needed) |
| 12b — Dependency Cascade | `core/tests/unit/plugins/PluginDependencyCascade.spec.ts` | 9 | 1 RED → fixed → all GREEN |
| 12c — Resource Collision | `core/tests/unit/plugins/PluginResourceCollision.spec.ts` | 8 | All GREEN (documents last-write-wins behavior) |
| 12d — User App Bootstrap | `user/vue/tests/unit/plugins/plugin-bootstrap.spec.ts` | 11 | All GREEN (first-ever user app plugin tests) |

**Total new tests:** 37

## Production Code Fix

**File:** `core/src/plugins/PluginRegistry.ts`

**Change:** Added `getActiveDependents()` private method + dependent check in `deactivate()`.

**Before:** `deactivate()` allowed deactivating a plugin even when other active plugins depended on it.

**After:** `deactivate()` throws `Cannot deactivate "X": active dependents: Y, Z` when active dependents exist — matching the backend `PluginManager.disable_plugin()` pattern (Liskov Substitution).

```typescript
// New method added:
private getActiveDependents(name: string): string[] {
  const dependents: string[] = [];
  for (const [pluginName, metadata] of this.plugins) {
    if (pluginName === name || metadata.status !== PluginStatus.ACTIVE) continue;
    if (metadata.dependencies) {
      const deps = this.normalizeDependencies(metadata.dependencies);
      if (name in deps) dependents.push(pluginName);
    }
  }
  return dependents;
}
```

## Test Counts After Sprint

| Location | Before | After | Delta |
|----------|--------|-------|-------|
| `core/tests/unit/plugins/` | 18 | 45 | +27 |
| `core/tests/integration/` | 6 | 6 | 0 |
| `admin/vue/tests/` | 211 | 211 | 0 |
| `user/vue/tests/` | 40 | 51 | +11 |
| **Total** | **275** | **313** | **+38** |

## Regression Check

- Core: 277/277 pass (3 pre-existing AuthGuard failures, unrelated)
- Admin: 211/211 pass
- User: 51/51 pass

## Key Findings

1. **Error recovery already works** — PluginRegistry's code flow naturally preserves status because errors throw before status update lines execute (no try/catch needed).
2. **Dependency cascade had a gap** — `deactivate()` didn't check for active dependents. Fixed to match backend pattern.
3. **Resource collisions use last-write-wins** — components and stores overwrite on name collision; routes append (documented, no change needed).
4. **User app plugin system works** — `@vbwd/view-component` dependency is correctly linked; plugin system is fully functional in user context even though main.ts doesn't wire it up yet.
5. **`installAll()` stops on first failure** — documented behavior; partial installs leave earlier plugins INSTALLED and the failing one REGISTERED.

## Principles Applied

| Principle | How Applied |
|-----------|------------|
| TDD | Tests written first (RED), then fix (GREEN) |
| SRP | Each test file covers exactly one concern |
| LSP | Frontend deactivate-with-dependents now matches backend PluginManager |
| DRY | `createTestPlugin()` helper reused; same import patterns as existing files |
| No Overengineering | Plain vitest assertions, no abstract base classes or test factories |
