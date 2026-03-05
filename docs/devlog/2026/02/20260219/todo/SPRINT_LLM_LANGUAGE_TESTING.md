# Sprint: LLM Language Testing & Validation
**Date**: February 19, 2026
**Status**: 🚀 In Progress
**Priority**: P0 (Blocks production)
**Estimated Duration**: 1-2 days

---

## Sprint Goal

Implement comprehensive unit tests that validate the language parameter flows correctly through the entire backend pipeline from route → service → prompt template → LLM adapter, ensuring LLM responses are generated in the user's selected language (Russian, German, French, etc.) instead of defaulting to English.

---

## Core Requirements (Non-Negotiable)

All work MUST follow these principles:

- **TDD (Test-Driven Development)**: Write failing tests FIRST, then implement code to pass them
- **SOLID Principles**:
  - Single Responsibility: Each test validates one behavior
  - Open/Closed: Tests extensible for new languages without modification
  - Liskov Substitution: Mock adapters are true substitutes
  - Interface Segregation: Tests use only needed mock methods
  - Dependency Injection: All dependencies explicitly passed to services
- **DI (Dependency Injection)**: Mock LLM adapter injected into service for testing
- **DRY (Don't Repeat Yourself)**: Reusable fixtures and parametrized tests for multiple languages
- **No Over-Engineering**: Tests are simple, focused, and readable
- **No Deprecated Methods**: Delete unused code immediately, don't create stubs
- **Clean Code**: Clear test names, minimal setup, obvious assertions
- **Pre-commit Validation**: All tests must pass `make pre-commit-quick` before commit

---

## Problem Statement

**Current Issue**: Despite frontend sending `language: "ru"` correctly, LLM responses are in English.

**Root Cause Found**: Invalid Jinja2 syntax in config.json (`{{language|English}}`) caused template variable to render as empty, dropping the language instruction.

**Fix Applied**: Corrected syntax to `{{language}}` in all 3 prompt templates.

**Remaining Work**: Validate the fix with comprehensive tests proving the language parameter flows through the entire system.

---

## Test Validation Strategy

### Test 1: Template Rendering (Unit)
**File**: `plugins/taro/tests/unit/services/test_prompt_service.py`

**Validates**:
- Jinja2 template correctly renders `{{language}}` variable
- Language instruction appears in final prompt
- Multiple language codes produce correct output

```python
def test_jinja2_template_renders_language_variable():
    """Verify {{language}} renders correctly in prompt template."""
    template_str = "RESPOND IN {{language}} LANGUAGE."
    template = Template(template_str)

    result = template.render(language="Русский (Russian)")
    assert "RESPOND IN Русский (Russian) LANGUAGE." in result

def test_prompt_service_renders_language_for_situation_reading():
    """Verify PromptService renders language in situation_reading template."""
    prompt_service = PromptService.from_dict({
        'situation_reading': {
            'template': 'RESPOND IN {{language}} LANGUAGE.\n\nSituation: {{situation_text}}'
        }
    })

    prompt = prompt_service.render('situation_reading', {
        'language': 'Deutsch (German)',
        'situation_text': 'Test situation'
    })

    assert 'RESPOND IN Deutsch (German) LANGUAGE.' in prompt

@pytest.mark.parametrize("lang_code,lang_name", [
    ("en", "English"),
    ("ru", "Русский (Russian)"),
    ("de", "Deutsch (German)"),
    ("fr", "Français (French)"),
    ("es", "Español (Spanish)"),
    ("ja", "日本語 (Japanese)"),
    ("th", "ไทย (Thai)"),
    ("zh", "中文 (Chinese)"),
])
def test_prompt_service_renders_all_supported_languages(lang_code, lang_name):
    """Verify PromptService renders all 8 languages correctly."""
    # Implementation...
```

---

### Test 2: Service Layer (Unit with Mocked LLM)
**File**: `plugins/taro/tests/unit/services/test_taro_session_service.py`

**Validates**:
- Service correctly converts language code to full name
- Service passes language to prompt rendering
- Service calls LLM with language instruction in prompt

```python
def test_generate_situation_reading_with_mocked_llm():
    """Verify service passes language parameter to mocked LLM adapter."""
    from unittest.mock import Mock, patch

    # Create mock LLM adapter
    mock_llm = Mock()
    mock_llm.chat.return_value = "Мой ответ на русском языке"

    # Create service with mocked LLM
    service = TaroSessionService(
        arcana_repo=mock_arcana_repo,
        session_repo=mock_session_repo,
        card_draw_repo=mock_card_draw_repo,
        llm_adapter=mock_llm,
        prompt_service=mock_prompt_service,
    )

    # Call service with Russian language
    result = service.generate_situation_reading(
        session_id="session-123",
        situation_text="My career decision",
        language="ru"
    )

    # Verify LLM was called
    assert mock_llm.chat.called

    # Extract the prompt that was passed to LLM
    call_args = mock_llm.chat.call_args
    prompt_passed_to_llm = call_args[1]['messages'][0]['content']

    # Verify language instruction is in the prompt
    assert "RESPOND IN Русский (Russian) LANGUAGE." in prompt_passed_to_llm

@pytest.mark.parametrize("lang_code,expected_lang_name", [
    ("ru", "Русский (Russian)"),
    ("de", "Deutsch (German)"),
    ("fr", "Français (French)"),
])
def test_situation_reading_respects_different_languages(lang_code, expected_lang_name):
    """Verify service correctly handles different language codes."""
    # Mock setup...

    result = service.generate_situation_reading(
        session_id="session-123",
        situation_text="Test situation",
        language=lang_code
    )

    # Verify the correct language was passed to LLM
    call_args = mock_llm.chat.call_args
    prompt = call_args[1]['messages'][0]['content']
    assert f"RESPOND IN {expected_lang_name} LANGUAGE." in prompt
```

---

### Test 3: Route Layer (Integration)
**File**: `plugins/taro/tests/unit/routes/test_taro_routes.py`

**Validates**:
- Route correctly extracts language from request JSON
- Route passes language to service method
- Response contains language-aware interpretation

```python
def test_submit_situation_route_with_language_parameter(client, test_session):
    """Verify /situation endpoint accepts and uses language parameter."""
    from unittest.mock import patch

    with patch('plugins.taro.src.services.taro_session_service.TaroSessionService.generate_situation_reading') as mock_method:
        mock_method.return_value = "Ответ на русском языке"

        response = client.post(
            f'/api/v1/taro/session/{test_session.id}/situation',
            json={
                'situation_text': 'My career question',
                'language': 'ru'
            },
            headers={'Authorization': f'Bearer {test_token}'}
        )

        # Verify endpoint called service with language
        mock_method.assert_called_once()
        call_kwargs = mock_method.call_args[1]
        assert call_kwargs['language'] == 'ru'

@pytest.mark.parametrize("lang_code", ["en", "ru", "de", "fr", "es", "ja", "th", "zh"])
def test_submit_situation_route_accepts_all_languages(client, test_session, lang_code):
    """Verify /situation endpoint accepts all 8 supported languages."""
    # Implementation...
    assert response.status_code == 200

def test_card_explanation_route_with_language():
    """Verify /card-explanation endpoint passes language to service."""
    # Similar to submit_situation test...

def test_follow_up_question_route_with_language():
    """Verify /follow-up-question endpoint passes language to service."""
    # Similar to submit_situation test...
```

---

### Test 4: End-to-End Behavior (Integration)
**File**: `plugins/taro/tests/unit/services/test_language_flow.py` (NEW)

**Validates**:
- Complete flow: language code → service → PromptService → rendered prompt contains instruction
- Language conversion (code → full name) is accurate
- PromptService correctly loads config with fixed templates

```python
def test_complete_language_flow_situation_reading():
    """Test complete flow: route → service → prompt → language instruction."""
    # Setup real PromptService with actual config.json
    prompt_service = PromptService(
        prompts_file="/path/to/plugins/taro/config.json"
    )

    # Mock LLM adapter
    mock_llm = Mock()
    mock_llm.chat.return_value = "Russian response"

    # Create service
    service = TaroSessionService(
        arcana_repo=real_arcana_repo,
        session_repo=real_session_repo,
        card_draw_repo=real_card_draw_repo,
        llm_adapter=mock_llm,
        prompt_service=prompt_service,
    )

    # Create session with real cards
    session = service.create_session(user_id="user-123")

    # Call with Russian language
    result = service.generate_situation_reading(
        session_id=str(session.id),
        situation_text="Career decision",
        language="ru"
    )

    # Verify flow
    assert mock_llm.chat.called
    prompt_sent = mock_llm.chat.call_args[1]['messages'][0]['content']
    assert "RESPOND IN Русский (Russian) LANGUAGE." in prompt_sent
    assert "Career decision" in prompt_sent
    assert "Card" in prompt_sent  # Cards context should be included

def test_language_code_to_name_conversion():
    """Verify _get_language_name conversion for all 8 languages."""
    conversions = {
        'en': 'English',
        'de': 'Deutsch (German)',
        'es': 'Español (Spanish)',
        'fr': 'Français (French)',
        'ja': '日本語 (Japanese)',
        'ru': 'Русский (Russian)',
        'th': 'ไทย (Thai)',
        'zh': '中文 (Chinese)',
    }

    for code, expected_name in conversions.items():
        result = TaroSessionService._get_language_name(code)
        assert result == expected_name, f"Code '{code}' should map to '{expected_name}', got '{result}'"
```

---

## Implementation Tasks (TDD Order)

### Phase 1: Template Rendering Tests (Foundation)
- [ ] **Task 1.1**: Write template rendering tests (test_prompt_service.py)
  - Test single language render
  - Test all 8 languages parametrized
  - Verify language instruction appears in output
  - Expected: Tests FAIL initially

- [ ] **Task 1.2**: Verify config.json fixes template syntax
  - Run tests against actual config.json with fixed syntax
  - Verify all tests PASS
  - Expected: Tests PASS after config fix

---

### Phase 2: Service Layer Tests
- [ ] **Task 2.1**: Write service unit tests with mocked LLM
  - Mock LLMAdapter.chat()
  - Inject into TaroSessionService
  - Call generate_situation_reading() with language="ru"
  - Assert mocked chat() was called with correct prompt
  - Expected: Tests FAIL initially (no language handling)

- [ ] **Task 2.2**: Implement/verify language parameter flow
  - Service receives `language` parameter
  - Calls `_get_language_name(language)` to convert code
  - Passes `language_name` to prompt_service.render()
  - Expected: Tests PASS after code review (already implemented)

- [ ] **Task 2.3**: Add parametrized tests for all 8 languages
  - @pytest.mark.parametrize with all language codes
  - Verify each language produces correct instruction in prompt
  - Expected: Tests PASS

---

### Phase 3: Route Layer Tests
- [ ] **Task 3.1**: Write route integration tests
  - POST /session/{id}/situation with language parameter
  - Verify route extracts language from JSON
  - Mock service method to verify language is passed
  - Expected: Tests PASS (routes already implemented)

- [ ] **Task 3.2**: Test all 3 endpoints (situation, explanation, follow-up)
  - /situation endpoint
  - /card-explanation endpoint
  - /follow-up-question endpoint
  - Expected: Tests PASS

---

### Phase 4: End-to-End Validation
- [ ] **Task 4.1**: Create new test file for complete flow
  - test_language_flow.py
  - Use real PromptService + mocked LLM
  - Create real session + cards
  - Verify complete pipeline works

- [ ] **Task 4.2**: Test language code conversion function
  - Verify _get_language_name() for all 8 languages
  - Test invalid codes default to English
  - Expected: Tests PASS

---

### Phase 5: Pre-commit Verification
- [ ] **Task 5.1**: Run full test suite
  ```bash
  cd vbwd-backend
  make pre-commit-quick
  ```
  - All new tests must PASS
  - No regressions in existing tests
  - All 8 languages validated

- [ ] **Task 5.2**: Manual verification (Optional but recommended)
  - Create session in browser with Russian UI
  - Request card explanation with language: "ru"
  - Verify LLM response is in Russian (if LLM available)

---

## Test Files To Create/Modify

### New Test Files
1. **`plugins/taro/tests/unit/services/test_language_flow.py`**
   - Complete end-to-end language flow tests
   - Real config.json + mocked LLM

### Modified Test Files
1. **`plugins/taro/tests/unit/services/test_taro_session_service.py`**
   - Add mocked LLM tests for generate_situation_reading()
   - Add parametrized language tests
   - Add answer_oracle_question() language tests

2. **`plugins/taro/tests/unit/routes/test_taro_routes.py`**
   - Add tests for language parameter in request JSON
   - Verify language passed to service layer
   - Test all 3 endpoints (situation, explanation, follow-up)

3. **`plugins/taro/tests/unit/services/test_prompt_service.py`** (if doesn't exist)
   - Template rendering with language variable
   - Config.json integration
   - All 8 languages parametrized

---

## Code Review Checklist

Before each commit:

- [ ] All new tests FAIL initially (TDD validation)
- [ ] All new tests PASS after implementation
- [ ] Test names clearly describe what they validate
- [ ] Mock objects are true substitutes (SOLID)
- [ ] No duplicate test logic (DRY)
- [ ] No over-engineering (tests are simple)
- [ ] No deprecated/unused code
- [ ] Code follows project style (black, flake8, mypy)
- [ ] `make pre-commit-quick` passes completely

---

## Success Criteria

### ✅ Tests Must Prove

1. **Language Parameter Flow**
   - Route accepts `language` in JSON ✅
   - Service receives `language` parameter ✅
   - Service converts code to full name ✅
   - Service passes to prompt_service.render() ✅
   - Final prompt contains language instruction ✅

2. **Template Rendering**
   - Jinja2 correctly renders `{{language}}` ✅
   - All 8 language codes produce correct output ✅
   - Language instruction appears in prompt ✅
   - No empty variables ✅

3. **Different Languages Handled**
   - Russian: "RESPOND IN Русский (Russian) LANGUAGE." ✅
   - German: "RESPOND IN Deutsch (German) LANGUAGE." ✅
   - French: "RESPOND IN Français (French) LANGUAGE." ✅
   - Spanish: "RESPOND IN Español (Spanish) LANGUAGE." ✅
   - Japanese: "RESPOND IN 日本語 (Japanese) LANGUAGE." ✅
   - Thai: "RESPOND IN ไทย (Thai) LANGUAGE." ✅
   - Chinese: "RESPOND IN 中文 (Chinese) LANGUAGE." ✅
   - English: "RESPOND IN English LANGUAGE." ✅

### ✅ Code Quality

- [ ] All tests PASS: `make pre-commit-quick` ✅
- [ ] Zero regressions in existing tests ✅
- [ ] Test coverage for all 3 endpoints ✅
- [ ] Code follows SOLID/DRY/clean code principles ✅
- [ ] No deprecated methods or stubs ✅

---

## Files Modified Today

### Configuration (Already Fixed)
- ✅ `vbwd-backend/plugins/taro/config.json` (Jinja2 syntax corrected)

### Tests (To Be Created)
- 🔲 `plugins/taro/tests/unit/services/test_language_flow.py`
- 🔲 Update `plugins/taro/tests/unit/services/test_taro_session_service.py`
- 🔲 Update `plugins/taro/tests/unit/routes/test_taro_routes.py`

---

## Expected Test Count

- **Current**: 715 backend tests passing
- **New Tests**: ~25-30 new tests (language validation across 3 test files)
- **Target**: 740-745 tests passing with zero regressions

---

## Timeline

| Phase | Tasks | Est. Duration |
|-------|-------|---|
| 1: Templates | 1.1, 1.2 | 30 min |
| 2: Service | 2.1, 2.2, 2.3 | 1 hour |
| 3: Routes | 3.1, 3.2 | 1 hour |
| 4: E2E | 4.1, 4.2 | 45 min |
| 5: Pre-commit | 5.1, 5.2 | 30 min |
| **Total** | | **~4 hours** |

---

## Pre-commit Check Commands

```bash
# Backend - Full validation
cd vbwd-backend
make pre-commit-quick        # Lint + unit tests

# If testing specific file
pytest plugins/taro/tests/unit/services/test_language_flow.py -v

# If testing specific test
pytest plugins/taro/tests/unit/services/test_language_flow.py::test_complete_language_flow_situation_reading -v
```

---

## Notes

- **Assumption**: LLMAdapter is already designed as injectable dependency
- **Assumption**: PromptService can load from config.json file or dict
- **Assumption**: All 3 endpoints already receive and pass language parameter (verified in code review)
- **Known Limitation**: These tests use mocked LLM, not real API (faster, isolated testing)
- **Future Work**: E2E browser tests with actual LLM responses (in separate sprint)

---

**Sprint Created**: February 19, 2026, 14:30 UTC
**Status**: 🚀 Ready for implementation
**Next Step**: Begin Task 1.1 (Write template rendering tests)
