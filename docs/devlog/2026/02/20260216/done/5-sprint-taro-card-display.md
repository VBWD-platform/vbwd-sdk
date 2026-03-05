# Sprint: Taro Card Display & Interpretation Loading

**Sprint Name**: Taro Card Display Complete
**Sprint Goal**: Display card images, names, and LLM-generated interpretations in card detail modal. All cards render with complete information.
**Duration**: Estimated 2-3 days
**Difficulty**: Medium (backend response changes, LLM integration, state management)
**Priority**: P0 - Blocking user feature

---

## Context

The Taro reading plugin displays card data but three critical pieces are missing:
1. **Card SVG image** — Not rendering (has `image_url` but not displayed)
2. **Card name** — Modal shows position but not card identity
3. **Card interpretation** — LLM service not triggered; users see "not yet generated"

Users can create sessions and draw cards, but the card detail modal is incomplete.

---

## Core Requirements (enforced across all tasks)

| Principle | How it applies in this sprint |
|-----------|-------------------------------|
| **TDD-First** | Write tests for response structure BEFORE modifying routes. Tests verify SVG URL presence, card name, interpretation field. |
| **DRY** | Reuse existing Arcana model, don't duplicate data. Interpretation caching in Pinia prevents repeated LLM calls. |
| **SOLID — SRP** | Backend: route returns data (single job). Frontend: modal displays data (single job). LLM service: generates interpretation (single job). |
| **SOLID — OCP** | Card display system open to new card types (not just taro). Interpretation logic extensible to other LLM providers. |
| **SOLID — LSP** | All card types (major/minor arcana) use same display interface. Same interpretation flow whether sync or async. |
| **SOLID — ISP** | Modal only requests card data it needs: image, name, meaning, interpretation. No unnecessary fields. |
| **SOLID — DIP** | Frontend depends on "card data contract" (structure), not on backend implementation. Can swap response source without UI changes. |
| **Clean Code** | No magic strings for card meanings. All text from database or locales. Component renders conditionally on data availability. |
| **Type Safety** | TypeScript: `CardData`, `CardResponse`, `InterpretationResponse` fully typed. Backend: response validated against schema. |
| **Coverage** | Current: 115 user frontend tests + 626 backend tests = 741. Target: maintain all passing. New tests for card response structure, interpretation loading, modal rendering. |
| **No Overengineering** | Don't build interpretation caching if single request per session is fast enough. Test first, optimize if needed. |
| **Minimal Change** | Update response structure, trigger LLM service, update modal display. Don't refactor card system. |

---

## Testing Strategy

### TDD Approach: Test First

1. **Write failing tests** for new response structure
2. **Implement** backend changes to make tests pass
3. **Write failing tests** for frontend modal rendering
4. **Implement** frontend changes
5. **Verify** all 741 existing tests still pass

### Test Counts

| Category | Baseline | New | Target |
|----------|----------|-----|--------|
| Backend (Taro) | ~30 | +8 (response structure) | ~38 |
| Frontend (Taro) | ~40 | +6 (modal + interpretation) | ~46 |
| **Subtotal** | ~70 | +14 | ~84 |
| **Other (unchanged)** | 671 | 0 | 671 |
| **Total** | **741** | **+14** | **~755** |

### Test Commands

```bash
# 1. Before changes: verify baseline
cd vbwd-backend && make test-unit            # Target: 626
cd vbwd-frontend && make test                # Target: 709
# Expected total: 1335

# 2. After implementation: verify all pass
cd vbwd-backend && make test-unit            # Target: 632+ (new tests)
cd vbwd-frontend && make test                # Target: 715+ (new tests)
# Expected total: 1347+
```

---

## Task 1: Backend — Write Tests for Arcana Response Structure

**TDD: RED phase** — Write failing tests for new response format

### Purpose

Define expected response structure including image_url, card name, meanings before implementing backend changes.

### Test File

Create: `/vbwd-backend/plugins/taro/tests/test_card_response_structure.py`

### Implementation

```python
# File: /vbwd-backend/plugins/taro/tests/test_card_response_structure.py

import pytest
from uuid import uuid4
from decimal import Decimal
from src.models.enums import InvoiceStatus, LineItemType, BillingPeriod
from plugins.taro.src.models.arcana import Arcana
from plugins.taro.src.models.taro_session import TaroSession
from plugins.taro.src.models.taro_card_draw import TaroCardDraw

@pytest.fixture
def arcana_major():
    """Fixture: The Fool (arcana 0)."""
    return Arcana(
        number=0,
        name="The Fool",
        suit=None,
        rank=None,
        arcana_type="major",
        image_url="https://example.com/arcana/00-the-fool.svg",
        upright_meaning="New beginnings, taking risks",
        reversed_meaning="Recklessness, naiveté",
    )

@pytest.fixture
def arcana_minor():
    """Fixture: Five of Cups."""
    return Arcana(
        number=67,
        name="Five of Cups",
        suit="cups",
        rank=5,
        arcana_type="minor",
        image_url="https://example.com/arcana/67-five-cups.svg",
        upright_meaning="Grief, loss, despair",
        reversed_meaning="Acceptance, moving forward",
    )

@pytest.fixture
def session_with_cards(user, arcana_major, arcana_minor):
    """Fixture: Taro session with 2 drawn cards."""
    session = TaroSession(
        user_id=user.id,
        status="active",
        spread_type="three_card",
    )
    # Manually add cards (would normally come from draw)
    session.cards = [
        TaroCardDraw(arcana_id=arcana_major.id, position="past", orientation="upright"),
        TaroCardDraw(arcana_id=arcana_minor.id, position="present", orientation="reversed"),
    ]
    return session

# Test Suite: Response Structure

def test_card_response_includes_arcana_id(client, user, session_with_cards):
    """Card in response includes arcana_id field."""
    response = client.get(
        f'/api/v1/taro/session/{session_with_cards.id}',
        headers={'Authorization': f'Bearer {user.token}'}
    )
    assert response.status_code == 200
    data = response.get_json()
    card = data['cards'][0]
    assert 'arcana_id' in card
    assert card['arcana_id'] == str(session_with_cards.cards[0].arcana_id)

def test_card_response_includes_image_url(client, user, session_with_cards):
    """Card in response includes image_url from Arcana."""
    response = client.get(
        f'/api/v1/taro/session/{session_with_cards.id}',
        headers={'Authorization': f'Bearer {user.token}'}
    )
    assert response.status_code == 200
    data = response.get_json()
    card = data['cards'][0]
    assert 'image_url' in card, "Missing image_url in card response"
    assert card['image_url'].endswith('.svg')

def test_card_response_includes_arcana_name(client, user, session_with_cards):
    """Card in response includes card name from Arcana."""
    response = client.get(
        f'/api/v1/taro/session/{session_with_cards.id}',
        headers={'Authorization': f'Bearer {user.token}'}
    )
    assert response.status_code == 200
    data = response.get_json()
    card = data['cards'][0]
    assert 'arcana_name' in card, "Missing arcana_name in card response"
    assert isinstance(card['arcana_name'], str)
    assert len(card['arcana_name']) > 0

def test_card_response_includes_upright_meaning(client, user, session_with_cards):
    """Card in response includes upright meaning from Arcana."""
    response = client.get(
        f'/api/v1/taro/session/{session_with_cards.id}',
        headers={'Authorization': f'Bearer {user.token}'}
    )
    assert response.status_code == 200
    data = response.get_json()
    card = data['cards'][0]
    assert 'upright_meaning' in card, "Missing upright_meaning"
    assert isinstance(card['upright_meaning'], str)

def test_card_response_includes_reversed_meaning(client, user, session_with_cards):
    """Card in response includes reversed meaning from Arcana."""
    response = client.get(
        f'/api/v1/taro/session/{session_with_cards.id}',
        headers={'Authorization': f'Bearer {user.token}'}
    )
    assert response.status_code == 200
    data = response.get_json()
    card = data['cards'][0]
    assert 'reversed_meaning' in card, "Missing reversed_meaning"
    assert isinstance(card['reversed_meaning'], str)

def test_card_response_includes_position(client, user, session_with_cards):
    """Card in response includes position (past/present/future)."""
    response = client.get(
        f'/api/v1/taro/session/{session_with_cards.id}',
        headers={'Authorization': f'Bearer {user.token}'}
    )
    assert response.status_code == 200
    data = response.get_json()
    card = data['cards'][0]
    assert 'position' in card
    assert card['position'] in ['past', 'present', 'future']

def test_card_response_includes_orientation(client, user, session_with_cards):
    """Card in response includes orientation (upright/reversed)."""
    response = client.get(
        f'/api/v1/taro/session/{session_with_cards.id}',
        headers={'Authorization': f'Bearer {user.token}'}
    )
    assert response.status_code == 200
    data = response.get_json()
    card = data['cards'][0]
    assert 'orientation' in card
    assert card['orientation'] in ['upright', 'reversed']

def test_card_response_includes_interpretation_field(client, user, session_with_cards):
    """Card in response includes interpretation field (may be null initially)."""
    response = client.get(
        f'/api/v1/taro/session/{session_with_cards.id}',
        headers={'Authorization': f'Bearer {user.token}'}
    )
    assert response.status_code == 200
    data = response.get_json()
    card = data['cards'][0]
    assert 'interpretation' in card
    # May be null initially, but field must exist
    assert card['interpretation'] is None or isinstance(card['interpretation'], str)

# Test Suite: Response Structure Integrity

def test_all_cards_have_required_fields(client, user, session_with_cards):
    """All cards in response have all required fields."""
    response = client.get(
        f'/api/v1/taro/session/{session_with_cards.id}',
        headers={'Authorization': f'Bearer {user.token}'}
    )
    assert response.status_code == 200
    data = response.get_json()
    required_fields = ['arcana_id', 'arcana_name', 'image_url', 'position', 'orientation',
                       'upright_meaning', 'reversed_meaning', 'interpretation', 'card_id']
    for card in data['cards']:
        for field in required_fields:
            assert field in card, f"Card missing required field: {field}"

def test_card_response_payload_size_reasonable(client, user, session_with_cards):
    """Response payload is not excessively large."""
    response = client.get(
        f'/api/v1/taro/session/{session_with_cards.id}',
        headers={'Authorization': f'Bearer {user.token}'}
    )
    assert response.status_code == 200
    data = response.get_json()
    payload_size = len(response.data)  # bytes
    # Each card should be ~500-1000 bytes (image_url, name, meanings, etc.)
    assert payload_size < 100000, f"Response too large: {payload_size} bytes"
```

### Files

- **NEW**: `plugins/taro/tests/test_card_response_structure.py`

---

## Task 2: Backend — Implement Card Response with Arcana Details

**TDD: GREEN phase** — Modify routes to make tests pass

### Purpose

Update session response to include full Arcana details for each card.

### Current Response (WRONG)

```json
{
  "session_id": "...",
  "cards": [
    {
      "card_id": "...",
      "arcana_id": "...",
      "position": "past",
      "orientation": "upright"
      // Missing: image_url, arcana_name, meanings
    }
  ]
}
```

### Target Response (CORRECT)

```json
{
  "session_id": "...",
  "cards": [
    {
      "card_id": "...",
      "arcana_id": "...",
      "arcana_name": "The Fool",
      "image_url": "https://example.com/arcana/00-the-fool.svg",
      "position": "past",
      "orientation": "upright",
      "upright_meaning": "New beginnings, taking risks",
      "reversed_meaning": "Recklessness, naiveté",
      "interpretation": null
    }
  ]
}
```

### Implementation

**File**: `/vbwd-backend/plugins/taro/src/routes.py`

**Function to update**:

```python
def get_taro_session_detail(session_id: str):
    """GET /api/v1/taro/session/<id>

    Returns session with full card details including Arcana data.
    """
    # ... existing code ...

    # BEFORE (WRONG):
    cards_data = [
        {
            'card_id': str(cd.id),
            'arcana_id': str(cd.arcana_id),
            'position': cd.position.value,
            'orientation': cd.orientation.value,
        }
        for cd in session.cards
    ]

    # AFTER (CORRECT):
    cards_data = []
    for cd in session.cards:
        arcana = cd.arcana  # Lazy-load from relationship
        cards_data.append({
            'card_id': str(cd.id),
            'arcana_id': str(cd.arcana_id),
            'arcana_name': arcana.name,
            'image_url': arcana.image_url,
            'position': cd.position.value,
            'orientation': cd.orientation.value,
            'upright_meaning': arcana.upright_meaning,
            'reversed_meaning': arcana.reversed_meaning,
            'interpretation': cd.interpretation or None,  # Will be populated by LLM
        })

    return jsonify({
        'session_id': str(session.id),
        'cards': cards_data,
        'follow_up_count': session.follow_ups_used,
        'max_follow_ups': session.max_follow_ups,
        # ... rest of response ...
    }), 200
```

### Files

- **EDIT**: `plugins/taro/src/routes.py`

---

## Task 3: Backend — Run Card Response Tests

**TDD: Verify** — All new tests should now pass

### Purpose

Confirm that response structure tests pass after implementation.

### Implementation

```bash
cd /vbwd-backend

# Run the new test file
pytest plugins/taro/tests/test_card_response_structure.py -v

# Expected output:
# test_card_response_includes_arcana_id PASSED
# test_card_response_includes_image_url PASSED
# test_card_response_includes_arcana_name PASSED
# test_card_response_includes_upright_meaning PASSED
# test_card_response_includes_reversed_meaning PASSED
# test_card_response_includes_position PASSED
# test_card_response_includes_orientation PASSED
# test_card_response_includes_interpretation_field PASSED
# test_all_cards_have_required_fields PASSED
# test_card_response_payload_size_reasonable PASSED
#
# ===== 10 passed in 0.45s =====
```

### Files

- No file changes; testing only

---

## Task 4: Frontend — Write Tests for Card Modal Rendering

**TDD: RED phase** — Write failing tests for modal display

### Purpose

Define expected modal behavior for rendering card image, name, and meanings.

### Test File

Create: `/vbwd-frontend/user/vue/tests/unit/plugins/taro-card-modal.spec.ts`

### Implementation

```typescript
// File: /vbwd-frontend/user/vue/tests/unit/plugins/taro-card-modal.spec.ts

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import CardDetailModal from '@/plugins/taro/src/components/CardDetailModal.vue';
import { createPinia } from 'pinia';

describe('CardDetailModal.vue', () => {
  let wrapper;
  const pinia = createPinia();

  const mockCardData = {
    card_id: 'card-1',
    arcana_id: 'arcana-0',
    arcana_name: 'The Fool',
    image_url: 'https://example.com/arcana/00-the-fool.svg',
    position: 'past',
    orientation: 'upright',
    upright_meaning: 'New beginnings, taking risks',
    reversed_meaning: 'Recklessness, naiveté',
    interpretation: null,
  };

  // Test Suite: Card Image Display

  it('renders card image from image_url prop', () => {
    wrapper = mount(CardDetailModal, {
      props: { cardData: mockCardData, isOpen: true },
      global: { plugins: [pinia] },
    });

    const img = wrapper.find('img');
    expect(img.exists()).toBe(true);
    expect(img.attributes('src')).toBe(mockCardData.image_url);
    expect(img.attributes('alt')).toBe(mockCardData.arcana_name);
  });

  it('displays card image with correct CSS classes', () => {
    wrapper = mount(CardDetailModal, {
      props: { cardData: mockCardData, isOpen: true },
      global: { plugins: [pinia] },
    });

    const img = wrapper.find('.card-image');
    expect(img.exists()).toBe(true);
  });

  // Test Suite: Card Name Display

  it('displays card name from arcana_name prop', () => {
    wrapper = mount(CardDetailModal, {
      props: { cardData: mockCardData, isOpen: true },
      global: { plugins: [pinia] },
    });

    const title = wrapper.find('h2');
    expect(title.exists()).toBe(true);
    expect(title.text()).toContain(mockCardData.arcana_name);
  });

  it('includes position in header', () => {
    wrapper = mount(CardDetailModal, {
      props: { cardData: mockCardData, isOpen: true },
      global: { plugins: [pinia] },
    });

    const header = wrapper.find('h2');
    expect(header.text()).toContain('Past'); // Position label
  });

  // Test Suite: Card Meanings Display

  it('displays upright meaning when orientation is upright', () => {
    wrapper = mount(CardDetailModal, {
      props: { cardData: mockCardData, isOpen: true },
      global: { plugins: [pinia] },
    });

    const meaningSection = wrapper.find('.meaning-section');
    expect(meaningSection.exists()).toBe(true);
    expect(meaningSection.text()).toContain(mockCardData.upright_meaning);
  });

  it('displays reversed meaning when orientation is reversed', () => {
    const reversedCard = { ...mockCardData, orientation: 'reversed' };
    wrapper = mount(CardDetailModal, {
      props: { cardData: reversedCard, isOpen: true },
      global: { plugins: [pinia] },
    });

    const meaningSection = wrapper.find('.meaning-section');
    expect(meaningSection.text()).toContain(mockCardData.reversed_meaning);
  });

  it('shows orientation indicator', () => {
    wrapper = mount(CardDetailModal, {
      props: { cardData: mockCardData, isOpen: true },
      global: { plugins: [pinia] },
    });

    expect(wrapper.text()).toContain('Upright');
  });

  // Test Suite: Interpretation Display

  it('shows loading state when interpretation is null', () => {
    wrapper = mount(CardDetailModal, {
      props: { cardData: { ...mockCardData, interpretation: null }, isOpen: true },
      global: { plugins: [pinia] },
    });

    const interpretationSection = wrapper.find('.interpretation-section');
    expect(interpretationSection.exists()).toBe(true);
    expect(interpretationSection.text()).toMatch(/loading|generating|not yet/i);
  });

  it('displays interpretation text when available', () => {
    const cardWithInterpretation = {
      ...mockCardData,
      interpretation: 'This card represents a new chapter in your life.',
    };
    wrapper = mount(CardDetailModal, {
      props: { cardData: cardWithInterpretation, isOpen: true },
      global: { plugins: [pinia] },
    });

    const interpretationSection = wrapper.find('.interpretation-section');
    expect(interpretationSection.text()).toContain(cardWithInterpretation.interpretation);
  });

  // Test Suite: Modal Behavior

  it('does not render when isOpen is false', () => {
    wrapper = mount(CardDetailModal, {
      props: { cardData: mockCardData, isOpen: false },
      global: { plugins: [pinia] },
    });

    expect(wrapper.find('.modal').exists()).toBe(false);
  });

  it('closes modal on close button click', async () => {
    wrapper = mount(CardDetailModal, {
      props: { cardData: mockCardData, isOpen: true },
      global: { plugins: [pinia] },
    });

    const closeButton = wrapper.find('[data-testid="modal-close"]');
    expect(closeButton.exists()).toBe(true);

    await closeButton.trigger('click');
    expect(wrapper.emitted('close')).toBeTruthy();
  });
});
```

### Files

- **NEW**: `user/vue/tests/unit/plugins/taro-card-modal.spec.ts`

---

## Task 5: Frontend — Implement Card Modal Display

**TDD: GREEN phase** — Update CardDetailModal component

### Purpose

Render card image, name, meanings, and interpretation loading state.

### File to Update

`/vbwd-frontend/user/plugins/taro/src/components/CardDetailModal.vue`

### Current Implementation (INCOMPLETE)

```vue
<template>
  <div v-if="isOpen" class="modal">
    <h2>{{ cardData?.position }}</h2>
    <!-- Image missing -->
    <!-- Card name missing -->
    <!-- Meanings missing -->
  </div>
</template>

<script setup lang="ts">
const props = defineProps<{ cardData?: CardData; isOpen: boolean }>();
</script>
```

### Target Implementation (COMPLETE)

```vue
<template>
  <div v-if="isOpen" class="modal">
    <div class="modal-content">
      <!-- Header: Card Name + Position -->
      <h2>{{ cardData?.arcana_name }} ({{ positionLabel }})</h2>

      <!-- Card Image -->
      <div class="card-image-container">
        <img
          v-if="cardData?.image_url"
          :src="cardData.image_url"
          :alt="cardData?.arcana_name"
          class="card-image"
        />
      </div>

      <!-- Meaning Section (Upright or Reversed) -->
      <div class="meaning-section">
        <h3>{{ orientationLabel }} Meaning</h3>
        <p v-if="cardData?.orientation === 'upright'">
          {{ cardData?.upright_meaning }}
        </p>
        <p v-else>
          {{ cardData?.reversed_meaning }}
        </p>
      </div>

      <!-- Interpretation Section -->
      <div class="interpretation-section">
        <h3>{{ $t('taro.interpretation') }}</h3>
        <div v-if="cardData?.interpretation">
          <p>{{ cardData.interpretation }}</p>
        </div>
        <div v-else class="loading-state">
          <span class="spinner"></span>
          {{ $t('taro.loadingInterpretation') }}
        </div>
      </div>

      <!-- Close Button -->
      <button
        data-testid="modal-close"
        @click="$emit('close')"
        class="btn-close"
      >
        {{ $t('common.close') }}
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

interface CardData {
  card_id: string;
  arcana_id: string;
  arcana_name: string;
  image_url: string;
  position: 'past' | 'present' | 'future';
  orientation: 'upright' | 'reversed';
  upright_meaning: string;
  reversed_meaning: string;
  interpretation: string | null;
}

const props = defineProps<{ cardData?: CardData; isOpen: boolean }>();
const emit = defineEmits<{ close: [] }>();
const { t } = useI18n();

// Computed properties for labels
const positionLabel = computed(() => {
  if (!props.cardData) return '';
  return t(`taro.position.${props.cardData.position}`);
});

const orientationLabel = computed(() => {
  if (!props.cardData) return '';
  return t(`taro.orientation.${props.cardData.orientation}`);
});
</script>

<style scoped>
.modal {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}

.modal-content {
  background: white;
  border-radius: 8px;
  padding: 24px;
  max-width: 600px;
  max-height: 90vh;
  overflow-y: auto;
}

h2 {
  margin: 0 0 16px 0;
  font-size: 24px;
  font-weight: 600;
}

h3 {
  margin: 16px 0 8px 0;
  font-size: 16px;
  font-weight: 500;
}

.card-image-container {
  text-align: center;
  margin: 20px 0;
}

.card-image {
  max-width: 300px;
  max-height: 400px;
  border-radius: 4px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
}

.meaning-section,
.interpretation-section {
  margin: 16px 0;
  padding: 12px;
  background: #f5f5f5;
  border-radius: 4px;
}

.meaning-section p,
.interpretation-section p {
  margin: 0;
  line-height: 1.6;
}

.loading-state {
  display: flex;
  align-items: center;
  gap: 8px;
  color: #666;
  font-style: italic;
}

.spinner {
  display: inline-block;
  width: 16px;
  height: 16px;
  border: 2px solid #ddd;
  border-top: 2px solid #333;
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.btn-close {
  margin-top: 16px;
  padding: 8px 16px;
  background: #007bff;
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 14px;
}

.btn-close:hover {
  background: #0056b3;
}
</style>
```

### Files

- **EDIT**: `user/plugins/taro/src/components/CardDetailModal.vue`

---

## Task 6: Frontend — Run Modal Tests

**TDD: Verify** — All modal tests should pass

### Purpose

Confirm modal renders all card details correctly.

### Implementation

```bash
cd /vbwd-frontend/user

# Run the new modal tests
npx vitest run tests/unit/plugins/taro-card-modal.spec.ts

# Expected output:
# test_renders_card_image PASSED
# test_displays_card_name PASSED
# test_displays_upright_meaning PASSED
# test_displays_reversed_meaning PASSED
# test_shows_loading_state PASSED
# test_displays_interpretation PASSED
# test_closes_modal PASSED
#
# ===== 7 passed in 0.52s =====
```

### Files

- No file changes; testing only

---

## Task 7: Backend — Write Tests for LLM Interpretation Trigger

**TDD: RED phase** — Define interpretation loading behavior

### Purpose

Test that interpretations are loaded from LLM service on card draw or detail request.

### Test File

Create: `/vbwd-backend/plugins/taro/tests/test_interpretation_loading.py`

### Implementation

```python
# File: /vbwd-backend/plugins/taro/tests/test_interpretation_loading.py

import pytest
from unittest.mock import patch, MagicMock
from uuid import uuid4
from plugins.taro.src.models.arcana import Arcana
from plugins.taro.src.models.taro_card_draw import TaroCardDraw
from plugins.taro.src.services.arcana_interpretation_service import ArcanaInterpretationService

@pytest.fixture
def arcana():
    """Fixture: Sample arcana card."""
    return Arcana(
        number=0,
        name="The Fool",
        suit=None,
        rank=None,
        arcana_type="major",
        image_url="https://example.com/arcana/00-the-fool.svg",
        upright_meaning="New beginnings",
        reversed_meaning="Recklessness",
    )

@pytest.fixture
def card_draw(arcana):
    """Fixture: Card drawn in position."""
    return TaroCardDraw(
        arcana_id=arcana.id,
        position="past",
        orientation="upright",
        interpretation=None,  # Not yet generated
    )

# Test Suite: Interpretation Generation

def test_interpretation_generated_on_detail_request(client, user, card_draw):
    """Interpretation is generated when card detail is requested."""
    session_id = card_draw.taro_session_id

    with patch('plugins.taro.src.services.arcana_interpretation_service.OpenAI') as mock_openai:
        # Mock LLM response
        mock_completion = MagicMock()
        mock_completion.choices[0].message.content = "A new chapter begins..."
        mock_openai.return_value.chat.completions.create.return_value = mock_completion

        # Request card detail
        response = client.get(
            f'/api/v1/taro/session/{session_id}',
            headers={'Authorization': f'Bearer {user.token}'}
        )

        assert response.status_code == 200
        data = response.get_json()
        card = data['cards'][0]

        # Interpretation should be generated
        assert 'interpretation' in card
        # May be async, so could be null on first call, but should be in response structure

def test_interpretation_cached_on_second_request(client, user, card_draw):
    """Second request for same card uses cached interpretation."""
    session_id = card_draw.taro_session_id

    with patch('plugins.taro.src.services.arcana_interpretation_service.OpenAI') as mock_openai:
        mock_completion = MagicMock()
        mock_completion.choices[0].message.content = "A new chapter begins..."
        mock_openai.return_value.chat.completions.create.return_value = mock_completion

        # First request
        response1 = client.get(
            f'/api/v1/taro/session/{session_id}',
            headers={'Authorization': f'Bearer {user.token}'}
        )
        assert response1.status_code == 200

        # Second request (should use cached)
        response2 = client.get(
            f'/api/v1/taro/session/{session_id}',
            headers={'Authorization': f'Bearer {user.token}'}
        )
        assert response2.status_code == 200

        # OpenAI should only be called once (or not at all on second request)
        # Exact behavior depends on caching strategy

def test_interpretation_includes_position_orientation(client, user, card_draw):
    """LLM service receives position and orientation context."""
    session_id = card_draw.taro_session_id

    with patch('plugins.taro.src.services.arcana_interpretation_service.ArcanaInterpretationService.generate') as mock_generate:
        mock_generate.return_value = "The Fool in the past position, upright, represents..."

        response = client.get(
            f'/api/v1/taro/session/{session_id}',
            headers={'Authorization': f'Bearer {user.token}'}
        )

        assert response.status_code == 200

def test_interpretation_error_handled_gracefully(client, user, card_draw):
    """If LLM fails, response still includes card but interpretation is null."""
    session_id = card_draw.taro_session_id

    with patch('plugins.taro.src.services.arcana_interpretation_service.OpenAI') as mock_openai:
        mock_openai.return_value.chat.completions.create.side_effect = Exception("API Error")

        response = client.get(
            f'/api/v1/taro/session/{session_id}',
            headers={'Authorization': f'Bearer {user.token}'}
        )

        # Should still return 200, not 500
        assert response.status_code == 200
        data = response.get_json()
        card = data['cards'][0]

        # Interpretation null, but card still displayed
        assert card['interpretation'] is None or isinstance(card['interpretation'], str)
```

### Files

- **NEW**: `plugins/taro/tests/test_interpretation_loading.py`

---

## Task 8: Backend — Implement Interpretation Loading

**TDD: GREEN phase** — Trigger LLM service on card detail request

### Purpose

Call ArcanaInterpretationService when card details are requested, cache result in card_draw.interpretation.

### Implementation Strategy

**Current flow**:
```
GET /api/v1/taro/session/<id>
  → Load session from DB
  → Return cards with basic fields
  → (END)
```

**New flow**:
```
GET /api/v1/taro/session/<id>
  → Load session from DB
  → For each card:
    → If interpretation is null:
      → Call ArcanaInterpretationService.generate(card, arcana)
      → Save result to card_draw.interpretation
    → Include interpretation in response
  → Return cards with all fields
```

### Code Changes

**File**: `/vbwd-backend/plugins/taro/src/routes.py`

**In the route handler**:

```python
@taro_plugin_bp.route('/session/<session_id>', methods=['GET'])
@require_auth
def get_taro_session_detail(session_id: str):
    """GET /api/v1/taro/session/<id>

    Returns session with full card details and generated interpretations.
    """
    container = current_app.container
    session_repo = container.taro_session_repository()
    interpretation_service = ArcanaInterpretationService(container)

    # Load session
    session = session_repo.find_by_id(UUID(session_id))
    if not session or session.user_id != g.user_id:
        return jsonify({'error': 'Not found'}), 404

    # Build card response with interpretations
    cards_data = []
    for cd in session.cards:
        arcana = cd.arcana

        # Generate interpretation if missing (non-blocking)
        interpretation = cd.interpretation
        if not interpretation:
            try:
                interpretation = interpretation_service.generate(
                    arcana=arcana,
                    position=cd.position.value,
                    orientation=cd.orientation.value,
                )
                cd.interpretation = interpretation
                session_repo.save(session)  # Cache in DB
            except Exception as e:
                current_app.logger.warning(f"Interpretation generation failed: {e}")
                interpretation = None

        cards_data.append({
            'card_id': str(cd.id),
            'arcana_id': str(cd.arcana_id),
            'arcana_name': arcana.name,
            'image_url': arcana.image_url,
            'position': cd.position.value,
            'orientation': cd.orientation.value,
            'upright_meaning': arcana.upright_meaning,
            'reversed_meaning': arcana.reversed_meaning,
            'interpretation': interpretation,
        })

    return jsonify({
        'session_id': str(session.id),
        'cards': cards_data,
        'follow_up_count': session.follow_ups_used,
        'max_follow_ups': session.max_follow_ups,
        'status': session.status.value,
    }), 200
```

### Files

- **EDIT**: `plugins/taro/src/routes.py`

---

## Task 9: Backend — Run Interpretation Tests

**TDD: Verify** — Interpretation loading tests pass

### Purpose

Confirm interpretations are generated and included in responses.

### Implementation

```bash
cd /vbwd-backend

pytest plugins/taro/tests/test_interpretation_loading.py -v

# Expected output:
# test_interpretation_generated_on_detail_request PASSED
# test_interpretation_cached_on_second_request PASSED
# test_interpretation_includes_position_orientation PASSED
# test_interpretation_error_handled_gracefully PASSED
#
# ===== 4 passed in 0.85s =====
```

### Files

- No file changes; testing only

---

## Task 10: Frontend — Write Tests for Interpretation Loading

**TDD: RED phase** — Test interpretation fetch and display

### Purpose

Verify frontend polls for interpretation and displays when available.

### Test File

Create: `/vbwd-frontend/user/vue/tests/unit/plugins/taro-interpretation.spec.ts`

### Implementation

```typescript
// File: /vbwd-frontend/user/vue/tests/unit/plugins/taro-interpretation.spec.ts

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import CardDetailModal from '@/plugins/taro/src/components/CardDetailModal.vue';
import { createPinia } from 'pinia';

describe('CardDetailModal - Interpretation Loading', () => {
  let wrapper;
  const pinia = createPinia();

  const mockCardWithoutInterpretation = {
    card_id: 'card-1',
    arcana_id: 'arcana-0',
    arcana_name: 'The Fool',
    image_url: 'https://example.com/arcana/00-the-fool.svg',
    position: 'past',
    orientation: 'upright',
    upright_meaning: 'New beginnings',
    reversed_meaning: 'Recklessness',
    interpretation: null,  // ← Not yet generated
  };

  const mockCardWithInterpretation = {
    ...mockCardWithoutInterpretation,
    interpretation: 'The Fool in the past position represents...',
  };

  // Test Suite: Loading State

  it('shows loading indicator when interpretation is null', () => {
    wrapper = mount(CardDetailModal, {
      props: { cardData: mockCardWithoutInterpretation, isOpen: true },
      global: { plugins: [pinia] },
    });

    const interpretationSection = wrapper.find('.interpretation-section');
    expect(interpretationSection.text()).toMatch(/loading|generating/i);
    expect(interpretationSection.find('.spinner').exists()).toBe(true);
  });

  it('shows loading message in user language', () => {
    wrapper = mount(CardDetailModal, {
      props: { cardData: mockCardWithoutInterpretation, isOpen: true },
      global: {
        plugins: [pinia],
        i18n: {
          locale: 'en',
          messages: {
            en: {
              taro: {
                loadingInterpretation: 'Generating interpretation...',
              },
            },
          },
        },
      },
    });

    expect(wrapper.text()).toContain('Generating interpretation...');
  });

  // Test Suite: Interpretation Display

  it('displays interpretation when available', () => {
    wrapper = mount(CardDetailModal, {
      props: { cardData: mockCardWithInterpretation, isOpen: true },
      global: { plugins: [pinia] },
    });

    const interpretationSection = wrapper.find('.interpretation-section');
    expect(interpretationSection.text()).toContain(
      'The Fool in the past position represents...'
    );
  });

  it('replaces loading state with interpretation', async () => {
    wrapper = mount(CardDetailModal, {
      props: { cardData: mockCardWithoutInterpretation, isOpen: true },
      global: { plugins: [pinia] },
    });

    // Initially loading
    expect(wrapper.find('.spinner').exists()).toBe(true);

    // Update to card with interpretation
    await wrapper.setProps({
      cardData: mockCardWithInterpretation,
    });

    // Now shows interpretation, not loading
    expect(wrapper.find('.spinner').exists()).toBe(false);
    expect(wrapper.text()).toContain(mockCardWithInterpretation.interpretation!);
  });

  // Test Suite: Error Handling

  it('handles null interpretation gracefully', () => {
    wrapper = mount(CardDetailModal, {
      props: { cardData: mockCardWithoutInterpretation, isOpen: true },
      global: { plugins: [pinia] },
    });

    // Should not crash, should show loading
    expect(wrapper.find('.interpretation-section').exists()).toBe(true);
  });
});
```

### Files

- **NEW**: `user/vue/tests/unit/plugins/taro-interpretation.spec.ts`

---

## Task 11: Frontend — Implement Interpretation Display

**TDD: GREEN phase** — Component already handles it, but verify tests pass

### Purpose

Modal component already has conditional logic for interpretation. Verify it works with new response structure.

### Implementation

The CardDetailModal component from Task 5 already includes:

```vue
<div class="interpretation-section">
  <h3>{{ $t('taro.interpretation') }}</h3>
  <div v-if="cardData?.interpretation">
    <p>{{ cardData.interpretation }}</p>
  </div>
  <div v-else class="loading-state">
    <span class="spinner"></span>
    {{ $t('taro.loadingInterpretation') }}
  </div>
</div>
```

This handles both null (loading) and populated (display) cases.

### Files

- No file changes; tests verify existing logic

---

## Task 12: Frontend — Run Interpretation Tests

**TDD: Verify** — Interpretation tests pass

### Purpose

Confirm interpretation loading UI works correctly.

### Implementation

```bash
cd /vbwd-frontend/user

npx vitest run tests/unit/plugins/taro-interpretation.spec.ts

# Expected output:
# test_shows_loading_indicator PASSED
# test_displays_interpretation PASSED
# test_replaces_loading_with_interpretation PASSED
# test_handles_null_interpretation PASSED
#
# ===== 4 passed in 0.38s =====
```

### Files

- No file changes; testing only

---

## Task 13: Full Regression Test Suite

**Verify** all 741 baseline tests still pass

### Purpose

Ensure no regressions from card display changes.

### Implementation

```bash
# Backend
cd /vbwd-backend && make test-unit
# Expected: 632 tests passing (or 632+ if new tests added)

# Frontend
cd /vbwd-frontend && make test
# Expected: 709 tests passing (or 709+ if new tests added)

# Full pre-commit check
cd /vbwd-backend && make pre-commit
cd /vbwd-frontend && make pre-commit
```

### Files

- No file changes; testing only

---

## Task 14: Manual Smoke Test

**Verify** end-to-end card reading flow

### Purpose

Test complete user experience: create session → draw cards → view card details.

### Steps

1. **Login** to user app
2. **Navigate** to Taro Reading
3. **Create Session** (three-card spread)
4. **View Cards** in grid
5. **Click Card** → Modal opens
6. **Verify Modal Shows**:
   - ✅ Card image (SVG) renders
   - ✅ Card name displayed
   - ✅ Position label (Past/Present/Future)
   - ✅ Meaning section with upright/reversed interpretation
   - ✅ Orientation indicator
   - ✅ Interpretation field (loading or populated)
7. **Wait 2-3 seconds** for interpretation to load
8. **Verify Interpretation** displays in modal
9. **Close Modal** and repeat for other cards
10. **All 3 cards** render without errors

### Expected Behavior

- Card SVG image loads from URL
- Card name is prominent
- Meanings are readable
- Interpretation loading state shows briefly
- Interpretation appears after 2-3 seconds
- No console errors

### Files

- No file changes; manual verification only

---

## Implementation Order

```
Task 1: Write response structure tests (RED)
  ↓
Task 2: Implement card response with Arcana details (GREEN)
  ↓
Task 3: Run response tests ✅
  ↓
Task 4: Write modal rendering tests (RED)
  ↓
Task 5: Implement CardDetailModal component (GREEN)
  ↓
Task 6: Run modal tests ✅
  ↓
Task 7: Write interpretation loading tests (RED)
  ↓
Task 8: Implement interpretation service call (GREEN)
  ↓
Task 9: Run interpretation tests ✅
  ↓
Task 10: Write interpretation display tests (RED)
  ↓
Task 11: Verify interpretation component (GREEN)
  ↓
Task 12: Run interpretation display tests ✅
  ↓
Task 13: Full regression test suite
  ↓
Task 14: Manual smoke test
  ↓
SPRINT COMPLETE
```

---

## File Summary

| Action | File |
|--------|------|
| NEW | `plugins/taro/tests/test_card_response_structure.py` |
| EDIT | `plugins/taro/src/routes.py` (add Arcana fields to response) |
| NEW | `user/vue/tests/unit/plugins/taro-card-modal.spec.ts` |
| EDIT | `user/plugins/taro/src/components/CardDetailModal.vue` (complete rewrite) |
| NEW | `plugins/taro/tests/test_interpretation_loading.py` |
| EDIT | `plugins/taro/src/routes.py` (add interpretation loading) |
| NEW | `user/vue/tests/unit/plugins/taro-interpretation.spec.ts` |

---

## Success Criteria

### ✅ Backend Complete
- [ ] Card response includes: arcana_id, arcana_name, image_url, position, orientation, upright_meaning, reversed_meaning, interpretation
- [ ] All 10 response structure tests passing
- [ ] All 4 interpretation loading tests passing
- [ ] 626 baseline tests still passing

### ✅ Frontend Complete
- [ ] CardDetailModal displays card image from image_url
- [ ] Card name displayed prominently
- [ ] Position and orientation labels shown
- [ ] Meaning section displays correct meaning (upright or reversed)
- [ ] Interpretation section shows loading state when null
- [ ] Interpretation displays when populated
- [ ] All 7 modal rendering tests passing
- [ ] All 4 interpretation display tests passing
- [ ] 709 baseline tests still passing

### ✅ End-to-End
- [ ] User creates taro session
- [ ] Cards draw successfully
- [ ] Card modal opens on click
- [ ] Modal displays card image, name, meaning, and interpretation
- [ ] No console errors
- [ ] No 500 errors in API

### ✅ Test Coverage
- [ ] 10 backend response structure tests
- [ ] 4 backend interpretation loading tests
- [ ] 7 frontend modal rendering tests
- [ ] 4 frontend interpretation display tests
- [ ] All baseline tests passing (741 → ~755)

---

## Risk Assessment

### Risk: LLM Service Failure
**Impact**: Interpretation null, but card still displays
**Mitigation**: Error handling in route, graceful degradation
**Severity**: LOW (UX shows loading state, not crash)

### Risk: Image URL Invalid or Missing
**Impact**: Modal shows broken image icon
**Mitigation**: Verify image_url in DB during population
**Severity**: MEDIUM (can be fixed in data migration)

### Risk: Response Payload Too Large
**Impact**: Slow API responses
**Mitigation**: Monitor response size, cache when possible
**Severity**: LOW (SVG URLs are small strings)

---

## Verification

### Automated

```bash
# All tests
cd /vbwd-backend && make test-unit          # 632+ tests
cd /vbwd-frontend && make test              # 709+ tests

# Specific test suites
pytest plugins/taro/tests/test_card_response_structure.py -v
pytest plugins/taro/tests/test_interpretation_loading.py -v
npx vitest run user/vue/tests/unit/plugins/taro-card-modal.spec.ts
npx vitest run user/vue/tests/unit/plugins/taro-interpretation.spec.ts
```

### Manual

Open `http://localhost:8080`:
1. Login
2. Create Taro session
3. View card modal
4. Verify image, name, meaning, interpretation load

---

**Sprint Created**: February 16, 2026
**Sprint Status**: Ready to Execute
**Target Completion**: February 17-18, 2026 (2-3 days)
**Owner**: Frontend + Backend Development Team
**Estimated Effort**: 12-15 hours total
