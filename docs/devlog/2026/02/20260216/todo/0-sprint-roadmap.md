# February 16, 2026 — Sprint Roadmap & Overlap Analysis

## Three Sprints Planned

| Sprint | Title | Priority | Duration | Status |
|--------|-------|----------|----------|--------|
| **1** | Plugin Architecture Audit & Migration | P0 | 5-7 days | 📋 Planned |
| **2** | Taro Card Display & Interpretation Loading | P0 | 2-3 days | 📋 Planned |
| **3** | (Reserved for follow-up improvements) | P1-P3 | TBD | 📋 Future |

---

## Sprint Details

### Sprint 1: Plugin Architecture Audit & Migration

**Location**: `docs/devlog/20260216/reports/3-sprint-plugin-architecture-audit.md`

**Goal**: Audit all 9 plugins and migrate plugin-specific code from core to plugin directories.

**Key Tasks**:
- Move Taro enums from `/src/models/enums.py` → `/plugins/taro/src/enums.py`
- Consolidate Analytics routes (core + plugin → plugin only)
- Update all imports to reflect new locations
- Verify core remains agnostic to plugins

**Files Modified**: 7 files across core and analytics plugin
**Test Count**: 632 baseline → 632 maintained (zero regressions)
**Estimated Effort**: 40-50 hours

---

### Sprint 2: Taro Card Display & Interpretation Loading

**Location**: `docs/devlog/20260216/reports/5-sprint-taro-card-display.md`

**Goal**: Display card images, names, and LLM-generated interpretations in card detail modal.

**Key Tasks**:
- Update API response to include full Arcana details
- Implement card display in modal (image, name, meaning)
- Add LLM interpretation loading and caching
- Verify complete card reading flow

**Files Modified**: 7 files (backend routes, frontend modal, tests)
**Test Count**: 741 baseline → ~755 (adds 14 new tests)
**Estimated Effort**: 15-20 hours

---

## Overlap Analysis

### ✅ Conclusion: NO MEANINGFUL OVERLAP

The two sprints are **fully compatible** and can run sequentially or in parallel.

### Detailed Breakdown

#### Shared Component: `plugins/taro/src/routes.py`

| Sprint | Changes | Impact |
|--------|---------|--------|
| **Sprint 1 (Audit)** | ❌ No changes | N/A |
| **Sprint 2 (Display)** | ✅ Adds Arcana fields + LLM call | Response structure enhanced |

**Compatibility**: ✅ **No conflict** — Display sprint only adds new fields, doesn't remove or reorganize existing ones

#### Shared Component: `plugins/taro/src/models/*.py`

| Sprint | Changes | Impact |
|--------|---------|--------|
| **Sprint 1 (Audit)** | ✅ Updates enum imports | From `src.models.enums` → `plugins.taro.src.enums` |
| **Sprint 2 (Display)** | ❌ No import changes | Uses enums however they're imported |

**Compatibility**: ✅ **No conflict** — Display sprint doesn't depend on import source

#### Shared Component: `plugins/taro/src/enums.py`

| Sprint | Changes | Impact |
|--------|---------|--------|
| **Sprint 1 (Audit)** | ✅ Creates file + populates with 4 enums | New plugin namespace file |
| **Sprint 2 (Display)** | ❌ No changes to file | Uses enums defined by Sprint 1 |

**Compatibility**: ✅ **No conflict** — Display sprint assumes enums exist (regardless of location)

#### Shared Directory: `plugins/taro/tests/`

| Sprint | Changes | Impact |
|--------|---------|--------|
| **Sprint 1 (Audit)** | ❌ No test changes | Existing tests still pass |
| **Sprint 2 (Display)** | ✅ Adds 3 new test files | New test coverage for features |

**Compatibility**: ✅ **No conflict** — Different test files, no overlap

---

## Recommended Execution Order

### Option A: Sequential (RECOMMENDED) ⭐

```
Timeline:
  Day 1-7:   Sprint 1 (Audit) ████████
  Day 8-10:  Sprint 2 (Display) ████
  Total: 10 days
```

**Benefits**:
- ✅ Cleaner git history
- ✅ Audit (foundational) done first
- ✅ Features built on clean architecture
- ✅ Easier to troubleshoot individual sprints

**Drawback**:
- ⏱️ Takes 10 days total (sequential)

---

### Option B: Parallel (POSSIBLE)

```
Timeline:
  Day 1-7:   Sprint 1 (Audit)     ████████
  Day 1-3:   Sprint 2 (Display)   ████ (overlaps)
  Total: 7 days
```

**Benefits**:
- ✅ Faster overall (7 days instead of 10)
- ✅ Can assign different teams

**Drawbacks**:
- ⚠️ Requires careful code review
- ⚠️ Potential merge conflicts in shared files
- ⚠️ Git history less linear

---

### Option C: Sprint 2 First (NOT RECOMMENDED) ⚠️

```
Timeline:
  Day 1-3:   Sprint 2 (Display)   ████
  Day 4-10:  Sprint 1 (Audit)     ████████
  Total: 10 days
```

**Why it works**:
- ✅ Display sprint doesn't depend on audit sprint
- ✅ Enums move doesn't affect route/modal logic

**Why it's not recommended**:
- ❌ Audit (P0) should be first priority
- ❌ Creates technical debt (unclean structure during Sprint 2)
- ❌ Harder to verify "clean core" while features use scattered code

---

## Execution Decision

**RECOMMENDED**: **Option A — Sequential Execution**

1. **Start Sprint 1 (Audit)** — Day 1
   - Establish clean architecture first
   - Move enums, consolidate routes
   - Verify all baseline tests pass
   - Estimated completion: Day 7

2. **Start Sprint 2 (Display)** — Day 8
   - Features built on clean foundation
   - Add card display + interpretation
   - Verify all baseline + new tests pass
   - Estimated completion: Day 10

---

## Risk Summary

### Sprint 1 Risks
| Risk | Severity | Mitigation |
|------|----------|-----------|
| Enum move breaks imports | MEDIUM | Full test suite validates imports |
| Analytics route consolidation breaks admin | MEDIUM | Frontend tests verify admin API calls |
| Circular imports emerge | LOW | Validation script in CI/CD |

### Sprint 2 Risks
| Risk | Severity | Mitigation |
|------|----------|-----------|
| LLM API fails, interpretation null | LOW | Graceful degradation (loading state) |
| SVG image URL invalid | MEDIUM | Data validation during population |
| Response payload too large | LOW | Monitor response size, implement caching |

**Overall Risk Level**: 🟢 **LOW** — Both sprints are low-risk with good test coverage

---

## Success Metrics

### Sprint 1 Success
- ✅ 632 backend tests passing (zero regressions)
- ✅ No plugin-specific code in `/src/`
- ✅ All plugins have correct directory structure
- ✅ Validation script integrated in CI/CD

### Sprint 2 Success
- ✅ 709+ frontend tests passing (new tests included)
- ✅ Card images render in modal
- ✅ Card names and meanings display
- ✅ LLM interpretations load and cache
- ✅ Complete E2E flow works: create session → view cards → see details

### Combined Success
- ✅ All 1341+ baseline tests passing
- ✅ Architecture enforced going forward
- ✅ User feature complete and working
- ✅ Ready for production deployment

---

## Files Created Today

### Reports (Detailed Specifications)
1. ✅ `1-report-card-system.md` — System architecture analysis
2. ✅ `2-architecture-guidelines.md` — Plugin architecture rules (CRITICAL)
3. ✅ `3-sprint-plugin-architecture-audit.md` — Detailed audit sprint specification
4. ✅ `5-sprint-taro-card-display.md` — Detailed display sprint specification
5. ✅ `0-sprint-roadmap.md` — This file (roadmap + overlap analysis)

### Documentation Structure

```
/docs/devlog/20260216/
├── reports/                    ← Sprint specifications & analysis
│   ├── 0-sprint-roadmap.md                 (this file)
│   ├── 1-report-card-system.md             (system analysis)
│   ├── 2-architecture-guidelines.md        (architecture rules)
│   ├── 3-sprint-plugin-architecture-audit.md (Sprint 1 detailed plan)
│   └── 5-sprint-taro-card-display.md       (Sprint 2 detailed plan)
├── todo/
│   └── tasks.md                            (user-facing todo list)
└── done/
    └── completed.md                        (completed tasks)
```

---

## Next Steps

### Immediate (Today)
- [ ] Review sprint specifications for clarity
- [ ] Approve execution order (recommend: Sequential Option A)
- [ ] Assign team members to sprints

### Sprint 1 Execution (When approved)
- [ ] Start Task 1: Create Taro enums file
- [ ] Follow task order through Task 15
- [ ] Verify all tests pass at each checkpoint
- [ ] Complete by estimated Day 7

### Sprint 2 Execution (When Sprint 1 complete)
- [ ] Start Task 1: Write response structure tests
- [ ] Follow task order through Task 14
- [ ] Complete manual smoke test
- [ ] Deploy to production by Day 10

---

## Questions & Clarifications

**Q: Can we run sprints in parallel?**
A: Yes, but sequential is recommended. See Option B above if speed is critical.

**Q: What if Sprint 1 takes longer than 5-7 days?**
A: Sprint 2 can start independently. They don't block each other.

**Q: Do we need to deploy after each sprint?**
A: Yes — both are P0 and should deploy after verification. Combined deploy at Day 10 is fine.

**Q: What about the P1/P2/P3 tasks from the original todo?**
A: Those become Sprint 3 (reserved for later). Current focus is Sprints 1 & 2 (P0 only).

---

**Roadmap Prepared**: February 16, 2026, 09:47 UTC
**Status**: ✅ Ready for execution
**Next Decision**: Approve execution order
