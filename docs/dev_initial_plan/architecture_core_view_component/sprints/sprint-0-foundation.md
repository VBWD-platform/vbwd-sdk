# Sprint 0: Core SDK Foundation

**Duration:** 1 week
**Goal:** Setup Core SDK project structure and build system
**Dependencies:** None

---

## Objectives

- [ ] Initialize Core SDK project with TypeScript + Vite
- [ ] Configure package.json for library build
- [ ] Setup build pipeline (ESM + CommonJS)
- [ ] Configure testing infrastructure (Vitest)
- [ ] Setup linting and formatting (ESLint + Prettier)
- [ ] Configure TypeScript strict mode
- [ ] Create initial directory structure
- [ ] Setup CI/CD pipeline (GitHub Actions)

---

## Tasks

### 1. Project Initialization

```bash
# Create Core SDK directory
mkdir -p frontend/core
cd frontend/core

# Initialize npm package
npm init -y

# Install dependencies
npm install vue@3 vue-router@4 pinia@2 axios@1 zod@3

# Install dev dependencies
npm install -D \
  typescript@5 \
  vite@5 \
  vitest \
  @vue/test-utils \
  happy-dom \
  eslint \
  @typescript-eslint/parser \
  @typescript-eslint/eslint-plugin \
  prettier \
  eslint-config-prettier \
  eslint-plugin-vue \
  @vitejs/plugin-vue \
  typedoc
```

### 2. Package.json Configuration

**File:** `frontend/core/package.json`

```json
{
  "name": "@vbwd/core-sdk",
  "version": "0.1.0",
  "description": "VBWD Core SDK - Shared plugin system for User and Admin applications",
  "type": "module",
  "main": "./dist/core-sdk.cjs",
  "module": "./dist/core-sdk.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "import": "./dist/core-sdk.js",
      "require": "./dist/core-sdk.cjs",
      "types": "./dist/index.d.ts"
    }
  },
  "files": [
    "dist"
  ],
  "scripts": {
    "dev": "vite build --watch",
    "build": "tsc && vite build",
    "test:unit": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage",
    "lint": "eslint src --ext .ts,.vue",
    "lint:fix": "eslint src --ext .ts,.vue --fix",
    "format": "prettier --write \"src/**/*.{ts,vue,json}\"",
    "format:check": "prettier --check \"src/**/*.{ts,vue,json}\"",
    "typecheck": "tsc --noEmit",
    "docs": "typedoc src/index.ts"
  },
  "keywords": [
    "vbwd",
    "plugin-system",
    "vue",
    "typescript"
  ],
  "author": "VBWD Team",
  "license": "BSL-1.1",
  "peerDependencies": {
    "vue": "^3.4.0",
    "vue-router": "^4.0.0",
    "pinia": "^2.0.0"
  }
}
```

### 3. TypeScript Configuration

**File:** `frontend/core/tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "allowImportingTsExtensions": true,
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedIndexedAccess": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "outDir": "./dist",
    "skipLibCheck": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "forceConsistentCasingInFileNames": true,
    "isolatedModules": true,
    "jsx": "preserve"
  },
  "include": ["src/**/*.ts", "src/**/*.vue"],
  "exclude": ["node_modules", "dist", "__tests__"]
}
```

### 4. Vite Configuration

**File:** `frontend/core/vite.config.ts`

```typescript
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { resolve } from 'path';

export default defineConfig({
  plugins: [vue()],
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      name: 'VbwdCoreSDK',
      formats: ['es', 'cjs'],
      fileName: (format) => `core-sdk.${format === 'es' ? 'js' : 'cjs'}`,
    },
    rollupOptions: {
      external: ['vue', 'vue-router', 'pinia', 'axios', 'zod'],
      output: {
        globals: {
          vue: 'Vue',
          'vue-router': 'VueRouter',
          pinia: 'Pinia',
          axios: 'axios',
          zod: 'zod',
        },
      },
    },
  },
  test: {
    globals: true,
    environment: 'happy-dom',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      lines: 95,
      functions: 95,
      branches: 95,
      statements: 95,
    },
  },
});
```

### 5. ESLint Configuration

**File:** `frontend/core/.eslintrc.cjs`

```javascript
module.exports = {
  root: true,
  env: {
    node: true,
    es2021: true,
  },
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
    'plugin:@typescript-eslint/recommended-requiring-type-checking',
    'plugin:vue/vue3-recommended',
    'prettier',
  ],
  parser: '@typescript-eslint/parser',
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module',
    project: './tsconfig.json',
  },
  plugins: ['@typescript-eslint', 'vue'],
  rules: {
    '@typescript-eslint/no-explicit-any': 'error',
    '@typescript-eslint/explicit-function-return-type': 'warn',
    '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    'vue/multi-word-component-names': 'off',
  },
};
```

### 6. Prettier Configuration

**File:** `frontend/core/.prettierrc.json`

```json
{
  "semi": true,
  "singleQuote": true,
  "tabWidth": 2,
  "trailingComma": "es5",
  "printWidth": 100,
  "arrowParens": "always"
}
```

### 7. Directory Structure

```bash
mkdir -p src/{plugin,api,auth,events,validation,access,sdk,components,composables,utils,types}
mkdir -p __tests__/{unit,integration}
mkdir -p docs
```

**File:** `frontend/core/src/index.ts`

```typescript
// Core SDK Entry Point
export * from './plugin';
export * from './api';
export * from './auth';
export * from './events';
export * from './validation';
export * from './access';
export * from './sdk';
export * from './components';
export * from './composables';
export * from './utils';
export * from './types';
```

### 8. Placeholder Files

Create empty barrel exports for each module:

**File:** `frontend/core/src/plugin/index.ts`
```typescript
// Plugin System (Sprint 1)
export {};
```

**File:** `frontend/core/src/api/index.ts`
```typescript
// API Client (Sprint 2)
export {};
```

**File:** `frontend/core/src/auth/index.ts`
```typescript
// Authentication (Sprint 3)
export {};
```

**File:** `frontend/core/src/events/index.ts`
```typescript
// Event Bus (Sprint 4)
export {};
```

**File:** `frontend/core/src/validation/index.ts`
```typescript
// Validation (Sprint 4)
export {};
```

**File:** `frontend/core/src/components/index.ts`
```typescript
// Shared Components (Sprint 5)
export {};
```

**File:** `frontend/core/src/composables/index.ts`
```typescript
// Composables (Sprint 6)
export {};
```

**File:** `frontend/core/src/utils/index.ts`
```typescript
// Utilities (Sprint 6)
export {};
```

**File:** `frontend/core/src/types/index.ts`
```typescript
// Common Types
export {};
```

**File:** `frontend/core/src/sdk/index.ts`
```typescript
// Platform SDK (Sprint 1)
export {};
```

**File:** `frontend/core/src/access/index.ts`
```typescript
// Access Control (Sprint 7)
export {};
```

### 9. CI/CD Pipeline

**File:** `frontend/core/.github/workflows/test.yml`

```yaml
name: Core SDK Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: frontend/core/package-lock.json

      - name: Install dependencies
        working-directory: frontend/core
        run: npm ci

      - name: Type check
        working-directory: frontend/core
        run: npm run typecheck

      - name: Lint
        working-directory: frontend/core
        run: npm run lint

      - name: Format check
        working-directory: frontend/core
        run: npm run format:check

      - name: Run tests
        working-directory: frontend/core
        run: npm run test:coverage

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./frontend/core/coverage/coverage-final.json
          flags: core-sdk
```

### 10. Sample Test

**File:** `frontend/core/__tests__/unit/setup.test.ts`

```typescript
import { describe, it, expect } from 'vitest';

describe('Core SDK Setup', () => {
  it('should pass basic test', () => {
    expect(true).toBe(true);
  });

  it('should import from index', async () => {
    const coreModule = await import('../../src/index');
    expect(coreModule).toBeDefined();
  });
});
```

### 11. README

**File:** `frontend/core/README.md`

```markdown
# @vbwd/core-sdk

VBWD Core SDK - Shared plugin system for User and Admin applications

## Installation

```bash
npm install @vbwd/core-sdk
```

## Development

```bash
# Install dependencies
npm install

# Run tests in watch mode
npm run test:watch

# Build library
npm run build

# Generate docs
npm run docs
```

## Architecture

See [Architecture Documentation](../../docs/architecture_core_view_sdk/README.md)

## License

BSL-1.1 Business Source License
```

---

## Testing Strategy

### Unit Tests
- [ ] Package can be imported without errors
- [ ] TypeScript types are generated correctly
- [ ] Build produces both ESM and CommonJS outputs
- [ ] All config files are valid

### Build Validation
```bash
# Build the package
npm run build

# Verify outputs exist
ls -la dist/
# Should show: core-sdk.js, core-sdk.cjs, index.d.ts

# Test import in Node.js (CommonJS)
node -e "const sdk = require('./dist/core-sdk.cjs'); console.log('CJS:', sdk);"

# Test import in ESM
node --input-type=module -e "import('./dist/core-sdk.js').then(sdk => console.log('ESM:', sdk));"
```

---

## Definition of Done

- [x] Project initialized with all dependencies
- [x] TypeScript strict mode enabled and passing
- [x] Build pipeline produces ESM + CommonJS + types
- [x] Vitest configured and sample test passing
- [x] ESLint configured with no errors
- [x] Prettier configured
- [x] Directory structure created
- [x] CI/CD pipeline configured
- [x] README with setup instructions
- [x] All placeholder files created
- [x] Git repository initialized
- [x] First commit made

---

## Notes

- This sprint establishes the foundation for all subsequent sprints
- No functional code yet - focus is on tooling and infrastructure
- The symlink approach will be used during development:
  ```bash
  # From frontend/user/vue/
  npm link ../../core

  # From frontend/admin/vue/
  npm link ../../core
  ```
- CI/CD will run on every push to ensure quality standards

---

## Next Sprint

[Sprint 1: Plugin System Core](./sprint-1-plugin-system.md)
