# Sprint Plan: Taro Plugin - MVP Implementation

**Date:** 2026-02-15
**Duration:** TBD (based on implementation complexity)
**Priority:** 🟢 **HIGH** - New plugin for token-based features
**Status:** Planning

---

## Sprint Goal

Implement the Taro (Tarot reading) plugin MVP with 3-card spreads, follow-up questions, token consumption tracking, and daily usage limits. Complete backend infrastructure (models, services, events, handlers) and full frontend integration with proper TDD-first approach.

---

## Core Development Requirements

This sprint adheres to strict development standards:

- **TDD (Test-Driven Development):** Tests written first, implementation follows (RED → GREEN → REFACTOR)
- **SOLID Principles:** Single responsibility, Open/closed, Liskov, Interface segregation, Dependency inversion
- **Event-Driven Architecture:** Routes emit events → Event Handlers → Services → Repositories
- **Clean Code:** Self-documenting, meaningful names, no magic numbers, comments explain WHY
- **No Over-Engineering:** Implement only what's needed NOW, simplest solution that works
- **Verification:** All changes verified with `./bin/pre-commit-check.sh --full`

---

## Feature Specifications

### Core Features
- **78-Card Tarot Deck:** 22 Major Arcana + 56 Minor Arcana (4 suits)
- **3-Card Spread:** Random card selection with position meaning (Past, Present, Future)
- **Card Interpretation:** LLM-generated explanations (upright/reversed considerations)
- **Follow-Up Questions:** Users can ask up to 3 follow-up questions per session (add-on dependent)
- **Session Management:** 30-minute expiry with 3-minute warning before timeout
- **Token Consumption:**
  - Fixed cost per session (e.g., 10 tokens)
  - Variable cost based on LLM response length
  - Daily limits by tarif plan (Basic: 1/day, Star: 3/day, Guru: 12/day)
  - Block access when daily limit reached with "come back tomorrow" message
- **Add-On Features:**
  - Same Cards Follow-Up: Ask about same 3 cards
  - Additional Card Follow-Up: Get 1 more card for new perspective
  - New Cards Follow-Up: Full new 3-card spread
- **Session History:** View previous spreads (cards, positions, explanations)
- **LLM Configuration:** Separate LLM config per plugin instance (not shared with Chat)

---

## Deliverables by Priority

### Phase 1: Backend Models & Database (TDD First)

**Objective:** Create all backend models with migrations, repositories, and comprehensive tests

#### 1.1 Arcana Model

**Test First:** `src/plugins/taro/tests/unit/models/test_arcana.py`
```python
def test_arcana_creation_with_all_fields()
def test_arcana_requires_name()
def test_arcana_requires_arcana_type()
def test_arcana_arcana_types_are_uppercase()
def test_major_arcana_has_number_0_to_21()
def test_minor_arcana_has_suit_and_rank()
def test_arcana_upright_meaning()
def test_arcana_reversed_meaning()
def test_arcana_image_url_generation()
```

**Then Implement:** `src/plugins/taro/models/arcana.py`
```python
class ArcanaType(enum.Enum):
    MAJOR_ARCANA = "MAJOR_ARCANA"
    CUPS = "CUPS"
    WANDS = "WANDS"
    SWORDS = "SWORDS"
    PENTACLES = "PENTACLES"

class Arcana(Base):
    id: str
    number: Optional[int]  # 0-21 for Major Arcana
    name: str              # "The Fool", "The Magician", etc.
    suit: Optional[str]    # "Cups", "Wands", "Swords", "Pentacles"
    rank: Optional[str]    # "Ace", "Two", ..., "King"
    arcana_type: ArcanaType
    upright_meaning: str
    reversed_meaning: str
    image_url: str
    created_at: datetime
```

**Database Migration:** `alembic/versions/YYYYMMDD_create_arcana_table.py`
- Creates `arcana` table with all fields
- Composite unique constraint on (arcana_type, number, suit, rank)
- Indexes on arcana_type, name for lookups

---

#### 1.2 TaroSession Model

**Test First:** `src/plugins/taro/tests/unit/models/test_taro_session.py`
```python
def test_taro_session_creation()
def test_taro_session_requires_user_id()
def test_taro_session_status_transitions()
def test_taro_session_expiry_calculation()
def test_taro_session_token_consumption_tracking()
def test_taro_session_follow_up_count()
def test_taro_session_daily_limit_checking()
```

**Then Implement:** `src/plugins/taro/models/taro_session.py`
```python
class SessionStatus(enum.Enum):
    ACTIVE = "ACTIVE"
    EXPIRED = "EXPIRED"
    CLOSED = "CLOSED"

class TaroSession(Base):
    id: str
    user_id: str
    status: SessionStatus = SessionStatus.ACTIVE
    started_at: datetime
    expires_at: datetime  # started_at + 30 minutes
    ended_at: Optional[datetime]
    spread_id: str  # 3-card spread unique ID
    tokens_consumed: int = 0
    follow_up_count: int = 0
    max_follow_ups: int = 3  # From add-on or tarif plan
    created_at: datetime
    updated_at: datetime
```

---

#### 1.3 TaroCardDraw Model (Spread Cards)

**Test First:** `src/plugins/taro/tests/unit/models/test_taro_card_draw.py`
```python
def test_card_draw_creation()
def test_card_draw_requires_session_id()
def test_card_draw_requires_arcana_id()
def test_card_draw_position_validation()
def test_card_draw_upright_reversed_tracking()
def test_card_draw_position_meanings()
```

**Then Implement:** `src/plugins/taro/models/taro_card_draw.py`
```python
class CardPosition(enum.Enum):
    PAST = "PAST"
    PRESENT = "PRESENT"
    FUTURE = "FUTURE"

class CardOrientation(enum.Enum):
    UPRIGHT = "UPRIGHT"
    REVERSED = "REVERSED"

class TaroCardDraw(Base):
    id: str
    session_id: str  # FK to TaroSession
    arcana_id: str   # FK to Arcana
    position: CardPosition
    orientation: CardOrientation  # Upright or Reversed
    ai_interpretation: str  # LLM-generated explanation
    created_at: datetime
```

---

#### 1.4 Repositories

**Test First:** `src/plugins/taro/tests/unit/repositories/test_arcana_repository.py`
```python
def test_get_arcana_by_id()
def test_get_all_arcanas()
def test_get_random_arcanas(count=3)
def test_filter_by_arcana_type()
def test_arcana_count_by_type()
```

**Then Implement:** `src/plugins/taro/repositories/arcana_repository.py`
```python
class ArcanaRepository:
    def get_by_id(self, arcana_id: str) -> Optional[Arcana]
    def get_all(self) -> List[Arcana]
    def get_random(self, count: int = 3) -> List[Arcana]
    def filter_by_type(self, arcana_type: ArcanaType) -> List[Arcana]
    def count_by_type(self) -> Dict[str, int]
```

**Test First:** `src/plugins/taro/tests/unit/repositories/test_taro_session_repository.py`
```python
def test_create_session()
def test_get_session_by_id()
def test_get_user_sessions(user_id)
def test_get_active_session(user_id)
def test_update_session_status()
def test_get_expired_sessions()
def test_delete_session()
```

**Then Implement:** `src/plugins/taro/repositories/taro_session_repository.py`
```python
class TaroSessionRepository:
    def create(self, user_id: str, expires_at: datetime) -> TaroSession
    def get_by_id(self, session_id: str) -> Optional[TaroSession]
    def get_user_sessions(self, user_id: str) -> List[TaroSession]
    def get_active_session(self, user_id: str) -> Optional[TaroSession]
    def update_status(self, session_id: str, status: SessionStatus) -> None
    def get_expired_sessions() -> List[TaroSession]
    def delete(self, session_id: str) -> None
```

**Test First:** `src/plugins/taro/tests/unit/repositories/test_taro_card_draw_repository.py`
```python
def test_create_card_draw()
def test_get_session_cards()
def test_get_card_by_position()
def test_update_card_interpretation()
```

**Then Implement:** `src/plugins/taro/repositories/taro_card_draw_repository.py`

---

### Phase 2: Backend Services & Events (TDD First)

**Objective:** Implement business logic with comprehensive tests and event emission

#### 2.1 TaroSessionService

**Test First:** `src/plugins/taro/tests/unit/services/test_taro_session_service.py`
```python
def test_create_session_for_user()
def test_check_daily_limit_basic_plan()
def test_check_daily_limit_star_plan()
def test_check_daily_limit_guru_plan()
def test_reject_session_when_limit_exceeded()
def test_session_expiry_calculation()
def test_session_status_update()
def test_get_active_session()
def test_session_timeout_detection()
def test_token_consumption_calculation()
def test_follow_up_limit_validation()
```

**Then Implement:** `src/plugins/taro/services/taro_session_service.py`
```python
class TaroSessionService:
    def __init__(
        self,
        session_repo: TaroSessionRepository,
        card_draw_repo: TaroCardDrawRepository,
        arcana_repo: ArcanaRepository,
        user_service: UserService,
        subscription_service: SubscriptionService,
        token_service: TokenService,
        event_dispatcher: EventDispatcher
    ):
        ...

    def create_session(self, user_id: str) -> TaroSession
        # Check daily limit
        # Deduct token cost
        # Create session with 30-min expiry
        # Emit TaroSessionCreatedEvent

    def check_daily_limit(self, user_id: str) -> Tuple[bool, int]
        # Get user's subscription plan
        # Count today's sessions
        # Return (allowed, remaining_today)

    def create_spread(self, session_id: str) -> List[TaroCardDraw]
        # Get 3 random cards
        # Assign positions (Past, Present, Future)
        # Randomize upright/reversed
        # Store card draws
        # Return card list

    def get_session_with_interpretation(self, session_id: str) -> dict
        # Get session and cards
        # Include LLM interpretations
        # Check expiry status

    def add_follow_up_question(
        self,
        session_id: str,
        question: str,
        follow_up_type: str  # "same_cards", "additional", "new_spread"
    ) -> TaroSession
        # Validate follow-up limit
        # Validate session not expired
        # Generate follow-up based on type
        # Emit TaroFollowUpEvent

    def close_session(self, session_id: str) -> None
        # Update status to CLOSED
        # Emit TaroSessionClosedEvent

    def cleanup_expired_sessions(self) -> int
        # Find expired sessions
        # Update status to EXPIRED
        # Return count cleaned
```

---

#### 2.2 Arcana Interpretation Service (LLM)

**Test First:** `src/plugins/taro/tests/unit/services/test_arcana_interpretation_service.py`
```python
def test_generate_interpretation_upright()
def test_generate_interpretation_reversed()
def test_interpret_3_card_spread()
def test_handle_llm_api_errors()
def test_cache_interpretations()
def test_token_cost_calculation()
```

**Then Implement:** `src/plugins/taro/services/arcana_interpretation_service.py`
```python
class ArcanaInterpretationService:
    def __init__(self, config: TaroLLMConfig, event_dispatcher: EventDispatcher):
        ...

    def generate_interpretation(
        self,
        arcana: Arcana,
        position: CardPosition,
        orientation: CardOrientation
    ) -> Tuple[str, int]  # Returns (interpretation, tokens_used)
        # Call LLM API
        # Generate unique interpretation
        # Track tokens used
        # Return interpretation + token cost

    def interpret_spread(
        self,
        cards: List[TaroCardDraw]
    ) -> Tuple[str, int]  # Returns (spread_interpretation, total_tokens)
        # Generate cohesive interpretation across 3 cards
        # Consider position meanings
        # Return overall interpretation

    def handle_follow_up(
        self,
        session: TaroSession,
        question: str,
        follow_up_type: str
    ) -> Tuple[str, int, List[TaroCardDraw]]
        # Generate follow-up based on type
        # Track additional tokens
        # Return interpretation + tokens + new cards
```

---

#### 2.3 Define Events

**Create:** `src/plugins/taro/events.py`
```python
class TaroSessionRequestedEvent(Event):
    user_id: str
    session_id: str
    created_at: datetime

class TaroSessionCreatedEvent(Event):
    session_id: str
    user_id: str
    expires_at: datetime
    initial_cards: List[dict]

class TaroFollowUpRequestedEvent(Event):
    session_id: str
    user_id: str
    question: str
    follow_up_type: str

class TaroSessionExpiredEvent(Event):
    session_id: str
    user_id: str
```

---

#### 2.4 Event Handlers

**Test First:** `src/plugins/taro/tests/unit/handlers/test_taro_event_handlers.py`
```python
def test_taro_session_created_handler()
def test_follow_up_handler()
def test_session_expired_handler()
def test_token_consumption_recorded()
```

**Then Implement:** `src/plugins/taro/handlers/taro_session_handler.py`
```python
class TaroSessionCreatedHandler(EventHandler):
    def __init__(
        self,
        session_service: TaroSessionService,
        token_service: TokenService
    ):
        ...

    def handle(self, event: TaroSessionCreatedEvent) -> HandlerResult
        # Generate initial card interpretations via LLM
        # Deduct tokens from user balance
        # Record token transaction
        # Emit token consumption event

class TaroFollowUpHandler(EventHandler):
    def handle(self, event: TaroFollowUpRequestedEvent) -> HandlerResult
        # Generate follow-up based on type
        # Calculate additional token cost
        # Deduct tokens
        # Update session follow-up count
```

---

#### 2.5 Backend Routes

**Test First:** `src/plugins/taro/tests/unit/routes/test_taro_routes.py`
```python
def test_create_session_route()
def test_create_session_requires_auth()
def test_create_session_checks_daily_limit()
def test_create_session_insufficient_tokens()
def test_get_session_route()
def test_get_session_not_found()
def test_add_follow_up_question_route()
def test_get_session_history_route()
def test_invalid_follow_up_type()
def test_session_already_expired()
```

**Then Implement:** `src/plugins/taro/routes.py`
```python
taro_bp = Blueprint('taro', __name__, url_prefix='/api/v1/user/taro')

@taro_bp.route('/session', methods=['POST'])
@require_auth
def create_session():
    """POST /api/v1/user/taro/session - Create new Taro session

    Request: { "question": "optional" }
    Response: { "session_id", "cards", "expires_at" }
    """

@taro_bp.route('/session/<session_id>', methods=['GET'])
@require_auth
def get_session(session_id):
    """GET /api/v1/user/taro/session/<id> - Get session details"""

@taro_bp.route('/session/<session_id>/follow-up', methods=['POST'])
@require_auth
def add_follow_up(session_id):
    """POST /api/v1/user/taro/session/<id>/follow-up

    Request: { "question", "type": "same_cards|additional|new_spread" }
    Response: { "interpretation", "tokens_used", "new_cards" }
    """

@taro_bp.route('/history', methods=['GET'])
@require_auth
def get_session_history():
    """GET /api/v1/user/taro/history - Get all past sessions"""

@taro_bp.route('/limits', methods=['GET'])
@require_auth
def get_limits():
    """GET /api/v1/user/taro/limits - Get daily usage limits"""
```

---

#### 2.6 Arcana Population Script

**Create:** `src/plugins/taro/bin/populate_arcanas.py` (Plugin-internal script)
```python
#!/usr/bin/env python3
"""
Populate the arcana table with 78 Tarot cards.
Includes 22 Major Arcana + 56 Minor Arcana (4 suits × 14 ranks)
"""

# 22 Major Arcana (0-21)
MAJOR_ARCANA = [
    {"number": 0, "name": "The Fool", "upright": "...", "reversed": "..."},
    # ... 21 more cards
]

# 56 Minor Arcana (4 suits × 14 ranks: Ace-10, Page, Knight, Queen, King)
CUPS = [...]
WANDS = [...]
SWORDS = [...]
PENTACLES = [...]
```

---

### Phase 3: Frontend Implementation

**Objective:** Create Vue components, Pinia store, and full UI integration

#### 3.1 Taro Pinia Store

**Test First:** `tests/unit/stores/test_taro.ts`
```typescript
describe('Taro Store', () => {
  it('should create session')
  it('should get session details')
  it('should add follow-up question')
  it('should handle session expiry')
  it('should track daily limit')
  it('should calculate remaining questions')
  it('should cache session history')
})
```

**Then Implement:** `user/vue/src/plugins/taro/stores/taro.ts`
```typescript
interface TaroCard {
  id: string
  name: string
  position: 'PAST' | 'PRESENT' | 'FUTURE'
  orientation: 'UPRIGHT' | 'REVERSED'
  interpretation: string
  imageUrl: string
}

interface TaroSession {
  id: string
  status: 'ACTIVE' | 'EXPIRED' | 'CLOSED'
  cards: TaroCard[]
  followUps: FollowUp[]
  expiresAt: string
  tokensConsumed: number
  createdAt: string
}

export const useTaroStore = defineStore('taro', {
  state: () => ({
    currentSession: null as TaroSession | null,
    sessionHistory: [] as TaroSession[],
    dailyRemaining: 0,
    dailyLimit: 0,
    maxFollowUps: 3,
    loading: false,
    error: null as string | null,
    warningTime: 180000  // 3 minutes before expiry
  }),

  actions: {
    async createSession(question?: string): Promise<TaroSession>
    async getSession(sessionId: string): Promise<TaroSession>
    async addFollowUp(sessionId: string, question: string, type: string)
    async getSessionHistory(): Promise<TaroSession[]>
    async getDailyLimits()
    async closeSession(sessionId: string)
  }
})
```

---

#### 3.2 Taro Dashboard View

**Create:** `user/vue/src/plugins/taro/views/Taro.vue`
```vue
<template>
  <div class="taro-dashboard">
    <!-- Daily Limit Alert -->
    <div v-if="dailyRemaining === 0" class="limit-reached">
      You've reached today's Taro reading limit. Come back tomorrow!
    </div>

    <!-- Active Session Display -->
    <div v-if="currentSession && !sessionExpired" class="session-container">
      <CardDisplay :cards="currentSession.cards" />
      <SessionInfo :session="currentSession" />
      <ExpiryWarning :expires-at="currentSession.expiresAt" />
      <QuestionInput :session-id="currentSession.id" />
    </div>

    <!-- Expired Session Message -->
    <div v-if="sessionExpired" class="session-expired">
      Session expired. Start a new reading?
    </div>

    <!-- No Active Session -->
    <div v-if="!currentSession" class="start-session">
      <button @click="startNewSession" :disabled="dailyRemaining === 0">
        Start Taro Reading
      </button>
    </div>

    <!-- Session History -->
    <SessionHistory :history="sessionHistory" />
  </div>
</template>
```

---

#### 3.3 CardDisplay Component

**Create:** `user/vue/src/plugins/taro/components/CardDisplay.vue`
```vue
<template>
  <div class="card-spread">
    <div v-for="card in cards" :key="card.id" class="card">
      <div class="card-image">
        <img :src="card.imageUrl" :alt="card.name" />
      </div>
      <div class="card-info">
        <h3>{{ card.name }}</h3>
        <p class="position">{{ formatPosition(card.position) }}</p>
        <p class="orientation" :class="card.orientation.toLowerCase()">
          {{ card.orientation }}
        </p>
        <div class="interpretation">
          {{ card.interpretation }}
        </div>
      </div>
    </div>
  </div>
</template>
```

---

#### 3.4 SessionHistory Component

**Create:** `user/vue/src/plugins/taro/components/SessionHistory.vue`
```vue
<template>
  <div class="history">
    <h2>Past Readings</h2>
    <div class="history-list">
      <div v-for="session in history" :key="session.id" class="history-item">
        <div class="session-date">
          {{ formatDate(session.createdAt) }}
        </div>
        <div class="session-cards">
          <span v-for="card in session.cards" :key="card.id" class="card-badge">
            {{ card.name }}
          </span>
        </div>
        <button @click="viewSession(session.id)">View</button>
      </div>
    </div>
  </div>
</template>
```

---

#### 3.5 Additional Components

**QuestionInput.vue** - Input for follow-up questions with type selector
**DailyLimitModal.vue** - Modal showing daily limit status and usage
**ExpiryWarning.vue** - 3-minute warning before session expires
**SessionInfo.vue** - Display session metadata (tokens used, follow-ups remaining)

---

#### 3.6 Router Configuration

**Update:** `user/vue/src/router/index.ts`
```typescript
{
  path: '/taro',
  name: 'Taro',
  component: () => import('@/plugins/taro/views/Taro.vue'),
  meta: { requiresAuth: true }
}
```

---

#### 3.7 Navigation Integration

**Update:** `user/vue/src/App.vue`
```vue
<nav>
  <!-- Add to menu -->
  <router-link to="/taro" class="nav-item">
    <i class="icon-tarot"></i> Taro Readings
  </router-link>
</nav>
```

---

### Phase 4: Testing & Verification

#### 4.1 Integration Tests

**Test:** `src/plugins/taro/tests/integration/test_taro_end_to_end.py`
```python
def test_full_session_flow():
    # Create user
    # Create session (should work)
    # Get session with cards
    # Add follow-up question
    # Verify token deduction
    # Verify daily limit tracking

def test_daily_limit_enforcement():
    # Create user with Basic plan (1/day limit)
    # Create first session (should work)
    # Try create second session (should fail)
    # Verify proper error message

def test_session_expiry():
    # Create session
    # Wait for expiry
    # Try to add follow-up (should fail with expired message)
```

---

#### 4.2 E2E Tests

**Test:** `user/vue/tests/e2e/taro.spec.ts`
```typescript
test('User can create and view Taro session', async ({ page }) => {
  // Navigate to Taro
  // Click "Start Reading"
  // See 3 cards displayed
  // See session expires in 30 minutes
  // Ask follow-up question
  // See response appear
})

test('Daily limit prevents new sessions', async ({ page }) => {
  // Create user with Basic plan
  // Create session (works)
  // Try create second session (blocked with message)
})
```

---

## Implementation Order

Follow this sequence to respect dependencies and TDD principles:

### Phase 1: Backend Models (TDD)
1. Write Arcana model tests → Implement model → Create migration
2. Write TaroSession model tests → Implement model → Create migration
3. Write TaroCardDraw model tests → Implement model → Create migration
4. Write Repository tests → Implement repositories
5. Create arcana population script (`src/plugins/taro/bin/populate_arcanas.py`)

### Phase 2: Backend Services (TDD)
6. Write TaroSessionService tests → Implement service
7. Write ArcanaInterpretationService tests → Implement service
8. Define Events (TaroSessionCreatedEvent, TaroFollowUpRequestedEvent)
9. Write Event Handler tests → Implement handlers
10. Write Backend route tests → Implement routes

### Phase 3: Frontend
11. Write Taro store tests → Implement Pinia store
12. Implement Taro.vue dashboard view
13. Implement CardDisplay component
14. Implement SessionHistory component
15. Implement QuestionInput component
16. Implement DailyLimitModal component
17. Implement ExpiryWarning component
18. Update Router configuration
19. Add Taro to navigation menu

### Phase 4: Testing & QA
20. Write and run integration tests
21. Write and run E2E tests
22. Manual testing in staging environment
23. Performance testing with token consumption
24. User acceptance testing

---

## Testing Strategy (TDD)

### Unit Tests
- Models: Field validation, relationships, status transitions
- Repositories: CRUD operations, queries, filtering
- Services: Business logic, token calculations, daily limits
- Stores: State mutations, async actions, error handling
- Components: Rendering, user interactions, computed properties

### Integration Tests
- Full session flow (create → interpret → follow-up → expire)
- Daily limit enforcement across multiple users
- Token consumption tracking and balance updates
- Event propagation and handler execution
- Database transactions and rollbacks

### E2E Tests
- User creates session and sees cards
- User asks follow-up question
- Daily limit blocks new sessions
- Session expiry warning appears
- Historical sessions can be viewed

### Validation
- `./bin/pre-commit-check.sh --full` passes all 3 parts
- `pytest src/plugins/taro/tests/` passes with 95%+ coverage
- `npm run test` passes in frontend
- No TypeScript errors
- No linting errors

---

## Directory Structure

```
vbwd-backend/src/plugins/taro/
├── __init__.py
├── models/
│   ├── __init__.py
│   ├── arcana.py
│   ├── taro_session.py
│   └── taro_card_draw.py
├── repositories/
│   ├── __init__.py
│   ├── arcana_repository.py
│   ├── taro_session_repository.py
│   └── taro_card_draw_repository.py
├── services/
│   ├── __init__.py
│   ├── taro_session_service.py
│   └── arcana_interpretation_service.py
├── events.py
├── handlers.py
├── routes.py
├── migrations/
│   └── taro_models_tables.py
├── bin/
│   └── populate_arcanas.py
└── tests/
    ├── __init__.py
    ├── unit/
    │   ├── __init__.py
    │   ├── models/
    │   │   ├── __init__.py
    │   │   ├── test_arcana.py
    │   │   ├── test_taro_session.py
    │   │   └── test_taro_card_draw.py
    │   ├── repositories/
    │   │   ├── __init__.py
    │   │   ├── test_arcana_repository.py
    │   │   ├── test_taro_session_repository.py
    │   │   └── test_taro_card_draw_repository.py
    │   ├── services/
    │   │   ├── __init__.py
    │   │   ├── test_taro_session_service.py
    │   │   └── test_arcana_interpretation_service.py
    │   ├── handlers/
    │   │   ├── __init__.py
    │   │   └── test_taro_event_handlers.py
    │   └── routes/
    │       ├── __init__.py
    │       └── test_taro_routes.py
    └── integration/
        ├── __init__.py
        └── test_taro_end_to_end.py

vbwd-frontend/user/vue/
├── src/plugins/taro/
│   ├── stores/
│   │   └── taro.ts
│   ├── views/
│   │   └── Taro.vue
│   ├── components/
│   │   ├── CardDisplay.vue
│   │   ├── SessionHistory.vue
│   │   ├── QuestionInput.vue
│   │   ├── DailyLimitModal.vue
│   │   ├── ExpiryWarning.vue
│   │   └── SessionInfo.vue
│   └── assets/
│       └── tarot-cards/  # Card images
└── tests/
    ├── unit/
    │   └── stores/test_taro.ts
    └── e2e/
        └── taro.spec.ts
```

---

## Success Criteria

### Phase 1 Complete
- ✅ All 3 models implemented with tests
- ✅ All 3 repositories working with tests
- ✅ Database migrations created and applied
- ✅ 78 Arcana cards populated in database
- ✅ Model-table consistency verified

### Phase 2 Complete
- ✅ TaroSessionService fully implemented
- ✅ ArcanaInterpretationService integrated with LLM
- ✅ Events defined and handlers implemented
- ✅ Backend routes working and tested
- ✅ Token consumption tracked correctly
- ✅ Daily limits enforced by tarif plan
- ✅ 95%+ test coverage for backend

### Phase 3 Complete
- ✅ Pinia store created with full state management
- ✅ All Vue components implemented and styled
- ✅ 3-card spread displays correctly
- ✅ Follow-up questions work with type selection
- ✅ Session history shows past readings
- ✅ Daily limit modal shows accurate counts
- ✅ Session expiry warning appears at 3 minutes
- ✅ No TypeScript errors

### Phase 4 Complete
- ✅ Integration tests pass (end-to-end flows)
- ✅ E2E tests pass (user interactions)
- ✅ Manual testing completed
- ✅ Performance acceptable with token calculations
- ✅ `./bin/pre-commit-check.sh --full` passes all parts

---

## Known Dependencies

- **Backend:** UserService, SubscriptionService, TokenService, EventDispatcher
- **Frontend:** Pinia (state), Vue Router (navigation), API client for requests
- **Database:** PostgreSQL with Alembic migrations
- **LLM:** Separate configuration instance (not shared with Chat plugin)
- **Token System:** Existing UserTokenBalance and TokenTransaction tables

---

## Notes

- Tarot deck has 78 cards: 22 Major + 14×4 Minor Arcana
- Cards drawn are random with seeded randomness for reproducibility in testing
- Sessions expire after 30 minutes, with warning at 3-minute mark
- Follow-up questions share the same session (not new sessions)
- Add-ons control follow-up modes (same cards vs additional vs new spread)
- Daily limits are per tarif plan (Basic 1, Star 3, Guru 12)
- LLM interpretations are unique per draw (not cached to avoid repetition)
- Token consumption is: fixed per session + variable based on LLM response

---

## Rollback Plan

If breaking issues occur:

1. Stop affected services
2. Downgrade database migrations:
   ```bash
   docker compose exec api alembic downgrade -1
   ```
3. Revert code changes
4. Re-run migrations and tests
5. All changes reversible because migrations have `downgrade()` functions

---

## Files to Create

### Backend Plugin Structure
- [ ] `src/plugins/taro/__init__.py`

### Backend Models & Migrations
- [ ] `src/plugins/taro/models/__init__.py`
- [ ] `src/plugins/taro/models/arcana.py`
- [ ] `src/plugins/taro/models/taro_session.py`
- [ ] `src/plugins/taro/models/taro_card_draw.py`
- [ ] `alembic/versions/YYYYMMDD_create_taro_tables.py`

### Backend Repositories
- [ ] `src/plugins/taro/repositories/__init__.py`
- [ ] `src/plugins/taro/repositories/arcana_repository.py`
- [ ] `src/plugins/taro/repositories/taro_session_repository.py`
- [ ] `src/plugins/taro/repositories/taro_card_draw_repository.py`

### Backend Services & Events
- [ ] `src/plugins/taro/services/__init__.py`
- [ ] `src/plugins/taro/services/taro_session_service.py`
- [ ] `src/plugins/taro/services/arcana_interpretation_service.py`
- [ ] `src/plugins/taro/events.py`
- [ ] `src/plugins/taro/handlers.py`
- [ ] `src/plugins/taro/routes.py`
- [ ] `src/plugins/taro/bin/populate_arcanas.py`

### Backend Tests (Plugin-Internal)
- [ ] `src/plugins/taro/tests/__init__.py`
- [ ] `src/plugins/taro/tests/unit/__init__.py`
- [ ] `src/plugins/taro/tests/unit/models/__init__.py`
- [ ] `src/plugins/taro/tests/unit/models/test_arcana.py`
- [ ] `src/plugins/taro/tests/unit/models/test_taro_session.py`
- [ ] `src/plugins/taro/tests/unit/models/test_taro_card_draw.py`
- [ ] `src/plugins/taro/tests/unit/repositories/__init__.py`
- [ ] `src/plugins/taro/tests/unit/repositories/test_arcana_repository.py`
- [ ] `src/plugins/taro/tests/unit/repositories/test_taro_session_repository.py`
- [ ] `src/plugins/taro/tests/unit/repositories/test_taro_card_draw_repository.py`
- [ ] `src/plugins/taro/tests/unit/services/__init__.py`
- [ ] `src/plugins/taro/tests/unit/services/test_taro_session_service.py`
- [ ] `src/plugins/taro/tests/unit/services/test_arcana_interpretation_service.py`
- [ ] `src/plugins/taro/tests/unit/handlers/__init__.py`
- [ ] `src/plugins/taro/tests/unit/handlers/test_taro_event_handlers.py`
- [ ] `src/plugins/taro/tests/unit/routes/__init__.py`
- [ ] `src/plugins/taro/tests/unit/routes/test_taro_routes.py`
- [ ] `src/plugins/taro/tests/integration/__init__.py`
- [ ] `src/plugins/taro/tests/integration/test_taro_end_to_end.py`

### Frontend
- [ ] `user/vue/src/plugins/taro/__init__.ts`
- [ ] `user/vue/src/plugins/taro/stores/taro.ts`
- [ ] `user/vue/src/plugins/taro/views/Taro.vue`
- [ ] `user/vue/src/plugins/taro/components/CardDisplay.vue`
- [ ] `user/vue/src/plugins/taro/components/SessionHistory.vue`
- [ ] `user/vue/src/plugins/taro/components/QuestionInput.vue`
- [ ] `user/vue/src/plugins/taro/components/DailyLimitModal.vue`
- [ ] `user/vue/src/plugins/taro/components/ExpiryWarning.vue`
- [ ] `user/vue/src/plugins/taro/components/SessionInfo.vue`
- [ ] `user/vue/tests/unit/stores/test_taro.ts`
- [ ] `user/vue/tests/e2e/taro.spec.ts`

---

## Estimated Effort

| Task | Estimate |
|------|----------|
| Models + Migrations + Tests | 2-3 hours |
| Repositories + Tests | 1-2 hours |
| TaroSessionService + Tests | 2-3 hours |
| ArcanaInterpretationService + Tests | 1-2 hours |
| Events & Handlers + Tests | 1 hour |
| Routes + Tests | 1-2 hours |
| Arcana Population Script | 30 mins |
| Frontend Store + Tests | 1-2 hours |
| Frontend Components (6 components) | 2-3 hours |
| Integration & E2E Tests | 1-2 hours |
| Manual Testing & QA | 1 hour |
| **Total** | **16-24 hours** |

---

**Sprint Lead:** Plugin Development
**Created:** 2026-02-15
**Target Start:** After Phase 1 of missing tables sprint (if dependent on token system)
**Dependencies:** UserTokenBalance tables must exist (from 01-missing-tables.md)

