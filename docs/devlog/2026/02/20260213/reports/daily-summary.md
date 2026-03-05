# Daily Report — 2026-02-13

## Overview

Completed 4 full sprints (27–30) plus a Sprint 31 bugfix. Focus areas: iframe embed widget, plugin i18n system, dashboard theming, LLM chat plugin, and dynamic nav visibility for disabled plugins.

## Sprint Summary

| Sprint | Description | New Tests | Status |
|--------|-------------|-----------|--------|
| 27 | Landing1 Iframe Embed Widget | +25 | DONE |
| 28 | Plugin i18n System | +26 | DONE |
| 29 | Dashboard Color Theme Plugin | +36 | DONE |
| 30 | LLM Chat Plugin (full-stack) | +99 | DONE |
| 31 | Hide nav items for disabled plugins | 0 (existing tests cover) | DONE |

**Total new tests today: +186** (1690 → 1851 after Sprints 27–30, verified 1851 stable after Sprint 31)

---

## Sprint 27: Landing1 Iframe Embed Widget

**Goal:** Make the landing1 pricing page embeddable on external websites via a JS widget + iframe.

**Key deliverables:**
- `EmbedLanding1View.vue` — chrome-free wrapper that communicates via `postMessage`
- `embed-widget.js` — zero-dependency IIFE script for external sites
- Nginx config with frame-permissive headers for `/embed/*` routes only
- Security: origin-validated postMessage, sandboxed iframe, allowlist-sanitized query params
- Regular routes protected with `X-Frame-Options: DENY`

**Files:** 5 new, 5 modified | **Tests:** +25 (13 embed view + 12 widget)

---

## Sprint 28: Plugin i18n System

**Goal:** Let plugins bundle their own translations instead of polluting global locale files.

**Key deliverables:**
- `PlatformSDK.addTranslations(locale, messages)` — merges into vue-i18n via `mergeLocaleMessage()`
- `deepMerge` utility for recursive object merging
- Per-plugin `locales/{en,de}.json` for all 5 user plugins (landing1, checkout, stripe, paypal, yookassa)
- Trimmed global `en.json`/`de.json` — removed plugin-specific keys

**Files:** 10 new locale files, 7 modified | **Tests:** +26 (8 deep-merge + 8 SDK + 10 integration)

---

## Sprint 29: Dashboard Color Theme Plugin

**Goal:** User-facing plugin to switch dashboard color theme with persistence.

**Key deliverables:**
- 5 presets: Default Blue, Dark, Forest Green, Ocean, Sunset
- 16 CSS custom properties with fallback values — zero regression without plugin
- `ThemeSelectorView.vue` — grid of theme preview cards with miniature mockups
- `localStorage` persistence via `vbwd_theme` key
- All hardcoded colors in `App.vue`, `UserLayout.vue`, `Dashboard.vue`, `Profile.vue` converted to CSS vars

**Files:** 8 new, 6 modified | **Tests:** +36 (21 presets + 7 apply/clear + 8 lifecycle)

---

## Sprint 30: LLM Chat Plugin (Full-Stack)

**Goal:** Token-billed AI chat at `/dashboard/chat` with admin-configurable LLM provider.

**Backend:**
- `ChatPlugin`, `LLMAdapter` (OpenAI-compatible), `ChatService`
- 3 `TokenCountingStrategy` implementations: WordCount, DataVolume, Tokenizer
- Routes: `POST /send`, `GET /config` (never exposes api_key), `POST /estimate`
- 62 backend tests

**Frontend:**
- `ChatView`, `ChatHeader`, `ChatMessage`, `ChatInput` components
- Real-time balance display, cost estimation, message history
- EN/DE locales, plugin config schema
- 37 frontend tests

**Files:** 14 new backend, 14 new frontend | **Tests:** +99 (62 backend + 37 frontend)

---

## Sprint 31: Hide Nav Items for Disabled Plugins

**Goal:** When plugins are disabled via admin panel, hide their nav links on next page refresh.

**Problem:** Plugin routes were correctly not registered when disabled, but nav links in `UserLayout.vue` were hardcoded — leading to visible links that 404.

**Solution:**
- `main.ts`: Build a `reactive(new Set<string>)` of enabled plugin names, provided via `app.provide('enabledPlugins', ...)`
- `UserLayout.vue`: `inject('enabledPlugins')`, added `v-if="enabledPlugins.has('theme-switcher')"` and `v-if="enabledPlugins.has('chat')"` on plugin nav links
- Core nav items (Dashboard, Profile, Subscription, Invoices, Plans, Tokens, Add-ons) remain unconditional

**Files:** 2 modified (`main.ts`, `UserLayout.vue`) | **Tests:** 293 user + 331 admin = 624 all passing

---

## Final Test Counts

| Suite | Count | Status |
|-------|-------|--------|
| Core | 316 | passing |
| User | 293 | passing |
| Admin | 331 | passing |
| Backend unit | 661 | passing (4 skipped) |
| Stripe plugin | 76 | passing |
| PayPal plugin | 55 | passing |
| YooKassa plugin | 57 | passing |
| Chat plugin (backend) | 62 | passing |
| **Total** | **1851** | **all passing** |

## Architecture Highlights

- **Plugin isolation**: Each plugin owns its routes, translations, config, and tests — no global pollution
- **CSS variable theming**: 16 vars with fallbacks ensure zero regression when theme plugin is disabled
- **Dynamic nav**: Nav links tied to runtime plugin registry — disable a plugin, nav updates on refresh
- **Security-first embed**: iframe sandboxing, origin validation, CSP headers, same-origin API calls
- **Strategy pattern**: 3 interchangeable token counting modes for chat billing flexibility
