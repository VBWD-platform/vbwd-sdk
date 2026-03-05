# Taro LLM Integration Setup Guide
**Date**: 2026-02-16
**Status**: ✅ DEPLOYED & READY

## Overview

The Tarot card interpretation system now integrates with OpenAI-compatible LLM APIs to generate personalized, context-aware card interpretations. When a session is created:

1. **3 cards are generated** with random arcanas and orientations
2. **Each card gets an interpretation** - either from LLM or fallback arcana meaning
3. **Cards are stored** in the database with interpretations
4. **Frontend displays** personalized interpretations to the user

---

## Architecture

### Backend Flow
```
User creates session
  ↓
TaroSessionService._generate_spread()
  ↓
For each card:
  1. Create TaroCardDraw with empty interpretation
  2. Call _generate_card_interpretation()
  3. If LLM configured → generate unique interpretation
  4. Else → use fallback (arcana meaning)
  5. Update card with interpretation
  ↓
Return cards to API
  ↓
Frontend displays with interpretations
```

### Services Involved
- **TaroSessionService**: Orchestrates session and card creation, calls LLM
- **LLMAdapter**: Handles OpenAI-compatible API calls
- **ArcanaRepository**: Provides random card selection
- **TaroCardDrawRepository**: Stores cards with interpretations

---

## Setup Instructions

### Option 1: OpenAI (Recommended for Production)

1. **Get API Key**:
   - Go to https://platform.openai.com/account/api-keys
   - Create new secret key
   - Copy the key

2. **Set Environment Variables**:
   ```bash
   # Edit /vbwd-backend/.env
   LLM_API_ENDPOINT=https://api.openai.com/v1
   LLM_API_KEY=sk-your-key-here
   LLM_MODEL=gpt-4-turbo  # or gpt-3.5-turbo for cheaper option
   ```

3. **Restart Backend**:
   ```bash
   cd vbwd-backend
   docker-compose restart api
   ```

4. **Verify**:
   - Check logs: `docker-compose logs api | grep -i "llm\|interpretation"`
   - Create a new taro session
   - Cards should have unique interpretations

---

### Option 2: DeepSeek (Open Source, Affordable)

1. **Get API Key**:
   - Go to https://platform.deepseek.com
   - Create account and API key
   - Copy the key

2. **Set Environment Variables**:
   ```bash
   # Edit /vbwd-backend/.env
   LLM_API_ENDPOINT=https://api.deepseek.com
   LLM_API_KEY=sk-your-deepseek-key
   LLM_MODEL=deepseek-chat
   ```

3. **Restart Backend** and verify as above

---

### Option 3: Local Ollama (Free, Privacy-Focused)

1. **Install Ollama**:
   ```bash
   # On macOS: brew install ollama
   # On Linux: download from https://ollama.ai
   # On Windows: download from https://ollama.ai

   # Run: ollama serve
   # In another terminal: ollama pull mistral
   ```

2. **Set Environment Variables**:
   ```bash
   # Edit /vbwd-backend/.env
   LLM_API_ENDPOINT=http://ollama:11434/v1
   LLM_API_KEY=not-needed
   LLM_MODEL=mistral
   ```

3. **If using Docker**:
   - Ollama needs network access to backend container
   - Update docker-compose to link services

---

### Option 4: No LLM (Fallback Mode - Current State)

If you don't set `LLM_API_ENDPOINT` and `LLM_API_KEY`:
- Interpretations use arcana base meanings
- No external API calls
- Works offline
- Less personalized but still functional

---

## What the LLM Does

For each card, the LLM generates a 1-2 sentence interpretation considering:

**Input to LLM**:
```
Card: Ace of Cups
Orientation: Upright
Position: Past
Base Meaning: New love, new opportunity, new relationship, fertility, abundance
Context: This card represents influences from the past
```

**Sample Output**:
```
"The Ace of Cups in your past suggests you recently experienced or are about to
experience a new beginning in romantic or creative matters. This upright card
indicates opportunities and abundance flowing into your life from that influence."
```

---

## Code Changes Made

### Backend Files Modified

1. **`taro_session_service.py`**:
   - Added LLMAdapter initialization
   - New method `_generate_card_interpretation()` for LLM calls
   - Modified `_generate_spread()` to generate interpretations during card creation
   - Fallback to arcana meaning if LLM fails

2. **`routes.py`**:
   - Updated `_get_taro_services()` to initialize LLMAdapter from environment variables
   - Logs warning if LLM not configured

### New Dependencies

- `LLMAdapter` (from `plugins/chat/src/llm_adapter.py`)
- `requests` library (already in dependencies)

---

## Testing

### Manual Test
1. Create a new Taro session: http://localhost:8080/dashboard/taro → "Start Reading"
2. Check conversation section above "Ask Follow-up Question"
3. Should show interpretations for all 3 cards

### Database Verification
```sql
SELECT position, ai_interpretation
FROM taro_card_draw
ORDER BY created_at DESC
LIMIT 3;
```

Should show:
- Position: PAST, PRESENT, FUTURE
- ai_interpretation: Non-empty text (either LLM-generated or fallback)

---

## Troubleshooting

### Interpretations still empty?
1. Check backend was restarted: `docker-compose ps`
2. Create a **new** session (old cards keep old interpretations)
3. Check logs: `docker-compose logs api | tail -50`

### LLM returns errors?
1. Verify API key is correct
2. Check API endpoint is accessible
3. Verify API key has credits/balance
4. Check rate limits aren't exceeded
5. Fallback will activate automatically

### Timeout on card creation?
1. LLM might be slow (30s timeout)
2. Check network connectivity
3. Try with local Ollama if using cloud API

---

## Performance Considerations

- **LLM API Calls**: 3 per session (one per card)
- **Response Time**: +5-10 seconds per session (LLM latency)
- **Cost**: Varies by provider
  - OpenAI GPT-4: ~$0.10-0.15 per session
  - DeepSeek: ~$0.001-0.01 per session
  - Local Ollama: Free

---

## Future Enhancements

1. **Async Interpretation Generation**:
   - Generate interpretations in background
   - Return initial response immediately
   - Update interpretations via WebSocket

2. **Batch Processing**:
   - Generate multiple interpretations together
   - Reduce API calls

3. **Caching**:
   - Cache interpretations for same card combinations
   - Reduce redundant API calls

4. **Follow-up Interpretations**:
   - Generate context-aware follow-up responses
   - Maintain conversation history

---

## Support

If LLM integration isn't working:
1. Check `/vbwd-backend/.env` for correct variables
2. Verify backend logs: `docker-compose logs api`
3. Test API endpoint: `curl https://api.openai.com/v1/models -H "Authorization: Bearer YOUR_KEY"`
4. Check token balance in your LLM provider dashboard

The system gracefully falls back to arcana meanings if LLM is unavailable, so interpretations will always be available to users.
