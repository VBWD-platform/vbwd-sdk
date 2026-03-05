# Sprint 30 Report: LLM Chat Plugin

## Summary

Full-stack LLM chat plugin with token-based billing. Users chat with an AI assistant at `/dashboard/chat`, paying tokens per message. Admin configures the LLM provider (model, API endpoint, API key) and token pricing via 3 interchangeable counting strategies.

## Backend (62 tests)

### New Files

| File | Description |
|------|-------------|
| `plugins/chat/__init__.py` | ChatPlugin class — metadata, lifecycle, blueprint, default config |
| `plugins/chat/token_counting.py` | 3 strategies: WordCount, DataVolume, Tokenizer + factory |
| `plugins/chat/llm_adapter.py` | LLMAdapter wrapping OpenAI-compatible chat completions API |
| `plugins/chat/chat_service.py` | ChatService orchestrating LLM call + token deduction |
| `plugins/chat/routes.py` | Flask blueprint: POST /send, GET /config, POST /estimate |
| `plugins/chat/tests/conftest.py` | Shared fixtures |
| `plugins/chat/tests/test_token_counting.py` | 22 tests — all 3 strategies + factory |
| `plugins/chat/tests/test_llm_adapter.py` | 10 tests — adapter, auth, error handling |
| `plugins/chat/tests/test_chat_service.py` | 13 tests — orchestration, deduction, balance |
| `plugins/chat/tests/test_routes.py` | 17 tests — /send, /config, /estimate routes |

### Design Patterns

- **Strategy Pattern**: 3 token counting strategies (WordCount, DataVolume, Tokenizer) — admin selects via config
- **Adapter Pattern**: LLMAdapter wraps HTTP calls to any OpenAI-compatible endpoint
- **DI**: ChatService receives TokenService, LLMAdapter, and CountingStrategy from outside
- **Security**: /config route NEVER exposes api_key or api_endpoint to frontend

## Frontend (37 tests)

### New Files

| File | Description |
|------|-------------|
| `plugins/chat/index.ts` | Plugin entry — route, translations, lifecycle |
| `plugins/chat/src/api.ts` | API client with TypeScript interfaces |
| `plugins/chat/src/ChatView.vue` | Main chat page — messages, balance, config fetch |
| `plugins/chat/src/ChatHeader.vue` | Balance display, model name, clear button |
| `plugins/chat/src/ChatMessage.vue` | Message bubble (user/assistant styling) |
| `plugins/chat/src/ChatInput.vue` | Textarea + send button, cost estimate, max length |
| `plugins/chat/locales/en.json` | 13 English translation keys |
| `plugins/chat/locales/de.json` | 13 German translation keys |
| `plugins/chat/config.json` | Frontend plugin config schema (showTokenCost, showModelName) |
| `plugins/chat/admin-config.json` | Admin panel UI config (Display tab) |
| `plugins/chat/tests/chat-plugin.spec.ts` | 8 tests — lifecycle, routes, translations |
| `plugins/chat/tests/chat-view.spec.ts` | 13 tests — mount, send, balance, errors, clear |
| `plugins/chat/tests/chat-message.spec.ts` | 6 tests — user/assistant styling, tokens display |
| `plugins/chat/tests/chat-input.spec.ts` | 10 tests — send, disable, validation, cost |

### Modified Files

| File | Change |
|------|--------|
| `user/vue/src/main.ts` | Added chatPlugin import and registration |
| `user/vue/src/layouts/UserLayout.vue` | Added Chat nav link |
| `user/vue/src/i18n/locales/en.json` | Added `nav.chat` key |
| `user/vue/src/i18n/locales/de.json` | Added `nav.chat` key |
| `user/plugins/plugins.json` | Added chat entry |
| `user/vitest.config.js` | Added `plugins/*/tests/*.spec.{js,ts}` include pattern |

## Test Results

| Suite | Tests | Status |
|-------|-------|--------|
| Chat backend | 62 | passing |
| Chat frontend | 37 | passing |
| User (full) | 293 | passing (+37) |
| Core | 316 | passing |
| Admin | 331 | passing |
| Backend unit | 661 | passing (4 skipped) |
| **Sprint total** | **99 new** | all passing |
