# Taro Oracle Prompt Management System - Complete Implementation Sprint

**Date**: 2026-02-17
**Status**: Ready for Implementation
**Complexity**: High (Core System - Reusable Across Plugins)

---

## Core Principles (Non-Negotiable)

### **TDD - Test-Driven Development**
- ✅ **Write tests first** - Before implementing each component
- ✅ **Red → Green → Refactor** - Tests drive design
- ✅ **100% coverage** for business logic (PromptService)
- ✅ **Meaningful tests** - Not just code coverage, but behavior validation

### **SOLID Principles**
- **S (Single Responsibility)**: PromptService only manages prompts, LLMAdapter handles API calls
- **O (Open/Closed)**: Prompt system extensible without modification (new prompts = data, not code)
- **L (Liskov)**: PromptService abstract enough for other plugins to use
- **I (Interface Segregation)**: Small, focused interfaces (load, render, validate, update)
- **D (Dependency Injection)**: PromptService injected into TaroSessionService

### **DI - Dependency Injection**
- ✅ No `new PromptService()` in code - inject via constructor
- ✅ PromptService injected into routes, services, tests
- ✅ Makes testing trivial (mock PromptService)

### **DRY - Don't Repeat Yourself**
- ✅ **One source of truth for prompts** - In JSON file, not scattered in code
- ✅ **No duplicate prompt rendering** - Single `render()` method
- ✅ **Shared metadata handling** - Defaults + overrides in one place

### **Liskov Substitution Principle**
- ✅ PromptService can be mocked in tests
- ✅ Could be extended to FileSystemPromptService, DatabasePromptService without breaking code

### **Clean Code**
- ✅ **Descriptive names**: `render_template()`, `validate_template()`, not `process()` or `handle()`
- ✅ **Functions < 20 lines**: Break complex logic into smaller functions
- ✅ **No magic strings**: Use constants for keys, slugs, metadata fields
- ✅ **Clear error messages**: Tell user exactly what's wrong

### **No Over-Engineering**
- ✅ JSON file storage (not custom DB schema)
- ✅ Jinja2 templates (not custom template engine)
- ✅ No version control/history tracking (simple reset to defaults)
- ✅ No advanced features (caching, hot-reloading) unless needed
- ✅ No ORM, no migrations - files are simple and portable

### **No Dead Code**
- ✅ Every method/class is used
- ✅ No "future feature" flags or unused parameters
- ✅ Remove hardcoded prompts completely (don't leave them as fallback)
- ✅ No commented-out code

---

## Executive Summary

Implement a **configurable prompt management system** for LLM-powered Taro readings. Prompts stored in JSON with Handlebars templating. Admin UI with two tabs: Metadata Defaults + Prompt List. File-based (no DB) for easy plugin portability.

**Key Features:**
- ✅ Handlebars template syntax for dynamic variables
- ✅ Metadata inheritance (defaults + per-prompt overrides)
- ✅ Two-tab admin UI (Defaults | Prompts)
- ✅ Reset to Defaults functionality
- ✅ Error handling for missing files
- ✅ Reusable across plugins
- ✅ **Built on TDD + SOLID principles**

---

## Data Model & File Structure

### **File Location & Format**

```
/vbwd-backend/plugins/taro-prompts.json
```

**Structure:**
```json
{
  "_meta": {
    "version": "1.0",
    "plugin": "taro",
    "description": "Taro Oracle LLM Prompts"
  },
  "_defaults": {
    "temperature": 0.7,
    "max_tokens": 2000,
    "timeout": 30
  },
  "system_prompt": {
    "template": "You are an expert Tarot card reader providing mystical insights.",
    "variables": []
  },
  "card_interpretation": {
    "template": "Generate a brief, insightful Tarot card interpretation (1-2 sentences):\n\nCard: {{card_name}}\nOrientation: {{orientation}}\nPosition: {{position}}\nBase Meaning: {{base_meaning}}\nContext: {{position_context}}\n\nProvide a mystical interpretation...",
    "variables": ["card_name", "orientation", "position", "base_meaning", "position_context"],
    "temperature": 0.7,
    "max_tokens": 300
  },
  "situation_reading": {
    "template": "You are an expert Tarot card reader providing profound, comprehensive mystical guidance...\n\nUSER'S SITUATION:\n{{situation_text}}\n\nTHE CARDS:\n{{cards_context}}\n\nProvide a comprehensive reading (4-6 detailed paragraphs)...",
    "variables": ["situation_text", "cards_context"],
    "temperature": 0.8,
    "max_tokens": 2500
  },
  "card_explanation": {
    "template": "You are an expert Tarot reader. The user wants to understand the three cards they drew.\n\nTHE CARDS:\n{{cards_context}}\n\nProvide a detailed explanation of each card's meaning and how they work together...",
    "variables": ["cards_context"],
    "temperature": 0.7,
    "max_tokens": 2000
  },
  "follow_up_question": {
    "template": "You are an expert Tarot card reader in an ongoing conversation with a seeker.\n\nPrevious cards:\n{{cards_context}}\n\nUser's question:\n{{question}}\n\nProvide a focused, insightful response that directly addresses their question...",
    "variables": ["cards_context", "question"],
    "temperature": 0.7,
    "max_tokens": 1000
  },
  "initial_greeting": {
    "template": "The cards have spoken. Do you seek a detailed explanation of each card, or shall we explore how they relate to your situation?",
    "variables": []
  }
}
```

### **Distribution File**

**File:** `/vbwd-backend/plugins/taro/prompts.json.dist`

Same structure as above - used for installation/reset.

---

## API Endpoints

### **Admin Endpoints** (Protected - Admin only)

```
GET    /api/v1/taro/admin/prompts
       → Return all prompts + defaults metadata

GET    /api/v1/taro/admin/prompts/defaults
       → Return only _defaults section

PUT    /api/v1/taro/admin/prompts/defaults
       Request: { "temperature": 0.8, "max_tokens": 2200, "timeout": 35 }
       → Update defaults

GET    /api/v1/taro/admin/prompts/{slug}
       → Return single prompt with resolved metadata (defaults merged)

PUT    /api/v1/taro/admin/prompts/{slug}
       Request: {
         "template": "...",
         "variables": [...],
         "temperature": 0.9,  // Optional override
         "max_tokens": 3000   // Optional override
       }
       → Update prompt (merge with defaults)

POST   /api/v1/taro/admin/prompts/reset
       → Reset all prompts to .dist defaults

POST   /api/v1/taro/admin/prompts/validate
       Request: { "template": "...", "variables": [...] }
       → Validate Handlebars syntax and variables
```

---

## Backend Implementation

### **Phase 1: Prompt Loader Service**

**File:** `vbwd-backend/plugins/taro/src/services/prompt_service.py`

```python
class PromptService:
    """Load, validate, and manage LLM prompts."""

    def __init__(self, prompts_file: str):
        self.prompts_file = prompts_file
        self.prompts = self._load_prompts()
        self.defaults = self.prompts.get('_defaults', {})

    def _load_prompts(self) -> dict:
        """Load prompts from JSON file. Raise error if missing."""
        if not os.path.exists(self.prompts_file):
            raise FileNotFoundError(
                f"Prompt file not found: {self.prompts_file}\n"
                f"Please ensure the file exists at {self.prompts_file}"
            )
        with open(self.prompts_file) as f:
            return json.load(f)

    def get_prompt(self, slug: str) -> dict:
        """Get prompt with resolved metadata (defaults merged)."""
        if slug.startswith('_'):
            raise ValueError(f"Cannot access internal prompt: {slug}")

        prompt = self.prompts.get(slug)
        if not prompt:
            raise ValueError(f"Prompt not found: {slug}")

        # Merge with defaults
        resolved = {**self.defaults}
        resolved.update(prompt)
        return resolved

    def render(self, slug: str, context: dict) -> str:
        """Render prompt template with context using Handlebars."""
        prompt = self.get_prompt(slug)
        template = prompt.get('template', '')

        # Use jinja2 for template rendering (Handlebars-like syntax)
        from jinja2 import Template
        try:
            t = Template(template)
            return t.render(context)
        except Exception as e:
            raise ValueError(f"Error rendering prompt '{slug}': {e}")

    def validate_template(self, template: str, variables: list) -> bool:
        """Validate template syntax and required variables."""
        from jinja2 import Template
        try:
            t = Template(template)
            # Check all variables are used
            # (basic validation - jinja2 doesn't fail on unused vars)
            return True
        except Exception as e:
            raise ValueError(f"Invalid template: {e}")

    def update_prompt(self, slug: str, data: dict) -> dict:
        """Update a prompt (template + optional metadata overrides)."""
        if slug.startswith('_'):
            raise ValueError(f"Cannot modify internal prompt: {slug}")

        prompt = self.prompts.get(slug, {})
        prompt.update(data)
        self.prompts[slug] = prompt
        self._save_prompts()

        return self.get_prompt(slug)

    def update_defaults(self, defaults: dict) -> dict:
        """Update default metadata."""
        self.defaults.update(defaults)
        self.prompts['_defaults'] = self.defaults
        self._save_prompts()
        return self.defaults

    def reset_to_defaults(self) -> None:
        """Reset all prompts to .dist defaults."""
        dist_file = self.prompts_file.replace('.json', '.json.dist')
        if not os.path.exists(dist_file):
            raise FileNotFoundError(f"Distribution file not found: {dist_file}")

        with open(dist_file) as f:
            self.prompts = json.load(f)
        self._save_prompts()

    def _save_prompts(self) -> None:
        """Save prompts to JSON file."""
        with open(self.prompts_file, 'w') as f:
            json.dump(self.prompts, f, indent=2)
```

### **Phase 2: Admin Routes**

**File:** `vbwd-backend/plugins/taro/src/routes.py` (Add to existing file)

```python
# Add to routes with @require_admin decorator

@taro_bp.route("/admin/prompts", methods=["GET"])
@require_auth
@require_admin
def get_all_prompts():
    """Get all prompts with resolved metadata."""
    try:
        prompt_service = _get_prompt_service()
        prompts = {}
        for slug, prompt in prompt_service.prompts.items():
            if not slug.startswith('_'):
                prompts[slug] = prompt_service.get_prompt(slug)

        return jsonify({
            "success": True,
            "prompts": prompts,
            "defaults": prompt_service.defaults
        }), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@taro_bp.route("/admin/prompts/defaults", methods=["GET"])
@require_auth
@require_admin
def get_prompt_defaults():
    """Get default metadata."""
    try:
        prompt_service = _get_prompt_service()
        return jsonify({
            "success": True,
            "defaults": prompt_service.defaults
        }), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@taro_bp.route("/admin/prompts/defaults", methods=["PUT"])
@require_auth
@require_admin
def update_prompt_defaults():
    """Update default metadata."""
    try:
        data = request.get_json() or {}
        prompt_service = _get_prompt_service()

        # Validate metadata fields
        allowed_keys = {'temperature', 'max_tokens', 'timeout'}
        data = {k: v for k, v in data.items() if k in allowed_keys}

        defaults = prompt_service.update_defaults(data)
        return jsonify({
            "success": True,
            "defaults": defaults
        }), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 400

@taro_bp.route("/admin/prompts/<slug>", methods=["GET"])
@require_auth
@require_admin
def get_prompt(slug):
    """Get single prompt."""
    try:
        prompt_service = _get_prompt_service()
        prompt = prompt_service.get_prompt(slug)
        return jsonify({
            "success": True,
            "prompt": prompt
        }), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 404

@taro_bp.route("/admin/prompts/<slug>", methods=["PUT"])
@require_auth
@require_admin
def update_prompt(slug):
    """Update a prompt."""
    try:
        data = request.get_json() or {}
        prompt_service = _get_prompt_service()

        # Validate template if provided
        if 'template' in data:
            variables = data.get('variables', [])
            prompt_service.validate_template(data['template'], variables)

        # Only allow specific fields
        allowed_keys = {'template', 'variables', 'temperature', 'max_tokens', 'timeout'}
        data = {k: v for k, v in data.items() if k in allowed_keys}

        updated = prompt_service.update_prompt(slug, data)
        return jsonify({
            "success": True,
            "prompt": updated
        }), 200
    except ValueError as e:
        return jsonify({"success": False, "error": str(e)}), 400
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@taro_bp.route("/admin/prompts/reset", methods=["POST"])
@require_auth
@require_admin
def reset_prompts():
    """Reset all prompts to defaults."""
    try:
        prompt_service = _get_prompt_service()
        prompt_service.reset_to_defaults()
        return jsonify({
            "success": True,
            "message": "Prompts reset to defaults"
        }), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 400

@taro_bp.route("/admin/prompts/validate", methods=["POST"])
@require_auth
@require_admin
def validate_prompt():
    """Validate prompt template syntax."""
    try:
        data = request.get_json() or {}
        template = data.get('template', '')
        variables = data.get('variables', [])

        prompt_service = _get_prompt_service()
        prompt_service.validate_template(template, variables)

        return jsonify({
            "success": True,
            "message": "Template is valid"
        }), 200
    except ValueError as e:
        return jsonify({"success": False, "error": str(e)}), 400
```

### **Phase 3: Service Integration**

**File:** `vbwd-backend/plugins/taro/src/services/taro_session_service.py` (Modify existing)

```python
class TaroSessionService:
    def __init__(
        self,
        arcana_repo: ArcanaRepository,
        session_repo: TaroSessionRepository,
        card_draw_repo: TaroCardDrawRepository,
        prompt_service: PromptService,  # NEW
        llm_adapter: Optional[LLMAdapter] = None,
    ):
        self.arcana_repo = arcana_repo
        self.session_repo = session_repo
        self.card_draw_repo = card_draw_repo
        self.prompt_service = prompt_service  # NEW
        self.llm_adapter = llm_adapter

    def _generate_card_interpretation(self, arcana, position, orientation) -> str:
        """Use prompt_service to render card interpretation."""
        if self.llm_adapter:
            try:
                meaning = (
                    arcana.upright_meaning
                    if orientation == CardOrientation.UPRIGHT
                    else arcana.reversed_meaning
                )

                # Render prompt with context
                prompt = self.prompt_service.render('card_interpretation', {
                    'card_name': arcana.name,
                    'orientation': orientation.value,
                    'position': position.value,
                    'base_meaning': meaning,
                    'position_context': self._get_position_context(position)
                })

                response = self.llm_adapter.chat(
                    messages=[{"role": "user", "content": prompt}]
                )
                if response:
                    return response.strip()
            except Exception as e:
                logger.warning(f"Error generating interpretation: {e}")

        # Fallback
        return f"{arcana.name}: {meaning}"

    def generate_situation_reading(self, session_id: str, situation_text: str) -> str:
        """Use prompt_service for situation reading."""
        # ... validation code ...

        if self.llm_adapter:
            try:
                cards_context = self._build_cards_context(cards)

                # Render prompt
                prompt = self.prompt_service.render('situation_reading', {
                    'situation_text': situation_text,
                    'cards_context': cards_context
                })

                # Get metadata (includes temperature, max_tokens, etc.)
                prompt_meta = self.prompt_service.get_prompt('situation_reading')

                response = self.llm_adapter.chat(
                    messages=[{"role": "user", "content": prompt}],
                    temperature=prompt_meta.get('temperature', 0.7),
                    max_tokens=prompt_meta.get('max_tokens', 2000)
                )
                # ... rest of method ...
```

---

## Frontend Admin Implementation

### **Admin Component: TaroPrompts.vue**

**File:** `vbwd-frontend/admin/vue/src/views/TaroPrompts.vue` (NEW)

```vue
<template>
  <div class="taro-prompts-page">
    <h1>Taro Oracle Prompts</h1>

    <!-- Tabs -->
    <div class="tabs">
      <button
        :class="['tab', { active: activeTab === 'defaults' }]"
        @click="activeTab = 'defaults'"
      >
        Metadata Defaults
      </button>
      <button
        :class="['tab', { active: activeTab === 'prompts' }]"
        @click="activeTab = 'prompts'"
      >
        Prompts List
      </button>
    </div>

    <!-- Tab 1: Defaults -->
    <div v-if="activeTab === 'defaults'" class="tab-content defaults-tab">
      <h2>Default Metadata</h2>
      <form @submit.prevent="saveDefaults">
        <div class="form-group">
          <label>Temperature (0.0 - 1.0)</label>
          <input
            v-model.number="defaults.temperature"
            type="number"
            min="0"
            max="1"
            step="0.1"
          />
        </div>
        <div class="form-group">
          <label>Max Tokens</label>
          <input
            v-model.number="defaults.max_tokens"
            type="number"
            min="100"
          />
        </div>
        <div class="form-group">
          <label>Timeout (seconds)</label>
          <input
            v-model.number="defaults.timeout"
            type="number"
            min="5"
          />
        </div>
        <button type="submit" class="btn btn-primary">Save Defaults</button>
        <button
          type="button"
          class="btn btn-danger"
          @click="resetToDefaults"
        >
          Reset All Prompts to Defaults
        </button>
      </form>
    </div>

    <!-- Tab 2: Prompts -->
    <div v-if="activeTab === 'prompts'" class="tab-content prompts-tab">
      <h2>Prompts</h2>
      <div class="prompts-list">
        <div
          v-for="(prompt, slug) in prompts"
          :key="slug"
          :class="['prompt-item', { expanded: expandedPrompt === slug }]"
        >
          <div
            class="prompt-header"
            @click="expandedPrompt = expandedPrompt === slug ? null : slug"
          >
            <span class="slug">{{ slug }}</span>
            <span class="icon">{{ expandedPrompt === slug ? '▼' : '▶' }}</span>
          </div>

          <div v-if="expandedPrompt === slug" class="prompt-editor">
            <!-- Template -->
            <div class="form-group">
              <label>Template (Handlebars)</label>
              <textarea
                v-model="editingPrompt.template"
                rows="8"
                class="template-textarea"
              />
            </div>

            <!-- Variables -->
            <div class="form-group">
              <label>Variables</label>
              <div class="variables-list">
                <span
                  v-for="(v, i) in editingPrompt.variables"
                  :key="i"
                  class="variable-tag"
                >
                  {{ v }}
                </span>
              </div>
            </div>

            <!-- Metadata Overrides -->
            <div class="form-group">
              <label>Metadata Overrides (optional)</label>
              <div class="override-inputs">
                <input
                  v-model.number="editingPrompt.temperature"
                  type="number"
                  min="0"
                  max="1"
                  step="0.1"
                  placeholder="Temperature"
                />
                <input
                  v-model.number="editingPrompt.max_tokens"
                  type="number"
                  placeholder="Max Tokens"
                />
                <input
                  v-model.number="editingPrompt.timeout"
                  type="number"
                  placeholder="Timeout"
                />
              </div>
            </div>

            <!-- Buttons -->
            <div class="form-actions">
              <button
                @click="savePrompt(slug)"
                class="btn btn-primary"
              >
                Save
              </button>
              <button
                @click="discardChanges"
                class="btn btn-secondary"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { api } from '@/api';

const activeTab = ref('defaults');
const defaults = ref({
  temperature: 0.7,
  max_tokens: 2000,
  timeout: 30
});
const prompts = ref({});
const expandedPrompt = ref<string | null>(null);
const editingPrompt = ref({});

onMounted(async () => {
  await loadPrompts();
});

async function loadPrompts() {
  try {
    const response = await api.get('/taro/admin/prompts');
    prompts.value = response.prompts;
    defaults.value = response.defaults;
  } catch (error) {
    console.error('Failed to load prompts:', error);
  }
}

async function saveDefaults() {
  try {
    await api.put('/taro/admin/prompts/defaults', defaults.value);
    alert('Defaults saved');
  } catch (error) {
    console.error('Failed to save defaults:', error);
  }
}

async function savePrompt(slug: string) {
  try {
    await api.put(`/taro/admin/prompts/${slug}`, editingPrompt.value);
    await loadPrompts();
    expandedPrompt.value = null;
    alert('Prompt saved');
  } catch (error) {
    console.error('Failed to save prompt:', error);
  }
}

function discardChanges() {
  expandedPrompt.value = null;
  editingPrompt.value = {};
}

async function resetToDefaults() {
  if (confirm('Reset all prompts to defaults? This cannot be undone.')) {
    try {
      await api.post('/taro/admin/prompts/reset');
      await loadPrompts();
      alert('Prompts reset to defaults');
    } catch (error) {
      console.error('Failed to reset prompts:', error);
    }
  }
}
</script>

<style scoped>
/* Tab styling */
.tabs {
  display: flex;
  gap: 1rem;
  margin-bottom: 2rem;
  border-bottom: 1px solid var(--color-border);
}

.tab {
  padding: 0.75rem 1.5rem;
  background: none;
  border: none;
  cursor: pointer;
  color: var(--color-text-secondary);
  border-bottom: 2px solid transparent;
}

.tab.active {
  color: var(--color-primary);
  border-bottom-color: var(--color-primary);
}

.tab-content {
  padding: 2rem 0;
}

/* Prompts list */
.prompts-list {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.prompt-item {
  border: 1px solid var(--color-border);
  border-radius: 0.5rem;
  overflow: hidden;
}

.prompt-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 1rem;
  background: var(--color-background-secondary);
  cursor: pointer;
}

.prompt-header:hover {
  background: var(--color-background);
}

.slug {
  font-weight: 600;
  font-family: monospace;
}

.prompt-editor {
  padding: 1.5rem;
  border-top: 1px solid var(--color-border);
}

.form-group {
  margin-bottom: 1.5rem;
}

.form-group label {
  display: block;
  margin-bottom: 0.5rem;
  font-weight: 600;
}

.template-textarea {
  width: 100%;
  font-family: monospace;
  padding: 0.75rem;
  border: 1px solid var(--color-border);
  border-radius: 0.25rem;
}

.variables-list {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.variable-tag {
  background: var(--color-primary-light);
  padding: 0.25rem 0.75rem;
  border-radius: 1rem;
  font-size: 0.85rem;
  font-family: monospace;
}

.override-inputs {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 1rem;
}

.override-inputs input {
  padding: 0.5rem;
  border: 1px solid var(--color-border);
  border-radius: 0.25rem;
}

.form-actions {
  display: flex;
  gap: 1rem;
  margin-top: 1rem;
}

.btn {
  padding: 0.75rem 1.5rem;
  border: none;
  border-radius: 0.25rem;
  cursor: pointer;
  font-weight: 600;
}

.btn-primary {
  background: var(--color-primary);
  color: white;
}

.btn-secondary {
  background: var(--color-background-secondary);
  color: var(--color-text-primary);
}

.btn-danger {
  background: var(--color-danger);
  color: white;
}
</style>
```

---

## Implementation Order (Strict TDD)

### **Phase 1: Core Service (No UI Yet)**

1. **Create `prompts.json.dist`** - Default prompts only
   - No code yet, just data
   - Use as reference for tests

2. **Write failing unit tests** for PromptService
   ```python
   test_load_prompts_success()
   test_load_prompts_missing_file_error()
   test_get_prompt_merges_defaults()
   test_render_with_context()
   test_validate_template_syntax()
   test_update_prompt()
   test_save_persists_to_file()
   ```
   - Tests should define the API (what methods exist, what they return)
   - Red phase: All tests fail (class doesn't exist yet)

3. **Implement PromptService** - Make tests pass
   - `__init__(prompts_file)`
   - `_load_prompts()`
   - `get_prompt(slug) -> dict`
   - `render(slug, context) -> str`
   - `validate_template(template, variables) -> bool`
   - `update_prompt(slug, data) -> dict`
   - `update_defaults(defaults) -> dict`
   - `reset_to_defaults()`
   - `_save_prompts()`
   - All tests pass (Green phase)
   - Refactor for cleaner code (Refactor phase)

4. **Write integration tests**
   - File I/O (loading, saving)
   - Template rendering with real Jinja2
   - Round-trip: load → render → save → reload

### **Phase 2: Admin API (Routes)**

5. **Write failing route tests**
   ```python
   test_get_all_prompts_admin_only()
   test_update_prompt_validation()
   test_reset_to_defaults_confirmation()
   test_invalid_slug_returns_404()
   ```

6. **Implement admin routes** - Make tests pass
   - GET /taro/admin/prompts
   - GET /taro/admin/prompts/defaults
   - PUT /taro/admin/prompts/defaults
   - GET /taro/admin/prompts/{slug}
   - PUT /taro/admin/prompts/{slug}
   - POST /taro/admin/prompts/reset
   - POST /taro/admin/prompts/validate

### **Phase 3: Admin UI**

7. **Implement admin UI** (TaroPrompts.vue)
   - Two-tab layout (Defaults | Prompts)
   - Wire to API endpoints
   - Edit template + metadata
   - Save/Reset buttons

### **Phase 4: Service Integration**

8. **Update TaroSessionService**
   - Inject PromptService via DI
   - Replace hardcoded prompts with `prompt_service.render(slug, context)`
   - Remove ALL old prompt code (no dead code)

### **Phase 5: Frontend User Changes**

9. **Update Taro.vue**
   - Remove card interpretation block (show only after all cards open)
   - Add second button: "Tell More About Cards"
   - Wire to new `card_explanation` prompt path

10. **Write E2E tests** - Full user flows
    - Card reveal → Oracle dialog → Ask about cards
    - Card reveal → Oracle dialog → Enter situation

### **Phase 6: Cleanup**

11. **Remove all dead code**
    - No leftover hardcoded prompts
    - No unused prompt methods
    - No commented-out code

---

## TDD Rules for This Sprint

- ✅ **Write test first** - Every method needs a failing test before implementation
- ✅ **One test = one behavior** - Not one test for entire class
- ✅ **Mock external dependencies** - Mock Jinja2, file I/O in unit tests
- ✅ **Green bar before moving on** - All tests must pass before next phase
- ✅ **No implementation details in tests** - Test *what*, not *how*

---

## Critical Files Checklist

- [ ] `/vbwd-backend/plugins/taro/prompts.json.dist` (NEW)
- [ ] `/vbwd-backend/plugins/taro-prompts.json` (runtime, gitignored)
- [ ] `plugins/taro/src/services/prompt_service.py` (NEW)
- [ ] `plugins/taro/src/routes.py` (ADD admin endpoints)
- [ ] `plugins/taro/src/services/taro_session_service.py` (MODIFY - use PromptService)
- [ ] `/vbwd-frontend/admin/vue/src/views/TaroPrompts.vue` (NEW)
- [ ] `/vbwd-frontend/admin/vue/src/router/index.ts` (ADD route)
- [ ] `vbwd-frontend/user/plugins/taro/src/Taro.vue` (MODIFY - two buttons, remove interpretation block)
- [ ] Tests (unit + e2e)

---

## Next Steps

**Ready to proceed with implementation?**

1. Confirm this sprint is correct
2. Ask any questions
3. Start with Phase 1 implementation

**Or should I clarify anything?**
