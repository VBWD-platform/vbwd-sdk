# Sprint 0: Foundation & Testing Infrastructure (Revised)

**Duration**: 1 week (5 days)
**Status**: 📋 Ready to Start
**Approach**: TDD with Unit & Integration Tests (Vitest)

---

## Goal

Establish robust build system, TypeScript configuration, and **unit/integration testing** infrastructure for the Core SDK framework library.

## Testing Strategy for Core SDK

**IMPORTANT**: Core SDK is a **framework library**, NOT an application:
- ✅ **Unit Tests** (Vitest): Test individual classes, functions, utilities
- ✅ **Integration Tests** (Vitest): Test how modules work together
- ✅ **Component Tests** (Vitest + Testing Library): Test Vue components
- ❌ **E2E Tests** (Playwright): NOT for SDK - only for user/admin apps

## TDD Workflow

### Day 1: Write Tests
Write all unit and integration tests BEFORE any implementation.

### Day 2: Watch Fail
Run tests and verify they fail for the right reasons.

### Day 3-4: Implement
Build minimum code to pass tests.

### Day 5: Refactor
Clean up, document, and optimize.

---

## Test Scenarios (Write First!)

### 1. Build System Tests

```typescript
// tests/unit/build.spec.ts
import { describe, it, expect } from 'vitest';
import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

describe('Build System', () => {
  it('should build without TypeScript errors', () => {
    expect(() => {
      execSync('npm run build', { stdio: 'pipe' });
    }).not.toThrow();
  });

  it('should generate ESM bundle', () => {
    const distPath = path.resolve(__dirname, '../../dist/index.mjs');
    expect(fs.existsSync(distPath)).toBe(true);
  });

  it('should generate CommonJS bundle', () => {
    const distPath = path.resolve(__dirname, '../../dist/index.cjs');
    expect(fs.existsSync(distPath)).toBe(true);
  });

  it('should generate TypeScript declarations', () => {
    const dtsPath = path.resolve(__dirname, '../../dist/index.d.ts');
    expect(fs.existsSync(dtsPath)).toBe(true);

    const content = fs.readFileSync(dtsPath, 'utf-8');
    expect(content).toContain('export');
  });

  it('should not contain any types in declarations', () => {
    const dtsPath = path.resolve(__dirname, '../../dist/index.d.ts');
    const content = fs.readFileSync(dtsPath, 'utf-8');

    const anyCount = (content.match(/:\s*any(?![a-zA-Z])/g) || []).length;
    expect(anyCount).toBeLessThan(3); // Allow minimal use in generics
  });
});
```

### 2. TypeScript Configuration Tests

```typescript
// tests/unit/typescript-config.spec.ts
import { describe, it, expect } from 'vitest';
import tsconfig from '../../tsconfig.json';

describe('TypeScript Configuration', () => {
  it('should have strict mode enabled', () => {
    expect(tsconfig.compilerOptions.strict).toBe(true);
  });

  it('should have noImplicitAny enabled', () => {
    expect(tsconfig.compilerOptions.noImplicitAny).toBe(true);
  });

  it('should have strictNullChecks enabled', () => {
    expect(tsconfig.compilerOptions.strictNullChecks).toBe(true);
  });

  it('should have strictFunctionTypes enabled', () => {
    expect(tsconfig.compilerOptions.strictFunctionTypes).toBe(true);
  });

  it('should have noUnusedLocals enabled', () => {
    expect(tsconfig.compilerOptions.noUnusedLocals).toBe(true);
  });

  it('should have noUnusedParameters enabled', () => {
    expect(tsconfig.compilerOptions.noUnusedParameters).toBe(true);
  });

  it('should target ES2022 or higher', () => {
    const target = tsconfig.compilerOptions.target.toLowerCase();
    expect(['es2022', 'es2023', 'esnext']).toContain(target);
  });

  it('should use ESNext modules', () => {
    expect(tsconfig.compilerOptions.module).toBe('ESNext');
  });

  it('should generate declarations', () => {
    expect(tsconfig.compilerOptions.declaration).toBe(true);
    expect(tsconfig.compilerOptions.declarationMap).toBe(true);
  });

  it('should have path aliases configured', () => {
    expect(tsconfig.compilerOptions.paths).toBeDefined();
    expect(tsconfig.compilerOptions.paths['@/*']).toEqual(['./src/*']);
  });
});
```

### 3. Package Configuration Tests

```typescript
// tests/unit/package-config.spec.ts
import { describe, it, expect } from 'vitest';
import pkg from '../../package.json';

describe('Package Configuration', () => {
  it('should be named @vbwd/core-sdk', () => {
    expect(pkg.name).toBe('@vbwd/core-sdk');
  });

  it('should be an ES module', () => {
    expect(pkg.type).toBe('module');
  });

  it('should have main entry points', () => {
    expect(pkg.main).toBe('./dist/index.cjs');
    expect(pkg.module).toBe('./dist/index.mjs');
    expect(pkg.types).toBe('./dist/index.d.ts');
  });

  it('should have exports field configured', () => {
    expect(pkg.exports).toBeDefined();
    expect(pkg.exports['.']).toBeDefined();
    expect(pkg.exports['.'].import).toBe('./dist/index.mjs');
    expect(pkg.exports['.'].require).toBe('./dist/index.cjs');
    expect(pkg.exports['.'].types).toBe('./dist/index.d.ts');
  });

  it('should have required scripts', () => {
    const requiredScripts = [
      'dev',
      'build',
      'test',
      'test:unit',
      'test:integration',
      'test:coverage',
      'type-check',
      'lint',
      'format'
    ];

    for (const script of requiredScripts) {
      expect(pkg.scripts[script]).toBeDefined();
    }
  });

  it('should have Vue 3 as peer dependency', () => {
    expect(pkg.peerDependencies.vue).toBeDefined();
    expect(pkg.peerDependencies.vue).toMatch(/^\^3\./);
  });

  it('should have required dependencies', () => {
    expect(pkg.dependencies.axios).toBeDefined();
    expect(pkg.dependencies.zod).toBeDefined();
  });

  it('should have required devDependencies', () => {
    const required = [
      'typescript',
      'vite',
      'vitest',
      '@vitejs/plugin-vue',
      'eslint',
      'prettier'
    ];

    for (const dep of required) {
      expect(pkg.devDependencies[dep]).toBeDefined();
    }
  });

  it('version should follow semver', () => {
    expect(pkg.version).toMatch(/^\d+\.\d+\.\d+(-[a-z0-9.]+)?$/);
  });
});
```

### 4. Project Structure Tests

```typescript
// tests/unit/project-structure.spec.ts
import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';

describe('Project Structure', () => {
  const rootDir = path.resolve(__dirname, '../..');

  it('should have all required source directories', () => {
    const dirs = [
      'src/plugins',
      'src/api',
      'src/auth',
      'src/events',
      'src/validation',
      'src/components',
      'src/composables',
      'src/access-control',
      'src/types',
      'src/utils'
    ];

    for (const dir of dirs) {
      const fullPath = path.join(rootDir, dir);
      expect(fs.existsSync(fullPath)).toBe(true);
      expect(fs.statSync(fullPath).isDirectory()).toBe(true);
    }
  });

  it('should have all required test directories', () => {
    const dirs = ['tests/unit', 'tests/integration', 'tests/fixtures'];

    for (const dir of dirs) {
      const fullPath = path.join(rootDir, dir);
      expect(fs.existsSync(fullPath)).toBe(true);
    }
  });

  it('should have all required config files', () => {
    const files = [
      'package.json',
      'tsconfig.json',
      'vite.config.ts',
      'vitest.config.ts',
      '.eslintrc.js',
      '.prettierrc.js',
      'README.md'
    ];

    for (const file of files) {
      const fullPath = path.join(rootDir, file);
      expect(fs.existsSync(fullPath)).toBe(true);
    }
  });

  it('src/index.ts should exist', () => {
    const indexPath = path.join(rootDir, 'src/index.ts');
    expect(fs.existsSync(indexPath)).toBe(true);
  });
});
```

### 5. Test Infrastructure Tests

```typescript
// tests/unit/test-infrastructure.spec.ts
import { describe, it, expect } from 'vitest';
import vitestConfig from '../../vitest.config';

describe('Test Infrastructure', () => {
  it('should have coverage configured', () => {
    expect(vitestConfig.test.coverage).toBeDefined();
    expect(vitestConfig.test.coverage.provider).toBe('v8');
  });

  it('should have coverage thresholds set', () => {
    const thresholds = vitestConfig.test.coverage.thresholds;
    expect(thresholds.lines).toBeGreaterThanOrEqual(95);
    expect(thresholds.functions).toBeGreaterThanOrEqual(95);
    expect(thresholds.branches).toBeGreaterThanOrEqual(95);
    expect(thresholds.statements).toBeGreaterThanOrEqual(95);
  });

  it('should use jsdom environment', () => {
    expect(vitestConfig.test.environment).toBe('jsdom');
  });

  it('should have globals enabled', () => {
    expect(vitestConfig.test.globals).toBe(true);
  });
});
```

### 6. Code Quality Tests

```typescript
// tests/unit/code-quality.spec.ts
import { describe, it, expect } from 'vitest';
import { execSync } from 'child_process';

describe('Code Quality', () => {
  it('should pass ESLint with no errors', () => {
    expect(() => {
      execSync('npm run lint', { stdio: 'pipe' });
    }).not.toThrow();
  });

  it('should pass TypeScript type checking', () => {
    expect(() => {
      execSync('npm run type-check', { stdio: 'pipe' });
    }).not.toThrow();
  });

  it('should be formatted with Prettier', () => {
    expect(() => {
      execSync('npm run format:check', { stdio: 'pipe' });
    }).not.toThrow();
  });
});
```

---

## Implementation Tasks (Do After Tests)

### Day 1: Write All Tests
- [ ] Create all test files above
- [ ] Run tests and document failures
- [ ] Verify tests fail for correct reasons

### Day 2: Project Setup

#### 1. Initialize Project
```bash
cd vbwd-frontend
mkdir -p core
cd core
npm init -y
```

#### 2. Install Dependencies
```bash
# Core dependencies
npm install vue@^3.4.0 vue-router@^4.0.0 pinia@^2.0.0 \
  axios@^1.6.0 zod@^3.22.0

# Dev dependencies
npm install -D typescript@^5.3.0 vite@^5.0.0 vitest@^1.0.0 \
  @vitejs/plugin-vue@^5.0.0 @vue/test-utils@^2.4.0 \
  @testing-library/vue@^8.0.0 happy-dom@^12.0.0 \
  @types/node@^20.0.0 eslint@^8.0.0 prettier@^3.0.0 \
  @typescript-eslint/parser@^6.0.0 \
  @typescript-eslint/eslint-plugin@^6.0.0 \
  eslint-plugin-vue@^9.0.0 \
  eslint-config-prettier@^9.0.0 \
  @vitest/coverage-v8@^1.0.0
```

### Day 3: Configuration Files

**tsconfig.json**:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "moduleResolution": "bundler",
    "strict": true,
    "noImplicitAny": true,
    "noImplicitThis": true,
    "strictNullChecks": true,
    "strictFunctionTypes": true,
    "strictPropertyInitialization": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "jsx": "preserve",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "outDir": "./dist",
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    },
    "types": ["vite/client", "vitest/globals"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "tests"]
}
```

**vite.config.ts**:
```typescript
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { resolve } from 'path';

export default defineConfig({
  plugins: [vue()],
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      name: 'VBWDCore',
      fileName: (format) => `index.${format === 'es' ? 'mjs' : 'cjs'}`,
      formats: ['es', 'cjs']
    },
    rollupOptions: {
      external: ['vue', 'vue-router', 'pinia', 'axios', 'zod'],
      output: {
        globals: {
          vue: 'Vue',
          'vue-router': 'VueRouter',
          pinia: 'Pinia',
          axios: 'axios',
          zod: 'zod'
        }
      }
    },
    sourcemap: true,
    minify: 'terser'
  },
  resolve: {
    alias: {
      '@': resolve(__dirname, './src')
    }
  }
});
```

**vitest.config.ts**:
```typescript
import { defineConfig } from 'vitest/config';
import vue from '@vitejs/plugin-vue';
import { resolve } from 'path';

export default defineConfig({
  plugins: [vue()],
  test: {
    globals: true,
    environment: 'happy-dom',
    setupFiles: ['./tests/setup.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html', 'lcov'],
      exclude: [
        'node_modules/',
        'tests/',
        '**/*.spec.ts',
        '**/*.test.ts',
        'dist/',
        '**/*.d.ts',
        'vite.config.ts',
        'vitest.config.ts'
      ],
      thresholds: {
        lines: 95,
        functions: 95,
        branches: 95,
        statements: 95
      }
    }
  },
  resolve: {
    alias: {
      '@': resolve(__dirname, './src')
    }
  }
});
```

**package.json scripts**:
```json
{
  "name": "@vbwd/core-sdk",
  "version": "0.1.0",
  "type": "module",
  "main": "./dist/index.cjs",
  "module": "./dist/index.mjs",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "import": "./dist/index.mjs",
      "require": "./dist/index.cjs",
      "types": "./dist/index.d.ts"
    }
  },
  "files": ["dist"],
  "scripts": {
    "dev": "vite",
    "build": "vite build && tsc --emitDeclarationOnly",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:unit": "vitest run tests/unit",
    "test:integration": "vitest run tests/integration",
    "test:coverage": "vitest run --coverage",
    "type-check": "tsc --noEmit",
    "lint": "eslint src tests --ext .ts,.tsx,.vue",
    "lint:fix": "eslint src tests --ext .ts,.tsx,.vue --fix",
    "format": "prettier --write \"src/**/*.{ts,tsx,vue}\" \"tests/**/*.{ts,tsx}\"",
    "format:check": "prettier --check \"src/**/*.{ts,tsx,vue}\" \"tests/**/*.{ts,tsx}\""
  }
}
```

### Day 4: Directory Structure
```bash
mkdir -p src/{plugins,api,auth,events,validation,components,composables,access-control,types,utils}
mkdir -p tests/{unit,integration,fixtures}
touch src/index.ts
touch tests/setup.ts
```

### Day 5: Documentation

Create **README.md**, **CONTRIBUTING.md** with TDD guidelines.

---

## Acceptance Criteria

- [ ] All unit tests pass
- [ ] TypeScript builds without errors (strict mode)
- [ ] ESLint passes with 0 errors
- [ ] Package builds ESM + CJS bundles
- [ ] Type declarations generated
- [ ] Test coverage infrastructure ready
- [ ] Documentation complete

---

## Success Metrics

- **Build Time**: < 30 seconds
- **Test Suite**: < 1 minute
- **Type Safety**: 100% (no `any`)
- **Linting**: 0 errors, 0 warnings

---

**Status**: ✅ Ready to implement
**Next Sprint**: Sprint 1 (Plugin System with unit tests)
