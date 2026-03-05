# Sprint 27: Landing1 Iframe Embed Widget

## Goal

Make the landing1 plugin embeddable on any external website via a simple JS snippet + `<div>` tag. An external site adds a `<script>` tag and places `<div id="vbwd-iframe"></div>` — an iframe appears with the landing1 content. Solve CORS, CSRF, and clickjacking challenges properly.

## Engineering Principles

- **TDD**: Tests first — write failing tests for the embed route, widget script, CORS headers, and iframe communication before implementation
- **SOLID — SRP**: Widget JS handles iframe creation only. Nginx handles CORS headers only. Embed route renders landing1 without layout chrome. Each layer has one job
- **SOLID — OCP**: The embed system is open for extension — future plugins can expose their own embed routes without modifying the widget infrastructure
- **SOLID — DIP**: Widget script depends on configuration (origin URL), not hardcoded values. Embed route depends on the same Landing1View component, not a duplicate
- **Liskov Substitution**: Embed route renders the same Landing1View component as the regular route — content is identical, only the wrapping differs
- **DI**: Widget configuration (API origin, theme, locale) injected via `data-*` attributes on the script tag, not hardcoded
- **Clean Code**: Readable, self-documenting, minimal comments
- **DRY**: Reuse existing `Landing1View.vue` component — zero duplication of plan fetching, rendering, or styling logic. Single nginx CORS config block reused for all embed routes
- **No overengineering**: No postMessage RPC framework, no SDK abstraction layer — just an iframe with proper headers. Add complexity only when needed
- **No backward compatibility**: No shims or fallbacks for the current non-embeddable state

## Testing Approach

All tests MUST pass before the sprint is considered complete. Run via:

```bash
# 1. User frontend tests
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# 2. Admin regression (no admin code changes expected)
cd vbwd-frontend/admin/vue && npx vitest run

# 3. Core regression
cd vbwd-frontend/core && npx vitest run

# 4. Full pre-commit check
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --user --unit
```

---

## Architecture

### How It Works — External Site Integration

**Step 1: External site adds the widget script + container div:**

```html
<!-- On any external website -->
<div id="vbwd-iframe"></div>
<script src="https://your-vbwd-instance.com/embed/widget.js"
        data-origin="https://your-vbwd-instance.com"
        data-locale="en"
        data-theme="light"></script>
```

**Step 2: Widget script creates an iframe:**

```
External Page (example.com)
┌─────────────────────────────────────┐
│ <div id="vbwd-iframe">              │
│   <iframe                           │
│     src="https://vbwd.com/embed/    │
│          landing1?locale=en"        │
│     style="width:100%;border:none"  │
│   ></iframe>                        │
│ </div>                              │
│ <script src="https://vbwd.com/     │
│   embed/widget.js"></script>        │
└─────────────────────────────────────┘
         │
         │ iframe loads
         ▼
VBWD User App (vbwd.com)
┌─────────────────────────────────────┐
│ /embed/landing1                     │
│ ┌─────────────────────────────────┐ │
│ │ Landing1View.vue (no layout)    │ │
│ │ - Fetches plans from /api      │ │
│ │ - Renders plan cards            │ │
│ │ - "Choose Plan" → postMessage   │ │
│ └─────────────────────────────────┘ │
│                                     │
│ Response Headers:                   │
│   X-Frame-Options: removed          │
│   Content-Security-Policy:          │
│     frame-ancestors *               │
│   Access-Control-Allow-Origin: *    │
└─────────────────────────────────────┘
```

### Security Model

| Threat | Mitigation |
|--------|------------|
| **Clickjacking** (iframe used to trick clicks) | Embed route explicitly allows framing via `frame-ancestors *` in CSP. Regular routes keep `X-Frame-Options: DENY`. Only the `/embed/*` path is frameable |
| **CSRF** (forged requests from iframe) | Embed is read-only — landing1 only fetches plans (GET). No state-changing operations. "Choose Plan" button sends `postMessage` to parent instead of navigating (parent decides what to do) |
| **CORS** (API calls from iframe on different origin) | The iframe loads from VBWD origin, so API calls from within the iframe are same-origin. No CORS issue for the iframe content itself. The `widget.js` script is served with permissive CORS since it's a static asset |
| **Data exfiltration** (parent page reading iframe content) | Same-origin policy prevents the parent from accessing iframe DOM. `postMessage` only sends explicit, controlled data (plan selection events) |
| **XSS via query params** | Widget script sanitizes `data-*` attributes. Embed route sanitizes `locale` and `theme` query params against allowlists |

### CORS vs CSRF — Why This Design

**Why iframe (not direct API calls from external site)?**
- Direct API calls from `example.com` to `vbwd.com/api/v1/tarif-plans` would require `Access-Control-Allow-Origin: *` on ALL API endpoints — massive security hole
- Iframe approach: the iframe content loads from `vbwd.com`, so all API calls inside the iframe are same-origin. Zero CORS headers needed on API routes
- Only the `widget.js` static file and the `/embed/*` HTML route need permissive headers

**Why postMessage (not direct navigation)?**
- Inside the iframe, navigating to `/checkout?plan=X` would navigate within the iframe — bad UX
- `postMessage` lets the parent page decide: open checkout in new tab, redirect the whole page, or show a modal
- Parent page validates `event.origin` to only accept messages from the trusted VBWD origin

---

## What Already Exists (NO changes needed)

| File | Provides |
|------|----------|
| `user/plugins/landing1/Landing1View.vue` | Plan fetching, rendering, card grid, responsive layout |
| `user/plugins/landing1/index.ts` | Plugin registration with `/landing1` route |
| `user/vue/src/i18n/` | EN/DE translations for landing1 keys |
| `container/user/nginx.conf` | Nginx config with SPA fallback, API proxy |

---

## What This Sprint Adds

| Layer | File | Provides |
|-------|------|----------|
| Frontend | `user/plugins/landing1/EmbedLanding1View.vue` | Wrapper that renders Landing1View without app layout, with postMessage for plan selection |
| Frontend | `user/plugins/landing1/embed-widget.js` | Standalone JS file that creates the iframe in `#vbwd-iframe` |
| Frontend | `user/plugins/landing1/index.ts` | **MODIFY** — add `/embed/landing1` route |
| Nginx | `container/user/nginx.conf` | **MODIFY** — add `/embed/` location with frame-permissive headers |
| Frontend | `user/vue/src/App.vue` | **MODIFY** — detect embed routes and skip layout |
| Tests | `user/vue/tests/unit/plugins/landing1-embed.spec.ts` | Widget + embed view tests |
| Tests | `user/vue/tests/unit/plugins/embed-widget.spec.ts` | Widget JS unit tests |

---

## Task 1: Embed Landing1 View Component

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/plugins/landing1/EmbedLanding1View.vue` | **NEW** |

### Component Design

`EmbedLanding1View.vue` is a thin wrapper around the existing `Landing1View.vue` that:

1. Renders `Landing1View` without any app chrome (no sidebar, no header, no footer)
2. Intercepts "Choose Plan" navigation and sends `postMessage` to parent window instead
3. Reads `locale` and `theme` from route query params
4. Applies minimal embed-specific styles (clean white background, no margin)

```html
<template>
  <div class="vbwd-embed" :class="themeClass">
    <Landing1View :embed-mode="true" @plan-selected="onPlanSelected" />
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Landing1View from './Landing1View.vue';

const route = useRoute();
const { locale } = useI18n();

const allowedLocales = ['en', 'de'];
const allowedThemes = ['light', 'dark'];

const themeClass = computed(() => {
  const theme = typeof route.query.theme === 'string' ? route.query.theme : 'light';
  return allowedThemes.includes(theme) ? `vbwd-embed--${theme}` : 'vbwd-embed--light';
});

onMounted(() => {
  // Set locale from query param (sanitized against allowlist)
  const queryLocale = typeof route.query.locale === 'string' ? route.query.locale : 'en';
  if (allowedLocales.includes(queryLocale)) {
    locale.value = queryLocale;
  }
});

function onPlanSelected(plan: { slug: string; name: string; price: number; currency: string }) {
  // Send plan selection to parent window via postMessage
  // Parent validates event.origin before acting
  if (window.parent !== window) {
    window.parent.postMessage({
      type: 'vbwd:plan-selected',
      payload: {
        planSlug: plan.slug,
        planName: plan.name,
        price: plan.price,
        currency: plan.currency,
      }
    }, '*');
  }
}
</script>

<style scoped>
.vbwd-embed {
  background: #ffffff;
  min-height: 100vh;
  padding: 20px;
  font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
}

.vbwd-embed--dark {
  background: #111827;
  color: #f3f4f6;
}
</style>
```

### Modify Landing1View.vue

Add `embed-mode` prop and `plan-selected` emit:

```typescript
// Add to Landing1View.vue
const props = defineProps<{
  embedMode?: boolean;
}>();

const emit = defineEmits<{
  (e: 'plan-selected', plan: { slug: string; name: string; price: number; currency: string }): void;
}>();

// Modify "Choose Plan" click handler:
function choosePlan(plan: TarifPlan) {
  if (props.embedMode) {
    emit('plan-selected', {
      slug: plan.slug,
      name: plan.name,
      price: plan.price,
      currency: plan.currency,
    });
  } else {
    router.push(`/checkout?tarif_plan_id=${plan.slug}`);
  }
}
```

This is a minimal, backward-compatible change — when `embedMode` is `false` (default), behavior is identical to current.

---

## Task 2: Embed Widget JavaScript

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/plugins/landing1/embed-widget.js` | **NEW** |

### Widget Design

A standalone, zero-dependency JavaScript file that external sites include. It:

1. Finds the `<div id="vbwd-iframe">` container
2. Reads configuration from `data-*` attributes on its own `<script>` tag
3. Creates an `<iframe>` pointing to `/embed/landing1` on the VBWD instance
4. Listens for `postMessage` events from the iframe
5. Dispatches custom DOM events on the container div for the host page to handle

```javascript
(function() {
  'use strict';

  // Find our script tag to read data attributes
  var scripts = document.querySelectorAll('script[data-origin]');
  var scriptTag = scripts[scripts.length - 1];

  if (!scriptTag) {
    console.error('[VBWD] Widget script must have a data-origin attribute');
    return;
  }

  var origin = scriptTag.getAttribute('data-origin') || '';
  var locale = scriptTag.getAttribute('data-locale') || 'en';
  var theme = scriptTag.getAttribute('data-theme') || 'light';
  var containerId = scriptTag.getAttribute('data-container') || 'vbwd-iframe';
  var height = scriptTag.getAttribute('data-height') || '600';

  // Sanitize origin — must be a valid URL
  try {
    new URL(origin);
  } catch (e) {
    console.error('[VBWD] Invalid data-origin URL:', origin);
    return;
  }

  // Find container
  var container = document.getElementById(containerId);
  if (!container) {
    console.error('[VBWD] Container element #' + containerId + ' not found');
    return;
  }

  // Build iframe URL
  var iframeSrc = origin + '/embed/landing1?locale=' +
    encodeURIComponent(locale) + '&theme=' + encodeURIComponent(theme);

  // Create iframe
  var iframe = document.createElement('iframe');
  iframe.src = iframeSrc;
  iframe.style.width = '100%';
  iframe.style.height = height + 'px';
  iframe.style.border = 'none';
  iframe.style.overflow = 'hidden';
  iframe.setAttribute('title', 'VBWD Plans');
  iframe.setAttribute('loading', 'lazy');
  iframe.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-forms allow-popups');

  container.appendChild(iframe);

  // Listen for postMessage from iframe
  window.addEventListener('message', function(event) {
    // Validate origin — only accept messages from our VBWD instance
    if (event.origin !== origin) {
      return;
    }

    var data = event.data;
    if (!data || typeof data !== 'object' || !data.type) {
      return;
    }

    if (data.type === 'vbwd:plan-selected') {
      // Dispatch custom event on container for host page to handle
      var customEvent = new CustomEvent('vbwd:plan-selected', {
        detail: data.payload,
        bubbles: true
      });
      container.dispatchEvent(customEvent);
    }

    if (data.type === 'vbwd:resize') {
      // Auto-resize iframe to content height
      iframe.style.height = data.payload.height + 'px';
    }
  });
})();
```

### Host Page Usage Example

```html
<div id="vbwd-iframe"></div>
<script src="https://your-vbwd.com/embed/widget.js"
        data-origin="https://your-vbwd.com"
        data-locale="en"
        data-theme="light"
        data-height="700"></script>

<script>
  // Listen for plan selection
  document.getElementById('vbwd-iframe').addEventListener('vbwd:plan-selected', function(e) {
    console.log('User selected plan:', e.detail.planSlug);
    // Redirect to your own checkout, or open VBWD checkout in new tab:
    window.open(e.detail.checkoutUrl, '_blank');
  });
</script>
```

---

## Task 3: Plugin Route Registration

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/plugins/landing1/index.ts` | **MODIFY** |

### Changes

Add the embed route to the landing1 plugin's `install()` hook:

```typescript
install(sdk: IPlatformSDK) {
  // Existing route
  sdk.addRoute({
    path: '/landing1',
    name: 'landing1',
    component: () => import('./Landing1View.vue'),
    meta: { requiresAuth: false }
  });

  // NEW: Embed route (frameable, no layout)
  sdk.addRoute({
    path: '/embed/landing1',
    name: 'landing1-embed',
    component: () => import('./EmbedLanding1View.vue'),
    meta: { requiresAuth: false, embed: true }
  });
},
```

### App.vue — Skip Layout for Embed Routes

Modify `App.vue` to detect `route.meta.embed` and skip the `UserLayout` wrapper:

```typescript
// In App.vue <script setup>
const isEmbedRoute = computed(() => route.meta.embed === true);

// In template — embed routes render without ANY layout chrome
// <UserLayout v-if="isAuthenticated && !isPublicRoute && !isEmbedRoute">
//   <router-view />
// </UserLayout>
// <router-view v-else />
```

This is a single computed property check — minimal change.

---

## Task 4: Nginx Configuration for Embed Routes

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/container/user/nginx.conf` | **MODIFY** |

### Changes

Add a dedicated location block for `/embed/` routes with frame-permissive headers:

```nginx
# Embed routes — allow framing from any origin
# Only /embed/* paths are frameable; all other routes remain protected
location /embed/ {
    # Serve SPA (same as root location)
    root /usr/share/nginx/html;
    try_files $uri $uri/ /index.html;

    # Remove X-Frame-Options to allow iframe embedding
    # (nginx may add this globally — explicitly remove it here)
    proxy_hide_header X-Frame-Options;

    # Allow framing from any origin
    add_header Content-Security-Policy "frame-ancestors *" always;

    # Allow the widget.js to be loaded cross-origin
    add_header Access-Control-Allow-Origin "*" always;
    add_header Access-Control-Allow-Methods "GET, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Content-Type" always;

    # Cache static embed assets
    add_header Cache-Control "public, max-age=3600" always;

    # Prevent MIME type sniffing
    add_header X-Content-Type-Options "nosniff" always;
}

# Widget JS — served as static file with CORS
location = /embed/widget.js {
    alias /usr/share/nginx/html/embed/widget.js;
    add_header Access-Control-Allow-Origin "*" always;
    add_header Content-Type "application/javascript" always;
    add_header Cache-Control "public, max-age=86400" always;
    add_header X-Content-Type-Options "nosniff" always;
}
```

### Key Security Properties

| Header | Value | Why |
|--------|-------|-----|
| `Content-Security-Policy: frame-ancestors *` | Allow any site to embed in iframe | Only on `/embed/*` routes. Regular routes keep `DENY` |
| `Access-Control-Allow-Origin: *` | Allow cross-origin script loading | Only for `widget.js` static file and embed HTML. NOT on `/api/*` |
| `X-Content-Type-Options: nosniff` | Prevent MIME sniffing | Security best practice for served JS files |
| `Cache-Control: public, max-age=3600` | 1 hour cache for embed pages | Balance between freshness and performance |

### What Stays Protected

- `/api/*` — No CORS changes. Same-origin only (iframe loads from VBWD origin, so API calls are same-origin)
- `/` — Keeps `X-Frame-Options: DENY` (not frameable)
- `/_plugins` — HMAC-protected, no CORS changes
- `/login`, `/dashboard/*` — Not frameable, auth-protected

---

## Task 5: Build Pipeline — Copy Widget JS to Dist

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/vue/vite.config.ts` (or `vite.config.js`) | **MODIFY** |
| `vbwd-frontend/container/user/Dockerfile` | **MODIFY** |

### Vite Config

Add `embed-widget.js` to the build output. Since it's a standalone file (not a module), copy it as a static asset:

```typescript
// In vite.config — add to build configuration
// Option A: Copy plugin for static assets
import { defineConfig } from 'vite';

export default defineConfig({
  // ... existing config ...
  build: {
    rollupOptions: {
      // ... existing options ...
    }
  },
  // Copy embed-widget.js to dist/embed/ during build
  plugins: [
    // ... existing plugins ...
    {
      name: 'copy-embed-widget',
      closeBundle() {
        // Copies embed-widget.js to dist/embed/widget.js
        const fs = require('fs');
        const path = require('path');
        const src = path.resolve(__dirname, '../../plugins/landing1/embed-widget.js');
        const destDir = path.resolve(__dirname, 'dist/embed');
        if (!fs.existsSync(destDir)) fs.mkdirSync(destDir, { recursive: true });
        fs.copyFileSync(src, path.join(destDir, 'widget.js'));
      }
    }
  ]
});
```

**Alternative (simpler)**: Place `embed-widget.js` in `user/vue/public/embed/widget.js` — Vite copies `public/` to `dist/` automatically.

### Dockerfile

No changes needed if using `public/` directory approach — Vite build already copies it.

---

## Task 6: Auto-Resize — Iframe Height Communication

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/plugins/landing1/EmbedLanding1View.vue` | **MODIFY** (add resize observer) |

### Design

The embed view observes its own content height and sends `postMessage` to the parent so the widget can resize the iframe dynamically (no scrollbars inside iframe):

```typescript
// Add to EmbedLanding1View.vue <script setup>
import { onMounted, onUnmounted } from 'vue';

let resizeObserver: ResizeObserver | null = null;

onMounted(() => {
  if (window.parent === window) return; // Not in iframe

  resizeObserver = new ResizeObserver((entries) => {
    for (const entry of entries) {
      const height = entry.borderBoxSize?.[0]?.blockSize ?? entry.target.scrollHeight;
      window.parent.postMessage({
        type: 'vbwd:resize',
        payload: { height: Math.ceil(height) }
      }, '*');
    }
  });

  const root = document.querySelector('.vbwd-embed');
  if (root) resizeObserver.observe(root);
});

onUnmounted(() => {
  resizeObserver?.disconnect();
});
```

This keeps the iframe at exactly the right height — no scrollbars, no wasted space.

---

## Task 7: Tests

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/vue/tests/unit/plugins/landing1-embed.spec.ts` | **NEW** |
| `vbwd-frontend/user/vue/tests/unit/plugins/embed-widget.spec.ts` | **NEW** |

### `landing1-embed.spec.ts` — Embed View Tests (~12 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_embed_route_registered` | Plugin registers `/embed/landing1` route with `meta.embed: true` |
| 2 | `test_embed_route_no_auth` | `meta.requiresAuth === false` |
| 3 | `test_embed_renders_landing1` | `EmbedLanding1View` renders `Landing1View` component |
| 4 | `test_embed_no_layout` | No sidebar, no header, no navigation elements |
| 5 | `test_embed_applies_light_theme` | Default theme class is `vbwd-embed--light` |
| 6 | `test_embed_applies_dark_theme` | `?theme=dark` → class `vbwd-embed--dark` |
| 7 | `test_embed_sanitizes_theme` | `?theme=<script>` → falls back to `vbwd-embed--light` |
| 8 | `test_embed_sets_locale_from_query` | `?locale=de` → `locale.value === 'de'` |
| 9 | `test_embed_sanitizes_locale` | `?locale=xx` → stays `en` |
| 10 | `test_plan_selected_sends_postmessage` | Click "Choose Plan" → `window.parent.postMessage` called with `vbwd:plan-selected` |
| 11 | `test_postmessage_payload_shape` | Payload has `planSlug`, `planName`, `price`, `currency` |
| 12 | `test_resize_observer_sends_height` | ResizeObserver callback → `postMessage` with `vbwd:resize` type |

### `embed-widget.spec.ts` — Widget JS Tests (~10 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_creates_iframe_in_container` | `#vbwd-iframe` contains an `<iframe>` element |
| 2 | `test_iframe_src_includes_origin` | `iframe.src` starts with `data-origin` value |
| 3 | `test_iframe_src_includes_locale` | `iframe.src` contains `locale=de` when `data-locale="de"` |
| 4 | `test_iframe_src_includes_theme` | `iframe.src` contains `theme=dark` when `data-theme="dark"` |
| 5 | `test_iframe_has_sandbox_attr` | `iframe.sandbox` includes `allow-scripts allow-same-origin` |
| 6 | `test_iframe_no_border` | `iframe.style.border === 'none'` |
| 7 | `test_invalid_origin_logs_error` | Invalid URL in `data-origin` → `console.error` called, no iframe created |
| 8 | `test_missing_container_logs_error` | No `#vbwd-iframe` div → `console.error` called |
| 9 | `test_postmessage_dispatches_custom_event` | `message` event from valid origin → `vbwd:plan-selected` CustomEvent dispatched on container |
| 10 | `test_postmessage_ignores_wrong_origin` | `message` event from wrong origin → no CustomEvent dispatched |

**Frontend test target: 185 → ~207 (+22: 12 embed view + 10 widget)**

---

## Implementation Order & Dependencies

```
Task 2: Widget JS (no deps — standalone file)
Task 1: EmbedLanding1View + Landing1View modifications (no deps)
  ↓ (Tasks 1 & 2 can run in parallel)
Task 3: Plugin route registration (deps: Task 1)
  ↓
Task 5: Build pipeline — copy widget to dist (deps: Task 2)
  ↓
Task 4: Nginx configuration (deps: Tasks 3, 5)
  ↓
Task 6: Auto-resize (deps: Task 1)
  ↓
Task 7: Tests (deps: all above)
```

---

## New Files Summary

```
user/plugins/landing1/
├── EmbedLanding1View.vue         ← Embed wrapper (no layout, postMessage)
├── embed-widget.js               ← Standalone JS for external sites
user/vue/public/embed/
├── widget.js                     ← Copied from above during build
user/vue/tests/unit/plugins/
├── landing1-embed.spec.ts        ← Embed view tests
├── embed-widget.spec.ts          ← Widget JS tests
```

**Modified files:**
- `user/plugins/landing1/Landing1View.vue` — add `embedMode` prop + `plan-selected` emit
- `user/plugins/landing1/index.ts` — add `/embed/landing1` route
- `user/vue/src/App.vue` — skip layout for `meta.embed` routes
- `container/user/nginx.conf` — add `/embed/` location with frame-permissive headers

---

## Test Targets

| Suite | Before | After | Delta |
|-------|--------|-------|-------|
| User | 185 | ~207 | +22 (embed view + widget tests) |
| Admin | 331 | 331 | 0 (no changes) |
| Core | 300 | 300 | 0 (no changes) |
| Backend | 849 | 849 | 0 (no changes) |
| **Total** | **1665** | **~1687** | **+22** |

## Verification Commands

```bash
# 1. User frontend tests
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# 2. Admin regression
cd vbwd-frontend/admin/vue && npx vitest run

# 3. Core regression
cd vbwd-frontend/core && npx vitest run

# 4. Rebuild containers
cd vbwd-frontend && docker compose up -d --build user-app

# 5. Manual verification — direct embed route
curl -sI http://localhost:8080/embed/landing1 | grep -i 'content-security-policy'
# Expected: content-security-policy: frame-ancestors *

# 6. Manual verification — widget.js served with CORS
curl -sI http://localhost:8080/embed/widget.js | grep -i 'access-control'
# Expected: access-control-allow-origin: *

# 7. Manual verification — regular route NOT frameable
curl -sI http://localhost:8080/landing1 | grep -i 'x-frame-options'
# Expected: x-frame-options: DENY (or no frame-ancestors * in CSP)

# 8. Manual verification — API NOT CORS-open
curl -sI http://localhost:8080/api/v1/tarif-plans | grep -i 'access-control'
# Expected: no Access-Control-Allow-Origin header
```
