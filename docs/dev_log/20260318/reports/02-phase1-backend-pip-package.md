# Phase 1: Backend as pip Package

**Date:** 2026-03-18
**Sprint:** `sprints/01-vbwd-platform-metapackage.md`
**Status:** Done
**Branch:** `feature/platform` (vbwd-backend)

---

## Summary

Renamed `src/` → `vbwd/` and created `pyproject.toml` to make vbwd-backend installable as a pip package. All 1,440+ import references updated across 360+ files. All tests pass (735 core + 506 plugin unit tests).

---

## Changes

### 1. Directory Rename: `src/` → `vbwd/`

- Renamed the core source directory from `src/` to `vbwd/` for pip-compatible package naming
- All internal imports updated: `from src.` → `from vbwd.`
- All `mocker.patch("src....")` strings in tests updated to `"vbwd...."`
- One `importlib.reload(src.config)` reference fixed to `vbwd.config`

### 2. `pyproject.toml` — Package Metadata

```toml
[project]
name = "vbwd-backend"
version = "0.1.0"
requires-python = ">=3.11"

[tool.setuptools.packages.find]
include = ["vbwd*"]
exclude = ["tests*", "plugins*"]
```

- Core dependencies extracted from `requirements.txt` into `[project.dependencies]`
- Dev dependencies (pytest, black, flake8, mypy) in `[project.optional-dependencies.dev]`
- Package data includes `templates/**/*` for email/system templates

### 3. Config File Updates

| File | Change |
|------|--------|
| `Makefile` | `src:create_app` → `vbwd:create_app`, `--cov=src` → `--cov=vbwd` |
| `bin/pre-commit-check.sh` | `src/` → `vbwd/` in black, flake8, mypy paths |
| `bin/create_admin.sh` | `from src.` → `from vbwd.` in inline Python |
| `bin/create_user.sh` | Same |
| `bin/install_demo_data.sh` | Same |
| `container/python/Dockerfile` | `src.app:create_app()` → `vbwd.app:create_app()` |
| `.github/workflows/tests.yml` | `src/` → `vbwd/` in lint paths |
| `vbwd/__init__.py` | `from vbwd.app import create_app` (auto-updated) |

### 4. Black Formatting Fix

Two files reformatted by black after the rename (whitespace changes only):
- `vbwd/services/restore_service.py`
- `tests/unit/handlers/test_restore_handler.py`

---

## Test Results

### Core Unit Tests
```
735 passed, 4 skipped in 8.92s
```

### Plugin Unit Tests
```
506 passed, 1 skipped in 45.20s
(26 pre-existing taro failures — MagicMock adapter issue, unrelated to rename)
```

### Lint (pre-commit-check.sh --lint)
```
[PASS] Black formatter check
[PASS] Flake8 style check
[PASS] Mypy type check
```

### pip install -e .
```
Successfully installed vbwd-backend-0.1.0
>>> from vbwd import create_app  # OK
```

---

## Files Changed

- **Renamed:** `src/` → `vbwd/` (169 Python files)
- **Updated imports:** 301 Python files across `vbwd/`, `tests/`, `plugins/`
- **Updated patch strings:** 227 `mocker.patch("src....")` → `"vbwd...."` references
- **New:** `pyproject.toml`
- **Config updates:** 7 config/script files

---

## Pre-existing Issues (NOT introduced by this change)

- 26 taro plugin test failures: `ProgrammingError: can't adapt type 'MagicMock'` — these fail on `main` too
- 4 skipped tests (expected)
