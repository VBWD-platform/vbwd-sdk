# Sprint Task: Update Installation Scripts for New Repository Structure

**Created**: 2026-02-21
**Priority**: 🔴 High
**Complexity**: Medium (3-4 hours estimated)
**Blocking**: Developer onboarding, setup documentation
**Status**: 🟡 Planned

---

## Problem Statement

The installation scripts (dev-install-ce.sh and dev-install-taro.sh) were written for the old monorepo structure where all frontend code was in `vbwd-frontend/`. With the recent split into 3 independent GitHub repositories, the scripts are now outdated and will fail during fresh setup.

**Impact**: New developers cannot easily set up the development environment.

---

## Required Changes

### 1. dev-install-ce.sh
**Current Location**: `/Users/dantweb/dantweb/vbwd-sdk/recipes/dev-install-ce.sh`

**Old Assumptions**:
```bash
# Old structure
vbwd-sdk/
└── vbwd-frontend/
    ├── user/vue/
    ├── admin/vue/
    └── core/
```

**New Reality**:
```bash
# New structure
vbwd-sdk/
├── vbwd-fe-core/          (separate GitHub repo)
│   ├── .git
│   ├── package.json
│   └── dist/
├── vbwd-fe-user/          (separate GitHub repo, has submodule)
│   ├── .git
│   ├── vbwd-fe-core/      ← git submodule
│   ├── package.json
│   └── node_modules/
├── vbwd-fe-admin/         (separate GitHub repo, has submodule)
│   ├── .git
│   ├── vbwd-fe-core/      ← git submodule
│   ├── package.json
│   └── node_modules/
└── vbwd-backend/
```

**Required Updates**:
1. Clone vbwd-fe-core separately first
2. Clone vbwd-fe-user with `--recurse-submodules`
3. Clone vbwd-fe-admin with `--recurse-submodules`
4. Build vbwd-fe-core: `npm install && npm run build`
5. Build vbwd-fe-user: `npm install`
6. Build vbwd-fe-admin: `npm install`

**New Script Structure**:
```bash
#!/bin/bash
set -e

# 1. Clone vbwd-fe-core (base library)
git clone https://github.com/dantweb/vbwd-fe-core.git vbwd-fe-core
cd vbwd-fe-core
npm install
npm run build  # Generate dist files needed by other repos
cd ..

# 2. Clone vbwd-fe-user with submodules
git clone --recurse-submodules https://github.com/dantweb/vbwd-fe-user.git vbwd-fe-user
cd vbwd-fe-user
npm install
cd ..

# 3. Clone vbwd-fe-admin with submodules
git clone --recurse-submodules https://github.com/dantweb/vbwd-fe-admin.git vbwd-fe-admin
cd vbwd-fe-admin
npm install
cd ..

# 4. Backend (unchanged)
git clone https://github.com/dantweb/vbwd-backend.git vbwd-backend
cd vbwd-backend
# ... existing backend setup
cd ..

echo "✓ All repositories cloned and dependencies installed"
```

### 2. dev-install-taro.sh
**Current Location**: `/Users/dantweb/dantweb/vbwd-sdk/recipes/dev-install-taro.sh`

**Changes Needed**:
1. Update path references from `vbwd-frontend/user/vue/` to `vbwd-fe-user/`
2. Update any commands that installed taro plugin
3. Verify plugin installation still works with new structure
4. Update import paths if script modifies config files

**Example updates**:
```bash
# Old
cd vbwd-frontend/user/vue
npm install @taro/plugin

# New
cd vbwd-fe-user
npm install @taro/plugin
```

---

## Testing Checklist

- [ ] **Fresh install test**: Run dev-install-ce.sh on clean directory
  - [ ] All repos clone successfully
  - [ ] All npm installs complete
  - [ ] No missing dependencies
  - [ ] Type checks pass in all repos
  - [ ] Linting passes in all repos

- [ ] **Taro setup test**: Run dev-install-taro.sh
  - [ ] Taro plugin installs correctly
  - [ ] Plugin configuration applies properly
  - [ ] Taro features available in vbwd-fe-user

- [ ] **Manual verification**:
  - [ ] `cd vbwd-fe-user && npm run dev` works
  - [ ] `cd vbwd-fe-admin && npm run dev` works
  - [ ] Both apps can import from vbwd-view-component
  - [ ] TypeScript compilation passes

---

## Dependencies

✅ **Completed**: vbwd-fe-* split with git submodules (2026-02-20)

This task depends on the completion of the repository split and is now ready to proceed.

---

## Documentation Updates

After completing the scripts, update:
1. `/docs/dev-setup.md` - Installation instructions
2. `README.md` - Quick start guide
3. Any other docs referencing old monorepo structure

---

## References

- **Previous Work**: [20260220-REPORT-frontend-split.md](../20260220-REPORT-frontend-split.md)
- **Repository Structure**: See status.md for directory layout
- **Git Submodules**: User/Admin repos contain vbwd-fe-core as submodule

---

## Acceptance Criteria

✅ Task complete when:
1. Both scripts updated and tested
2. Fresh install from scratch works
3. All tests pass in all 3 repos
4. Developer can build and run all apps locally
5. Documentation updated with new structure
6. Scripts have clear comments explaining the multi-repo setup

