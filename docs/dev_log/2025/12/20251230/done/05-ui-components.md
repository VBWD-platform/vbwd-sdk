# Sprint 5: View Core Extraction & UI Components

**Priority:** HIGH
**Duration:** 3-4 days
**Focus:** Extract shared view core to separate repo, create UI component library

> **Core Requirements:** See [sprint-plan.md](./sprint-plan.md) for mandatory TDD-first, SOLID, DI, Clean Code, and No Over-Engineering requirements.

---

## Problem Statement

Both `frontend/user` and `frontend/admin` need to share a common ancestor package for:
- UI components (buttons, inputs, modals, etc.)
- API client
- Event bus
- Plugin system
- Composables and utilities

Currently, `vbwd-frontend/core` exists within the monorepo but should be extracted to a **separate repository** for better:
- Version management
- Independent releases
- Reusability across projects
- Clear dependency boundaries

**Reference Architecture:** See `/docs/architecture_core_view_sdk/` for the complete vision.

---

## 5.0 Extract Core to Separate Repository (CRITICAL - DO FIRST)

### Problem
The core SDK is tightly coupled to the monorepo. It should be an independent, versionable package.

### Goal
Create `vbwd/view-component` (or `@vbwd/view-component`) as a separate GitHub repository that both `frontend/user` and `frontend/admin` depend on.

### Steps

#### 5.0.1 Create New Repository

```bash
# Create new repo: vbwd/view-component (or vbwd-view-core)
# Initialize with:
gh repo create vbwd/view-component --public --description "Shared Vue 3 component library for VBWD applications"
```

#### 5.0.2 Repository Structure

```
vbwd-view-component/
├── package.json                    # @vbwd/view-component
├── tsconfig.json
├── vite.config.ts
├── vitest.config.ts
├── README.md
├── CHANGELOG.md
│
├── src/
│   ├── index.ts                    # Main exports
│   │
│   ├── components/                 # UI Components
│   │   ├── ui/
│   │   │   ├── Button.vue
│   │   │   ├── Input.vue
│   │   │   ├── Modal.vue
│   │   │   ├── Card.vue
│   │   │   ├── Badge.vue
│   │   │   ├── Alert.vue
│   │   │   ├── Spinner.vue
│   │   │   ├── Table.vue
│   │   │   ├── Pagination.vue
│   │   │   └── Dropdown.vue
│   │   ├── forms/
│   │   │   ├── FormField.vue
│   │   │   ├── FormGroup.vue
│   │   │   └── FormError.vue
│   │   ├── layout/
│   │   │   ├── Container.vue
│   │   │   ├── Row.vue
│   │   │   └── Col.vue
│   │   └── index.ts
│   │
│   ├── plugins/                    # Plugin System
│   │   ├── PluginRegistry.ts
│   │   ├── PlatformSDK.ts
│   │   ├── types.ts
│   │   └── index.ts
│   │
│   ├── api/                        # API Client
│   │   ├── ApiClient.ts
│   │   ├── errors.ts
│   │   ├── types.ts
│   │   └── index.ts
│   │
│   ├── events/                     # Event Bus
│   │   ├── EventBus.ts
│   │   ├── events.ts
│   │   └── index.ts
│   │
│   ├── composables/                # Vue Composables
│   │   ├── useApi.ts
│   │   ├── useAuth.ts
│   │   ├── useForm.ts
│   │   ├── useNotification.ts
│   │   └── index.ts
│   │
│   ├── utils/                      # Utilities
│   │   ├── format.ts
│   │   ├── date.ts
│   │   ├── storage.ts
│   │   └── index.ts
│   │
│   └── styles/                     # Base Styles
│       ├── variables.css
│       ├── reset.css
│       └── index.css
│
├── tests/
│   ├── unit/
│   │   ├── components/
│   │   ├── plugins/
│   │   ├── api/
│   │   └── events/
│   └── setup.ts
│
└── .github/
    └── workflows/
        ├── test.yml
        ├── release.yml
        └── npm-publish.yml
```

#### 5.0.3 Package Configuration

**package.json:**
```json
{
  "name": "@vbwd/view-component",
  "version": "0.1.0",
  "description": "Shared Vue 3 component library and SDK for VBWD applications",
  "type": "module",
  "main": "./dist/index.cjs",
  "module": "./dist/index.mjs",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "import": "./dist/index.mjs",
      "require": "./dist/index.cjs",
      "types": "./dist/index.d.ts"
    },
    "./components": {
      "import": "./dist/components/index.mjs",
      "types": "./dist/components/index.d.ts"
    },
    "./styles": {
      "import": "./dist/styles/index.css"
    }
  },
  "files": ["dist"],
  "scripts": {
    "dev": "vite",
    "build": "vite build && vue-tsc --emitDeclarationOnly",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage",
    "lint": "eslint src tests --ext .ts,.vue",
    "format": "prettier --write \"src/**/*.{ts,vue}\"",
    "prepublishOnly": "npm run build && npm run test"
  },
  "peerDependencies": {
    "vue": "^3.4.0",
    "vue-router": "^4.0.0",
    "pinia": "^2.0.0"
  },
  "dependencies": {
    "axios": "^1.6.0",
    "zod": "^3.22.0"
  },
  "devDependencies": {
    "@vitejs/plugin-vue": "^5.0.0",
    "@vue/test-utils": "^2.4.0",
    "typescript": "^5.3.0",
    "vite": "^5.0.0",
    "vitest": "^1.0.0",
    "vue": "^3.4.0",
    "vue-tsc": "^1.8.0"
  },
  "repository": {
    "type": "git",
    "url": "https://github.com/vbwd/view-component.git"
  },
  "keywords": ["vue", "components", "vbwd", "sdk", "typescript"],
  "license": "BSL-1.1"
}
```

#### 5.0.4 Migration Steps

1. **Create new repository:**
   ```bash
   # Create vbwd/view-component repo on GitHub
   gh repo create vbwd/view-component --public
   cd /tmp && git clone https://github.com/vbwd/view-component.git
   ```

2. **Copy and adapt current core:**
   ```bash
   # Copy from current monorepo
   cp -r vbwd-sdk/vbwd-frontend/core/* /tmp/view-component/

   # Update package.json name to @vbwd/view-component
   # Update imports to use relative paths
   # Add component library structure
   ```

3. **Initial publish (GitHub Packages or npm):**
   ```bash
   cd /tmp/view-component
   npm publish --access public
   ```

4. **Update frontend/user and frontend/admin:**
   ```json
   // frontend/user/vue/package.json
   {
     "dependencies": {
       "@vbwd/view-component": "^0.1.0"
     }
   }

   // frontend/admin/vue/package.json
   {
     "dependencies": {
       "@vbwd/view-component": "^0.1.0"
     }
   }
   ```

5. **Update imports:**
   ```typescript
   // Before (monorepo path)
   import { EventBus, ApiClient } from '@vbwd/core-sdk';

   // After (external package)
   import { EventBus, ApiClient } from '@vbwd/view-component';
   import { Button, Input, Modal } from '@vbwd/view-component/components';
   ```

6. **Remove old core from monorepo:**
   ```bash
   # After confirming everything works
   rm -rf vbwd-sdk/vbwd-frontend/core
   ```

### Acceptance Criteria
- [ ] New repository `vbwd/view-component` created
- [ ] Package published to npm as `@vbwd/view-component`
- [ ] Both frontend apps install and use the external package
- [ ] All existing tests pass
- [ ] CI/CD pipeline for the new repo

---

## 5.1 Create UI Component Library

### Problem
After extraction, the component library needs to be built out with common UI components.

### Components to Create

| Component | Priority | Description |
|-----------|----------|-------------|
| Button | HIGH | Primary, secondary, danger, ghost, link variants |
| Input | HIGH | Text, password, email with validation |
| Modal | HIGH | Dialog with header, body, footer slots |
| Card | HIGH | Container with header and content |
| Alert | HIGH | Success, error, warning, info messages |
| Spinner | HIGH | Loading indicator |
| Badge | MEDIUM | Status indicators |
| Table | MEDIUM | Data table with sorting |
| Pagination | MEDIUM | Page navigation |
| Dropdown | MEDIUM | Select menu |
| FormField | MEDIUM | Input wrapper with label/error |
| FormGroup | LOW | Group of form fields |

### Implementation Standards

1. **TypeScript:** Full type coverage
2. **Props:** Typed with defaults
3. **Events:** Typed emit definitions
4. **Slots:** Named slots for flexibility
5. **CSS Variables:** Themeable via CSS custom properties
6. **Accessibility:** ARIA attributes, keyboard navigation

### Example: Button Component

**File:** `src/components/ui/Button.vue`
```vue
<template>
  <button
    :type="type"
    :class="buttonClasses"
    :disabled="disabled || loading"
    @click="$emit('click', $event)"
  >
    <Spinner v-if="loading" class="btn-spinner" />
    <slot />
  </button>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import Spinner from './Spinner.vue';

type ButtonVariant = 'primary' | 'secondary' | 'danger' | 'ghost' | 'link';
type ButtonSize = 'sm' | 'md' | 'lg';

const props = withDefaults(defineProps<{
  type?: 'button' | 'submit' | 'reset';
  variant?: ButtonVariant;
  size?: ButtonSize;
  disabled?: boolean;
  loading?: boolean;
  block?: boolean;
}>(), {
  type: 'button',
  variant: 'primary',
  size: 'md',
});

defineEmits<{
  click: [event: MouseEvent];
}>();

const buttonClasses = computed(() => [
  'vbwd-btn',
  `vbwd-btn-${props.variant}`,
  `vbwd-btn-${props.size}`,
  { 'vbwd-btn-block': props.block, 'vbwd-btn-loading': props.loading }
]);
</script>

<style scoped>
.vbwd-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  padding: var(--vbwd-btn-padding-y, 0.5rem) var(--vbwd-btn-padding-x, 1rem);
  font-size: var(--vbwd-btn-font-size, 1rem);
  font-weight: 500;
  border-radius: var(--vbwd-btn-radius, 0.375rem);
  border: 1px solid transparent;
  cursor: pointer;
  transition: all 0.15s ease-in-out;
}

.vbwd-btn-primary {
  background-color: var(--vbwd-color-primary, #3b82f6);
  color: white;
}

.vbwd-btn-primary:hover:not(:disabled) {
  background-color: var(--vbwd-color-primary-dark, #2563eb);
}

.vbwd-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
</style>
```

---

## 5.2 Update Frontend Apps

### Problem
After core extraction, both apps need to be updated to use the external package.

### Steps for frontend/user

1. **Install dependency:**
   ```bash
   cd vbwd-frontend/user/vue
   npm install @vbwd/view-component
   ```

2. **Update main.ts:**
   ```typescript
   import { createApp } from 'vue';
   import { createPinia } from 'pinia';
   import App from './App.vue';
   import router from './router';

   // Import from external package
   import {
     eventBus,
     ApiClient,
     Button,
     Input,
     Modal
   } from '@vbwd/view-component';

   const app = createApp(App);

   // Register global components
   app.component('VButton', Button);
   app.component('VInput', Input);
   app.component('VModal', Modal);

   app.use(createPinia());
   app.use(router);
   app.mount('#app');
   ```

3. **Update existing imports throughout the app**

### Steps for frontend/admin

Same as user app with admin-specific configurations.

---

## 5.3 Component Documentation (Optional)

### Options

1. **Storybook** - Visual component explorer
2. **VitePress** - Documentation site
3. **README with examples** - Minimal approach

### Recommendation
Start with README examples in the new repo. Add Storybook later if needed.

---

## Checklist

### 5.0 Repository Extraction (CRITICAL)
- [ ] Create `vbwd/view-component` GitHub repository
- [ ] Set up package.json with @vbwd/view-component name
- [ ] Copy existing core code (plugins, api, events)
- [ ] Set up build configuration (Vite)
- [ ] Set up test configuration (Vitest)
- [ ] Add CI/CD workflow (.github/workflows)
- [ ] Publish initial version to npm
- [ ] Update frontend/user to use external package
- [ ] Update frontend/admin to use external package
- [ ] Verify all existing functionality works
- [ ] Remove old core from monorepo (optional, can keep as reference)

### 5.1 UI Components
- [ ] Button component with variants
- [ ] Input component with validation
- [ ] Modal component with slots
- [ ] Card component
- [ ] Alert component
- [ ] Spinner component
- [ ] Badge component
- [ ] Table component
- [ ] Pagination component
- [ ] Dropdown component
- [ ] Form components (FormField, FormGroup, FormError)
- [ ] Layout components (Container, Row, Col)
- [ ] Component exports from index.ts
- [ ] CSS variables for theming

### 5.2 App Updates
- [ ] frontend/user installs @vbwd/view-component
- [ ] frontend/admin installs @vbwd/view-component
- [ ] All imports updated
- [ ] Components registered globally
- [ ] Tests pass

### 5.3 Documentation
- [ ] README with installation instructions
- [ ] Component API documentation
- [ ] Usage examples
- [ ] CHANGELOG.md

---

## Verification Commands

```bash
# In new view-component repo
npm run build
npm run test
npm publish --dry-run

# In frontend/user
npm install @vbwd/view-component
npm run dev
npm run test

# In frontend/admin
npm install @vbwd/view-component
npm run dev
npm run test

# Verify imports work
grep -r "@vbwd/view-component" vbwd-frontend/user/
grep -r "@vbwd/view-component" vbwd-frontend/admin/
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub / npm Registry                     │
│                                                              │
│   ┌─────────────────────────────────────────────────────┐   │
│   │              vbwd/view-component                     │   │
│   │              @vbwd/view-component                         │   │
│   │                                                      │   │
│   │   ┌──────────┐ ┌──────────┐ ┌──────────┐           │   │
│   │   │Components│ │ Plugins  │ │   API    │           │   │
│   │   └──────────┘ └──────────┘ └──────────┘           │   │
│   │   ┌──────────┐ ┌──────────┐ ┌──────────┐           │   │
│   │   │  Events  │ │Composable│ │  Utils   │           │   │
│   │   └──────────┘ └──────────┘ └──────────┘           │   │
│   └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ npm install @vbwd/view-component
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    vbwd-sdk Monorepo                         │
│                                                              │
│   ┌────────────────────┐      ┌────────────────────┐        │
│   │   vbwd-frontend/   │      │   vbwd-frontend/   │        │
│   │      user/vue      │      │     admin/vue      │        │
│   │                    │      │                    │        │
│   │ Uses @vbwd/view-   │      │ Uses @vbwd/view-   │        │
│   │ core components    │      │ core components    │        │
│   │                    │      │                    │        │
│   │ + User plugins     │      │ + Admin plugins    │        │
│   │ + User views       │      │ + Admin views      │        │
│   └────────────────────┘      └────────────────────┘        │
│                                                              │
│   ┌────────────────────────────────────────────────┐        │
│   │              vbwd-backend/                      │        │
│   │              Flask API Server                   │        │
│   └────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

---

## Related Documentation

- [Core View SDK Architecture](/docs/architecture_core_view_sdk/README.md)
- [Sprint Plan](/docs/devlog/20251230/todo/sprint-plan.md)
