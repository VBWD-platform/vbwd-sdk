# Sprint 30: LLM Chat Plugin

## Goal

Create a full-stack chat plugin (backend + user frontend) that adds an LLM chat window to the user dashboard at `/dashboard/chat`. Each message costs tokens — the user sees their token balance in the chat header, and tokens are deducted per message based on admin-configured counting mode (words, data volume, or tokenized). The admin configures the LLM provider (model, API endpoint, API key) and token pricing via the plugin's backend config.

## Engineering Principles

- **TDD**: Tests first — write failing tests for token counting strategies, chat service, API routes, and Vue components before implementation
- **SOLID — SRP**: `ChatService` handles LLM communication. `TokenCountingStrategy` handles token calculation. `ChatPlugin` handles lifecycle. Each has one job
- **SOLID — OCP**: Adding a new token counting mode (e.g., character-based) requires only adding a new strategy class — no modifications to ChatService or routes
- **SOLID — DIP**: ChatService depends on abstract `LLMAdapter` interface, not on a specific provider. TokenCountingStrategy is injected, not hardcoded
- **SOLID — LSP**: All token counting strategies implement the same interface — `calculate_tokens(text: str, config: dict) -> int` — and are interchangeable
- **Strategy Pattern**: Token counting uses the Strategy pattern — `WordCountStrategy`, `DataVolumeStrategy`, `TokenizerStrategy` — selected by admin config
- **Adapter Pattern**: LLM communication uses an adapter (`LLMAdapter`) wrapping the HTTP call to the configured endpoint — same pattern as Stripe/PayPal/YooKassa SDK adapters
- **DI**: Backend uses dependency injection — ChatService receives TokenService and LLMAdapter from the container, not constructed internally
- **Clean Code**: Self-documenting names (`deduct_tokens_for_message`, `calculate_token_cost`, `ChatMessageView`). No magic numbers — all pricing constants from config
- **DRY**: Token deduction logic lives in one place (ChatService). Frontend API client is reused. Shared error handling patterns
- **No overengineering**: No streaming (MVP uses request/response). No chat history persistence in DB (session-only, localStorage backup). No multi-model switching by user (admin picks one model). No file uploads

## Testing Approach

All tests MUST pass before the sprint is considered complete:

```bash
# 1. Backend chat plugin tests
cd vbwd-backend && make test-unit  # includes plugins/chat/tests/

# 2. User frontend tests (chat plugin)
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# 3. Core regression
cd vbwd-frontend/core && npx vitest run

# 4. Admin regression
cd vbwd-frontend/admin/vue && npx vitest run

# 5. Backend full regression
cd vbwd-backend && make test-unit
```

---

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────┐
│ User Dashboard — /dashboard/chat                         │
│                                                          │
│ ┌──────────────────────────────────────────────────────┐ │
│ │ Token Balance: 1,250 TKN              [model name]  │ │
│ ├──────────────────────────────────────────────────────┤ │
│ │                                                      │ │
│ │  [Assistant] Hello! How can I help you?              │ │
│ │                                                      │ │
│ │  [User] What features does the Pro plan include?     │ │
│ │                                                      │ │
│ │  [Assistant] The Pro plan includes...                │ │
│ │                                                      │ │
│ ├──────────────────────────────────────────────────────┤ │
│ │ [Type your message...                    ] [Send]    │ │
│ │ Est. cost: ~3 TKN                                    │ │
│ └──────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

```
User types message
       │
       ▼
Frontend: POST /api/v1/chat/send
  { message: "...", session_id: "..." }
       │
       ▼
Backend ChatRoute:
  1. Validate auth (require_auth)
  2. Check plugin enabled
  3. Call ChatService.send_message()
       │
       ▼
ChatService:
  1. Count tokens: strategy.calculate_tokens(message)
  2. Check balance: token_service.get_balance(user_id)
  3. If insufficient → return error
  4. Call LLM: llm_adapter.chat(messages, model)
  5. Count response tokens: strategy.calculate_tokens(response)
  6. Total cost = request_tokens + response_tokens
  7. Deduct: token_service.debit_tokens(user_id, total_cost, USAGE)
  8. Return response + tokens_used + remaining_balance
       │
       ▼
Frontend: Display response, update balance
```

### Token Counting Strategies

Admin selects one of three modes in plugin config:

| Mode | Config Key | How It Works | Example |
|------|-----------|--------------|---------|
| `words` | `words_per_token` | `ceil(word_count / words_per_token)` | 10 words/token → "Hello world" = 1 TKN |
| `data_volume` | `mb_per_token` | `ceil(bytes / (mb_per_token * 1024 * 1024))` | 0.001 MB/token → 1KB message = 1 TKN |
| `tokenizer` | `tokens_per_token` | Uses tiktoken-compatible count, `ceil(tiktoken_count / tokens_per_token)` | 100 LLM tokens/token = 1 TKN |

Minimum cost per message: **1 TKN** (even empty messages cost at least 1 token to prevent abuse).

### Admin Plugin Configuration

Backend config (set via admin panel or `plugin_config` table):

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `llm_api_endpoint` | string | `""` | LLM API endpoint URL (e.g., `https://api.openai.com/v1/chat/completions`) |
| `llm_api_key` | string | `""` | API key for authentication |
| `llm_model` | string | `"gpt-4o-mini"` | Model identifier sent to the API |
| `counting_mode` | enum | `"words"` | One of: `words`, `data_volume`, `tokenizer` |
| `words_per_token` | int | `10` | Words per 1 platform token (when mode=words) |
| `mb_per_token` | float | `0.001` | MB per 1 platform token (when mode=data_volume) |
| `tokens_per_token` | int | `100` | LLM tokens per 1 platform token (when mode=tokenizer) |
| `system_prompt` | string | `"You are a helpful assistant."` | System prompt prepended to every conversation |
| `max_message_length` | int | `4000` | Maximum characters per user message |
| `max_history_messages` | int | `20` | Max conversation history sent to LLM |

Frontend plugin config (set via admin panel for user-app):

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `showTokenCost` | boolean | `true` | Show estimated token cost before sending |
| `showModelName` | boolean | `true` | Show LLM model name in chat header |

### Security

| Threat | Mitigation |
|--------|------------|
| API key exposure | Key stored in backend config only — never sent to frontend |
| Token theft (send many messages) | Balance check before LLM call, debit after response, minimum 1 TKN per message |
| Prompt injection | System prompt is admin-controlled, user message is clearly delimited in the API payload |
| Message size abuse | `max_message_length` enforced on both frontend and backend |
| Replay attacks | Standard `@require_auth` middleware, session validation |
| Insufficient balance race condition | `debit_tokens()` is atomic — raises ValueError if balance < cost |

---

## What Already Exists (referenced, not modified)

| File | Provides |
|------|----------|
| `vbwd-backend/src/services/token_service.py` | `debit_tokens()`, `get_balance()`, `credit_tokens()` |
| `vbwd-backend/src/models/token.py` | `UserTokenBalance`, `TokenTransaction` models |
| `vbwd-backend/src/models/enums.py` | `TokenTransactionType.USAGE` |
| `vbwd-backend/src/plugins/base.py` | `BasePlugin` abstract class with `get_blueprint()`, `on_enable()`, etc. |
| `vbwd-backend/src/plugins/manager.py` | `PluginManager` with discovery, registration, blueprint collection |
| `vbwd-frontend/core/src/plugins/types.ts` | `IPlugin`, `IPlatformSDK` interfaces |
| `vbwd-frontend/user/vue/src/layouts/UserLayout.vue` | Sidebar nav, layout |
| `vbwd-frontend/user/vue/src/main.ts` | Plugin registration |

---

## What This Sprint Adds

### Backend

| Layer | File | Provides |
|-------|------|----------|
| Plugin | `src/plugins/chat/__init__.py` | `ChatPlugin(BasePlugin)` — metadata, lifecycle, blueprint |
| Adapter | `src/plugins/chat/llm_adapter.py` | `LLMAdapter` — HTTP calls to configured LLM endpoint |
| Service | `src/plugins/chat/chat_service.py` | `ChatService` — orchestrates LLM call + token deduction |
| Strategy | `src/plugins/chat/token_counting.py` | `TokenCountingStrategy` base + 3 implementations |
| Routes | `src/plugins/chat/routes.py` | Flask blueprint: `/api/v1/chat/send`, `/api/v1/chat/config` |
| Tests | `src/plugins/chat/tests/test_chat_service.py` | ChatService unit tests |
| Tests | `src/plugins/chat/tests/test_token_counting.py` | Token counting strategy tests |
| Tests | `src/plugins/chat/tests/test_routes.py` | Route integration tests |
| Tests | `src/plugins/chat/tests/test_llm_adapter.py` | LLM adapter tests (mocked HTTP) |

### Frontend (User Plugin)

Directory structure:
```
user/plugins/chat/
├── index.ts                  # Plugin entry point
├── config.json               # Plugin config schema
├── admin-config.json         # Admin panel UI config
├── src/
│   ├── ChatView.vue          # Main chat page
│   ├── ChatMessage.vue       # Message bubble component
│   ├── ChatInput.vue         # Input + send button component
│   ├── ChatHeader.vue        # Balance + model + clear button
│   └── api.ts                # API client (sendMessage, getChatConfig, estimateCost)
├── locales/
│   ├── en.json               # English translations
│   └── de.json               # German translations
└── tests/
    ├── chat-plugin.spec.ts   # Plugin lifecycle tests
    ├── chat-view.spec.ts     # ChatView component tests
    ├── chat-message.spec.ts  # ChatMessage component tests
    └── chat-input.spec.ts    # ChatInput component tests
```

| Layer | File | Provides |
|-------|------|----------|
| Plugin | `user/plugins/chat/index.ts` | Plugin entry — route, translations, activate/deactivate |
| View | `user/plugins/chat/src/ChatView.vue` | Main chat page with message list, input, balance display |
| Component | `user/plugins/chat/src/ChatMessage.vue` | Single message bubble (user/assistant styling) |
| Component | `user/plugins/chat/src/ChatInput.vue` | Input field with send button, character count, cost estimate |
| Component | `user/plugins/chat/src/ChatHeader.vue` | Token balance display, model name, clear chat button |
| API | `user/plugins/chat/src/api.ts` | `sendMessage()`, `getChatConfig()` API calls |
| i18n | `user/plugins/chat/locales/en.json` | English translations |
| i18n | `user/plugins/chat/locales/de.json` | German translations |
| Config | `user/plugins/chat/config.json` | Frontend plugin config schema |
| Config | `user/plugins/chat/admin-config.json` | Admin panel UI for frontend config |
| Tests | `user/plugins/chat/tests/chat-plugin.spec.ts` | Plugin lifecycle tests |
| Tests | `user/plugins/chat/tests/chat-view.spec.ts` | ChatView component tests |
| Tests | `user/plugins/chat/tests/chat-message.spec.ts` | ChatMessage component tests |
| Tests | `user/plugins/chat/tests/chat-input.spec.ts` | ChatInput component tests |

### Modified Files

| File | Change |
|------|--------|
| `user/vue/src/main.ts` | Add `chatPlugin` import and registration |
| `user/vue/src/i18n/locales/en.json` | Add `nav.chat` key |
| `user/vue/src/i18n/locales/de.json` | Add `nav.chat` key |
| `user/vue/src/layouts/UserLayout.vue` | Add Chat nav link (`/dashboard/chat`) |
| `user/plugins/plugins.json` | Add `chat` entry |

---

## Task 1: Token Counting Strategies (Backend)

### Files

| File | Action |
|------|--------|
| `vbwd-backend/src/plugins/chat/token_counting.py` | **NEW** |
| `vbwd-backend/src/plugins/chat/tests/test_token_counting.py` | **NEW** |

### Interface

```python
from abc import ABC, abstractmethod
import math

class TokenCountingStrategy(ABC):
    @abstractmethod
    def calculate_tokens(self, text: str, config: dict) -> int:
        """Return platform token cost for the given text. Minimum 1."""
        pass

class WordCountStrategy(TokenCountingStrategy):
    def calculate_tokens(self, text: str, config: dict) -> int:
        words_per_token = config.get('words_per_token', 10)
        word_count = len(text.split())
        return max(1, math.ceil(word_count / words_per_token))

class DataVolumeStrategy(TokenCountingStrategy):
    def calculate_tokens(self, text: str, config: dict) -> int:
        mb_per_token = config.get('mb_per_token', 0.001)
        bytes_count = len(text.encode('utf-8'))
        mb_count = bytes_count / (1024 * 1024)
        return max(1, math.ceil(mb_count / mb_per_token))

class TokenizerStrategy(TokenCountingStrategy):
    def calculate_tokens(self, text: str, config: dict) -> int:
        tokens_per_token = config.get('tokens_per_token', 100)
        # Approximate: 1 LLM token ≈ 4 characters (GPT family heuristic)
        estimated_llm_tokens = max(1, len(text) // 4)
        return max(1, math.ceil(estimated_llm_tokens / tokens_per_token))

def get_counting_strategy(mode: str) -> TokenCountingStrategy:
    strategies = {
        'words': WordCountStrategy(),
        'data_volume': DataVolumeStrategy(),
        'tokenizer': TokenizerStrategy(),
    }
    return strategies.get(mode, WordCountStrategy())
```

### Tests (~15 tests)

```
test_word_count_simple_sentence
test_word_count_respects_config
test_word_count_minimum_one_token
test_word_count_empty_string
test_data_volume_small_message
test_data_volume_utf8_multibyte
test_data_volume_respects_config
test_data_volume_minimum_one_token
test_tokenizer_approximation
test_tokenizer_respects_config
test_tokenizer_minimum_one_token
test_get_counting_strategy_words
test_get_counting_strategy_data_volume
test_get_counting_strategy_tokenizer
test_get_counting_strategy_unknown_defaults_to_words
```

---

## Task 2: LLM Adapter (Backend)

### Files

| File | Action |
|------|--------|
| `vbwd-backend/src/plugins/chat/llm_adapter.py` | **NEW** |
| `vbwd-backend/src/plugins/chat/tests/test_llm_adapter.py` | **NEW** |

### Interface

```python
import requests
from typing import List, Dict, Optional

class LLMAdapter:
    def __init__(self, api_endpoint: str, api_key: str, model: str,
                 system_prompt: str = "You are a helpful assistant.",
                 timeout: int = 30):
        self.api_endpoint = api_endpoint
        self.api_key = api_key
        self.model = model
        self.system_prompt = system_prompt
        self.timeout = timeout

    def chat(self, messages: List[Dict[str, str]]) -> str:
        """
        Send messages to LLM and return assistant response text.

        Args:
            messages: List of {"role": "user"|"assistant", "content": "..."}

        Returns:
            Assistant response text.

        Raises:
            LLMError: If the API call fails.
        """
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": self.system_prompt},
                *messages
            ]
        }

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }

        response = requests.post(
            self.api_endpoint,
            json=payload,
            headers=headers,
            timeout=self.timeout
        )

        if response.status_code != 200:
            raise LLMError(f"LLM API returned {response.status_code}: {response.text}")

        data = response.json()
        return data["choices"][0]["message"]["content"]


class LLMError(Exception):
    """Raised when LLM API call fails."""
    pass
```

### Notes

- Uses the **OpenAI-compatible** chat completions format (`/v1/chat/completions`) — works with OpenAI, Anthropic (via proxy), Ollama, LiteLLM, vLLM, etc.
- `Bearer` auth header — standard for most LLM APIs
- Timeout configurable (default 30s)

### Tests (~10 tests)

```
test_chat_success_returns_content
test_chat_sends_system_prompt
test_chat_sends_model_in_payload
test_chat_sends_auth_header
test_chat_raises_on_non_200
test_chat_raises_on_timeout
test_chat_raises_on_invalid_json
test_chat_includes_message_history
test_chat_empty_messages_list
test_constructor_stores_config
```

---

## Task 3: Chat Service (Backend)

### Files

| File | Action |
|------|--------|
| `vbwd-backend/src/plugins/chat/chat_service.py` | **NEW** |
| `vbwd-backend/src/plugins/chat/tests/test_chat_service.py` | **NEW** |

### Interface

```python
from typing import List, Dict
from uuid import UUID

class ChatService:
    def __init__(self, token_service, llm_adapter, counting_strategy, config: dict):
        self.token_service = token_service
        self.llm_adapter = llm_adapter
        self.counting_strategy = counting_strategy
        self.config = config

    def send_message(
        self,
        user_id: UUID,
        message: str,
        history: List[Dict[str, str]]
    ) -> dict:
        """
        Send a message to LLM, deduct tokens, return response.

        Returns:
            {
                "response": "Assistant reply text",
                "tokens_used": 5,
                "balance": 1245
            }

        Raises:
            ValueError: If insufficient token balance.
            LLMError: If LLM API call fails.
        """
        # 1. Validate message length
        max_length = self.config.get('max_message_length', 4000)
        if len(message) > max_length:
            raise ValueError(f"Message exceeds maximum length of {max_length} characters")

        # 2. Calculate cost for user message
        request_cost = self.counting_strategy.calculate_tokens(message, self.config)

        # 3. Check balance (pre-flight)
        balance = self.token_service.get_balance(user_id)
        if balance < request_cost:
            raise ValueError("Insufficient token balance")

        # 4. Trim history to max_history_messages
        max_history = self.config.get('max_history_messages', 20)
        trimmed_history = history[-max_history:]

        # 5. Call LLM
        messages = trimmed_history + [{"role": "user", "content": message}]
        response_text = self.llm_adapter.chat(messages)

        # 6. Calculate response cost
        response_cost = self.counting_strategy.calculate_tokens(response_text, self.config)
        total_cost = request_cost + response_cost

        # 7. Deduct tokens
        updated_balance = self.token_service.debit_tokens(
            user_id=user_id,
            amount=total_cost,
            transaction_type='USAGE',
            reference_id=None,
            description=f"Chat: {total_cost} tokens ({request_cost} sent + {response_cost} received)"
        )

        return {
            "response": response_text,
            "tokens_used": total_cost,
            "balance": updated_balance.balance
        }

    def estimate_cost(self, message: str) -> int:
        """Estimate token cost for a message (before sending)."""
        return self.counting_strategy.calculate_tokens(message, self.config)
```

### Tests (~12 tests)

```
test_send_message_returns_response
test_send_message_deducts_tokens
test_send_message_returns_updated_balance
test_send_message_insufficient_balance_raises
test_send_message_counts_both_request_and_response_tokens
test_send_message_trims_history
test_send_message_validates_max_length
test_send_message_llm_error_no_deduction
test_estimate_cost_returns_token_count
test_estimate_cost_minimum_one
test_send_message_uses_configured_strategy
test_send_message_passes_history_to_llm
```

---

## Task 4: Chat Plugin & Routes (Backend)

### Files

| File | Action |
|------|--------|
| `vbwd-backend/src/plugins/chat/__init__.py` | **NEW** |
| `vbwd-backend/src/plugins/chat/routes.py` | **NEW** |
| `vbwd-backend/src/plugins/chat/tests/__init__.py` | **NEW** |
| `vbwd-backend/src/plugins/chat/tests/test_routes.py` | **NEW** |

### Plugin Class

```python
# __init__.py
from src.plugins.base import BasePlugin, PluginMetadata

class ChatPlugin(BasePlugin):
    @property
    def metadata(self) -> PluginMetadata:
        return PluginMetadata(
            name='chat',
            version='1.0.0',
            author='VBWD',
            description='LLM chat with token-based billing'
        )

    def get_blueprint(self):
        from .routes import chat_bp
        return chat_bp

    def get_url_prefix(self):
        return '/api/v1/chat'

    def on_enable(self):
        pass

    def on_disable(self):
        pass
```

### Routes

```python
# routes.py
from flask import Blueprint, request, jsonify
from src.middleware.auth import require_auth

chat_bp = Blueprint('chat', __name__)

@chat_bp.route('/send', methods=['POST'])
@require_auth
def send_message():
    """
    POST /api/v1/chat/send
    Body: { "message": "...", "history": [...] }
    Response: { "response": "...", "tokens_used": 5, "balance": 1245 }
    """
    pass

@chat_bp.route('/config', methods=['GET'])
@require_auth
def get_chat_config():
    """
    GET /api/v1/chat/config
    Response: {
        "model": "gpt-4o-mini",
        "max_message_length": 4000,
        "counting_mode": "words",
        "show_token_cost": true,
        "show_model_name": true
    }
    NOTE: Never returns api_key or api_endpoint to frontend.
    """
    pass

@chat_bp.route('/estimate', methods=['POST'])
@require_auth
def estimate_cost():
    """
    POST /api/v1/chat/estimate
    Body: { "message": "..." }
    Response: { "estimated_tokens": 3 }
    """
    pass
```

### Tests (~15 tests)

```
test_send_message_success
test_send_message_returns_tokens_used
test_send_message_unauthorized
test_send_message_empty_body
test_send_message_missing_message_field
test_send_message_insufficient_balance
test_send_message_plugin_disabled
test_send_message_llm_error_returns_502
test_get_config_returns_safe_fields
test_get_config_never_returns_api_key
test_get_config_never_returns_api_endpoint
test_get_config_unauthorized
test_estimate_cost_success
test_estimate_cost_empty_message
test_estimate_cost_unauthorized
```

---

## Task 5: Frontend Chat Plugin Entry

### Files

| File | Action |
|------|--------|
| `vbwd-frontend/user/plugins/chat/index.ts` | **NEW** |
| `vbwd-frontend/user/plugins/chat/src/api.ts` | **NEW** |
| `vbwd-frontend/user/plugins/chat/locales/en.json` | **NEW** |
| `vbwd-frontend/user/plugins/chat/locales/de.json` | **NEW** |
| `vbwd-frontend/user/plugins/chat/config.json` | **NEW** |
| `vbwd-frontend/user/plugins/chat/admin-config.json` | **NEW** |
| `vbwd-frontend/user/vue/src/main.ts` | **MODIFY** — add chatPlugin |
| `vbwd-frontend/user/vue/src/i18n/locales/en.json` | **MODIFY** — add `nav.chat` |
| `vbwd-frontend/user/vue/src/i18n/locales/de.json` | **MODIFY** — add `nav.chat` |
| `vbwd-frontend/user/vue/src/layouts/UserLayout.vue` | **MODIFY** — add Chat nav link |
| `vbwd-frontend/user/plugins/plugins.json` | **MODIFY** — add chat entry |

### Plugin Entry

```typescript
// index.ts
import type { IPlugin, IPlatformSDK } from '@vbwd/view-component';
import en from './locales/en.json';
import de from './locales/de.json';

export const chatPlugin: IPlugin = {
  name: 'chat',
  version: '1.0.0',
  description: 'LLM chat with token-based billing',

  install(sdk: IPlatformSDK) {
    sdk.addRoute({
      path: '/dashboard/chat',
      name: 'chat',
      component: () => import('./src/ChatView.vue'),
      meta: { requiresAuth: true }
    });
    sdk.addTranslations('en', en);
    sdk.addTranslations('de', de);
  },

  activate() { this._active = true; },
  deactivate() { this._active = false; }
};
```

### API Client

```typescript
// src/api.ts
export async function sendMessage(message: string, history: Array<{role: string; content: string}>) {
  const res = await fetch('/api/v1/chat/send', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${localStorage.getItem('auth_token')}` },
    body: JSON.stringify({ message, history })
  });
  if (!res.ok) throw await res.json();
  return res.json(); // { response, tokens_used, balance }
}

export async function getChatConfig() {
  const res = await fetch('/api/v1/chat/config', {
    headers: { 'Authorization': `Bearer ${localStorage.getItem('auth_token')}` }
  });
  if (!res.ok) throw new Error('Failed to load chat config');
  return res.json(); // { model, max_message_length, counting_mode, ... }
}

export async function estimateCost(message: string) {
  const res = await fetch('/api/v1/chat/estimate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${localStorage.getItem('auth_token')}` },
    body: JSON.stringify({ message })
  });
  if (!res.ok) return { estimated_tokens: 0 };
  return res.json(); // { estimated_tokens }
}
```

### Locale Files

```json
// locales/en.json
{
  "chat": {
    "title": "Chat",
    "placeholder": "Type your message...",
    "send": "Send",
    "balance": "Balance",
    "tokensUsed": "{count} tokens used",
    "estimatedCost": "Est. cost: ~{count} TKN",
    "insufficientBalance": "Insufficient token balance. Please purchase more tokens.",
    "errorSending": "Failed to send message. Please try again.",
    "clearChat": "Clear Chat",
    "cleared": "Chat cleared",
    "configError": "Chat is not configured. Please contact the administrator.",
    "model": "Model",
    "emptyState": "Start a conversation by typing a message below."
  }
}
```

```json
// locales/de.json
{
  "chat": {
    "title": "Chat",
    "placeholder": "Nachricht eingeben...",
    "send": "Senden",
    "balance": "Guthaben",
    "tokensUsed": "{count} Token verwendet",
    "estimatedCost": "Geschätzte Kosten: ~{count} TKN",
    "insufficientBalance": "Nicht genügend Token-Guthaben. Bitte kaufen Sie weitere Token.",
    "errorSending": "Nachricht konnte nicht gesendet werden. Bitte versuchen Sie es erneut.",
    "clearChat": "Chat löschen",
    "cleared": "Chat gelöscht",
    "configError": "Chat ist nicht konfiguriert. Bitte kontaktieren Sie den Administrator.",
    "model": "Modell",
    "emptyState": "Beginnen Sie ein Gespräch, indem Sie unten eine Nachricht eingeben."
  }
}
```

### Admin Config (Frontend)

```json
// config.json
{
  "showTokenCost": {
    "type": "boolean",
    "default": true,
    "description": "Show estimated token cost before sending"
  },
  "showModelName": {
    "type": "boolean",
    "default": true,
    "description": "Show LLM model name in chat header"
  }
}
```

```json
// admin-config.json
{
  "tabs": [
    {
      "id": "display",
      "label": "Display",
      "fields": [
        { "key": "showTokenCost", "label": "Show Token Cost", "component": "checkbox" },
        { "key": "showModelName", "label": "Show Model Name", "component": "checkbox" }
      ]
    }
  ]
}
```

### Nav & Registration

```json
// en.json (global) — add to "nav" object
"chat": "Chat"

// de.json (global) — add to "nav" object
"chat": "Chat"
```

```html
<!-- UserLayout.vue — add after appearance link -->
<router-link to="/dashboard/chat" class="nav-item" data-testid="nav-chat">
  {{ $t('nav.chat') }}
</router-link>
```

---

## Task 6: Frontend Chat Components

### Files

| File | Action |
|------|--------|
| `vbwd-frontend/user/plugins/chat/src/ChatView.vue` | **NEW** |
| `vbwd-frontend/user/plugins/chat/src/ChatHeader.vue` | **NEW** |
| `vbwd-frontend/user/plugins/chat/src/ChatMessage.vue` | **NEW** |
| `vbwd-frontend/user/plugins/chat/src/ChatInput.vue` | **NEW** |

### ChatView.vue (Main Container)

```
┌─ ChatView ──────────────────────────────────────┐
│ ┌─ ChatHeader ────────────────────────────────┐ │
│ │ Balance: 1,250 TKN          Model: gpt-4o   │ │
│ │                              [Clear Chat]    │ │
│ └──────────────────────────────────────────────┘ │
│ ┌─ Messages Area (scrollable) ────────────────┐ │
│ │ ┌─ ChatMessage (assistant) ───────────────┐ │ │
│ │ │ Hello! How can I help you?              │ │ │
│ │ └─────────────────────────────────────────┘ │ │
│ │ ┌─ ChatMessage (user) ────────────────────┐ │ │
│ │ │ What features does the Pro plan include? │ │ │
│ │ └─────────────────────────────────────────┘ │ │
│ │ ┌─ ChatMessage (assistant) ───────────────┐ │ │
│ │ │ The Pro plan includes...                │ │ │
│ │ │ Tokens used: 5 TKN                      │ │ │
│ │ └─────────────────────────────────────────┘ │ │
│ └──────────────────────────────────────────────┘ │
│ ┌─ ChatInput ─────────────────────────────────┐ │
│ │ [Type your message...              ] [Send] │ │
│ │ Est. cost: ~3 TKN                           │ │
│ └──────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────┘
```

**ChatView responsibilities**:
- Manages `messages` array (reactive, session-only)
- Fetches config on mount (`getChatConfig()`)
- Fetches initial balance (`GET /api/v1/user/tokens/balance`)
- Delegates sending to `sendMessage()` API, updates balance from response
- Auto-scrolls to bottom on new messages
- Error handling (insufficient balance, LLM errors)

**ChatHeader props**: `balance: number`, `modelName: string`, `showModel: boolean`
**ChatHeader emits**: `clear`

**ChatMessage props**: `role: 'user' | 'assistant'`, `content: string`, `tokensUsed?: number`

**ChatInput props**: `disabled: boolean`, `maxLength: number`, `estimatedCost: number`, `showCost: boolean`
**ChatInput emits**: `send(message: string)`

### Styling

All components use CSS variables from the theme system:

```css
/* Chat uses existing theme variables */
.chat-container { background: var(--vbwd-card-bg, #fff); }
.chat-header { border-bottom: 1px solid var(--vbwd-border-light, #eee); }
.message-user { background: var(--vbwd-color-primary, #3498db); color: white; }
.message-assistant { background: var(--vbwd-page-bg, #f5f5f5); color: var(--vbwd-text-body, #333); }
.chat-input { border: 1px solid var(--vbwd-border-color, #ddd); }
.send-btn { background: var(--vbwd-color-primary, #3498db); }
.balance-display { color: var(--vbwd-color-success, #27ae60); }
.balance-low { color: var(--vbwd-color-danger, #e74c3c); }
```

---

## Task 7: Frontend Tests

### Files

| File | Action |
|------|--------|
| `user/plugins/chat/tests/chat-plugin.spec.ts` | **NEW** |
| `user/plugins/chat/tests/chat-view.spec.ts` | **NEW** |
| `user/plugins/chat/tests/chat-message.spec.ts` | **NEW** |
| `user/plugins/chat/tests/chat-input.spec.ts` | **NEW** |

**Note**: The user vitest config (`user/vitest.config.js`) includes `vue/tests/unit/**/*.spec.{js,ts}`. Since plugin tests now live in `plugins/chat/tests/`, the vitest include pattern must be extended:

```js
include: [
  'vue/tests/unit/**/*.spec.{js,ts}',
  'vue/tests/integration/**/*.spec.{js,ts}',
  'plugins/*/tests/*.spec.{js,ts}'   // <-- add this
],
```

### chat-plugin.spec.ts (~8 tests)

```
test_plugin_has_correct_metadata
test_plugin_registers_chat_route
test_plugin_route_requires_auth
test_plugin_adds_en_translations
test_plugin_adds_de_translations
test_plugin_activate_sets_active
test_plugin_deactivate_sets_inactive
test_plugin_full_lifecycle
```

### chat-view.spec.ts (~12 tests)

```
test_renders_chat_container
test_displays_empty_state_initially
test_fetches_config_on_mount
test_fetches_balance_on_mount
test_sends_message_and_displays_response
test_updates_balance_after_send
test_shows_loading_indicator_while_sending
test_disables_input_while_sending
test_displays_insufficient_balance_error
test_displays_llm_error
test_clear_chat_removes_messages
test_auto_scrolls_on_new_message
```

### chat-message.spec.ts (~6 tests)

```
test_renders_user_message_with_correct_style
test_renders_assistant_message_with_correct_style
test_displays_message_content
test_displays_tokens_used_for_assistant
test_hides_tokens_used_when_not_provided
test_renders_markdown_content (if applicable)
```

### chat-input.spec.ts (~8 tests)

```
test_renders_input_and_send_button
test_emits_send_with_message_text
test_clears_input_after_send
test_disables_when_disabled_prop
test_prevents_empty_message_send
test_enforces_max_length
test_shows_estimated_cost
test_hides_cost_when_show_cost_false
```

---

## Task 8: Backend Admin Config (Backend Plugin Config)

### Files

| File | Action |
|------|--------|
| `vbwd-backend/src/plugins/chat/__init__.py` | **MODIFY** — add default config |

### Default Config

The `ChatPlugin.initialize()` method sets default config values:

```python
DEFAULT_CONFIG = {
    'llm_api_endpoint': '',
    'llm_api_key': '',
    'llm_model': 'gpt-4o-mini',
    'counting_mode': 'words',
    'words_per_token': 10,
    'mb_per_token': 0.001,
    'tokens_per_token': 100,
    'system_prompt': 'You are a helpful assistant.',
    'max_message_length': 4000,
    'max_history_messages': 20,
}
```

Admin sets these values via the existing admin plugin config UI (backend plugins section in admin panel). The `PluginManager` persists config to the database.

---

## Expected Test Counts

| Suite | New Tests | Description |
|-------|-----------|-------------|
| Backend `plugins/chat/tests/test_token_counting.py` | ~15 | Token counting strategies |
| Backend `plugins/chat/tests/test_llm_adapter.py` | ~10 | LLM adapter (mocked HTTP) |
| Backend `plugins/chat/tests/test_chat_service.py` | ~12 | Chat service orchestration |
| Backend `plugins/chat/tests/test_routes.py` | ~15 | Flask route tests |
| Frontend `chat-plugin.spec.ts` | ~8 | Plugin lifecycle |
| Frontend `chat-view.spec.ts` | ~12 | Main chat view |
| Frontend `chat-message.spec.ts` | ~6 | Message component |
| Frontend `chat-input.spec.ts` | ~8 | Input component |
| **Total** | **~86** | |

---

## Implementation Order

1. **Task 1** — Token counting strategies (backend, no dependencies)
2. **Task 2** — LLM adapter (backend, no dependencies)
3. **Task 3** — Chat service (backend, depends on Tasks 1 & 2)
4. **Task 4** — Chat plugin & routes (backend, depends on Task 3)
5. **Task 8** — Backend admin config (backend, depends on Task 4)
6. **Task 5** — Frontend plugin entry, API client, i18n, registration
7. **Task 6** — Frontend chat components (depends on Task 5)
8. **Task 7** — Frontend tests (parallel with Task 6, TDD)

Tasks 1 & 2 can be implemented in parallel. Tasks 5-7 can begin once backend routes are testable.
