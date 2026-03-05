# Quick Reference: LLM Language Testing

## Summary
- **87 Tests**: 77 unit + 10 integration
- **All Languages**: 8 tested (en, ru, de, fr, es, ja, th, zh)
- **Status**: ✅ Production Ready

---

## Run All Unit Tests (77 tests)

```bash
docker compose exec api pytest \
  plugins/taro/tests/unit/services/test_prompt_service.py::TestLanguageVariableRendering \
  plugins/taro/tests/unit/services/test_taro_session_service.py::TestLanguageParameterFlow \
  plugins/taro/tests/unit/routes/test_taro_routes.py::TestLanguageParameterInRoutes \
  plugins/taro/tests/unit/services/test_language_flow.py \
  -v
```

**Expected**: ✅ 77 passed in ~3.5 seconds

---

## Run Integration Tests (10 tests, needs real LLM API)

```bash
# All integration tests
docker compose exec api pytest plugins/taro/tests/integration/test_real_llm_language.py -v -s

# Specific test
docker compose exec api pytest \
  plugins/taro/tests/integration/test_real_llm_language.py::TestRealLLMLanguageCommunication::test_real_llm_situation_reading_with_russian_language \
  -v -s
```

**Expected**: Real LLM responses in requested language

---

## Skip Integration Tests (CI/CD)

```bash
export SKIP_LLM_TESTS=1
make pre-commit-quick
```

---

## Test Breakdown by Phase

### Phase 1: Template Rendering (14 tests)
```bash
pytest plugins/taro/tests/unit/services/test_prompt_service.py::TestLanguageVariableRendering -v
```
**Validates**: Jinja2 renders `{{language}}` correctly

### Phase 2: Service Layer (18 tests)
```bash
pytest plugins/taro/tests/unit/services/test_taro_session_service.py::TestLanguageParameterFlow -v
```
**Validates**: Language parameter flows through service + mocked LLM

### Phase 3: Route Layer (23 tests)
```bash
pytest plugins/taro/tests/unit/routes/test_taro_routes.py::TestLanguageParameterInRoutes -v
```
**Validates**: Routes extract and pass language parameter

### Phase 4: E2E Flow (22 tests)
```bash
pytest plugins/taro/tests/unit/services/test_language_flow.py -v
```
**Validates**: Complete flow with real PromptService + mocked LLM

---

## Configuration

Edit to add real LLM credentials:
```bash
vbwd-backend/plugins/config.json
```

Required fields:
```json
{
  "taro": {
    "llm_api_endpoint": "https://api.deepseek.com",
    "llm_api_key": "sk-...",
    "llm_model": "deepseek-reasoner"
  }
}
```

---

## Files Created

### Unit Tests (77 tests)
- `test_prompt_service.py::TestLanguageVariableRendering` — 14 tests
- `test_taro_session_service.py::TestLanguageParameterFlow` — 18 tests
- `test_taro_routes.py::TestLanguageParameterInRoutes` — 23 tests
- `test_language_flow.py` — 22 tests (NEW)

### Integration Tests (10 tests)
- `tests/integration/test_real_llm_language.py` — 10 tests (NEW)

### Documentation
- `SPRINT_LLM_LANGUAGE_TESTING.md` — Sprint specification
- `TASKS_CHECKLIST.md` — Task tracking
- `status.md` — Daily status
- `SPRINT_COMPLETED.md` — Completion report
- `INTEGRATION_TEST_CREATED.md` — Integration guide
- `SESSION_SUMMARY.md` — Full session summary
- `QUICK_REFERENCE.md` — This file

---

## Languages Tested

| Code | Language | Status |
|------|----------|--------|
| en | English | ✅ |
| ru | Русский (Russian) | ✅ |
| de | Deutsch (German) | ✅ |
| fr | Français (French) | ✅ |
| es | Español (Spanish) | ✅ |
| ja | 日本語 (Japanese) | ✅ |
| th | ไทย (Thai) | ✅ |
| zh | 中文 (Chinese) | ✅ |

---

## Endpoints Tested

| Endpoint | Tests | Status |
|----------|-------|--------|
| `/situation` | 11 | ✅ |
| `/card-explanation` | 8 | ✅ |
| `/follow-up-question` | 13 | ✅ |

---

## What's Fixed

**Before**: LLM responses in English even when language="ru"
**Problem**: Invalid Jinja2 syntax `{{language|English}}`
**After**: Fixed syntax `{{language}}`
**Result**: Language instruction renders correctly in all prompts

---

## Key Commands

| Task | Command |
|------|---------|
| Run all unit tests | `pytest plugins/taro/tests/unit/... -v` |
| Run integration tests | `pytest plugins/taro/tests/integration/... -v -s` |
| Skip integration tests | `SKIP_LLM_TESTS=1 make pre-commit-quick` |
| Run Phase 1 only | `pytest test_prompt_service.py::TestLanguageVariableRendering -v` |
| Run Phase 2 only | `pytest test_taro_session_service.py::TestLanguageParameterFlow -v` |
| Run Phase 3 only | `pytest test_taro_routes.py::TestLanguageParameterInRoutes -v` |
| Run Phase 4 only | `pytest test_language_flow.py -v` |

---

## Test Times

| Component | Duration |
|-----------|----------|
| Template Rendering | 0.25s |
| Service Layer | 1.69s |
| Route Layer | 0.28s |
| E2E Flow | 2.24s |
| **Total Unit** | **3.45s** |
| Integration (1 test) | ~6-10s* |
| **(*with real LLM)** | |

---

## Static Analysis

All code passes:
- ✅ Black formatting
- ✅ Flake8 linting
- ✅ MyPy type checking
- ✅ Zero regressions

---

## Documentation

- **Sprint Plan**: `SPRINT_LLM_LANGUAGE_TESTING.md`
- **Tasks**: `TASKS_CHECKLIST.md`
- **Integration Guide**: `tests/integration/README.md`
- **Full Summary**: `SESSION_SUMMARY.md`

---

**Status**: ✅ Ready for Production
**Last Updated**: February 19, 2026
