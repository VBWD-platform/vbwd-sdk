# VBWD — Usage & Solutions

---

## Pitch

**VBWD is an open-source, self-hosted SaaS platform kit.** Drop it on your server, configure your payment provider, and you have a fully working subscription business — with user portal, admin backoffice, token economy, add-ons, webhooks, and a plugin system that lets you extend everything without touching core code.

---

## Short Description

VBWD (Community Edition) is a self-hosted SaaS billing and subscriber management platform built for developers who want full ownership of their stack. It ships with a Python/Flask REST API, a Vue 3 user-facing storefront, and a Vue 3 admin backoffice — all wired together and ready to run with a single `docker-compose up`.

Out of the box you get:

- Subscription plans with multi-currency pricing and billing periods
- Token economy (buy credits, spend on features)
- Add-ons (purchasable extras on top of plans)
- Invoicing with line-item detail
- Stripe, PayPal, and YooKassa payment integrations (plugin-based, swappable)
- Admin dashboard — users, plans, subscriptions, invoices, analytics, webhooks
- Plugin system on both backend and frontend — extend without modifying core files
- 1,851+ passing tests across the entire stack

Licensed CC0 (public domain). No vendor lock-in, no cloud fees.

---

## Detailed Description

### Who It Is For

| Persona | Use case |
|---------|----------|
| **Indie developer / micro-SaaS founder** | Ship a subscription product without building billing infrastructure from scratch |
| **Agency** | White-label base for client SaaS projects; customize via plugins |
| **Enterprise / internal tools** | Self-hosted subscriber management with full data ownership |
| **Platform builder** | Extend VBWD with plugins to build vertical products (AI tools, content services, booking systems, etc.) |

---

### Core Platform Features

#### Subscription Billing
- Tariff plans with multiple pricing tiers (monthly, annual, custom periods)
- Multi-currency support with exchange rates and regional tax configuration
- Subscription lifecycle: `PENDING → ACTIVE → CANCELLED → EXPIRED`
- Upgrade, downgrade, pause, and cancel operations via API

#### Token Economy
- Users purchase token bundles (credits)
- Plugins consume tokens for premium actions (AI requests, readings, API calls)
- Token balance tracking with transaction history
- Per-plan token limits configurable in plan features JSON

#### Add-Ons
- Purchasable extras on top of base subscriptions
- Admin can bind add-ons to specific tariff plans
- Separate invoicing line items per add-on

#### Invoicing
- Full invoice lifecycle: `INVOICED → PAID → EXPIRED → CANCELLED`
- Line-item detail: subscription, token bundle, add-on charges
- Invoice PDF ready (planned)
- User-facing invoice history with payment links

#### Payment Providers
Payments are provider-agnostic. Each provider is a backend plugin:

| Provider | Status |
|----------|--------|
| Stripe | Implemented — webhooks, checkout, plan sync |
| PayPal | Implemented — order creation, capture, webhooks |
| YooKassa | Implemented — RU-market payment flow |
| Mock provider | Built-in for development and testing |

Switch providers by enabling/disabling plugins in the admin panel — no code changes required.

#### User Management
- JWT-based authentication (register, login, refresh, logout)
- Password reset via token email flow
- User profiles with billing address
- Role-based access control: `USER`, `ADMIN`, `VENDOR`
- Admin can create, edit, and impersonate users

#### Webhooks
- Outbound webhooks on subscription and payment events
- Configurable endpoints per event type
- Retry logic and delivery logs
- Test webhook endpoint for integration verification

#### Analytics
- Active session counts (analytics plugin)
- Subscription and revenue overview in admin dashboard
- Event log for all domain events

---

### Architecture

#### Backend (`vbwd-backend/`)

```
Routes → Services → Repositories → Models
```

- **Framework:** Python 3.11, Flask 3.0
- **Database:** PostgreSQL 16 with Alembic migrations (35 models)
- **Cache / Pub-Sub:** Redis 7
- **Auth:** JWT (access + refresh tokens, bcrypt password hashing)
- **DI:** `dependency-injector` throughout — every service is injectable and testable
- **Events:** Domain event dispatcher with typed event classes and handler modules
- **65+ REST API endpoints** across auth, user, admin, webhook, and plugin namespaces

**API namespace overview:**

| Namespace | Purpose |
|-----------|---------|
| `POST /api/v1/auth/*` | Register, login, logout, password reset |
| `GET/PUT /api/v1/user/*` | Profile, billing address, subscriptions, invoices, tokens, add-ons |
| `GET /api/v1/tarif-plans/*` | Public plan catalog |
| `POST /api/v1/checkout` | Purchase flow |
| `GET /api/v1/invoices/*` | Invoice history and detail |
| `GET /api/v1/settings/*` | Countries, payment methods, terms |
| `* /api/v1/admin/*` | Full admin operations (auth-gated, admin role required) |
| `POST /api/v1/webhooks/*` | Inbound payment provider callbacks |
| `* /api/v1/plugins/*` | Plugin-registered endpoints (dynamic) |

#### Frontend Core Library (`vbwd-fe-core/`)

Shared Vue 3 component library published as `vbwd-view-component`. Used by both user and admin apps via git submodule.

- Plugin registry with dependency resolution (topological sort)
- Type-safe Axios API client with JWT interceptors and token refresh
- Auth service, event bus, validation (Zod), access control guards
- Base UI components (buttons, modals, tables, forms, cards)
- Pinia stores (auth, cart, subscriptions)

#### User App (`vbwd-fe-user/` — port 8080)

Plugin-based Vue 3 SPA. Core app is a minimal shell; all features are delivered as plugins:

| Plugin | Routes |
|--------|--------|
| `landing1` | `/` — Marketing landing page with pricing, embeddable via JS widget |
| `checkout` | `/checkout` — Multi-step purchase flow |
| `stripe` / `paypal` / `yookassa` | Payment form components |
| `theme-switcher` | `/dashboard/theme` — 5 color presets, CSS-var based |
| `chat` | `/dashboard/chat` — LLM AI chat, token-billed |
| `cms` | `/:slug` — Dynamic CMS pages |

Core authenticated routes (always present): Dashboard, Profile, Subscription, Invoices, Plans, Tokens, Add-Ons.

#### Admin App (`vbwd-fe-admin/` — port 8081)

Flat-structure Vue 3 backoffice (no plugin dependency for core views):

| Section | Capabilities |
|---------|-------------|
| Dashboard | KPIs, revenue overview, active sessions |
| Users | List, create, edit, view details, subscription history |
| Plans | CRUD, pricing tiers, feature flags, add-on binding |
| Subscriptions | View, create, cancel, details |
| Invoices | List, detail, status management |
| Add-Ons | CRUD, plan binding |
| Token Bundles | Define credit packages |
| Payment Methods | Enable/disable, ordering, i18n labels |
| Countries | Enable/disable, ordering |
| Analytics | Revenue and session charts |
| Webhooks | Endpoints, delivery logs |
| Settings | Plugin management, config, enable/disable |

---

### Plugin System

The defining architectural principle: **core is agnostic, plugins are gnostic.**

Core files are never modified for business-specific features. Every extension lives in its own plugin directory.

#### Backend Plugins

```
plugins/<name>/
├── __init__.py          # Plugin class (auto-discovered)
├── config.json          # Config schema (types, defaults)
├── admin-config.json    # Admin UI layout
└── src/
    ├── models/          # SQLAlchemy models
    ├── repositories/    # Data access
    ├── services/        # Business logic
    └── routes.py        # Flask blueprint (dynamic registration)
```

Plugin lifecycle: `DISCOVERED → REGISTERED → INITIALIZED → ENABLED ↔ DISABLED`

State persisted to `plugins/plugins.json` — survives Gunicorn worker restarts. Enable/disable via admin panel with no server restart required.

**Built-in backend plugins:**

| Plugin | Description |
|--------|-------------|
| `analytics` | Active session counts, dashboard widget |
| `cms` | Full CMS: pages, categories, image uploads, slug routing |
| `chat` | LLM AI chat with OpenAI-compatible adapter, token billing, 3 counting strategies |
| `taro` | AI Tarot reading — 3-card spreads, follow-ups, per-plan daily limits |
| `stripe` | Stripe checkout, webhooks, plan sync |
| `paypal` | PayPal orders, capture, webhooks |
| `yookassa` | YooKassa payment flow |
| `demoplugin` | Reference implementation for plugin authors |

#### Frontend Plugins

```typescript
const myPlugin: IPlugin = {
  name: 'my-feature',
  version: '1.0.0',
  install(sdk) {
    sdk.addRoute({ path: '/my-page', component: () => import('./MyPage.vue') });
    sdk.createStore('myStore', { state: () => ({ data: null }) });
    sdk.addTranslations('en', { my_feature: { title: 'My Feature' } });
  },
  activate() {},
  deactivate() {}
};
```

Plugins can add routes, Pinia stores, Vue components, and translations. Nav links automatically show/hide based on plugin enabled state.

---

### Solutions by Use Case

#### "I need a subscription SaaS, fast"

1. Run `./recipes/dev-install-ce.sh` — clones all repos, installs dependencies, starts services
2. Configure payment provider credentials in admin settings
3. Define your tariff plans (name, price, billing period, feature flags)
4. Customize landing page via `landing1` plugin
5. Go live

#### "I need a token-based AI product"

Use the token economy + AI chat plugin as your base:
- Define token bundles (e.g. 100 tokens for $5)
- Per-plan daily limits and per-action token costs
- LLM adapter supports any OpenAI-compatible endpoint (OpenAI, Azure, local Ollama)
- Admin can reset user quotas, view consumption

See `plugins/chat/` and `plugins/taro/` as reference implementations.

#### "I need to embed the pricing page on an external site"

The `landing1` plugin ships a zero-dependency JS widget:
```html
<script src="https://your-domain.com/embed-widget.js"></script>
<div id="vbwd-pricing"></div>
```

The widget renders an iframe with sandbox isolation, postMessage communication, and origin-validated security. The iframe route (`/embed/*`) has frame-permissive CSP headers; all other routes have `X-Frame-Options: DENY`.

#### "I need CMS-managed content pages"

Enable the `cms` backend plugin and the frontend `cms` plugin:
- Admin creates pages with rich content, categories, and images
- Pages served at `/:slug` — dynamic slug routing on the frontend
- Image upload API with local storage (S3-compatible storage planned)
- Full CRUD admin UI auto-registered in the admin panel

#### "I need a white-label product with custom branding"

- Theme switcher plugin: 5 presets, 16 CSS custom properties, localStorage persistence
- All colors are CSS variables with fallbacks — no regression when plugin is off
- Plugin i18n: each plugin owns its own `locales/{en,de}.json` — no global key pollution
- Override any view by adding a plugin that registers the same route path

#### "I need multiple payment providers"

Each payment provider is a separate plugin. Enable multiple simultaneously — the user selects their preferred method at checkout. No code changes; just enable the plugins in admin settings.

---

### Testing

| Suite | Count | Tool |
|-------|-------|------|
| Backend unit + integration | 661 | pytest |
| Stripe plugin | 76 | pytest |
| PayPal plugin | 55 | pytest |
| YooKassa plugin | 57 | pytest |
| Chat plugin (backend) | 62 | pytest |
| Core library | 316 | Vitest |
| User app | 293 | Vitest + Playwright |
| Admin app | 331 | Vitest + Playwright |
| **Total** | **1,851** | |

All tests pass. TDD is the development standard — no feature ships without tests.

Test credentials:
- Admin: `admin@example.com` / `AdminPass123@`
- User: `test@example.com` / `TestPass123@`

---

### Tech Stack Summary

| Layer | Technology |
|-------|-----------|
| Backend API | Python 3.11, Flask 3.0, Gunicorn |
| Database | PostgreSQL 16, SQLAlchemy 2.0, Alembic |
| Cache | Redis 7 |
| Frontend | Vue 3, TypeScript, Vite, Pinia, Vue Router 4 |
| Validation | Zod (frontend), marshmallow (backend) |
| Auth | JWT (access + refresh), bcrypt |
| Testing | pytest, Vitest, Playwright |
| Infrastructure | Docker, Docker Compose, Nginx |
| License | BSL 1.1 (Business Source Licence) |

---

### Quick Start

```bash
# Full setup: backend + all 3 frontend repos
./recipes/dev-install-ce.sh

# Start backend services
cd vbwd-backend && make up

# Start user app (port 8080)
cd vbwd-fe-user && npm run dev

# Start admin app (port 8081)
cd vbwd-fe-admin && npm run dev
```

Environment variables: copy `.env.example` to `.env` in `vbwd-backend/`. Required: `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET_KEY`.

---

### Roadmap

| Item | Status |
|------|--------|
| Stripe, PayPal, YooKassa payments | Done |
| CMS plugin (pages, categories, images) | Done |
| LLM AI chat plugin | Done |
| Token economy + billing | Done |
| Embeddable pricing widget | Done |
| Plugin i18n system | Done |
| Dashboard color themes | Done |
| GitHub Repo Manager plugin | Planned |
| PDF invoice generation | Planned |
| Celery async task queue | Planned |
| GraphQL API | Planned |
| Marketplace Edition (multi-vendor SaaS) | Future |

---

*License: CC0 1.0 Universal — public domain. No attribution required.*
