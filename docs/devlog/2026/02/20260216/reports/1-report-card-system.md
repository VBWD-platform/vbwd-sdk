# Report: Tarot Card System Architecture

## Overview
The Taro (Tarot) plugin implements a complete card reading system with AI-powered interpretations. This document describes how cards flow through the system, from database to frontend display, including the randomization and LLM interpretation mechanisms.

---

## 1. Card Data Architecture

### 1.1 Database Structure

**Arcana Table** - Contains all 78 tarot cards:
```
Column              | Type        | Description
--------------------|-------------|------------------------------------------
id                  | UUID        | Unique card identifier
name                | String(255) | Card name (e.g., "The Fool", "Ace of Cups")
number              | Integer     | Major Arcana: 0-21, Minor Arcana: NULL
suit                | String      | Major: NULL, Minor: CUPS/WANDS/SWORDS/PENTACLES
rank                | String      | Major: NULL, Minor: ACE/TWO/THREE/.../KING
arcana_type         | String      | MAJOR_ARCANA or suit name
upright_meaning     | Text        | Interpretation for upright orientation
reversed_meaning    | Text        | Interpretation for reversed orientation
image_url           | String      | SVG asset URL (/api/v1/taro/assets/arcana/...)
config              | JSONB       | Additional card metadata
created_at          | DateTime    | Record creation timestamp
updated_at          | DateTime    | Last update timestamp
```

**Card Population** (22 Major + 56 Minor = 78 total):
- Major Arcana: "The Fool" (0) → "The World" (21)
- Minor Arcana: 4 suits × 14 ranks each
  - Cups: Ace, Two, Three, Four, Five, Six, Seven, Eight, Nine, Ten, Page, Knight, Queen, King
  - Wands: Same ranks
  - Swords: Same ranks
  - Pentacles: Same ranks

### 1.2 SVG Asset Structure

Cards are stored as SVG files in the plugin directory:
```
/vbwd-backend/plugins/taro/assets/arcana/
├── major/
│   ├── 00-the-fool.svg
│   ├── 01-the-magician.svg
│   └── ... (22 files)
└── minor/
    ├── cups/
    │   ├── ace-of-cups.svg
    │   └── ... (14 files)
    ├── wands/ (14 files)
    ├── swords/ (14 files)
    └── pentacles/ (14 files)
```

Image URLs follow pattern:
- Major: `/api/v1/taro/assets/arcana/major/{number:02d}-{name}.svg`
- Minor: `/api/v1/taro/assets/arcana/minor/{suit}/{rank}-of-{suit}.svg`

---

## 2. Card Flow to Frontend

### 2.1 Session Creation Flow

```
User Request (Frontend)
    ↓
POST /api/v1/taro/session
    ↓
[Backend Authentication Check]
    ├─ Verify JWT token
    ├─ Check token balance (10 tokens required)
    └─ Check daily session limit (default 3/day)
    ↓
[Generate 3-Card Spread]
    ├─ Randomize 3 cards from 78 total
    ├─ Random orientation: UPRIGHT or REVERSED
    └─ Create TaroCardDraw records
    ↓
[Return Session Response] HTTP 201
```

### 2.2 Session Response Structure

```json
{
  "success": true,
  "session": {
    "session_id": "uuid",
    "status": "ACTIVE",
    "expires_at": "2026-02-16T07:51:21.123Z",
    "follow_up_count": 0,
    "max_follow_ups": 3,
    "cards": [
      {
        "card_id": "uuid",
        "position": "PAST|PRESENT|FUTURE",
        "orientation": "UPRIGHT|REVERSED",
        "arcana_id": "uuid",
        "interpretation": null  // Loaded async by LLM
      },
      // ... 2 more cards
    ],
    "tokens_consumed": 10
  }
}
```

### 2.3 Data Fetching on Frontend

The Pinia store (`useTaroStore`) manages:

1. **Session Creation**:
   - Calls `POST /api/v1/taro/session`
   - Stores `currentSession` with basic card data
   - Card details loaded on-demand when user opens card modal

2. **Card Details Fetching**:
   - When user clicks on a card, modal is opened
   - `CardDetailModal.vue` searches for card in `currentSession.cards`
   - Uses `arcana_id` to match with Arcana table
   - **Current Issue**: Not fetching full Arcana details (name, SVG URL)

3. **Future Optimization**:
   - Could pre-fetch all Arcana data at plugin load time
   - Could cache Arcana data in Pinia store
   - Currently doing single-card lookup when modal opens

---

## 3. Card Randomization System

### 3.1 Randomizer Implementation

**Location**: `/vbwd-backend/plugins/taro/src/services/taro_session_service.py`

```python
def _draw_cards(self, count: int = 3) -> List[Arcana]:
    """Draw random cards from deck of 78."""
    all_arcana = self.arcana_repo.get_all()  # Fetch all 78 cards

    # Random selection without replacement
    selected = random.sample(all_arcana, count)

    return selected
```

### 3.2 Randomization Properties

- **Method**: Python's `random.sample()` - ensures no duplicates
- **Uniformity**: Each card has equal probability (1/78 for first, 1/77 for second, etc.)
- **Orientation**: Random choice between UPRIGHT (probability: 50%) and REVERSED (probability: 50%)
  ```python
  orientation = random.choice(['UPRIGHT', 'REVERSED'])
  ```
- **Position**: Assigned sequentially as PAST, PRESENT, FUTURE (not randomized)

### 3.3 Card Spread Types

**Current Implementation**: 3-card spread (Past, Present, Future)

**For Follow-ups**:
- `SAME_CARDS`: Reinterpret existing cards with different question
- `ADDITIONAL`: Draw 1 additional card
- `NEW_SPREAD`: Draw new 3-card spread

---

## 4. LLM Integration for Interpretations

### 4.1 Interpretation Generation Flow

```
Session Created
    ↓
[Event: TaroSessionRequestedEvent]
    ↓
[Event Listener: TaroSessionCreatedListener]
    ├─ Wait for event emission
    └─ Trigger async interpretation generation
    ↓
[For Each Card in Spread]
    ├─ Get card name and position from Arcana table
    ├─ Determine orientation: UPRIGHT or REVERSED
    ├─ Fetch appropriate meaning from Arcana
    │   ├─ If UPRIGHT: use upright_meaning
    │   └─ If REVERSED: use reversed_meaning
    ├─ Build prompt for LLM with:
    │   ├─ Card name and traditional meaning
    │   ├─ Card position (Past/Present/Future)
    │   ├─ Orientation (affects interpretation tone)
    │   └─ User's original question (for context)
    ↓
[Call OpenAI API]
    ├─ Model: GPT-4 or GPT-3.5-turbo
    ├─ System prompt: Professional tarot reader persona
    ├─ User message: Formatted card + context
    └─ Generate: Personalized interpretation (200-300 words)
    ↓
[Store Interpretation]
    ├─ Update TaroCardDraw record
    ├─ Field: ai_interpretation
    ├─ Mark interpretation as GENERATED
    └─ Log token usage (cost tracking)
    ↓
[WebSocket Notification to Frontend]
    └─ Real-time update: Interpretation ready
```

### 4.2 Interpretation Caching

- **Current**: Interpreted on-demand when session created
- **Strategy**: Each card's interpretation is unique per session
  - Same card could appear in different sessions
  - Each would get unique interpretation based on question & position
- **Cost**: ~50-100 tokens per card × 3 cards = 150-300 tokens per session
- **Optimization Opportunity**: Cache generic interpretations, personalize with context injection

### 4.3 LLM Service Architecture

**Location**: `/vbwd-backend/plugins/taro/src/services/arcana_interpretation_service.py`

**Important**: Plugin-specific LLM services are kept in the plugin directory to maintain core backend agnosticism.

```python
class ArcanaInterpretationService:
    """Service for generating Tarot card interpretations via LLM."""

    def __init__(
        self,
        llm_client,              # LLM client (OpenAI, Anthropic, etc.)
        card_draw_repo,          # Repository for card data
        model_name: str = "gpt-4",
        temperature: float = 0.8,
        max_tokens: int = 200,
    ):
        """Initialize interpretation service with configurable LLM."""
        self.llm_client = llm_client
        self.card_draw_repo = card_draw_repo
        self.model_name = model_name
        self.temperature = temperature
        self.max_tokens = max_tokens

    def generate_interpretation(
        self,
        arcana: Arcana,
        position: CardPosition,  # PAST, PRESENT, FUTURE
        orientation: CardOrientation  # UPRIGHT, REVERSED
    ) -> Tuple[str, int]:
        """Generate unique interpretation for a card in context.

        Returns:
            Tuple of (interpretation: str, tokens_used: int)
        """
        # Implementation uses LLM client to generate interpretation
        # based on card name, position, orientation, and meanings
```

**Architecture Principles**:
- ✅ Plugin-specific services: Kept in `/plugins/taro/src/services/`
- ✅ Core services: Only in `/src/services/` (generic, plugin-agnostic)
- ✅ LLM integration: Each plugin manages its own LLM interactions
- ✅ Dependency injection: LLM client passed as constructor parameter
- ✅ Abstraction: Plugin doesn't assume specific LLM provider

**For Future Plugins** (Both Backend AND Frontend):

Every plugin must follow the complete app-like structure:

```
Backend Plugin: /vbwd-backend/plugins/{plugin-name}/
├── src/
│   ├── routes.py              - API endpoints
│   ├── services/              - Business logic
│   ├── repositories/          - Data access
│   ├── models/                - Domain models
│   ├── events.py              - Domain events
│   └── bin/                   - Scripts (migrations, population, etc.)
├── assets/                    - Static files (optional)
├── tests/
│   ├── unit/
│   └── integration/
├── alembic/                   - Database migrations
│   └── versions/
├── locales/
│   ├── en.json
│   └── de.json
├── config.json                - Plugin settings
└── admin-config.json          - Admin UI configuration

Frontend Plugin: /vbwd-frontend/{user|admin}/plugins/{plugin-name}/
├── src/
│   ├── components/            - Vue components
│   ├── stores/                - Pinia stores
│   ├── services/              - Business logic
│   ├── utils/                 - Utilities
│   ├── routes.ts              - Routes definition
│   ├── index.ts               - Entry point
│   └── types.ts               - TypeScript types
├── assets/                    - Images, SVGs, etc.
├── tests/
│   ├── unit/
│   └── e2e/
├── locales/
│   ├── en.json
│   └── de.json
├── config.json                - Plugin settings
└── admin-config.json          - Admin UI configuration
```

**This structure ensures**:
- ✅ Core remains completely agnostic
- ✅ Plugins are independently deployable
- ✅ Consistent patterns across all plugins
- ✅ Each plugin is self-documenting
- ✅ Shared utilities come from core only
- ✅ No plugin-specific code in core

### 4.4 Token Cost Tracking

Each interpretation consumes tokens:
- **Input tokens**: Card name + meaning + position + question
- **Output tokens**: Generated interpretation (100-200 tokens typically)
- **Total per card**: ~150-250 tokens
- **Total per session**: ~450-750 tokens (3 cards)

Tracked in:
- User token balance (deducted from account)
- Invoice/transaction history
- Session metadata: `tokens_consumed`

---

## 5. Current Card Display Issues

### 5.1 Problem

Card modal shows:
- ✅ Position (PAST/PRESENT/FUTURE)
- ✅ Orientation (UPRIGHT/REVERSED)
- ✅ Card ID & Arcana ID
- ❌ Card image/SVG
- ❌ Card name
- ❌ Card interpretation

### 5.2 Root Cause

The `TaroCardDraw` record (what's sent from backend) contains:
- `card_id`, `position`, `orientation`, `arcana_id`, `ai_interpretation`

But is missing:
- `arcana_name` - Card name like "The Fool" or "Ace of Cups"
- `image_url` - SVG asset URL
- `upright_meaning` / `reversed_meaning` - Traditional meanings

### 5.3 Solution Required

**Option A: Include Arcana Details in Card Response**
- Modify session API to include Arcana object in card data
- Include: name, image_url, suit, rank, number
- Pros: Single API call, all data available
- Cons: Larger response payload

**Option B: Fetch Arcana Separately**
- Modal loads from `arcana_id` when opened
- Call GET `/api/v1/arcana/{arcana_id}`
- Pros: Lazy loading, smaller session response
- Cons: Additional API call per card

**Option C: Pre-fetch All Arcana at Plugin Load**
- Load all 78 Arcana at plugin initialization
- Store in Pinia with index by ID
- Instant lookup without extra API calls
- Pros: Best performance, single bulk call
- Cons: More memory usage

### 5.4 Implementation Status

**Recommended**: Option C (pre-fetch all Arcana at plugin load)
- One-time load of 78 cards
- ~100KB max payload
- Instant lookups after that
- Improves UX significantly

---

## 6. Architecture Overview

### 6.1 Unified Plugin Architecture (Backend + Frontend)

**Core Principle**: Both backend and frontend maintain complete separation between core (agnostic) and plugins (self-contained).

#### Backend Structure

```
CORE BACKEND (/src/)
├── routes/              - API endpoints (generic, agnostic)
├── services/            - Business logic (shared, plugin-agnostic)
├── repositories/        - Data access (generic)
├── models/              - Domain models (shared)
├── extensions.py        - Database, cache, etc.
└── ... (other core utilities)

PLUGIN: TARO (/plugins/taro/)
├── src/                 - Plugin source code
│   ├── routes.py        - Taro-specific API endpoints
│   ├── services/        - Plugin business logic
│   │   ├── taro_session_service.py
│   │   └── arcana_interpretation_service.py  ← LLM (plugin-specific!)
│   ├── repositories/    - Plugin data access
│   ├── models/          - Plugin domain models
│   ├── events.py        - Plugin domain events
│   └── bin/
│       └── populate_arcanas.py
├── assets/              - SVG card images (optional but recommended)
├── tests/               - Plugin tests (unit, integration)
├── alembic/             - Database migrations (plugin-specific tables)
├── locales/             - Translations (en.json, de.json, etc.)
├── config.json          - Plugin configuration
└── admin-config.json    - Admin panel configuration
```

#### Frontend Structure

```
CORE FRONTEND (/core/src/)
├── components/          - Shared Vue components (agnostic)
├── stores/              - Shared Pinia stores (agnostic)
├── plugins/             - Plugin registry & system (agnostic)
├── utils/               - Shared utilities
└── ... (other core utilities)

PLUGIN: TARO (/user/plugins/taro/ or /admin/plugins/taro/)
├── src/                 - Plugin source code
│   ├── components/      - Plugin Vue components
│   ├── stores/          - Plugin Pinia stores
│   ├── services/        - Plugin business logic
│   ├── utils/           - Plugin utilities
│   ├── routes.ts        - Plugin routes/pages
│   ├── index.ts         - Plugin entry point
│   └── types.ts         - Plugin TypeScript types
├── assets/              - Plugin images, SVGs, etc.
├── tests/               - Plugin tests (unit, E2E)
├── locales/             - Translations (en.json, de.json, etc.)
├── config.json          - Plugin configuration
└── admin-config.json    - Admin panel configuration
```

**Key Principles**:
- ✅ Core is **completely agnostic** to plugins (both backend and frontend)
- ✅ Each plugin is **self-contained** and independently deployable
- ✅ Plugin-specific code never touches core directories
- ✅ LLM, API calls, business logic all stay in plugin
- ✅ Both backend and frontend follow **identical structural patterns**
- ✅ Migrations, locales, config files are all plugin-local

### 6.2 Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    DATABASE (PostgreSQL)                     │
├─────────────────────────────────────────────────────────────┤
│  Arcana (78 cards)  │  TaroSession  │  TaroCardDraw         │
│  ─ name             │  ─ id         │  ─ id                 │
│  ─ suit             │  ─ user_id    │  ─ card_id            │
│  ─ rank             │  ─ status     │  ─ position           │
│  ─ image_url        │  ─ created_at │  ─ orientation        │
│  ─ upright_meaning  │               │  ─ ai_interpretation  │
│  ─ reversed_meaning │               │  ─ generated_at       │
└────────────────────┬────────────────┬────────────────────────┘
                     │                │
        ┌────────────▼────────────────▼──────────────┐
        │   CORE Backend API (Flask/Python)          │
        ├───────────────────────────────────────────┤
        │ Generic routes, services, repositories     │
        └────────────┬───────────────────────────────┘
                     │
        ┌────────────▼──────────────────────────────────────┐
        │    TARO PLUGIN (Autonomous, Self-Contained)       │
        ├──────────────────────────────────────────────────┤
        │ Routes:                                          │
        │  POST /api/v1/taro/session                       │
        │  POST /api/v1/taro/session/{id}/follow-up        │
        │  GET /api/v1/taro/limits                         │
        │  GET /api/v1/taro/history                        │
        │  GET /api/v1/taro/assets/arcana/...              │
        │                                                  │
        │ Services:                                        │
        │  - TaroSessionService (session logic)            │
        │  - ArcanaInterpretationService (LLM)             │
        │  - TaroCardDrawRepository (data access)          │
        │  - ArcanaRepository (card data)                  │
        │                                                  │
        │ External: OpenAI API (for interpretations)       │
        └────────────┬───────────────────────────────────┬─┘
                     │                                   │
        ┌────────────▼──────────────────────────────────▼──────────┐
        │        Frontend (Vue.js + Pinia)                         │
        ├─────────────────────────────────────────────────────────┤
        │ Plugin Store: useTaroStore                               │
        │  - currentSession (TaroSession + TaroCardDraw + Arcana) │
        │  - sessionHistory                                        │
        │  - arcanaCache (future: all 78 cards)                   │
        │                                                          │
        │ Components:                                              │
        │  - Taro.vue (main dashboard)                            │
        │  - SessionHistory.vue                                   │
        │  - CardDisplay.vue                                      │
        │  - CardDetailModal.vue (displays card with SVG)        │
        └──────────────────────────────────────────────────────────┘
```

---

## 7. Recommendations

### 7.1 Immediate (Today)

1. ✅ Add Arcana details to card response in session creation
2. ✅ Fix CardDetailModal to display card image
3. ✅ Fetch interpretation from backend when modal loads
4. 🔄 Test full flow with actual LLM generations

### 7.2 Short-term (This Week)

1. Pre-fetch all Arcana data at plugin load time
2. Implement proper interpretation caching strategy
3. Add card meanings display in modal
4. Test with multiple users and concurrent sessions

### 7.3 Long-term (Future)

1. Implement advanced spread types (Celtic Cross, etc.)
2. Add interpretation history/journal
3. Machine learning for personalized interpretations
4. Community interpretation sharing
5. Card deck customization

---

## 8. Token Usage Summary

| Operation | Tokens | Notes |
|-----------|--------|-------|
| Session creation | 10 | Base cost |
| LLM interpretation (1 card) | 150-250 | Variable based on LLM response |
| Follow-up question | 15 | Base cost |
| LLM follow-up interpretation | 200-300 | Usually longer responses |
| **Total per session** | **450-800** | With 3 cards + interpretation |

---

## 9. Known Issues & Blockers

| Issue | Status | Priority | Notes |
|-------|--------|----------|-------|
| Card SVG not displaying | 🔴 Blocker | P0 | Modal missing image_url |
| Card name not shown | 🔴 Blocker | P0 | Modal shows only position |
| Interpretation not fetched | 🔴 Blocker | P0 | Needs LLM service call |
| Props undefined error | ✅ Fixed | - | CardDetailModal component |
| Missing locales | ✅ Fixed | - | All translation keys added |
| Follow-ups maxed out | ✅ Fixed | - | Response fields added |

---

**Report Generated**: February 16, 2026, 08:00 UTC
**Author**: Claude Code
**Status**: In Progress - Waiting on card display fixes
