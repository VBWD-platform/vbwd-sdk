# Task 6: Frontend Core SDK Integration

**Priority:** HIGH
**Focus:** Bridge the gap between Core SDK and frontend apps
**Estimated Time:** 4-5 hours

---

## Problem Statement

Current State:
- Core SDK has excellent ApiClient, but apps use raw axios
- Core SDK has plugin system, but apps are monolithic
- Each app manages its own auth/token handling
- Code duplication between User and Admin apps

Target State:
- Both apps use Core SDK ApiClient
- Shared authentication through Core SDK
- Consistent error handling
- Single source of truth for API configuration

---

## Core Requirements

- TDD-First: Tests before integration
- SOLID: Use SDK abstractions
- Clean Code: Remove duplication
- No Over-Engineering: Minimal changes to achieve integration

---

## 6.1 Link Core SDK to Apps

### Setup npm workspace linking

```bash
cd /home/dtkachev/dantweb/vbwd-sdk/vbwd-frontend

# Build Core SDK
cd core
npm install
npm run build

# Link to User App
cd ../user/vue
npm link ../../core

# Link to Admin App
cd ../admin/vue
npm link ../../core
```

### Update package.json (both apps)

```json
{
  "dependencies": {
    "@vbwd/core-sdk": "file:../../core"
  }
}
```

---

## 6.2 Replace Axios with Core SDK ApiClient

### User App Store Refactor

**File:** `user/vue/src/stores/submission.js`

**Test First:** `user/vue/tests/unit/stores/submission.spec.js`
```javascript
import { setActivePinia, createPinia } from 'pinia'
import { useSubmissionStore } from '@/stores/submission'
import { ApiClient } from '@vbwd/core-sdk'

// Mock the API client
vi.mock('@vbwd/core-sdk', () => ({
  ApiClient: {
    post: vi.fn(),
    get: vi.fn()
  }
}))

describe('SubmissionStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.clearAllMocks()
  })

  it('submits using ApiClient', async () => {
    const store = useSubmissionStore()
    ApiClient.post.mockResolvedValue({ data: { id: '123' } })

    await store.submit({ images: [], email: 'test@test.com' })

    expect(ApiClient.post).toHaveBeenCalledWith('/api/user/submit', expect.any(Object))
    expect(store.submissionId).toBe('123')
  })

  it('handles submission error', async () => {
    const store = useSubmissionStore()
    ApiClient.post.mockRejectedValue(new Error('Network error'))

    await store.submit({ images: [], email: 'test@test.com' })

    expect(store.error).toBe('Network error')
  })

  it('gets status using ApiClient', async () => {
    const store = useSubmissionStore()
    store.submissionId = '123'
    ApiClient.get.mockResolvedValue({ data: { status: 'completed' } })

    await store.getStatus()

    expect(ApiClient.get).toHaveBeenCalledWith('/api/user/status/123')
  })
})
```

**Refactored Store:**
```javascript
import { defineStore } from 'pinia'
import { createApiClient } from '@vbwd/core-sdk'

// Create API client instance
const api = createApiClient({
  baseURL: import.meta.env.VITE_API_URL || '/api'
})

export const useSubmissionStore = defineStore('submission', {
  state: () => ({
    submissionId: null,
    status: null,
    error: null,
    loading: false
  }),

  actions: {
    async submit(formData) {
      this.loading = true
      this.error = null

      try {
        const response = await api.post('/user/submit', formData)
        this.submissionId = response.data.id
        this.status = 'submitted'
        return response.data
      } catch (error) {
        this.error = error.message || 'Submission failed'
        throw error
      } finally {
        this.loading = false
      }
    },

    async getStatus() {
      if (!this.submissionId) return

      try {
        const response = await api.get(`/user/status/${this.submissionId}`)
        this.status = response.data.status
        return response.data
      } catch (error) {
        this.error = error.message
        throw error
      }
    },

    reset() {
      this.submissionId = null
      this.status = null
      this.error = null
      this.loading = false
    }
  }
})
```

### Admin App Store Refactor

**File:** `admin/vue/src/stores/auth.js`

**Test First:** `admin/vue/tests/unit/stores/auth.spec.js`
```javascript
import { setActivePinia, createPinia } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { createApiClient } from '@vbwd/core-sdk'

vi.mock('@vbwd/core-sdk')

describe('AuthStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    localStorage.clear()
  })

  it('login stores token via SDK', async () => {
    const mockApi = {
      post: vi.fn().mockResolvedValue({ data: { token: 'test-token' } }),
      setAuthToken: vi.fn()
    }
    createApiClient.mockReturnValue(mockApi)

    const store = useAuthStore()
    await store.login('admin@test.com', 'password')

    expect(mockApi.post).toHaveBeenCalledWith('/auth/login', {
      email: 'admin@test.com',
      password: 'password'
    })
    expect(mockApi.setAuthToken).toHaveBeenCalledWith('test-token')
    expect(store.isAuthenticated).toBe(true)
  })

  it('logout clears token', async () => {
    const mockApi = {
      clearAuthToken: vi.fn()
    }
    createApiClient.mockReturnValue(mockApi)

    const store = useAuthStore()
    store.token = 'test-token'

    store.logout()

    expect(mockApi.clearAuthToken).toHaveBeenCalled()
    expect(store.token).toBeNull()
  })
})
```

**Refactored Store:**
```javascript
import { defineStore } from 'pinia'
import { createApiClient } from '@vbwd/core-sdk'

const api = createApiClient({
  baseURL: import.meta.env.VITE_API_URL || '/api'
})

export const useAuthStore = defineStore('auth', {
  state: () => ({
    token: null,
    user: null,
    error: null
  }),

  getters: {
    isAuthenticated: (state) => !!state.token
  },

  actions: {
    async login(email, password) {
      try {
        const response = await api.post('/auth/login', { email, password })
        this.token = response.data.token
        this.user = response.data.user

        // Set token in API client for future requests
        api.setAuthToken(this.token)

        // Persist token
        localStorage.setItem('auth_token', this.token)

        return response.data
      } catch (error) {
        this.error = error.message
        throw error
      }
    },

    logout() {
      this.token = null
      this.user = null
      api.clearAuthToken()
      localStorage.removeItem('auth_token')
    },

    initAuth() {
      const token = localStorage.getItem('auth_token')
      if (token) {
        this.token = token
        api.setAuthToken(token)
      }
    }
  }
})
```

---

## 6.3 Remove Global Axios Mutations

### Problem

Current admin store does this (BAD):
```javascript
import axios from 'axios'

// BAD: Mutates global axios instance
axios.defaults.headers.common['Authorization'] = `Bearer ${token}`
```

### Solution

Use Core SDK's encapsulated API client:
```javascript
import { createApiClient } from '@vbwd/core-sdk'

const api = createApiClient({ baseURL: '/api' })

// GOOD: Encapsulated, no global mutation
api.setAuthToken(token)
```

---

## 6.4 Create Shared API Module

**File:** `core/src/api/index.ts` (extend existing)

Add convenience methods:
```typescript
export function createApiClient(config: ApiClientConfig): IApiClient {
  const client = new ApiClient(config)
  return client
}

export interface IApiClient {
  get<T>(url: string, config?: RequestConfig): Promise<ApiResponse<T>>
  post<T>(url: string, data?: unknown, config?: RequestConfig): Promise<ApiResponse<T>>
  put<T>(url: string, data?: unknown, config?: RequestConfig): Promise<ApiResponse<T>>
  delete<T>(url: string, config?: RequestConfig): Promise<ApiResponse<T>>

  setAuthToken(token: string): void
  clearAuthToken(): void

  onTokenExpired(callback: () => void): void
}
```

---

## 6.5 Update App Entry Points

### User App `main.js`
```javascript
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'

// Core SDK initialization
import { initializeSDK } from '@vbwd/core-sdk'

const app = createApp(App)

// Initialize SDK with config
initializeSDK({
  apiBaseUrl: import.meta.env.VITE_API_URL || '/api',
  wsUrl: import.meta.env.VITE_WS_URL || '/socket.io'
})

app.use(createPinia())
app.use(router)
app.mount('#app')
```

### Admin App `main.js`
```javascript
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import { initializeSDK } from '@vbwd/core-sdk'
import { useAuthStore } from './stores/auth'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)

// Initialize SDK
initializeSDK({
  apiBaseUrl: import.meta.env.VITE_API_URL || '/api'
})

// Restore auth state
const authStore = useAuthStore()
authStore.initAuth()

app.use(router)
app.mount('#app')
```

---

## 6.6 Test Setup for Frontend Apps

### Install test dependencies

```bash
cd user/vue
npm install -D vitest @vue/test-utils happy-dom

cd ../admin/vue
npm install -D vitest @vue/test-utils happy-dom
```

### Add vitest.config.js (both apps)
```javascript
import { defineConfig } from 'vitest/config'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath } from 'url'

export default defineConfig({
  plugins: [vue()],
  test: {
    environment: 'happy-dom',
    globals: true,
    coverage: {
      reporter: ['text', 'html'],
      exclude: ['node_modules/', 'tests/']
    }
  },
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    }
  }
})
```

### Add test script to package.json
```json
{
  "scripts": {
    "test": "vitest",
    "test:coverage": "vitest run --coverage"
  }
}
```

---

## Checklist

### Core SDK Linking
- [ ] Core SDK built successfully
- [ ] User app linked to Core SDK
- [ ] Admin app linked to Core SDK
- [ ] Both apps can import from @vbwd/core-sdk

### Store Refactoring
- [ ] User submission store uses ApiClient
- [ ] Admin auth store uses ApiClient
- [ ] No global axios mutations
- [ ] Token handling via SDK

### Tests
- [ ] Vitest configured for User app
- [ ] Vitest configured for Admin app
- [ ] Store tests written and passing
- [ ] 80%+ coverage target

### Verification
```bash
# Build Core SDK
cd core && npm run build

# Test User App
cd user/vue && npm test

# Test Admin App
cd admin/vue && npm test
```

---

## Files Modified

### Core SDK
- [ ] `core/src/api/index.ts` - Export createApiClient
- [ ] `core/src/index.ts` - Export initializeSDK

### User App
- [ ] `user/vue/package.json` - Add @vbwd/core-sdk
- [ ] `user/vue/src/stores/submission.js` - Use ApiClient
- [ ] `user/vue/src/main.js` - Initialize SDK
- [ ] `user/vue/vitest.config.js` - Create
- [ ] `user/vue/tests/unit/stores/submission.spec.js` - Create

### Admin App
- [ ] `admin/vue/package.json` - Add @vbwd/core-sdk
- [ ] `admin/vue/src/stores/auth.js` - Use ApiClient
- [ ] `admin/vue/src/main.js` - Initialize SDK
- [ ] `admin/vue/vitest.config.js` - Create
- [ ] `admin/vue/tests/unit/stores/auth.spec.js` - Create
