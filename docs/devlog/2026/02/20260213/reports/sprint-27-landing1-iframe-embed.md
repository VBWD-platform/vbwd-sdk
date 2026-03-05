# Sprint 27: Landing1 Iframe Embed Widget — Report

**Date:** 2026-02-13
**Status:** DONE
**Priority:** HIGH

## Summary

Made the landing1 plugin embeddable on any external website via a JS widget + iframe. External sites add a `<script>` tag and a `<div id="vbwd-iframe">` — an iframe appears with the landing1 content. Solved CORS, CSRF, and clickjacking challenges using an iframe-based architecture where API calls remain same-origin.

## What Was Implemented

### 1. Landing1View.vue — embedMode Support

Added `embedMode` prop and `plan-selected` emit to the existing `Landing1View.vue` component. When `embedMode` is `true`, clicking "Choose Plan" emits an event instead of navigating to `/checkout`. Backward-compatible — when `embedMode` is `false` (default), behavior is identical to current.

**Files modified:**
- `user/plugins/landing1/Landing1View.vue` — added props, emit, and conditional choosePlan logic

### 2. EmbedLanding1View.vue — Embed Wrapper

Created a thin wrapper around `Landing1View` that:
- Renders without any app chrome (no sidebar, no header, no SessionExpiredModal)
- Intercepts `plan-selected` events and forwards via `window.parent.postMessage()`
- Reads `locale` and `theme` from query params with allowlist sanitization
- Applies light/dark theme class
- Uses ResizeObserver to auto-communicate content height to parent via postMessage

**Files created:**
- `user/plugins/landing1/EmbedLanding1View.vue`

### 3. Embed Widget JavaScript

Created a standalone, zero-dependency IIFE script that external sites include:
- Reads configuration from `data-*` attributes on its `<script>` tag
- Creates a sandboxed iframe pointing to `/embed/landing1`
- Listens for `postMessage` events from the iframe (origin-validated)
- Dispatches `CustomEvent`s on the container for the host page to handle
- Auto-resizes iframe on `vbwd:resize` messages

**Files created:**
- `user/plugins/landing1/embed-widget.js` — source
- `user/vue/public/embed/widget.js` — copy in Vite public dir (auto-copied to dist)

### 4. Plugin Route Registration

Added `/embed/landing1` route to the landing1 plugin with `meta: { embed: true, requiresAuth: false }`. Updated `App.vue` to detect `route.meta.embed` and skip the UserLayout wrapper and SessionExpiredModal.

**Files modified:**
- `user/plugins/landing1/index.ts` — added embed route
- `user/vue/src/App.vue` — added `isEmbedRoute` computed, 3-way template conditional

### 5. Nginx Configuration

Added dedicated location blocks for embed routes with frame-permissive headers:
- `/embed/widget.js` — static JS with `Access-Control-Allow-Origin: *`
- `/embed/` — SPA fallback with `Content-Security-Policy: frame-ancestors *` and CORS headers
- `/` — now explicitly sets `X-Frame-Options: DENY` to prevent framing of regular routes

**Files modified:**
- `container/user/nginx.conf` — added 2 new location blocks, updated root location

### 6. Tests

Created 2 new test files with 25 tests total:

**`landing1-embed.spec.ts`** (13 tests):
- Embed route registered with correct path and meta
- Both regular and embed routes registered (2 routes)
- EmbedLanding1View renders Landing1View with `embedMode: true`
- Light/dark theme from query params, sanitization of invalid themes
- Locale setting from query params, sanitization of invalid locales
- postMessage sent on plan-selected with correct payload shape

**`embed-widget.spec.ts`** (12 tests):
- Creates iframe in container with correct src
- Locale and theme included in iframe URL
- Sandbox attribute set, border none, custom height
- Error logging for invalid origin and missing container
- Origin-validated postMessage dispatches CustomEvent
- Ignores messages from wrong origin
- Resize message updates iframe height

### 7. Existing Test Fix

Updated `landing1.spec.ts` to account for the new embed route — changed `expect(routes).toHaveLength(1)` to `routes.find()` assertion since the plugin now registers 2 routes.

## Security Model

| Concern | Mitigation |
|---------|-----------|
| **Clickjacking** | Only `/embed/*` routes allow framing (`frame-ancestors *`). Regular routes have `X-Frame-Options: DENY` |
| **CSRF** | Embed is read-only — only fetches plans (GET). "Choose Plan" sends postMessage, doesn't mutate state |
| **CORS on API** | Not needed — iframe loads from VBWD origin, so API calls are same-origin. Only widget.js and embed HTML have CORS headers |
| **XSS via query params** | `locale` and `theme` sanitized against explicit allowlists |
| **Data exfiltration** | Same-origin policy prevents parent from reading iframe DOM. Only explicit postMessage data is shared |
| **Replay/injection via postMessage** | Widget validates `event.origin` against the configured VBWD origin |
| **Iframe abuse** | `sandbox` attribute restricts iframe capabilities to `allow-scripts allow-same-origin allow-forms allow-popups` |

## External Site Usage

```html
<div id="vbwd-iframe"></div>
<script src="https://your-vbwd.com/embed/widget.js"
        data-origin="https://your-vbwd.com"
        data-locale="en"
        data-theme="light"
        data-height="700"></script>

<script>
  document.getElementById('vbwd-iframe').addEventListener('vbwd:plan-selected', function(e) {
    console.log('Plan selected:', e.detail.planSlug, e.detail.planName, e.detail.price);
  });
</script>
```

## Test Results

| Suite | Before | After | Delta |
|-------|--------|-------|-------|
| User | 185 | 210 | +25 (13 embed view + 12 widget) |
| Admin | 331 | 331 | 0 (no changes) |
| Core | 300 (1 skipped) | 300 (1 skipped) | 0 (no changes) |
| Backend | 849 (4 skipped) | 849 (4 skipped) | 0 (no changes) |
| **Total** | **1665** | **1690** | **+25** |

## Files Changed

| Action | File |
|--------|------|
| NEW | `user/plugins/landing1/EmbedLanding1View.vue` |
| NEW | `user/plugins/landing1/embed-widget.js` |
| NEW | `user/vue/public/embed/widget.js` |
| NEW | `user/vue/tests/unit/plugins/landing1-embed.spec.ts` (13 tests) |
| NEW | `user/vue/tests/unit/plugins/embed-widget.spec.ts` (12 tests) |
| MODIFY | `user/plugins/landing1/Landing1View.vue` — embedMode prop + plan-selected emit |
| MODIFY | `user/plugins/landing1/index.ts` — added /embed/landing1 route |
| MODIFY | `user/vue/src/App.vue` — embed route detection, skip layout |
| MODIFY | `container/user/nginx.conf` — embed location blocks with CORS/CSP headers |
| MODIFY | `user/vue/tests/unit/plugins/landing1.spec.ts` — updated route count assertion |
