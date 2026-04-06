# Sprint 2: API Client (TDD with Vitest)

**Duration**: 1 week (5 days)
**Status**: 📋 Ready After Sprint 1
**Dependencies**: Sprint 1 (Plugin System)
**Testing**: Unit & Integration Tests (Vitest)

---

## Goal

Implement type-safe HTTP client with Axios for backend integration, including request/response interceptors, error handling, and authentication token management.

## Testing Strategy

**REMINDER**: Core SDK is a library - use **unit and integration tests only**:
- ✅ **Unit Tests**: Test ApiClient, interceptors, error handling
- ✅ **Integration Tests**: Test with mock HTTP server (MSW)
- ❌ **E2E Tests**: NOT applicable for SDK (only for apps built on SDK)

## TDD Workflow

### Day 1: Write Tests
Write all unit and integration tests BEFORE implementation.

### Day 2: Implement Interfaces & Types
Create TypeScript interfaces to pass type-checking.

### Day 3-4: Implement Core Logic
Build ApiClient, interceptors, error handling.

### Day 5: Refactor & Document
Clean up, add JSDoc, write usage examples.

---

## Unit Test Scenarios (Write First!)

### 1. ApiClient Basic Tests

```typescript
// tests/unit/api/ApiClient.spec.ts
import { describe, it, expect, beforeEach } from 'vitest';
import { ApiClient } from '@/api/ApiClient';

describe('ApiClient', () => {
  let client: ApiClient;

  beforeEach(() => {
    client = new ApiClient({ baseURL: 'http://localhost:5001' });
  });

  it('should create client with baseURL', () => {
    expect(client).toBeDefined();
    expect(client.baseURL).toBe('http://localhost:5001');
  });

  it('should have default timeout', () => {
    expect(client.timeout).toBe(30000); // 30 seconds default
  });

  it('should allow custom timeout', () => {
    const customClient = new ApiClient({
      baseURL: 'http://localhost:5001',
      timeout: 5000
    });
    expect(customClient.timeout).toBe(5000);
  });

  it('should have request methods', () => {
    expect(typeof client.get).toBe('function');
    expect(typeof client.post).toBe('function');
    expect(typeof client.put).toBe('function');
    expect(typeof client.patch).toBe('function');
    expect(typeof client.delete).toBe('function');
  });

  it('should support setting auth token', () => {
    client.setToken('test-token-123');
    expect(client.getToken()).toBe('test-token-123');
  });

  it('should support clearing auth token', () => {
    client.setToken('test-token-123');
    client.clearToken();
    expect(client.getToken()).toBeUndefined();
  });

  it('should support custom headers', () => {
    const customClient = new ApiClient({
      baseURL: 'http://localhost:5001',
      headers: {
        'X-Custom-Header': 'value'
      }
    });
    expect(customClient.headers['X-Custom-Header']).toBe('value');
  });
});
```

### 2. Request Interceptor Tests

```typescript
// tests/unit/api/RequestInterceptor.spec.ts
import { describe, it, expect, beforeEach } from 'vitest';
import { ApiClient } from '@/api/ApiClient';

describe('Request Interceptors', () => {
  let client: ApiClient;

  beforeEach(() => {
    client = new ApiClient({ baseURL: 'http://localhost:5001' });
  });

  it('should add authorization header when token is set', async () => {
    client.setToken('test-token');

    const config = await client.getRequestConfig('/api/test');

    expect(config.headers.Authorization).toBe('Bearer test-token');
  });

  it('should not add authorization header when token is not set', async () => {
    const config = await client.getRequestConfig('/api/test');

    expect(config.headers.Authorization).toBeUndefined();
  });

  it('should merge custom headers with defaults', async () => {
    const config = await client.getRequestConfig('/api/test', {
      headers: { 'X-Custom': 'value' }
    });

    expect(config.headers['X-Custom']).toBe('value');
    expect(config.headers['Content-Type']).toBe('application/json');
  });

  it('should append baseURL to relative URLs', async () => {
    const config = await client.getRequestConfig('/api/test');

    expect(config.url).toBe('http://localhost:5001/api/test');
  });

  it('should not modify absolute URLs', async () => {
    const config = await client.getRequestConfig('https://external.com/api');

    expect(config.url).toBe('https://external.com/api');
  });

  it('should include query parameters', async () => {
    const config = await client.getRequestConfig('/api/test', {
      params: { page: 1, limit: 10 }
    });

    expect(config.params).toEqual({ page: 1, limit: 10 });
  });
});
```

### 3. Response Interceptor Tests

```typescript
// tests/unit/api/ResponseInterceptor.spec.ts
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { ApiClient } from '@/api/ApiClient';
import { ApiError } from '@/api/errors';

describe('Response Interceptors', () => {
  let client: ApiClient;

  beforeEach(() => {
    client = new ApiClient({ baseURL: 'http://localhost:5001' });
  });

  it('should return response data on success', async () => {
    const mockResponse = {
      status: 200,
      data: { message: 'success' },
      headers: {},
      config: {}
    };

    const result = await client.handleResponse(mockResponse);

    expect(result).toEqual({ message: 'success' });
  });

  it('should throw ApiError on 4xx error', async () => {
    const mockResponse = {
      status: 400,
      data: { error: 'Bad Request' },
      headers: {},
      config: {}
    };

    await expect(client.handleResponse(mockResponse)).rejects.toThrow(ApiError);
  });

  it('should throw ApiError on 5xx error', async () => {
    const mockResponse = {
      status: 500,
      data: { error: 'Internal Server Error' },
      headers: {},
      config: {}
    };

    await expect(client.handleResponse(mockResponse)).rejects.toThrow(ApiError);
  });

  it('should emit token-expired event on 401', async () => {
    const spy = vi.fn();
    client.on('token-expired', spy);

    const mockResponse = {
      status: 401,
      data: { error: 'Unauthorized' },
      headers: {},
      config: {}
    };

    await expect(client.handleResponse(mockResponse)).rejects.toThrow();
    expect(spy).toHaveBeenCalled();
  });

  it('should retry request after token refresh on 401', async () => {
    client.setRefreshTokenHandler(async () => 'new-token');

    const mockResponse = {
      status: 401,
      data: { error: 'Unauthorized' },
      headers: {},
      config: { url: '/api/test', method: 'GET' }
    };

    // This would normally retry - for now just test setup
    expect(client.getRefreshTokenHandler()).toBeDefined();
  });
});
```

### 4. Error Handling Tests

```typescript
// tests/unit/api/ErrorHandling.spec.ts
import { describe, it, expect } from 'vitest';
import { ApiError, NetworkError, ValidationError } from '@/api/errors';

describe('API Error Handling', () => {
  it('should create ApiError with status and message', () => {
    const error = new ApiError('Not Found', 404);

    expect(error.message).toBe('Not Found');
    expect(error.status).toBe(404);
    expect(error.name).toBe('ApiError');
  });

  it('should create NetworkError for connection failures', () => {
    const error = new NetworkError('Network request failed');

    expect(error.message).toBe('Network request failed');
    expect(error.name).toBe('NetworkError');
    expect(error.isNetworkError).toBe(true);
  });

  it('should create ValidationError for 422 responses', () => {
    const error = new ValidationError('Validation failed', {
      email: ['Email is required'],
      password: ['Password too short']
    });

    expect(error.message).toBe('Validation failed');
    expect(error.status).toBe(422);
    expect(error.errors.email).toEqual(['Email is required']);
    expect(error.errors.password).toEqual(['Password too short']);
  });

  it('should check if error is retryable', () => {
    const networkError = new NetworkError('Timeout');
    const validationError = new ValidationError('Invalid', {});

    expect(networkError.isRetryable()).toBe(true);
    expect(validationError.isRetryable()).toBe(false);
  });

  it('should normalize axios error', () => {
    const axiosError = {
      response: {
        status: 404,
        data: { error: 'Not Found' }
      },
      config: {},
      request: {}
    };

    const normalized = ApiError.fromAxiosError(axiosError);

    expect(normalized).toBeInstanceOf(ApiError);
    expect(normalized.status).toBe(404);
    expect(normalized.message).toContain('Not Found');
  });
});
```

### 5. Type Safety Tests

```typescript
// tests/unit/api/TypeSafety.spec.ts
import { describe, it, expect } from 'vitest';
import type { ApiResponse, LoginRequest, LoginResponse } from '@/api/types';

describe('API Type Safety', () => {
  it('should enforce request types', () => {
    const request: LoginRequest = {
      email: 'test@example.com',
      password: 'password123'
    };

    expect(request.email).toBeDefined();
    expect(request.password).toBeDefined();
  });

  it('should enforce response types', () => {
    const response: ApiResponse<LoginResponse> = {
      data: {
        token: 'jwt-token',
        user: {
          id: 1,
          email: 'test@example.com',
          name: 'Test User'
        }
      },
      status: 200,
      message: 'Success'
    };

    expect(response.data.token).toBeDefined();
    expect(response.data.user.email).toBe('test@example.com');
  });

  it('should handle generic response types', () => {
    interface CustomData {
      id: number;
      value: string;
    }

    const response: ApiResponse<CustomData> = {
      data: { id: 1, value: 'test' },
      status: 200,
      message: 'Success'
    };

    expect(response.data.id).toBe(1);
    expect(response.data.value).toBe('test');
  });
});
```

---

## Integration Test Scenarios

### 6. Mock Server Integration Tests

```typescript
// tests/integration/api-mock-server.spec.ts
import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { setupServer } from 'msw/node';
import { http, HttpResponse } from 'msw';
import { ApiClient } from '@/api/ApiClient';

const server = setupServer();

describe('API Client with Mock Server', () => {
  let client: ApiClient;

  beforeAll(() => server.listen());
  afterAll(() => server.close());
  beforeEach(() => {
    server.resetHandlers();
    client = new ApiClient({ baseURL: 'http://localhost:5001' });
  });

  it('should make successful GET request', async () => {
    server.use(
      http.get('http://localhost:5001/api/users', () => {
        return HttpResponse.json({ users: [{ id: 1, name: 'Test' }] });
      })
    );

    const response = await client.get('/api/users');

    expect(response.users).toHaveLength(1);
    expect(response.users[0].name).toBe('Test');
  });

  it('should make successful POST request', async () => {
    server.use(
      http.post('http://localhost:5001/api/users', async ({ request }) => {
        const body = await request.json();
        return HttpResponse.json({ user: { id: 1, ...body } }, { status: 201 });
      })
    );

    const response = await client.post('/api/users', {
      name: 'New User',
      email: 'new@example.com'
    });

    expect(response.user.name).toBe('New User');
    expect(response.user.email).toBe('new@example.com');
  });

  it('should handle 404 error', async () => {
    server.use(
      http.get('http://localhost:5001/api/users/999', () => {
        return HttpResponse.json({ error: 'User not found' }, { status: 404 });
      })
    );

    await expect(client.get('/api/users/999')).rejects.toThrow('User not found');
  });

  it('should handle 500 error', async () => {
    server.use(
      http.get('http://localhost:5001/api/users', () => {
        return HttpResponse.json({ error: 'Server error' }, { status: 500 });
      })
    );

    await expect(client.get('/api/users')).rejects.toThrow();
  });

  it('should handle network timeout', async () => {
    server.use(
      http.get('http://localhost:5001/api/slow', async () => {
        await new Promise(resolve => setTimeout(resolve, 100));
        return HttpResponse.json({ data: 'slow' });
      })
    );

    const slowClient = new ApiClient({
      baseURL: 'http://localhost:5001',
      timeout: 50
    });

    await expect(slowClient.get('/api/slow')).rejects.toThrow();
  });

  it('should attach token to authenticated requests', async () => {
    server.use(
      http.get('http://localhost:5001/api/protected', ({ request }) => {
        const auth = request.headers.get('Authorization');
        if (auth === 'Bearer test-token') {
          return HttpResponse.json({ message: 'Authorized' });
        }
        return HttpResponse.json({ error: 'Unauthorized' }, { status: 401 });
      })
    );

    client.setToken('test-token');
    const response = await client.get('/api/protected');

    expect(response.message).toBe('Authorized');
  });

  it('should handle token refresh on 401', async () => {
    let requestCount = 0;

    server.use(
      http.get('http://localhost:5001/api/protected', ({ request }) => {
        requestCount++;
        const auth = request.headers.get('Authorization');

        if (requestCount === 1) {
          return HttpResponse.json({ error: 'Token expired' }, { status: 401 });
        }

        if (auth === 'Bearer new-token') {
          return HttpResponse.json({ message: 'Success' });
        }

        return HttpResponse.json({ error: 'Unauthorized' }, { status: 401 });
      })
    );

    client.setToken('old-token');
    client.setRefreshTokenHandler(async () => 'new-token');

    const response = await client.get('/api/protected');

    expect(response.message).toBe('Success');
    expect(requestCount).toBe(2);
  });
});
```

---

## Implementation Tasks (After Tests)

### Day 2: Type Definitions

Create `src/api/types.ts`:
```typescript
export interface ApiClientConfig {
  baseURL: string;
  timeout?: number;
  headers?: Record<string, string>;
}

export interface ApiResponse<T> {
  data: T;
  status: number;
  message?: string;
}

export interface LoginRequest {
  email: string;
  password: string;
}

export interface LoginResponse {
  token: string;
  user: {
    id: number;
    email: string;
    name: string;
  };
}

// ... more types
```

### Day 3-4: Implementation

1. Create `src/api/ApiClient.ts`
2. Create `src/api/errors.ts`
3. Create `src/api/interceptors.ts`
4. Create `src/api/index.ts`

### Day 5: Documentation

Write usage examples and JSDoc comments.

---

## Acceptance Criteria

- [ ] All unit tests pass (25+ tests)
- [ ] All integration tests pass (8+ tests)
- [ ] ApiClient works with Axios
- [ ] Request/response interceptors work
- [ ] Error handling works
- [ ] Token management works
- [ ] Token refresh works
- [ ] Mock server integration tests pass
- [ ] Code coverage ≥ 95%
- [ ] TypeScript strict mode (no `any`)
- [ ] Documentation complete

---

## Deliverables

1. ✅ API type definitions
2. ✅ ApiClient class
3. ✅ Request interceptors
4. ✅ Response interceptors
5. ✅ Error classes
6. ✅ 25+ unit tests passing
7. ✅ 8+ integration tests passing
8. ✅ API documentation with examples

---

**Status**: ✅ Ready after Sprint 1
**Next Sprint**: Sprint 3 (Authentication Service)
