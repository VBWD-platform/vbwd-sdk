# Sprint 22: Separate Admin and User Containers

## Context

Currently, admin and user apps share a **single Dockerfile** (`container/frontend/Dockerfile`) that builds both apps into one nginx image. The docker-compose defines separate services (`user-app:8080`, `admin-app:8081`) but both are built from the same multi-stage Dockerfile, meaning:

- Every container contains BOTH apps' built assets (even if only one is served)
- A change to either app triggers a full rebuild of both
- The nginx config inside serves both `/` (user) and `/admin` (admin) from the same container
- Dev services (`user-dev`, `admin-dev`) are already separate but production containers are not truly independent

### Current Architecture

```
container/frontend/Dockerfile   ← single file, multi-stage, builds both apps
  → build-core  (core library)
  → build-user  (user Vue app)
  → build-admin (admin Vue app)
  → nginx       (serves both: /usr/share/nginx/html/user + /admin)

docker-compose.yaml:
  user-app:   port 8080 → same Dockerfile
  admin-app:  port 8081 → same Dockerfile
```

### Target Architecture

```
container/user/Dockerfile       ← builds core + user only
  → nginx (serves user at /)

container/admin/Dockerfile      ← builds core + admin only
  → nginx (serves admin at /)

docker-compose.yaml:
  user-app:   port 8080 → container/user/Dockerfile
  admin-app:  port 8081 → container/admin/Dockerfile
```

This sprint separates them into fully independent containers so each app has its own Dockerfile, nginx config, and only includes its own assets.

---

## Core Requirements (enforced across all tasks)

| Principle | How it applies in this sprint |
|-----------|-------------------------------|
| **TDD-First** | No application code changes in this sprint, but all existing tests MUST pass after infrastructure changes. Run full pre-commit checks before and after to confirm zero regressions. |
| **DRY** | Both Dockerfiles share the same `build-core` stage pattern but are independent files (no Docker build inheritance — simplicity over abstraction). Nginx configs share the same proxy block structure; duplication is acceptable here because each container's config will diverge in Sprint 23. |
| **SOLID — SRP** | Each container serves exactly one app. One Dockerfile per app. One nginx config per app. No cross-concerns — user container knows nothing about admin, admin container knows nothing about user. |
| **SOLID — OCP** | Each container is independently extensible. Sprint 23 will add a Node.js API server to the user container without touching the admin container. |
| **SOLID — LSP** | Both containers expose the same interface to the outside world: port 80 serving an SPA with `/api` proxy. Any consumer (browser, reverse proxy) can interact with either container identically. |
| **SOLID — ISP** | Each container only includes the assets it needs. User container has no admin build artifacts. Admin container has no user build artifacts. Smaller images, faster builds. |
| **SOLID — DIP** | Docker-compose services depend on the abstract contract (port 80, serves HTML, proxies `/api`) not on the concrete Dockerfile. Swapping the underlying image is transparent to docker-compose. |
| **Clean Code** | Descriptive stage names in Dockerfiles (`build-core`, `build-user`, `build-admin`). Clear comments in nginx configs. No magic numbers — all ports and paths are self-documenting. |
| **Type Safety** | N/A — infrastructure-only sprint, no TypeScript changes. |
| **Coverage** | Regression baseline: all existing 1335 tests must pass unchanged. No new tests needed (no new application code). |
| **Minimal Change** | Keep existing dev services (`user-dev`, `admin-dev`, `*-test`) as-is. Only production containers change. |

---

## Testing Approach

No application code changes — only Docker infrastructure. All existing tests MUST pass before the sprint is considered complete.

```bash
# 1. Pre-flight: confirm baseline passes BEFORE any changes
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --unit
cd vbwd-frontend && ./bin/pre-commit-check.sh --user --unit
cd vbwd-frontend/core && npx vitest run

# 2. Rebuild and start both containers with new Dockerfiles
cd vbwd-frontend && docker compose up -d --build user-app admin-app

# 3. Verify containers are running and serving correct apps
curl -s http://localhost:8080/ | grep -q '<div id="app">' && echo "User OK"
curl -s http://localhost:8081/ | grep -q '<div id="app">' && echo "Admin OK"

# 4. Verify API proxy works from both containers
curl -s http://localhost:8080/api/v1/tarif-plans | head -c 100
curl -s http://localhost:8081/api/v1/tarif-plans | head -c 100

# 5. Post-flight: confirm all tests still pass AFTER changes
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --unit
cd vbwd-frontend && ./bin/pre-commit-check.sh --user --unit
cd vbwd-frontend/core && npx vitest run

# 6. Full combined pre-commit check (admin + user, unit + style)
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --user --unit

# 7. Backend regression check (no backend changes, but verify nothing broke)
cd vbwd-backend && make test-unit
```

**Test categories for this sprint:**

| Category | Command | What it covers |
|----------|---------|----------------|
| Admin unit | `--admin --unit` | All 305 admin tests — regression check |
| User unit | `--user --unit` | All 115 user tests — regression check |
| Core unit | `cd core && npx vitest run` | All 289 core tests — regression check |
| Admin style | `--admin --style` | ESLint + vue-tsc TypeScript check |
| Backend unit | `cd vbwd-backend && make test-unit` | All 626 backend tests — regression check |

**Existing test counts (must not regress):**
- Admin: 305 tests
- User: 115 tests
- Core: 289 tests
- Backend: 626 tests
- **Total: 1335**

---

## Task 1: Create User Dockerfile

Create `container/user/Dockerfile` that builds only core + user app.

```dockerfile
# Build stage - Core library
FROM node:20-alpine AS build-core

WORKDIR /app/core
COPY core/package*.json ./
RUN npm install
COPY core/ ./
RUN npm run build

# Build stage - User app
FROM node:20-alpine AS build-user

WORKDIR /app
COPY --from=build-core /app/core /app/core

WORKDIR /app/user
COPY user/package*.json ./
RUN npm install
COPY user/ ./
RUN npx vite build

# Production stage
FROM nginx:alpine

COPY --from=build-user /app/user/dist /usr/share/nginx/html
COPY container/user/nginx.conf /etc/nginx/nginx.conf
RUN mkdir -p /var/log/nginx

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

### Files:
- NEW: `container/user/Dockerfile`

---

## Task 2: Create User nginx.conf

Simplified nginx config serving only the user app at `/`.

```nginx
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;

    sendfile on;
    keepalive_timeout 65;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

    server {
        listen 80;
        server_name localhost;

        # User app
        location / {
            root /usr/share/nginx/html;
            index index.html;
            try_files $uri $uri/ /index.html;
        }

        # API proxy
        location /api {
            proxy_pass http://host.docker.internal:5000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
            proxy_read_timeout 300s;
        }

        # Health endpoint proxy
        location /health {
            proxy_pass http://host.docker.internal:5000/health;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
        }

        # WebSocket proxy
        location /socket.io {
            proxy_pass http://host.docker.internal:5000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_read_timeout 86400s;
        }
    }
}
```

### Files:
- NEW: `container/user/nginx.conf`

---

## Task 3: Create Admin Dockerfile

Create `container/admin/Dockerfile` that builds only core + admin app.

```dockerfile
# Build stage - Core library
FROM node:20-alpine AS build-core

WORKDIR /app/core
COPY core/package*.json ./
RUN npm install
COPY core/ ./
RUN npm run build

# Build stage - Admin app
FROM node:20-alpine AS build-admin

WORKDIR /app
COPY --from=build-core /app/core /app/core

WORKDIR /app/admin/vue
COPY admin/vue/package*.json ./
RUN npm install
COPY admin/vue/ ./
COPY admin/plugins/ /app/admin/plugins/
RUN npx vite build

# Production stage
FROM nginx:alpine

COPY --from=build-admin /app/admin/vue/dist /usr/share/nginx/html
COPY container/admin/nginx.conf /etc/nginx/nginx.conf
RUN mkdir -p /var/log/nginx

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

### Files:
- NEW: `container/admin/Dockerfile`

---

## Task 4: Create Admin nginx.conf

Simplified nginx config serving only the admin app at `/`.

**Important:** The admin app's Vue Router uses `base: '/admin'`, so nginx must handle both `/admin/*` and `/` properly. The app builds with the `/admin` base path, so we use `alias` to serve from root.

```nginx
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;

    sendfile on;
    keepalive_timeout 65;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

    server {
        listen 80;
        server_name localhost;

        # Admin app
        location / {
            root /usr/share/nginx/html;
            index index.html;
            try_files $uri $uri/ /index.html;
        }

        # API proxy
        location /api {
            proxy_pass http://host.docker.internal:5000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
            proxy_read_timeout 300s;
        }

        # Health endpoint proxy
        location /health {
            proxy_pass http://host.docker.internal:5000/health;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
        }

        # WebSocket proxy
        location /socket.io {
            proxy_pass http://host.docker.internal:5000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_read_timeout 86400s;
        }
    }
}
```

### Files:
- NEW: `container/admin/nginx.conf`

---

## Task 5: Update docker-compose.yaml

Point each service to its own Dockerfile. Keep dev/test services unchanged.

```yaml
services:
  user-app:
    build:
      context: .
      dockerfile: container/user/Dockerfile
    ports:
      - "8080:80"
    environment:
      - VITE_API_URL=/api/v1
    extra_hosts:
      - "host.docker.internal:host-gateway"

  admin-app:
    build:
      context: .
      dockerfile: container/admin/Dockerfile
    ports:
      - "8081:80"
    environment:
      - VITE_API_URL=/api/v1
    extra_hosts:
      - "host.docker.internal:host-gateway"

  # Dev and test services remain unchanged...
```

**Changes:**
- `user-app`: `dockerfile: container/user/Dockerfile`, remove `args.APP_DIR`
- `admin-app`: `dockerfile: container/admin/Dockerfile`, remove `args.APP_DIR`
- All other services (`user-dev`, `admin-dev`, `*-test`, `core-*`) stay the same

### Files:
- EDIT: `docker-compose.yaml`

---

## Task 6: Clean Up Legacy Dockerfile

After both new Dockerfiles are working, the old shared `container/frontend/Dockerfile` and `container/frontend/nginx.conf` become dead code. Remove them.

### Files:
- DELETE: `container/frontend/Dockerfile`
- DELETE: `container/frontend/nginx.conf`

---

## Implementation Order

1. Task 1 — User Dockerfile
2. Task 2 — User nginx.conf
3. Task 3 — Admin Dockerfile
4. Task 4 — Admin nginx.conf
5. Task 5 — Update docker-compose.yaml
6. Task 6 — Remove legacy files
7. Verification — rebuild + smoke test

---

## File Summary

| Action | File |
|--------|------|
| NEW | `container/user/Dockerfile` |
| NEW | `container/user/nginx.conf` |
| NEW | `container/admin/Dockerfile` |
| NEW | `container/admin/nginx.conf` |
| EDIT | `docker-compose.yaml` |
| DELETE | `container/frontend/Dockerfile` |
| DELETE | `container/frontend/nginx.conf` |

---

## Verification

### Automated

```bash
# Rebuild both containers
cd vbwd-frontend && docker compose up -d --build user-app admin-app

# Verify containers are running
docker compose ps

# Verify user app serves HTML
curl -s http://localhost:8080/ | grep -q '<div id="app">'

# Verify admin app serves HTML
curl -s http://localhost:8081/ | grep -q '<div id="app">'

# Verify API proxy works from both
curl -s http://localhost:8080/api/v1/tarif-plans | head -c 100
curl -s http://localhost:8081/api/v1/tarif-plans | head -c 100

# Ensure unit tests still pass (no app code changed)
cd vbwd-frontend && make test
```

### Manual Smoke Test

1. Open `http://localhost:8080` → user app loads, login works
2. Open `http://localhost:8081` → admin app loads, login works
3. Navigate through user app pages: dashboard, plans, invoices → all work
4. Navigate through admin app pages: users, settings, plugins → all work
5. Verify user container does NOT serve admin app at `/admin`
6. Verify admin container does NOT serve user app at `/`
7. Stop one container, verify the other still works independently
