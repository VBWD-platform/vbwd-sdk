# Sprint 3 Preparation: Plugin Architecture Audit & Migration

## Current Status
- ✅ Sprint 5 COMPLETE: Taro plugin stabilized, all tests passing
- ✅ 1335+ tests passing across frontend and backend
- ✅ All critical bugs fixed
- ✅ Ready to proceed with architectural improvements

---

## Sprint 3 Overview

**Objective**: Audit all 9 plugins and migrate plugin-specific code from core directories to plugin directories.

**Expected Duration**: 5-7 days
**Priority**: P0 (Critical for maintainability)

---

## Three Key Migrations

### Migration 1: Taro Enums (HIGHEST PRIORITY)
**Current State**: 4 Taro-specific enums in `/src/models/enums.py`

**Enums to Move**:
```python
ArcanaType           # Lines 88-95
CardOrientation      # Lines 98-102
CardPosition         # Lines 105-110
TaroSessionStatus    # Lines 113-118
```

**Target Location**: `/plugins/taro/src/enums.py`

**Files That Need Import Updates**:
1. `/plugins/taro/src/models/arcana.py`
2. `/plugins/taro/src/models/taro_card_draw.py`
3. `/plugins/taro/src/models/taro_session.py`
4. `/plugins/taro/src/services/taro_session_service.py`
5. `/plugins/taro/src/routes.py`
6. `/plugins/taro/tests/**/*.py` (multiple test files)
7. `/vbwd-frontend/user/vue/src/**/*.ts` (frontend imports)

**Testing Strategy**:
- Write failing tests that expect NEW import paths
- Move enums
- Update all imports
- Verify all 1335+ tests still pass

**Estimated Effort**: 3-4 hours

---

### Migration 2: Analytics Route Duplication
**Current State**: Analytics logic duplicated in core and plugin

**Core Location**: `/src/routes/admin/analytics.py` (76 lines)
**Plugin Location**: `/plugins/analytics/src/routes.py`

**Migration Steps**:
1. Review both implementations
2. Move core route to plugin
3. Update admin dashboard to call plugin API
4. Remove core duplicate
5. Verify all admin tests still pass

**Testing Strategy**:
- Dashboard E2E tests verify API calls work
- Analytics endpoint tests pass

**Estimated Effort**: 2-3 hours

---

### Migration 3: Payment SDK Organization
**Current State**: Review-only (may not require action)

**Current Location**: `/src/sdk/` (payment adapters)
**Question**: Should these be in `/plugins/{stripe,paypal,yookassa}/src/sdk/`?

**Decision Needed**:
- If payment adapters are plugin-specific → move to plugins
- If shared across plugins → keep in core

**Estimated Effort**: 1-2 hours (review only)

---

## Sprint 3 Starting Checklist

### Pre-Sprint
- [ ] Read full sprint specification: `3-sprint-plugin-architecture-audit.md`
- [ ] Review audit findings in detail
- [ ] Identify all import paths that will change
- [ ] Plan test update strategy

### Phase 1: Taro Enum Migration
- [ ] Create `/plugins/taro/src/enums.py`
- [ ] Copy 4 enums from core
- [ ] Write tests for new location
- [ ] Update imports in 8+ files
- [ ] Run full test suite (target: 1335+ pass)
- [ ] Commit with clear message

### Phase 2: Analytics Route Migration
- [ ] Review both analytics implementations
- [ ] Plan deduplication strategy
- [ ] Write tests expecting plugin route
- [ ] Move core route to plugin
- [ ] Update admin dashboard
- [ ] Run admin E2E tests
- [ ] Commit with clear message

### Phase 3: Payment SDK Review
- [ ] Evaluate payment adapter organization
- [ ] Document decision
- [ ] If migration needed, execute similar to Phase 1
- [ ] Commit with clear message

### Phase 4: Verification
- [ ] Run full test suite: `make test-unit && make test` ✅ 1335+
- [ ] Run static analysis: `make lint` ✅ ALL PASS
- [ ] Manual sanity checks for critical features
- [ ] Create completion report

---

## Key Requirements for Sprint 3

### Testing (TDD-First)
- ✅ Zero existing tests should break
- ✅ All 1335+ tests must still pass
- ✅ New tests verify migration locations

### Code Quality
- ✅ No backward compatibility shims (old paths deleted completely)
- ✅ All imports verified with type checkers
- ✅ Clean imports (core ← plugins OK, plugins → core NOT OK)

### Architecture
- ✅ Core remains plugin-agnostic
- ✅ Each plugin self-contained
- ✅ No cross-plugin dependencies

---

## Success Criteria

Sprint 3 is complete when:
1. ✅ Taro enums moved and all imports updated
2. ✅ Analytics routes deduplicated
3. ✅ Payment SDK reviewed and decision documented
4. ✅ All 1335+ tests passing
5. ✅ Static analysis passing
6. ✅ No imports from plugins in core `/src/`

---

## Files to Review Before Starting

1. `/docs/devlog/20260216/todo/3-sprint-plugin-architecture-audit.md` - Full specification
2. `/plugins/taro/src/models/arcana.py` - Example of enum usage
3. `/src/models/enums.py` - Current enum locations
4. `/plugins/analytics/src/routes.py` - Analytics plugin implementation

---

## Command Reference

```bash
# Run all tests
cd vbwd-backend && make test-unit              # Backend: 960+
cd vbwd-frontend && make test                  # Frontend: 284+
# Expected total: 1335+

# Static analysis
cd vbwd-backend && make lint                   # BLACK, FLAKE8, MYPY

# After migrations, verify no core→plugin imports
grep -r "from plugins" /vbwd-backend/src/      # Should be EMPTY
```

---

## Notes for Sprint 3 Lead

- All prerequisites are complete and verified
- Test infrastructure is stable
- No architectural debt from Sprint 5
- Clean starting point for architectural improvements
- Full documentation available in sprint specification

**Status**: Ready to begin Sprint 3 ✅
