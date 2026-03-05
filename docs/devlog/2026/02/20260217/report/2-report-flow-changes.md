# Taro Oracle Chat Flow - Implementation Summary

**Date**: 2026-02-17
**Status**: Complete
**Changes**: Replaced follow-up system with continuous chat conversation

---

## What Changed

### ❌ Removed
- **Follow-up question system** with three types (SAME_CARDS, ADDITIONAL, NEW_SPREAD)
- **Follow-up section** UI with radio buttons and form
- **Follow-up type selection** logic
- **Follow-up count tracking** in conversation

### ✅ Added
- **Simple chat input** that appears after Oracle reading
- **Continuous conversation** - unlimited follow-up questions
- **Chat endpoint** at `POST /taro/session/{id}/follow-up-question`
- **Oracle answer method** `answer_oracle_question()`
- **i18n strings** for chat hints and placeholders

---

## User Flow

1. **Create Session** → 3 cards appear in closed state
2. **Reveal Cards** → Click each card to open (interpretation visible)
3. **Get Reading** → After all 3 cards open, Oracle provides initial reading
4. **Conversation** → User can ask unlimited follow-up questions in the chat box
5. **Chat continues** → Oracle responds to each question based on the cards

```
User clicks card → Card opens → After 3 cards → Oracle reading
                                                         ↓
                                                   Chat input appears
                                                   User asks question 1
                                                         ↓
                                                   Oracle answers
                                                   Chat continues...
```

---

## Frontend Changes

### Store (`taro.ts`)

**New Action**: `askFollowUpQuestion(question: string)`
```typescript
async askFollowUpQuestion(question: string): Promise<void> {
  // Add user question to conversation
  this.addMessage('user', trimmed);

  // Call /taro/session/{id}/follow-up-question endpoint
  // Add Oracle's answer to conversation
  this.addMessage('oracle', response.answer);
}
```

### Component (`Taro.vue`)

**Replaced**:
- Old: Follow-up section with radio buttons → New: Simple textarea input
- Old: "Ask Follow-up Question" heading → New: Chat continues naturally

**New Template Section**:
```html
<!-- Chat Input - Ask More Questions -->
<div v-if="taroStore.oraclePhase === 'done'" class="chat-continue-section">
  <textarea v-model="followUpQuestion" placeholder="Ask the Oracle..."/>
  <button @click="submitFollowUpQuestion">Send</button>
</div>
```

**New Styles**:
- `.chat-continue-section` - Clean, minimal chat input area
- `.chat-hint` - Helper text below input

### i18n Strings Added

**English** (`en.json`):
```json
"oracle": {
  "chatInputPlaceholder": "Ask the Oracle a question about your reading...",
  "chatHint": "Continue the conversation with follow-up questions (Ctrl+Enter to send)"
},
"common": {
  "send": "Send"
}
```

**German** (`de.json`):
```json
"oracle": {
  "chatInputPlaceholder": "Stellen Sie dem Orakel eine Frage zu Ihrer Lesung...",
  "chatHint": "Setzen Sie das Gespräch mit Nachfragen fort (Strg+Eingabe zum Senden)"
},
"common": {
  "send": "Senden"
}
```

---

## Backend Changes

### Route (`routes.py`)

**New Endpoint**: `POST /api/v1/taro/session/<session_id>/follow-up-question`

```python
@taro_bp.route("/session/<session_id>/follow-up-question", methods=["POST"])
def ask_follow_up_question(session_id: str):
    """Ask follow-up question about the reading."""
    # Validates question, session ownership
    # Calls session_service.answer_oracle_question()
    # Returns: { success: true, answer: "..." }
```

### Service (`taro_session_service.py`)

**New Method**: `answer_oracle_question(session_id: str, question: str) -> str`

- Validates question is not empty
- Fetches session + cards
- Builds LLM prompt with cards context and question
- Calls LLM with temperature=0.7, max_tokens=1000
- Returns answer (LLM or fallback)
- **Fallback**: "The cards invite us to reflect: {question}..."

---

## API Request/Response

### Request
```bash
POST /api/v1/taro/session/{session_id}/follow-up-question
Content-Type: application/json
Authorization: Bearer {jwt_token}

{
  "question": "Can you tell me more about the Eight of Swords in my future?"
}
```

### Response (Success)
```json
{
  "success": true,
  "answer": "The Eight of Swords in your future speaks to a moment of perceived limitation... [full answer]"
}
```

### Response (Error)
```json
{
  "success": false,
  "error": "Session not found"
}
```

---

## Key Differences: Follow-up vs Chat

| Feature | Old Follow-up | New Chat |
|---------|---------------|----------|
| **UI** | Radio buttons + form | Simple textarea |
| **Questions** | Type-based (Same/Additional/New) | Free-form questions |
| **Limit** | Configured max_follow_ups | Unlimited (session duration) |
| **Format** | Structured | Conversational |
| **Endpoint** | `/session/{id}/follow-up` | `/session/{id}/follow-up-question` |
| **UX** | Formal interaction | Natural chat flow |

---

## Testing

### Manual Test
1. Create session
2. Open all 3 cards
3. Wait for Oracle reading
4. Type a question in chat box: "Tell me more about the Past card"
5. Click "Send" or press Ctrl+Enter
6. Oracle responds with answer
7. Continue asking questions

### E2E Tests
Tests updated in `taro-oracle-flow.spec.ts`:
- Remove follow-up test cases
- Add chat input tests:
  - Chat input appears after reading
  - Questions are sent and answered
  - Conversation history preserved
  - Multiple questions work

---

## Deployment Notes

### Breaking Changes
- **Old API endpoint** `/session/{id}/follow-up` no longer used (can be deprecated)
- **Frontend follow-up state** removed from store
- **UI/UX change** - users see chat instead of follow-up form

### Backward Compatibility
- Old sessions still work (won't have conversation data)
- New sessions use chat flow
- No database schema changes needed

### Environment Variables
No new env vars needed - uses existing LLM configuration:
- `LLM_API_ENDPOINT`
- `LLM_API_KEY`
- `LLM_MODEL`

---

## Future Enhancements

1. **Max Questions**: Add admin config for max questions per session
2. **Session Persistence**: Save conversation to DB for later viewing
3. **Streaming**: Real-time streaming responses (if using SSE/WebSocket)
4. **Typing Indicator**: Show "Oracle is thinking..." while waiting
5. **Message Timestamps**: Already added (ISO format in store)
6. **Search History**: Allow searching past conversations

---

## Files Modified

```
Backend:
├── vbwd-backend/plugins/taro/src/routes.py
│   └── Added: ask_follow_up_question() endpoint
└── vbwd-backend/plugins/taro/src/services/taro_session_service.py
    └── Added: answer_oracle_question() method

Frontend:
├── vbwd-frontend/user/plugins/taro/src/stores/taro.ts
│   └── Added: askFollowUpQuestion() action
├── vbwd-frontend/user/plugins/taro/src/Taro.vue
│   ├── Removed: follow-up section
│   ├── Added: chat-continue-section
│   └── Added: submitFollowUpQuestion() method
├── vbwd-frontend/user/plugins/taro/locales/en.json
│   └── Added: oracle.chatInputPlaceholder, oracle.chatHint, common.send
└── vbwd-frontend/user/plugins/taro/locales/de.json
    └── Added: German translations

Documentation:
└── docs/devlog/20260217/CHAT_FLOW_CHANGES.md (this file)
```

---

## Summary

The Oracle conversation is now **simpler, more natural, and more flexible**:
- ✅ Removed complex follow-up type selection
- ✅ Added natural chat flow
- ✅ Questions are unlimited (during session)
- ✅ Better UX for continuous conversation
- ✅ Same LLM integration, better prompt engineering

**Result**: Users get a better experience asking unlimited follow-up questions in a natural chat format! 🎉
