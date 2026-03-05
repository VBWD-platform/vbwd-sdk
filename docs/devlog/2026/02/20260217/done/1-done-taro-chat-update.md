# Oracle Conversation Flow — Sprint Plan

**Date**: 2026-02-17
**Feature**: Taro Card Oracle Conversation Flow
**Status**: Planning

## Sprint Goal

Implement an interactive Oracle conversation flow for the Taro card reading plugin, enabling:
1. **Card Reveal Mechanic**: Users click cards to reveal orientation and interpretation
2. **Oracle Dialog**: After all 3 cards opened, Oracle guides user through conversation
3. **Situation-Based Reading**: User describes their situation; LLM generates contextual interpretation
4. **Conversation Memory**: Messages persisted in store for context

---

## Context

**Current State**:
- Taro cards show orientation + interpretation immediately on load
- No interactive reveal flow
- No contextual reading based on user's situation

**Design Goals**:
- TDD: Tests written first, implementation follows
- SOLID: Single responsibility, loose coupling
- DRY: No code duplication
- LISKOV: Proper inheritance/composition patterns
- No Over-Engineering: Minimal viable features only

---

## Part 1: Frontend State Management

### `taro.ts` Store Changes

**New State**:
```typescript
openedCards: Set<string>                          // card_ids user has opened
conversationMessages: ConversationMessage[]        // Oracle + user messages
oraclePhase: 'idle' | 'asking_mode' | 'asking_situation' | 'reading' | 'done'
situationText: string                             // User-entered situation description
```

**New Interface**:
```typescript
interface ConversationMessage {
  role: 'oracle' | 'user';
  content: string;
  timestamp: string;
}
```

**New Getter**:
```typescript
allCardsOpened(): boolean  // true when openedCards.size === 3
```

**New Actions**:
- `openCard(cardId: string)`: Adds card to `openedCards`, triggers Oracle if all 3 opened
- `setOraclePhase(phase)`: Transitions state machine
- `addMessage(role, content)`: Appends message to conversation
- `submitSituation(text: string)`: Validates, calls LLM endpoint, updates phase to 'reading'

**Validation**:
- `openCard` on already-opened card is idempotent (no-op)
- `submitSituation` validates `situationText` ≤ 100 words
- Phase transitions are state-machine enforced

---

## Part 2: Frontend Components

### `CardDisplay.vue` Changes

**New Prop**: `isOpened: boolean`

**Rendering Logic**:
- `!isOpened`: Show card back, "Click to reveal" hint, dimmed appearance
- `isOpened`: Show current interpretation, normal appearance

**CSS Changes**:
- Closed state: `opacity: 0.7`, `cursor: pointer`, hover scale transform
- Opened state: `opacity: 1`, `pointer-events: none` (immutable)

**Key Point**: Minimal component change. Card state driven by parent (`Taro.vue`).

### `Taro.vue` Changes

**Card Grid Section**:
1. Pass `isOpened` prop to each `CardDisplay`:
   ```html
   :is-opened="taroStore.openedCards.has(card.card_id)"
   ```
2. On `card-click` → call `taroStore.openCard(cardId)` instead of opening modal directly
3. Modal only opens when card already opened (user clicks opened card)

**Oracle Dialog Section** (appears after all cards opened):

Three phases displayed as Oracle messages + user input:

**Phase: `asking_mode`**
```
Oracle: "The cards have spoken. Do you seek a detailed explanation of
each card, or shall we explore how they relate to your situation?"

[Button: "Explain the Cards"] [Button: "Discuss My Situation"]
```

**Phase: `asking_situation`**
```
Oracle: "Please describe your situation in a few words (up to 100 words)."

[Textarea with word counter]
[Submit Button]
```

**Phase: `reading`**
```
[Loading indicator] "Oracle is reflecting on your cards and situation..."
```

**Phase: `done`**
```
Oracle: "[Full contextual interpretation from LLM]"
```

**Conversation Section**:
- Displays `conversationMessages` array
- Only shown after first card opened
- Message bubbles with role indicator (Oracle/User) and timestamp

---

## Part 3: Backend Service & Route

### New Service Method

**File**: `vbwd-backend/plugins/taro/src/services/taro_session_service.py`

**Method**: `generate_situation_reading(session_id: str, situation_text: str) -> str`

**Logic**:
1. Load session + 3 cards from database
2. Validate `situation_text` ≤ 100 words
3. Build LLM prompt with all 3 cards + situation
4. Call LLM (with fallback if unavailable)
5. Return interpretation string

**Fallback**: If LLM unavailable, return generic message

### New API Route

**File**: `vbwd-backend/plugins/taro/src/routes.py`

**Endpoint**: `POST /api/v1/taro/session/<session_id>/situation`

**Request**:
```json
{
  "situation_text": "I'm facing a career decision..."
}
```

**Response** (success):
```json
{
  "success": true,
  "interpretation": "Based on the cards and your situation..."
}
```

**Response** (validation error):
```json
{
  "success": false,
  "error": "Situation text must be ≤ 100 words"
}
```

**Validations**:
- `situation_text` required, non-empty
- `situation_text` ≤ 100 words
- Session exists and belongs to user
- Session has exactly 3 cards

---

## Part 4: Internationalization

### New i18n Keys

**File**: `vbwd-frontend/user/plugins/taro/locales/en.json`

```json
{
  "oracle": {
    "cardsRevealed": "The cards have spoken.",
    "explainMode": "Do you seek a detailed explanation of each card, or shall we explore how they relate to your situation?",
    "explainButton": "Explain the Cards",
    "situationButton": "Discuss My Situation",
    "situationPrompt": "Please describe your situation in a few words (up to 100 words).",
    "situationLabel": "Your Situation",
    "wordCount": "{count} / 100 words",
    "reading": "Oracle is reflecting on your cards and situation...",
    "cardClickHint": "Click to reveal"
  }
}
```

**File**: `vbwd-frontend/user/plugins/taro/locales/de.json`

(German translations of above keys)

---

## Part 5: Testing Strategy (TDD)

### Backend Unit Tests

**File**: `vbwd-backend/plugins/taro/tests/unit/test_taro_session_service.py`

**Test Cases**:
1. `test_generate_situation_reading_success`: Happy path, LLM returns interpretation
2. `test_generate_situation_reading_fallback`: LLM unavailable, generic fallback returned
3. `test_generate_situation_reading_word_limit`: situation_text > 100 words raises validation error
4. `test_situation_endpoint_returns_400_on_word_limit`: Route returns 400 with error message

**Test Data**: Use fixtures for session + 3 cards with known interpretations

### Frontend Unit Tests

**File**: `vbwd-frontend/user/plugins/taro/src/__tests__/oracleFlow.spec.ts`

**Test Cases**:
1. `openCard` adds card to `openedCards`
2. After 3 cards opened, `allCardsOpened` returns true
3. After 3 cards opened, `oraclePhase` becomes `asking_mode`
4. `openCard` on already-opened card is idempotent
5. `CardDisplay` renders closed state when `!isOpened`
6. `CardDisplay` renders opened state with interpretation when `isOpened`
7. `addMessage` appends message with correct timestamp
8. `submitSituation` validates word count ≤ 100
9. `submitSituation` fails if text exceeds 100 words

### Frontend E2E Tests

**File**: `vbwd-frontend/user/vue/tests/e2e/taro.spec.ts`

**Test Cases** (extend existing):
1. Cards show closed state (dimmed, "Click to reveal") on session load
2. Clicking closed card reveals it (orientation + interpretation visible)
3. Revealed card is not clickable again (pointer-events: none)
4. After opening all 3 cards, Oracle dialog appears with `asking_mode` message
5. Clicking "Discuss My Situation" transitions to `asking_situation`
6. Textarea shows word counter
7. Submitting situation > 100 words shows validation error
8. Submitting valid situation triggers loading state
9. After LLM response, Oracle message appears in conversation

---

## Implementation Order (TDD)

1. ✅ Create this sprint document
2. Write failing backend unit tests for `generate_situation_reading`
3. Implement `generate_situation_reading` method + endpoint → tests pass
4. Write failing frontend unit tests for store changes
5. Implement store changes → tests pass
6. Update `CardDisplay.vue` (closed/opened visual states)
7. Update `Taro.vue` (wire props, Oracle dialog, conversation section)
8. Add i18n strings
9. Write E2E tests → verify end-to-end flow
10. Pre-commit verification (lint, unit, e2e)

---

## Critical Files Checklist

| File | Change | Status |
|------|--------|--------|
| `docs/devlog/20260217/sprint/SPRINT.md` | Create sprint doc | ✅ |
| `vbwd-backend/plugins/taro/tests/unit/test_taro_session_service.py` | Add unit tests | ⏳ |
| `vbwd-backend/plugins/taro/src/services/taro_session_service.py` | Add method | ⏳ |
| `vbwd-backend/plugins/taro/src/routes.py` | Add route | ⏳ |
| `vbwd-frontend/user/plugins/taro/src/__tests__/oracleFlow.spec.ts` | Add tests | ⏳ |
| `vbwd-frontend/user/plugins/taro/src/stores/taro.ts` | Add state | ⏳ |
| `vbwd-frontend/user/plugins/taro/src/components/CardDisplay.vue` | Add prop, styles | ⏳ |
| `vbwd-frontend/user/plugins/taro/src/Taro.vue` | Wire flow, dialog, messages | ⏳ |
| `vbwd-frontend/user/plugins/taro/locales/en.json` | Add keys | ⏳ |
| `vbwd-frontend/user/plugins/taro/locales/de.json` | Add keys | ⏳ |
| `vbwd-frontend/user/vue/tests/e2e/taro.spec.ts` | Add E2E tests | ⏳ |

---

## Pre-commit Verification

**Backend**:
```bash
cd vbwd-backend
make pre-commit-quick   # lint + unit tests
```

**Frontend**:
```bash
cd vbwd-frontend
./bin/pre-commit-check.sh --admin --unit     # Admin unit tests
./bin/pre-commit-check.sh --admin --style    # Lint + TypeScript
```

**E2E** (manual):
```bash
cd vbwd-frontend/user/vue
npx playwright test taro
```

---

## Notes

- **State Machine**: `oraclePhase` enforces valid transitions (idle → asking_mode → asking_situation → reading → done)
- **Idempotency**: Opening already-opened card is safe
- **Accessibility**: Word counter updates in real-time, forms are keyboard-accessible
- **Graceful Degradation**: If LLM unavailable, user gets fallback message
- **No Over-Engineering**: No persistence of conversation to DB; stateless LLM calls
