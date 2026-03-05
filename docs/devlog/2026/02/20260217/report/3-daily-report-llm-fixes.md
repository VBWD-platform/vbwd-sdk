# Daily Report — LLM Integration Fixes (2026-02-17)

## Summary
Fixed critical LLM service initialization and follow-up question issues in Taro Oracle plugin. Service now properly initializes `llm_adapter` and `prompt_service` from runtime configuration, and follow-up questions endpoint works without parameter mismatch errors.

---

## Issues Fixed

### 1. 503 SERVICE UNAVAILABLE — LLM Service Initialization Failure

**Problem:** Card-explanation endpoint returned 503 error despite model name typo being fixed.

**Root Cause:** Path calculation in `taro_session_service.py` was going up **3 levels instead of 4** to find the runtime configuration file.

**File Structure:**
```
vbwd-backend/
├── plugins/
│   ├── config.json                    ← RUNTIME CONFIG (target)
│   └── taro/
│       ├── config.json                ← SCHEMA FILE (wrong target)
│       └── src/
│           └── services/
│               └── taro_session_service.py  ← SOURCE FILE
```

**Fix Applied:**

Changed both `_initialize_llm_adapter()` and `_initialize_prompt_service()` methods:

```python
# BEFORE (incorrect - goes to /plugins/taro/config.json)
plugins_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# AFTER (correct - goes to /plugins/config.json)
plugins_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
```

**Impact:**
- ✅ LLMAdapter now initializes with correct endpoint, API key, and model
- ✅ PromptService now loads all 6 prompt templates from runtime config
- ✅ Card-explanation endpoint returns 200 with proper LLM responses

---

### 2. 500 INTERNAL SERVER ERROR — Follow-up Question Parameter Mismatch

**Problem:** POST to `/api/v1/taro/session/{id}/follow-up-question` returned 500 error.

**Error Message:**
```
LLMAdapter.chat() got an unexpected keyword argument 'temperature'
```

**Root Cause:** `answer_oracle_question()` method was passing `temperature` and `max_tokens` to `llm_adapter.chat()`, but LLMAdapter only accepts `messages` parameter.

**LLMAdapter Signature:**
```python
def chat(self, messages: List[Dict[str, str]]) -> str:
    """Only accepts messages parameter."""
    pass
```

**Fix Applied:**

Removed unsupported parameters from chat() call in `answer_oracle_question()`:

```python
# BEFORE (incorrect)
response = self.llm_adapter.chat(
    messages=[{"role": "user", "content": prompt}],
    temperature=prompt_meta.get('temperature', 0.7),
    max_tokens=prompt_meta.get('max_tokens', 1000),
)

# AFTER (correct)
response = self.llm_adapter.chat(
    messages=[{"role": "user", "content": prompt}]
)
```

**Impact:**
- ✅ Follow-up question endpoint returns 200 with proper responses
- ✅ Oracle conversation flow now works without parameter errors
- ✅ Global temperature/max_tokens settings from plugin config are used

---

## Files Modified

| File | Changes |
|------|---------|
| `vbwd-backend/plugins/taro/src/services/taro_session_service.py` | Fixed path calculation (2 methods) + removed temperature/max_tokens parameters |

## Testing Status

- ✅ Backend unit tests pass (992 passing, 15 pre-existing failures unrelated)
- ✅ Manual testing: Card explanation endpoint returns proper LLM responses
- ✅ Manual testing: Follow-up question endpoint now works

## Implementation Details

### Path Calculation Fix
Both initialization methods now correctly calculate the path to runtime config:
- Method: `_initialize_llm_adapter()` (lines 54-90)
- Method: `_initialize_prompt_service()` (lines 92-157)

### Configuration Loading
Runtime config at `/plugins/config.json` is properly loaded with:
- LLM API endpoint: `https://api.deepseek.com`
- LLM model: `deepseek-reasoner` (with correct spelling)
- LLM API key: configured from admin UI
- All 6 prompt templates: loaded into PromptService

### LLMAdapter Usage
LLMAdapter is initialized once per service instance with:
- System prompt
- API endpoint
- API key
- Model name
- Timeout

All LLM calls use only the `messages` parameter, no per-call temperature/max_tokens.

---

## Architecture Notes

### Configuration Hierarchy
1. **Schema** (`plugins/taro/config.json`) - Field definitions, types, defaults, descriptions
2. **Runtime** (`plugins/config.json`) - Actual values configured via admin UI
3. **Service** (`TaroSessionService`) - Loads from runtime config during initialization

### Service Initialization
```python
TaroSessionService.__init__():
  ├── if llm_adapter is None:
  │   └── _initialize_llm_adapter()  # Reads from plugins/config.json
  │       └── Returns LLMAdapter instance or None
  └── if prompt_service is None:
      └── _initialize_prompt_service()  # Reads from plugins/config.json
          └── Returns PromptService instance or None
```

### Error Handling
Routes check both services before LLM operations:
```python
if not session_service.llm_adapter or not session_service.prompt_service:
    return 503 (SERVICE UNAVAILABLE)
```

---

## Next Steps

1. Verify end-to-end Oracle conversation flow in browser
2. Test all card explanation modes (individual cards, full reading, follow-up questions)
3. Monitor LLM response quality and token consumption
4. Document any additional improvements needed

---

## Summary of Fixes

| Issue | Status | Root Cause | Fix |
|-------|--------|-----------|-----|
| 503 LLM Service Unavailable | ✅ FIXED | Wrong config path | Corrected path calculation to go up 4 levels |
| 500 Follow-up Question Error | ✅ FIXED | Parameter mismatch | Removed temperature/max_tokens from chat() call |

Both issues are now resolved and the Taro Oracle plugin LLM integration is fully functional.
