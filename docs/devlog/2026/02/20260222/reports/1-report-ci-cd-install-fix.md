# Report: Docker Dev Environment & CI/CD Installation Fix

**Date:** 2026-02-22
**Branch:** `feature/macfix`
**Author:** Claude Code (Opus 4.6)

---

## Summary

Complete fix of the Docker-based development environment for all three frontend applications (`vbwd-fe-user`, `vbwd-fe-admin`, `vbwd-fe-core`) and the backend plugin system. The existing Docker Compose configurations were broken due to incorrect volume mounts, missing services, and mismatched authentication methods.

---

## Issues Found & Fixed

### 1. Docker Compose Volume Mount — Missing `package.json`

**Problem:** Both `vbwd-fe-user` and `vbwd-fe-admin` had `./vue:/app` as volume mount, but `package.json` and `vite.config.js` live in the project root, not inside `vue/`.

**Error:**
```
npm error enoent Could not read package.json: ENOENT: no such file or directory, open '/app/package.json'
```

**Fix:** Changed volume mount from `./vue:/app` to `.:/app` in all docker-compose services for both frontend apps. This mounts the entire project root, giving the container access to `package.json`, `vite.config.js`, `vue/`, `plugins/`, and `bin/`.

**Files changed:**
- `vbwd-fe-user/docker-compose.yaml`
- `vbwd-fe-admin/docker-compose.yaml`

---

### 2. Incorrect Relative Path for `vbwd-fe-core` Volume

**Problem:** Volume mount `../../vbwd-fe-core:/app/vbwd-fe-core` resolved to `/Users/dantweb/dantweb/vbwd-fe-core` (a different, outdated repo) instead of the correct `/Users/dantweb/dantweb/vbwd-sdk-2/vbwd-fe-core`.

**Error:**
```
vbwd-view-component (imported by /app/vue/src/stores/checkout.ts) — Are they installed?
```

**Fix:** Changed `../../vbwd-fe-core` to `../vbwd-fe-core` in all docker-compose services.

**Files changed:**
- `vbwd-fe-user/docker-compose.yaml`
- `vbwd-fe-admin/docker-compose.yaml`

---

### 3. Nginx Reverse Proxy Setup (Ports 8080/8081)

**Problem:** No nginx proxy existed. Vite dev servers were exposed directly on ports 5173/5174, but the project expects user app on 8080 and admin app on 8081 with API proxying to backend.

**Fix:** Added nginx services and configuration files for both apps:
- User app: nginx on port 8080, proxies to Vite (dev:5173), backend (host.docker.internal:5000), Socket.IO, and plugin API (plugin-api:3001)
- Admin app: nginx on port 8081, proxies to Vite (dev:5173) and backend

**Key nginx features:**
- `resolver 127.0.0.11 valid=5s` — Docker DNS resolver with TTL to avoid stale IP caching
- Variable-based `proxy_pass` (`set $vite`, `set $backend`) — forces DNS re-resolution on each request

**Files created:**
- `vbwd-fe-user/nginx.dev.conf`
- `vbwd-fe-admin/nginx.dev.conf`

**Files changed:**
- `vbwd-fe-user/docker-compose.yaml` (added nginx service)
- `vbwd-fe-admin/docker-compose.yaml` (added nginx service)

---

### 4. Vite `allowedHosts` — 403 Forbidden

**Problem:** Vite's security feature rejected requests from nginx because the `Host` header didn't match expected values. Since the hostname is configurable (not hardcoded), Vite needs to accept all hosts.

**Error:** `403 Forbidden` when accessing through nginx proxy.

**Fix:** Added `allowedHosts: true` to `server` config in both Vite configurations.

**Files changed:**
- `vbwd-fe-user/vite.config.js`
- `vbwd-fe-admin/vite.config.js`

---

### 5. Vite `envDir` — `.env` Not Read

**Problem:** With `root: './vue'`, Vite looks for `.env` files in `vue/` subdirectory, but `.env` files are in the project root. This caused `VITE_PLUGIN_API_SECRET` and other env vars to not be available at runtime.

**Error:** `HMAC key data must not be empty` on admin settings page.

**Fix:** Added `envDir: resolve(__dirname)` to both Vite configs so `.env` is read from the project root.

**Files changed:**
- `vbwd-fe-user/vite.config.js`
- `vbwd-fe-admin/vite.config.js`

---

### 6. Vite `root` and `build.outDir` for Admin App

**Problem:** Admin app's root-level `vite.config.js` was missing `root: './vue'`, causing build to fail with "Could not resolve entry module index.html". Path aliases (`@`, `@plugins`) pointed to wrong directories.

**Error:**
```
Could not resolve entry module "index.html"
```

**Fix:** Added `root: './vue'`, corrected alias paths (`vue/src`, `plugins`), added `build.outDir: '../dist'`.

**Files changed:**
- `vbwd-fe-admin/vite.config.js`

---

### 7. Rollup Platform Mismatch (Admin — Vite 7)

**Problem:** Admin app uses Vite 7 / Rollup 4 which requires platform-specific native binaries. The `package-lock.json` generated on macOS only includes `@rollup/rollup-darwin-arm64`, but the Docker container runs `linux-arm64-musl`.

**Error:**
```
Cannot find module @rollup/rollup-linux-arm64-musl
```

**Fix:** Changed `npm install` to `npm install --no-package-lock` in the admin's dev container command. This ignores the macOS-specific lockfile and resolves fresh for the container's platform without modifying the host's `package-lock.json`.

**Files changed:**
- `vbwd-fe-admin/docker-compose.yaml`

---

### 8. Plugin API Server Missing from Docker

**Problem:** The user app's plugin API server (Express on port 3001) was not included in docker-compose. Admin's "User Plugins" settings page hit Vite instead of the plugin API, getting HTML back.

**Error:**
```
Unexpected token '<', "<!DOCTYPE "... is not valid JSON
```

**Fix:** Added `plugin-api` service to user app's docker-compose, and added `/_plugins` proxy location in nginx config.

**Files changed:**
- `vbwd-fe-user/docker-compose.yaml` (added `plugin-api` service)
- `vbwd-fe-user/nginx.dev.conf` (added `/_plugins` location)

---

### 9. HMAC Shared Secret Not Configured

**Problem:** Admin app signs requests to user plugin API with HMAC-SHA256, but `VITE_PLUGIN_API_SECRET` (admin) and `PLUGIN_API_SECRET` (user) were not set in either `.env` file.

**Error:** `HMAC key data must not be empty`

**Fix:** Generated a shared 64-character hex secret and added it to both apps' `.env` files and docker-compose environment.

**Files changed:**
- `vbwd-fe-admin/.env` (added `VITE_PLUGIN_API_SECRET`)
- `vbwd-fe-user/.env` (added `PLUGIN_API_SECRET`)
- `vbwd-fe-user/docker-compose.yaml` (plugin-api service env)

---

### 10. Taro Plugin — JWT Authentication Mismatch

**Problem:** Taro plugin routes used `flask_jwt_extended.verify_jwt_in_request()` which is a different JWT library than what the backend uses. The backend signs tokens via PyJWT with `config.SECRET_KEY`, but `flask_jwt_extended` validates against `JWT_SECRET_KEY` — different values.

**Error:**
```
{"message": "Error retrieving limits: Signature verification failed", "success": false}
```

**Fix:** Replaced `verify_jwt_in_request()` + `get_jwt_identity()` with the project's standard `@require_auth` decorator + `g.user_id` across all 7 user-facing taro routes. Removed the `flask_jwt_extended` import.

**Files changed:**
- `vbwd-backend/plugins/taro/src/routes.py`

---

### 11. Makefile Tab/Space Issue

**Problem:** `rebuild-core` target used spaces instead of tabs for the recipe line.

**Error:** `Makefile:43: *** missing separator. Stop.`

**Fix:** Replaced spaces with tab character.

**Files changed:**
- `Makefile`

---

### 12. Demo Data — Token Bundles & Test User Details

**Added:**
- 2 token bundles to `install_demo_data.sh`: 100 tokens (3 EUR), 500 tokens (10 EUR)
- Test user profile details to `reset-database.sh`: Marc Muster, Hugo-Junkers 23, Frankfurt am Main 60386, DE

**Files changed:**
- `vbwd-backend/bin/install_demo_data.sh`
- `vbwd-backend/bin/reset-database.sh`

---

## Files Changed Summary

| File | Action |
|------|--------|
| `vbwd-fe-user/docker-compose.yaml` | Rewritten — volume mounts, nginx, plugin-api service |
| `vbwd-fe-admin/docker-compose.yaml` | Rewritten — volume mounts, nginx, --no-package-lock |
| `vbwd-fe-user/nginx.dev.conf` | Created — reverse proxy config |
| `vbwd-fe-admin/nginx.dev.conf` | Created — reverse proxy config |
| `vbwd-fe-user/vite.config.js` | Added allowedHosts, envDir |
| `vbwd-fe-admin/vite.config.js` | Added root, envDir, allowedHosts, build.outDir, fixed aliases |
| `vbwd-fe-user/.env` | Added PLUGIN_API_SECRET |
| `vbwd-fe-admin/.env` | Added VITE_PLUGIN_API_SECRET |
| `vbwd-backend/plugins/taro/src/routes.py` | Replaced flask_jwt_extended with @require_auth |
| `vbwd-backend/bin/install_demo_data.sh` | Added token bundles |
| `vbwd-backend/bin/reset-database.sh` | Added test user details (Marc Muster) |
| `Makefile` | Fixed tab/space issue |

---

## Current Service Architecture

```
localhost:8080  -->  nginx  -->  Vite dev (fe-user:5173)
                           -->  Backend API (host:5000)  /api/
                           -->  Plugin API (plugin-api:3001)  /_plugins/
                           -->  Socket.IO (host:5000)  /socket.io/

localhost:8081  -->  nginx  -->  Vite dev (fe-admin:5173)
                           -->  Backend API (host:5000)  /api/

localhost:5000  -->  Flask/Gunicorn API (PostgreSQL, Redis)
```

---

## Startup Commands

```bash
# Backend
cd vbwd-backend && make up

# Build core library (required first)
cd vbwd-fe-core && npm install && npm run build

# User app (port 8080)
cd vbwd-fe-user && docker compose --profile dev up -d

# Admin app (port 8081)
cd vbwd-fe-admin && docker compose --profile dev up -d

# Reset database with demo data
cd vbwd-backend && ./bin/reset-database.sh
```