# Sprint Tasks Checklist
**Sprint**: LLM Language Testing & Validation
**Date**: February 19, 2026
**Total Tasks**: 16
**Estimated Duration**: ~4 hours

---

## Phase 1: Template Rendering Tests (30 min)
**Goal**: Validate Jinja2 template correctly renders `{{language}}` variable

### Task 1.1: Write Template Rendering Unit Tests
**File**: `plugins/taro/tests/unit/services/test_prompt_service.py`

- [ ] Create test for single language variable rendering
  - Input: `"RESPOND IN {{language}} LANGUAGE."`
  - Language: "Русский (Russian)"
  - Assert: "RESPOND IN Русский (Russian) LANGUAGE." in result

- [ ] Create parametrized test for all 8 languages
  - Languages: en, ru, de, fr, es, ja, th, zh
  - Assert: Each produces correct output

- [ ] Test PromptService.render() with language variable
  - Use real PromptService
  - Verify language in situation_reading template

**Expected**: Tests FAIL initially (validate test quality), then verify behavior

---

### Task 1.2: Verify Config Fix Works
**File**: `vbwd-backend/plugins/taro/config.json`

- [ ] Confirm syntax is `{{language}}` (not `{{language|English}}`)
- [ ] Run template tests against actual config
- [ ] Verify all language tests PASS
- [ ] All 3 templates fixed:
  - [ ] situation_reading_template (line 59)
  - [ ] card_explanation_template (line 64)
  - [ ] follow_up_question_template (line 69)

**Expected**: All template tests PASS

---

## Phase 2: Service Layer Tests (1 hour)
**Goal**: Verify service passes language to mocked LLM adapter

### Task 2.1: Mock LLMAdapter & Write Service Tests
**File**: `plugins/taro/tests/unit/services/test_taro_session_service.py`

- [ ] Create fixture for mocked LLMAdapter
  ```python
  @pytest.fixture
  def mock_llm_adapter():
      mock = Mock()
      mock.chat.return_value = "Mocked LLM response"
      return mock
  ```

- [ ] Write test: `test_generate_situation_reading_with_mocked_llm`
  - Setup: Create service with mocked LLM
  - Action: Call service.generate_situation_reading(language="ru")
  - Assert: mock.chat() was called
  - Assert: Prompt contains "RESPOND IN Русский (Russian) LANGUAGE."

- [ ] Write test: `test_language_parameter_passed_to_llm_adapter`
  - Verify language parameter flows: route → service → mocked LLM

**Expected**: Tests PASS (service already implements language)

---

### Task 2.2: Verify Language Code Conversion
**File**: `plugins/taro/tests/unit/services/test_taro_session_service.py`

- [ ] Test: `test_get_language_name_conversion`
  - Call: `TaroSessionService._get_language_name("ru")`
  - Assert: Returns "Русский (Russian)"
  - Repeat for all 8 language codes

- [ ] Test: `test_get_language_name_invalid_defaults_to_english`
  - Call: `_get_language_name("invalid")`
  - Assert: Returns "English"

**Expected**: Tests PASS

---

### Task 2.3: Parametrized Tests for All Languages
**File**: `plugins/taro/tests/unit/services/test_taro_session_service.py`

- [ ] Create parametrized test: `test_situation_reading_all_languages`
  - @pytest.mark.parametrize with all 8 language codes
  - For each: Setup session, call service, verify language in prompt
  - Assert: Correct language instruction for each

- [ ] Create parametrized test: `test_answer_oracle_question_all_languages`
  - Same as above but for follow-up questions

- [ ] Create parametrized test: `test_all_endpoints_respect_language`
  - Test situation_reading, answer_oracle_question, card explanation

**Expected**: All 8 languages validated, tests PASS

---

## Phase 3: Route Layer Tests (1 hour)
**Goal**: Verify routes accept & pass language parameter

### Task 3.1: Write Route Integration Tests
**File**: `plugins/taro/tests/unit/routes/test_taro_routes.py`

- [ ] Test: `test_submit_situation_accepts_language_parameter`
  - POST /api/v1/taro/session/{id}/situation
  - JSON: `{situation_text: "...", language: "ru"}`
  - Mock service.generate_situation_reading()
  - Assert: Mock called with language="ru"

- [ ] Test: `test_submit_situation_extracts_language_from_request`
  - Verify route parses JSON correctly
  - Test missing language (should default to "en")

**Expected**: Tests PASS

---

### Task 3.2: Test Card Explanation Endpoint
**File**: `plugins/taro/tests/unit/routes/test_taro_routes.py`

- [ ] Test: `test_card_explanation_accepts_language`
  - POST /api/v1/taro/session/{id}/card-explanation
  - JSON: `{language: "de"}`
  - Verify language passed to service

- [ ] Test: `test_card_explanation_all_languages`
  - Parametrized test for all 8 languages

**Expected**: Tests PASS

---

### Task 3.3: Test Follow-Up Question Endpoint
**File**: `plugins/taro/tests/unit/routes/test_taro_routes.py`

- [ ] Test: `test_follow_up_question_accepts_language`
  - POST /api/v1/taro/session/{id}/follow-up-question
  - JSON: `{question: "...", language: "fr"}`
  - Verify language passed to service

- [ ] Test: `test_follow_up_question_all_languages`
  - Parametrized test for all 8 languages

**Expected**: Tests PASS

---

## Phase 4: End-to-End Tests (45 min)
**Goal**: Complete flow with real PromptService + mocked LLM

### Task 4.1: Create Complete Flow Test File
**File**: `plugins/taro/tests/unit/services/test_language_flow.py` (NEW)

- [ ] Create test: `test_complete_language_flow_situation_reading`
  - Setup: Real PromptService + real config.json
  - Setup: Real session with cards + mocked LLM
  - Action: Call service.generate_situation_reading(language="ru")
  - Assert: Correct prompt sent to LLM
  - Assert: Language instruction in prompt
  - Assert: Cards context in prompt
  - Assert: Situation text in prompt

- [ ] Create test: `test_complete_language_flow_all_endpoints`
  - Same as above for all 3 endpoints
  - situation_reading, answer_oracle_question, card_explanation

**Expected**: Tests PASS with real config & full context

---

### Task 4.2: Language Code Mapping Tests
**File**: `plugins/taro/tests/unit/services/test_language_flow.py`

- [ ] Test: `test_all_8_language_codes_convert_correctly`
  - Verify each code → full name mapping
  - en → English
  - ru → Русский (Russian)
  - de → Deutsch (German)
  - fr → Français (French)
  - es → Español (Spanish)
  - ja → 日本語 (Japanese)
  - th → ไทย (Thai)
  - zh → 中文 (Chinese)

- [ ] Test: `test_language_code_case_insensitive`
  - Call: `_get_language_name("RU")`
  - Assert: Returns "Русский (Russian)"

- [ ] Test: `test_invalid_language_code_defaults_to_english`
  - Call: `_get_language_name("invalid")`
  - Assert: Returns "English"

**Expected**: Tests PASS

---

## Phase 5: Pre-commit Verification (30 min)
**Goal**: Validate all tests pass with pre-commit script

### Task 5.1: Run Full Backend Test Suite
**Command**: `cd vbwd-backend && make pre-commit-quick`

- [ ] Static Analysis PASSES
  - [ ] black formatting OK
  - [ ] flake8 linting OK
  - [ ] mypy type checking OK

- [ ] Unit Tests PASS
  - [ ] All 715+ original tests PASS
  - [ ] All 25-30 new tests PASS
  - [ ] Zero regressions
  - [ ] Final count: 740-745 tests

- [ ] Report Results
  - [ ] Document test count before/after
  - [ ] Verify no regressions

**Expected**: All tests PASS, pre-commit succeeds

---

### Task 5.2: Manual Verification (Optional)
**Goal**: Validate behavior manually if LLM available

- [ ] Create session in frontend with Russian language selected
- [ ] Submit situation or ask for card explanation
- [ ] Check network request includes `language: "ru"`
- [ ] If LLM available: Verify response is in Russian
  - [ ] Not "Interpretation of Your Tarot Spread" (English)
  - [ ] But rather Russian equivalent

**Expected**: Frontend → Backend → LLM flow works with language

---

## Summary of Tests to Create/Modify

### New Files
- [ ] `plugins/taro/tests/unit/services/test_language_flow.py`
  - ~12 tests: Template rendering, complete flow, language mapping

### Modified Files
- [ ] `plugins/taro/tests/unit/services/test_taro_session_service.py`
  - +8 tests: Service layer with mocked LLM, language conversion, parametrized tests

- [ ] `plugins/taro/tests/unit/routes/test_taro_routes.py`
  - +5 tests: All 3 endpoints, all 8 languages, parametrized

### Updated/Created
- [ ] `plugins/taro/tests/unit/services/test_prompt_service.py`
  - +5 tests: Template rendering, Jinja2 validation, all languages

**Total New Tests**: 25-30
**Total Test Count After**: 740-745

---

## Success Checklist

### Code Quality
- [ ] All new tests follow TDD (test → implementation)
- [ ] Test names are clear and descriptive
- [ ] No duplicate test logic (DRY)
- [ ] Mocks are proper substitutes (SOLID)
- [ ] No over-engineering
- [ ] No deprecated methods
- [ ] Code passes black, flake8, mypy

### Test Coverage
- [ ] Template rendering validated ✓
- [ ] Language parameter flow validated ✓
- [ ] All 8 languages tested ✓
- [ ] All 3 endpoints tested ✓
- [ ] Service layer with mocked LLM ✓
- [ ] Complete end-to-end flow ✓

### Pre-commit Validation
- [ ] `make pre-commit-quick` PASSES ✓
- [ ] Zero regressions in existing tests ✓
- [ ] All new tests PASS ✓

---

## Time Tracking

| Phase | Task | Estimated | Actual | Status |
|-------|------|-----------|--------|--------|
| 1 | 1.1 Template tests | 15 min | - | 🔲 |
| 1 | 1.2 Config verify | 15 min | - | 🔲 |
| 2 | 2.1 Mock LLM tests | 20 min | - | 🔲 |
| 2 | 2.2 Language conversion | 20 min | - | 🔲 |
| 2 | 2.3 Parametrized tests | 20 min | - | 🔲 |
| 3 | 3.1 Route tests | 20 min | - | 🔲 |
| 3 | 3.2 Explanation endpoint | 20 min | - | 🔲 |
| 3 | 3.3 Follow-up endpoint | 20 min | - | 🔲 |
| 4 | 4.1 E2E flow tests | 25 min | - | 🔲 |
| 4 | 4.2 Language mapping | 20 min | - | 🔲 |
| 5 | 5.1 Pre-commit validation | 20 min | - | 🔲 |
| 5 | 5.2 Manual verification | 10 min | - | 🔲 |
| | **TOTAL** | **~4 hours** | | 🔲 |

---

## Notes

- Mark [ ] with [x] as you complete each task
- Update "Actual" time column as you work
- If task takes longer than estimated, note reason
- Keep this checklist visible while working
- Run tests frequently (TDD approach)
- Pre-commit validation is CRITICAL - don't skip it

---

**Created**: February 19, 2026, 14:50 UTC
**Status**: 🚀 Ready to Begin
**Next Task**: Start Task 1.1 - Write template rendering tests
