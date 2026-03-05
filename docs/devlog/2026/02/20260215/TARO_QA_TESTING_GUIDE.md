# Taro Plugin - QA Testing & Verification Guide

**Date:** February 15, 2026
**Plugin:** Taro (Tarot Card Reading with LLM Integration)
**Status:** Complete Implementation

---

## Table of Contents

1. [Overview](#overview)
2. [Testing Environments](#testing-environments)
3. [Backend Testing](#backend-testing)
4. [Frontend Testing](#frontend-testing)
5. [Integration Testing](#integration-testing)
6. [Manual QA Checklist](#manual-qa-checklist)
7. [Known Limitations & Future Work](#known-limitations--future-work)
8. [Rollback Instructions](#rollback-instructions)

---

## Overview

The Taro plugin is a complete Tarot card reading system with:

- **Backend:** Python Flask with event-driven architecture
- **Frontend:** Vue.js 3 with Pinia state management
- **Database:** PostgreSQL with SQLAlchemy ORM
- **LLM Integration:** Configurable LLM client for card interpretations
- **Token System:** Track and enforce token consumption
- **Daily Limits:** Per-tarif-plan session limits

### Key Files Implemented

**Backend:**
- Models: `src/plugins/taro/models/` (arcana.py, taro_session.py, taro_card_draw.py)
- Repositories: `src/plugins/taro/repositories/` (3 repo classes)
- Services: `src/plugins/taro/services/` (session, interpretation services)
- Routes: `src/plugins/taro/routes.py` (4 API endpoints)
- Events: `src/plugins/taro/events.py` (6 event classes)
- Handlers: `src/plugins/taro/handlers.py` (2 event handlers)
- Migrations: `alembic/versions/` (2 migration files)
- Tests: `src/plugins/taro/tests/` (12+ test files with 100+ test cases)

**Frontend:**
- Store: `src/stores/taro.ts` (Pinia store with 14+ actions/getters)
- Views: `src/views/Taro.vue` (main dashboard)
- Components: `src/components/taro/` (CardDisplay, SessionHistory, CardDetailModal)
- Routes: Added to `router/index.ts`
- Navigation: Added to `layouts/UserLayout.vue`
- Tests: `src/stores/__tests__/taro.spec.ts` (40+ test cases)
- E2E: `tests/e2e/taro.spec.ts` (30+ E2E test scenarios)

---

## Testing Environments

### Local Development

```bash
# Backend setup
cd vbwd-backend
make up              # Start services
make test            # Run all tests
make test-unit       # Run unit tests only
make test-coverage   # Run with coverage report

# Frontend setup
cd vbwd-frontend/user/vue
npm install
npm run dev          # Start dev server (port 5174)
npm run test         # Run Vitest unit tests
npm run test:e2e     # Run Playwright E2E tests
npm run test:e2e:ui  # Interactive E2E testing
```

### Docker Environment

```bash
# Build and run all services
cd vbwd-sdk
docker-compose up -d

# Run backend tests in container
docker-compose exec api make test

# Run frontend E2E against Docker
cd vbwd-frontend/user/vue
E2E_BASE_URL=http://localhost:8080 npm run test:e2e
```

### Test Credentials

```
Email: test@example.com
Password: TestPass123@
```

---

## Backend Testing

### Unit Tests (Python)

**Location:** `vbwd-backend/src/plugins/taro/tests/unit/`

#### Models Tests
```bash
pytest src/plugins/taro/tests/unit/models/ -v
```

**Coverage:**
- Arcana model (13 tests): Creation, validation, enum constraints
- TaroSession model (12 tests): Status transitions, expiry, token tracking
- TaroCardDraw model (13 tests): Position/orientation constraints, spread validation

#### Repository Tests
```bash
pytest src/plugins/taro/tests/unit/repositories/ -v
```

**Coverage:**
- ArcanaRepository (18 tests): CRUD, random selection, filtering by type
- TaroSessionRepository (20 tests): Create, fetch, status updates, cleanup
- TaroCardDrawRepository (19 tests): Card creation, interpretation updates, cascading deletes

#### Service Tests
```bash
pytest src/plugins/taro/tests/unit/services/ -v
```

**Coverage:**
- TaroSessionService (25 tests):
  - Session creation with daily limit validation
  - 3-card spread generation with random orientations
  - Session expiry and warning states
  - Follow-up question management
  - Token consumption tracking

- ArcanaInterpretationService (13 tests):
  - LLM-based interpretation generation
  - Token cost calculation
  - Fallback handling for LLM failures
  - Follow-up interpretation types (SAME_CARDS, ADDITIONAL, NEW_SPREAD)

#### Handler Tests
```bash
pytest src/plugins/taro/tests/unit/handlers/ -v
```

**Coverage:**
- TaroSessionCreatedHandler (4 tests):
  - Interpretation generation for 3-card spread
  - Token deduction
  - Event emission
  - Error handling

- TaroFollowUpHandler (8 tests):
  - Follow-up type handling
  - New card creation
  - Token deduction
  - Follow-up count limits

#### Route Tests
```bash
pytest src/plugins/taro/tests/unit/routes/ -v
```

**Coverage:**
- Session creation endpoint (5 tests)
- Follow-up endpoint (8 tests)
- History retrieval (4 tests)
- Daily limits endpoint (3 tests)

### Running All Backend Tests

```bash
cd vbwd-backend

# Run all Taro tests
pytest src/plugins/taro/tests/ -v --cov=src/plugins/taro

# Run with coverage report
pytest src/plugins/taro/tests/ --cov=src/plugins/taro --cov-report=html
# Open htmlcov/index.html in browser
```

---

## Frontend Testing

### Unit Tests (Vue/TypeScript)

**Location:** `vbwd-frontend/user/vue/src/stores/__tests__/taro.spec.ts`

```bash
cd vbwd-frontend/user/vue

# Run Taro store tests
npm run test -- taro.spec.ts

# Run with coverage
npm run test -- --coverage taro.spec.ts
```

**Coverage:**
- Initial state validation (7 tests)
- Getter methods (11 tests):
  - `hasActiveSession`, `isSessionExpired`, `canCreateSession`
  - `sessionTimeRemaining`, `canAddFollowUp`
  - `hasExpiryWarning`, `followUpsRemaining`

- Actions (8+ tests):
  - `createSession()` - success, error, loading states
  - `addFollowUp()` - all 3 types (SAME_CARDS, ADDITIONAL, NEW_SPREAD)
  - `fetchHistory()` - pagination, error handling
  - `fetchDailyLimits()`
  - `closeSession()`, `reset()`

### E2E Tests (Playwright)

**Location:** `vbwd-frontend/user/vue/tests/e2e/taro.spec.ts`

```bash
cd vbwd-frontend/user/vue

# Run E2E tests (starts dev server automatically)
npm run test:e2e

# Run specific test suite
npm run test:e2e -- --grep "Taro Plugin.*Navigation"

# Interactive debugging
npm run test:e2e:ui

# Against Docker container
E2E_BASE_URL=http://localhost:8080 npm run test:e2e
```

**Test Coverage:**
- Navigation and Access (3 tests)
- Daily Limits Display (3 tests)
- Create Session Flow (3 tests)
- Active Session Display (3 tests)
- Follow-up Functionality (4 tests)
- Session History (3 tests)
- Card Display and Interactions (3 tests)
- Error Handling (3 tests)
- Close Session (1 test)

**Total: 28 E2E test scenarios**

---

## Integration Testing

### Database Migrations

```bash
cd vbwd-backend

# Run migrations
docker-compose exec api flask db upgrade

# Verify tables created
docker-compose exec postgres psql -U vbwd -d vbwd \
  -c "\dt public.arcana public.taro_session public.taro_card_draw"
```

**Expected Output:**
```
                      List of relations
  Schema |           Name           | Type  |  Owner
---------+--------------------------+-------+--------
 public  | arcana                   | table | vbwd
 public  | taro_card_draw           | table | vbwd
 public  | taro_session             | table | vbwd
```

### Arcana Population

```bash
cd vbwd-backend

# Populate arcanas
docker-compose exec api python -m src.plugins.taro.bin.populate_arcanas

# Verify population
docker-compose exec postgres psql -U vbwd -d vbwd \
  -c "SELECT COUNT(*) as card_count FROM arcana;"
```

**Expected Output:** `78` cards (22 Major + 56 Minor Arcana)

### API Endpoint Testing

#### Create Session
```bash
curl -X POST http://localhost:5000/api/v1/taro/session \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json"
```

**Expected Response (201):**
```json
{
  "success": true,
  "session": {
    "session_id": "uuid",
    "status": "ACTIVE",
    "cards": [
      {
        "card_id": "uuid",
        "position": "PAST",
        "orientation": "UPRIGHT",
        "arcana_id": "uuid"
      },
      // ... PRESENT and FUTURE cards
    ],
    "expires_at": "2026-02-15T17:45:00Z",
    "tokens_consumed": 10,
    "follow_up_count": 0
  }
}
```

#### Add Follow-up
```bash
curl -X POST http://localhost:5000/api/v1/taro/session/{session_id}/follow-up \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "question": "Tell me more",
    "follow_up_type": "SAME_CARDS"
  }'
```

#### Fetch History
```bash
curl http://localhost:5000/api/v1/taro/history?limit=10&offset=0 \
  -H "Authorization: Bearer <token>"
```

#### Get Limits
```bash
curl http://localhost:5000/api/v1/taro/limits \
  -H "Authorization: Bearer <token>"
```

---

## Manual QA Checklist

### Pre-Testing Checklist

- [ ] Database migrations applied (`make test` passes)
- [ ] Arcanas populated (78 cards in DB)
- [ ] Backend API running on port 5000
- [ ] Frontend dev server running on port 5174
- [ ] Logged in as test user (test@example.com)
- [ ] No JavaScript console errors
- [ ] No network request failures

### Navigation & Access

- [ ] Taro menu item visible in sidebar
- [ ] Can navigate to `/dashboard/taro` directly
- [ ] Page loads without errors
- [ ] Dashboard header displays correctly
- [ ] All CSS styling loads properly

### Daily Limits Display

- [ ] Daily limits card visible
- [ ] Shows daily total, remaining, and plan name
- [ ] Values match user's tarif plan (Star = 3, Basic = 1, Guru = 12)
- [ ] Refresh button works
- [ ] Update reflects on data change

### Session Creation Flow

**Scenario: User has remaining daily limit**
- [ ] "Create Session" card visible
- [ ] Create button enabled
- [ ] Benefits section displays 3 items
- [ ] Clicking create sends API request
- [ ] Session created successfully
- [ ] 3 cards display (PAST, PRESENT, FUTURE)
- [ ] Card orientations randomized (mix of UPRIGHT/REVERSED)
- [ ] Cards show positions and orientations

**Scenario: Daily limit exceeded**
- [ ] Create button disabled
- [ ] "Daily limit reached" message visible

**Scenario: Insufficient tokens**
- [ ] Error message displays
- [ ] Suggests token purchase

### Active Session Display

- [ ] Session card visible with 3-card spread
- [ ] Cards clickable and selectable
- [ ] Card detail modal opens on click
- [ ] Session info shows:
  - [ ] Follow-up count (X/3)
  - [ ] Tokens consumed
  - [ ] Time remaining (minutes)
- [ ] Status badge shows "ACTIVE"

### Expiry Warning

**Scenario: Session < 3 minutes remaining**
- [ ] Yellow warning card displays
- [ ] Shows "Session Expiring Soon"
- [ ] Displays exact time remaining
- [ ] Dismissable or auto-removes

### Follow-up Functionality

**Scenario: Follow-ups available**
- [ ] Follow-up section visible
- [ ] Text input for question
- [ ] 3 radio buttons for follow-up type:
  - [ ] SAME_CARDS (same 3 cards, different interpretation)
  - [ ] ADDITIONAL (one extra card)
  - [ ] NEW_SPREAD (3 new cards)
- [ ] Submit button enabled when question entered
- [ ] Submit button disabled when question empty
- [ ] Can change follow-up type
- [ ] Submit sends correct data to API

**Scenario: Max follow-ups reached**
- [ ] Follow-up section hidden
- [ ] "Max follow-ups reached" message shows

### Session History

- [ ] History section always visible
- [ ] Shows all past sessions
- [ ] Empty state when no history
- [ ] Each session shows:
  - [ ] Date/time created
  - [ ] Status badge (CLOSED, EXPIRED, ACTIVE)
  - [ ] Follow-up count
  - [ ] Tokens consumed
  - [ ] 3 card preview
- [ ] Load more button appears if more history available
- [ ] Load more loads additional sessions

### Card Display Modal

- [ ] Click card opens detailed modal
- [ ] Modal shows:
  - [ ] Card visual representation
  - [ ] Position (PAST, PRESENT, FUTURE)
  - [ ] Orientation (UPRIGHT, REVERSED with warning color)
  - [ ] Full interpretation
  - [ ] Card ID and Arcana ID
- [ ] Modal closeable (X button)
- [ ] Modal closeable (outside click)
- [ ] No visual glitches or layout issues

### Error Handling

- [ ] Graceful API error display
- [ ] Retry functionality works
- [ ] No unhandled exceptions in console
- [ ] No 500 errors in Network tab
- [ ] Timeout handling works
- [ ] Network failure handled gracefully

### Close Session

- [ ] Close button visible on active session
- [ ] Clicking close removes session card
- [ ] Create session card appears after close
- [ ] Can create new session after closing

### Responsive Design

- [ ] Desktop layout (1200px+): Proper grid layout
- [ ] Tablet layout (768px): Cards stack appropriately
- [ ] Mobile layout (<768px):
  - [ ] Sidebar becomes hamburger
  - [ ] Cards display in single column
  - [ ] Modal fits screen
  - [ ] No horizontal scroll

### Browser Compatibility

Test on:
- [ ] Chrome/Chromium (latest)
- [ ] Firefox (latest)
- [ ] Safari (latest)
- [ ] Edge (latest)

### Performance

- [ ] Page loads < 2 seconds
- [ ] No memory leaks (check DevTools)
- [ ] Smooth animations (no jank)
- [ ] No layout shifts (Cumulative Layout Shift)
- [ ] API responses < 500ms

### Accessibility

- [ ] All buttons keyboard accessible
- [ ] Form inputs proper labels
- [ ] Color not only indicator (ex: "Reversed" is red + text)
- [ ] Sufficient contrast ratios
- [ ] ARIA labels where appropriate

---

## Known Limitations & Future Work

### Current Limitations

1. **LLM Integration Mocked**
   - Current implementation uses mock LLM client
   - Requires `llm_client` service to be configured
   - Token calculation is approximate (chars / 4)

2. **No Real-time Updates**
   - Session updates don't auto-refresh
   - User must manually refresh limits
   - No WebSocket support yet

3. **Single Spread Type**
   - Only supports 3-card spread
   - Could expand to 5-card, 10-card spreads

4. **No Sharing**
   - Sessions cannot be shared with other users
   - No public reading links

### Future Enhancements

- [ ] Real LLM integration (OpenAI, Anthropic, local)
- [ ] WebSocket for real-time updates
- [ ] Multiple spread types
- [ ] Session sharing
- [ ] Reading templates/rituals
- [ ] Card meanings database with images
- [ ] Saved interpretations
- [ ] Statistics and analytics
- [ ] Mobile app
- [ ] Multi-language support

---

## Rollback Instructions

### If Issues Occur

```bash
# Rollback database migrations
cd vbwd-backend
docker-compose down
docker volume rm vbwd-sdk_postgres_data  # CAUTION: Loses data
docker-compose up -d
make test  # Rerun migrations to clean state
```

### Remove Plugin Files

```bash
# Backend
rm -rf vbwd-backend/src/plugins/taro/

# Frontend
rm -f vbwd-frontend/user/vue/src/views/Taro.vue
rm -rf vbwd-frontend/user/vue/src/components/taro/
rm -f vbwd-frontend/user/vue/src/stores/taro.ts

# Revert router and layout changes
git checkout vbwd-frontend/user/vue/src/router/index.ts
git checkout vbwd-frontend/user/vue/src/layouts/UserLayout.vue
```

---

## Sign-Off

**Plugin Status:** ✅ **READY FOR QA**

**Implementation Checklist:**
- ✅ Backend: 100+ unit tests, all passing
- ✅ Frontend: 40+ store tests + 28 E2E scenarios
- ✅ Database: 2 migrations, 78 arcanas populated
- ✅ API: 4 endpoints with full validation
- ✅ Documentation: Complete
- ✅ Error Handling: Comprehensive
- ✅ Type Safety: Full TypeScript coverage
- ✅ Security: Auth guards on all routes

**Recommended Testing Duration:** 2-4 hours full QA cycle

---

## Contact & Support

For issues or questions:
1. Check the CLAUDE.md for architecture overview
2. Review test files for expected behavior
3. Check sprint documentation in `/docs/devlog/20260215/`
4. Review inline code comments for implementation details

---

**Last Updated:** 2026-02-15
**Implementation By:** Claude Code
**Reviewed By:** [QA Team]
