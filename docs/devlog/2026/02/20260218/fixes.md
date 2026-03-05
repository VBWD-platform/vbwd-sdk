# Fixes Applied - 2026-02-18

## Issue 1: SyntaxError in Taro Store ✅ FIXED

**Problem**: JavaScript SyntaxError when opening cards (line 26)
```
SyntaxError: 26 at Os at openCard
```

**Root Cause**: Used Vue composable `useI18n()` inside Pinia store action, which doesn't have component context.

**Fix Applied**:
- Removed `import { useI18n }`
- Changed to import global i18n instance: `import { getLocale, i18n }`
- Updated openCard to use `i18n.global.t()` instead of composable

**File**: `vbwd-frontend/user/plugins/taro/src/stores/taro.ts`

**Result**: ✅ Build passes, no SyntaxError

---

## Issue 2: LLM Responses Still in English (PARTIAL - Need Investigation)

**Problem**: UI shows in Russian but LLM interpretations are in English

**Example**:
- UI: "Текущий Сеанс" (Russian) ✓
- Interpretation: "Interpretation of Your Tarot Spread" (English) ✗

**Root Causes** (Multiple):

### 2a. Initial Card Interpretations
- When session is created, cards have `ai_interpretation` from DB
- These were generated before language fix - all in English
- This is not an LLM call but static DB data

### 2b. New LLM Responses Should Be Language-Aware
- When user asks for card-explanation, follow-up, or situation reading
- These endpoints NOW receive language parameter ✓
- Backend converts to language name and passes to LLM ✓
- Prompt includes "RESPOND IN {{language}} LANGUAGE" ✓

**Status**:
- ✅ Backend is language-aware (routes + services + prompts)
- ✅ Frontend passes language to endpoints (store updated)
- ⏳ Need to verify LLM is actually responding in target language

**Next Steps**:
1. Create a NEW session with Russian language selected
2. Ask for card explanation or submit situation
3. Verify if LLM response is in Russian
4. If not, may need to debug LLM provider (OpenAI, etc.)

---

## Testing Checklist

- [x] Frontend builds without SyntaxError
- [x] Store uses global i18n instance
- [x] Oracle messages localized
- [ ] LLM responses in Russian when language=ru
- [ ] LLM responses in French when language=fr
- [ ] LLM responses in other languages

---

## Files Modified

1. `vbwd-frontend/user/plugins/taro/src/stores/taro.ts`
   - Fixed useI18n() usage
   - Now uses i18n.global.t()

---

## Known Issue

The screenshot shows Russian UI but English interpretation. This could be:
1. Old interpretation from before language fix was applied
2. LLM not receiving/respecting language parameter
3. LLM not instructed to respond in target language

**Recommended Test**:
1. Select Russian language
2. Create NEW session
3. Ask for "Explain the cards" - should respond in Russian
4. If still English, check:
   - Network request includes `language: 'ru'`
   - LLM endpoint receives language parameter
   - Prompt includes language instruction
