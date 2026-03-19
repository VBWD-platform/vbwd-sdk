# VBWD-SDK Architecture

**Project:** VBWD-SDK - Digital Subscriptions & SaaS Sales Platform
**Status:** Active Development
**Last Updated:** 2026-01-02
**License:** BSL 1.1 (Business Source Licence)

---

## Implementation Status (2026-01-02)

| Feature | Status | Notes |
|---------|--------|-------|
| **User Management** | ✅ Implemented | Registration, login, profile, JWT auth |
| **Tariff Plans** | ✅ Implemented | CRUD, features, limits, billing periods |
| **Subscriptions** | ✅ Implemented | Create, cancel, extend, upgrade/downgrade |
| **Invoices** | ✅ Implemented | Generation, status tracking, PDF ready |
| **Admin API** | ✅ Implemented | Full CRUD for all entities |
| **Analytics API** | ✅ Implemented | Overview, revenue, user metrics |
| **Webhook System** | ✅ Implemented | Event dispatch, retry logic |
| **Event System** | ✅ Implemented | Domain events with handlers |
| **SDK Adapter Pattern** | ✅ Implemented | MockAdapter, interface ready |
| **Plugin System** | ✅ Implemented | BasePlugin, PluginManager, lifecycle |
| **Payment Integration** | ⏳ Planned | Stripe/PayPal adapters |
| **Multi-tenancy** | ⏳ Planned | Future ME edition |

### Plugin System (Backend)

Located in `src/plugins/`:

| File | Purpose |
|------|---------|
| `base.py` | `BasePlugin` ABC, `PluginMetadata`, `PluginStatus` |
| `manager.py` | `PluginManager` - registration, lifecycle, dependencies |
| `payment_provider.py` | `PaymentProviderPlugin` interface |
| `providers/mock_payment_plugin.py` | Mock payment provider for testing |

**Plugin Lifecycle:**
```
DISCOVERED → REGISTERED → INITIALIZED → ENABLED ⇄ DISABLED
```

**Usage:**
```python
from src.plugins.manager import PluginManager
from src.plugins.providers.mock_payment_plugin import MockPaymentPlugin

manager = PluginManager(event_dispatcher)
manager.register_plugin(MockPaymentPlugin())
manager.initialize_plugin("mock_payment", config={})
manager.enable_plugin("mock_payment")
```

**Backend Tests:** 292 unit + integration tests
**Frontend Tests:** 71 unit tests, 108 E2E tests (admin)

---

## 1. Project Overview

VBWD-SDK is a headless Python Flask API backend for digital subscriptions and SaaS sales. The platform provides:

- **User management** with separated public/private data
- **Tariff plans** for subscription-based services
- **Subscription lifecycle** management
- **Invoice & payment processing** via PayPal/Stripe
- **Primitive internal admin** for basic operations

### Business Model

Users browse tariff plans on a static frontend, select a plan, proceed to checkout, and complete payment via PayPal or Stripe. The backend manages subscriptions, invoices, and user data.

---

## 2. System Architecture

### 2.1 Container Architecture (Docker)

```
+---------------------------------------------------------------------+
|                        VBWD-SDK Stack                                |
+---------------------------------------------------------------------+
|                                                                      |
|   +--------------+     +---------------+     +--------------+        |
|   |  frontend    |     |    python     |     |   postgres   |        |
|   |  (Vue.js)    |<--->|   (Flask)     |<--->|    (DB)      |        |
|   +--------------+     +---------------+     +--------------+        |
|         |                    |                     |                 |
|         |                    |                     |                 |
|         v                    v                     v                 |
|   +---------------------------------------------------------------+  |
|   |                    data/ (volumes)                            |  |
|   |   +-- python/logs/                                            |  |
|   |   +-- frontend/logs/                                          |  |
|   |   +-- postgres/ (binary data)                                 |  |
|   +---------------------------------------------------------------+  |
|                                                                      |
|                    +-------------------------+                       |
|                    |  External Services      |                       |
|                    |  - PayPal API           |                       |
|                    |  - Stripe API           |                       |
|                    |  - Email Service        |                       |
|                    +-------------------------+                       |
|                                                                      |
+---------------------------------------------------------------------+
```

### 2.2 Technology Stack

| Layer           | Technology         | Container  |
|-----------------|--------------------|------------|
| Frontend (User) | Vue.js 3           | frontend   |
| Frontend (Admin)| Vue.js 3           | frontend   |
| Backend API     | Python 3 / Flask   | python     |
| Database        | PostgreSQL 16      | postgres   |
| Payments        | PayPal, Stripe     | external   |

### 2.3 API Architecture (Headless)

The backend is a pure REST API with no server-side rendering:

```
+------------------+          +------------------+
|  Static Frontend |   HTTP   |  Flask REST API  |
|  (Vue.js SPA)    | <------> |  /api/v1/*       |
+------------------+          +------------------+
                                     |
                              +------+------+
                              |             |
                        +-----v-----+ +-----v-----+
                        | PostgreSQL| | External  |
                        |  Database | | APIs      |
                        +-----------+ +-----------+
```

---

## 3. Data Model

### 3.1 Entity Overview

| Entity            | Purpose                                         |
|-------------------|-------------------------------------------------|
| `user`            | Core user record (login, status, indexes)       |
| `user_details`    | Private user data (name, address, phone)        |
| `user_case`       | Case/project description for the subscription   |
| `currency`        | Supported currencies with exchange rates        |
| `tax`             | VAT and regional tax configurations             |
| `tax_rate`        | Historical tax rates for auditing               |
| `tarif_plan`      | Available subscription plans (base pricing)     |
| `tarif_plan_price`| Multi-currency pricing overrides                |
| `subscription`    | User's active/inactive subscriptions            |
| `user_invoice`    | Payment records with tax breakdown              |

### 3.2 Entity Relationship Diagram

See: `puml/data-model.puml`

```
+----------------+       +------------------+
|     user       |       |   user_details   |
+----------------+       +------------------+
| id (PK)        |<------| user_id (FK)     |
| email          |       | first_name       |
| password_hash  |       | last_name        |
| status         |       | address_line_1   |
| role           |       | address_line_2   |
| created_at     |       | city             |
| updated_at     |       | postal_code      |
+----------------+       | country          |
       |                 | phone            |
       |                 +------------------+
       |
       |         +------------------+
       |         |    user_case     |
       |         +------------------+
       +-------->| id (PK)          |
       |         | user_id (FK)     |
       |         | description      |
       |         | date_started     |
       |         | status           |
       |         | created_at       |
       |         +------------------+
       |
       |         +------------------+
       |         |   subscription   |
       |         +------------------+
       +-------->| id (PK)          |
       |         | user_id (FK)     |
       |         | tarif_plan_id(FK)|-------+
       |         | status           |       |
       |         | started_at       |       |
       |         | expires_at       |       |
       |         | created_at       |       |
       |         +------------------+       |
       |                                    |
       |         +------------------+       |   +------------------+
       |         |   user_invoice   |       |   |   tarif_plan     |
       |         +------------------+       |   +------------------+
       +-------->| id (PK)          |       +-->| id (PK)          |
                 | user_id (FK)     |           | name             |
                 | tarif_plan_id(FK)|---------->| description      |
                 | subscription_id  |           | price            |
                 | amount           |           | currency         |
                 | currency         |           | billing_period   |
                 | status           |           | features (JSON)  |
                 | payment_method   |           | is_active        |
                 | payment_ref      |           | created_at       |
                 | invoiced_at      |           +------------------+
                 | paid_at          |
                 | created_at       |
                 +------------------+
```

### 3.3 Entity Details

#### 3.3.1 User (`user`)

| Field          | Type         | Description                              |
|----------------|--------------|------------------------------------------|
| `id`           | BIGINT PK    | Auto-increment primary key               |
| `email`        | VARCHAR(255) | Unique, indexed, login identifier        |
| `password_hash`| VARCHAR(255) | Bcrypt hashed password                   |
| `status`       | ENUM         | `pending`, `active`, `suspended`, `deleted` |
| `role`         | ENUM         | `user`, `admin`                          |
| `created_at`   | DATETIME     | Account creation timestamp               |
| `updated_at`   | DATETIME     | Last modification timestamp              |

**Indexes:**
- `idx_user_email` (UNIQUE) on `email`
- `idx_user_status` on `status`
- `idx_user_created_at` on `created_at`

#### 3.3.2 User Details (`user_details`)

| Field           | Type         | Description                             |
|-----------------|--------------|-----------------------------------------|
| `id`            | BIGINT PK    | Auto-increment primary key              |
| `user_id`       | BIGINT FK    | Reference to `user.id`                  |
| `first_name`    | VARCHAR(100) | User's first name                       |
| `last_name`     | VARCHAR(100) | User's last name                        |
| `address_line_1`| VARCHAR(255) | Primary address line                    |
| `address_line_2`| VARCHAR(255) | Secondary address line (optional)       |
| `city`          | VARCHAR(100) | City                                    |
| `postal_code`   | VARCHAR(20)  | Postal/ZIP code                         |
| `country`       | VARCHAR(2)   | ISO 3166-1 alpha-2 country code         |
| `phone`         | VARCHAR(20)  | Phone number with country code          |
| `created_at`    | DATETIME     | Record creation timestamp               |
| `updated_at`    | DATETIME     | Last modification timestamp             |

**Indexes:**
- `idx_user_details_user_id` (UNIQUE) on `user_id`

#### 3.3.3 User Case (`user_case`)

| Field          | Type         | Description                              |
|----------------|--------------|------------------------------------------|
| `id`           | BIGINT PK    | Auto-increment primary key               |
| `user_id`      | BIGINT FK    | Reference to `user.id`                   |
| `description`  | TEXT         | Case/project description                 |
| `date_started` | DATE         | When the case/project started            |
| `status`       | ENUM         | `draft`, `active`, `completed`, `archived` |
| `created_at`   | DATETIME     | Record creation timestamp                |
| `updated_at`   | DATETIME     | Last modification timestamp              |

**Indexes:**
- `idx_user_case_user_id` on `user_id`
- `idx_user_case_status` on `status`

#### 3.3.4 Tariff Plan (`tarif_plan`)

| Field           | Type          | Description                            |
|-----------------|---------------|----------------------------------------|
| `id`            | BIGINT PK     | Auto-increment primary key             |
| `name`          | VARCHAR(100)  | Plan display name                      |
| `slug`          | VARCHAR(100)  | URL-friendly identifier                |
| `description`   | TEXT          | Plan description                       |
| `price`         | DECIMAL(10,2) | Plan price                             |
| `currency`      | VARCHAR(3)    | ISO 4217 currency code (EUR, USD)      |
| `billing_period`| ENUM          | `monthly`, `quarterly`, `yearly`, `one_time` |
| `features`      | JSON          | Feature list as JSON array             |
| `is_active`     | BOOLEAN       | Whether plan is available for purchase |
| `sort_order`    | INT           | Display order                          |
| `created_at`    | DATETIME      | Record creation timestamp              |
| `updated_at`    | DATETIME      | Last modification timestamp            |

**Indexes:**
- `idx_tarif_plan_slug` (UNIQUE) on `slug`
- `idx_tarif_plan_is_active` on `is_active`

#### 3.3.5 Subscription (`subscription`)

| Field          | Type         | Description                              |
|----------------|--------------|------------------------------------------|
| `id`           | BIGINT PK    | Auto-increment primary key               |
| `user_id`      | BIGINT FK    | Reference to `user.id`                   |
| `tarif_plan_id`| BIGINT FK    | Reference to `tarif_plan.id`             |
| `status`       | ENUM         | `active`, `inactive`, `cancelled`, `expired` |
| `started_at`   | DATETIME     | Subscription start date                  |
| `expires_at`   | DATETIME     | Subscription expiration date             |
| `cancelled_at` | DATETIME     | When subscription was cancelled (null)   |
| `created_at`   | DATETIME     | Record creation timestamp                |
| `updated_at`   | DATETIME     | Last modification timestamp              |

**Indexes:**
- `idx_subscription_user_id` on `user_id`
- `idx_subscription_status` on `status`
- `idx_subscription_expires_at` on `expires_at`

#### 3.3.6 User Invoice (`user_invoice`)

| Field            | Type          | Description                           |
|------------------|---------------|---------------------------------------|
| `id`             | BIGINT PK     | Auto-increment primary key            |
| `user_id`        | BIGINT FK     | Reference to `user.id`                |
| `tarif_plan_id`  | BIGINT FK     | Reference to `tarif_plan.id`          |
| `subscription_id`| BIGINT FK     | Reference to `subscription.id`        |
| `invoice_number` | VARCHAR(50)   | Unique invoice identifier             |
| `amount`         | DECIMAL(10,2) | Invoice amount                        |
| `currency`       | VARCHAR(3)    | ISO 4217 currency code                |
| `status`         | ENUM          | `invoiced`, `paid`, `expired`, `cancelled` |
| `payment_method` | ENUM          | `paypal`, `stripe`, `manual`          |
| `payment_ref`    | VARCHAR(255)  | External payment reference ID         |
| `invoiced_at`    | DATETIME      | When invoice was created              |
| `paid_at`        | DATETIME      | When payment was received             |
| `expires_at`     | DATETIME      | Payment deadline                      |
| `created_at`     | DATETIME      | Record creation timestamp             |
| `updated_at`     | DATETIME      | Last modification timestamp           |

**Indexes:**
- `idx_user_invoice_user_id` on `user_id`
- `idx_user_invoice_status` on `status`
- `idx_user_invoice_invoice_number` (UNIQUE) on `invoice_number`

---

## 4. User Flow

### 4.1 End-User Purchase Journey

See: `puml/user-flow.puml`

```
+-------------------------------------------------------------------+
|                    End-User Purchase Journey                       |
+-------------------------------------------------------------------+
|                                                                    |
|  1. LANDING PAGE                                                   |
|     +-- User arrives at static landing page                        |
|     +-- Marketing content, value proposition                       |
|                    |                                               |
|                    v                                               |
|  2. TARIFF SELECTION                                               |
|     +-- User views available tariff plans                          |
|     +-- Compares features and pricing                              |
|     +-- Clicks "Subscribe" on chosen plan                          |
|                    |                                               |
|                    v                                               |
|  3. REGISTRATION/LOGIN                                             |
|     +-- New user: Creates account (email, password)                |
|     +-- Existing user: Logs in                                     |
|                    |                                               |
|                    v                                               |
|  4. CHECKOUT                                                       |
|     +-- Reviews order summary                                      |
|     +-- Enters billing details (user_details)                      |
|     +-- Selects payment method (PayPal/Stripe)                     |
|                    |                                               |
|                    v                                               |
|  5. PAYMENT                                                        |
|     +-- Redirects to PayPal/Stripe                                 |
|     +-- Completes payment                                          |
|     +-- Returns to confirmation page                               |
|                    |                                               |
|                    v                                               |
|  6. CONFIRMATION                                                   |
|     +-- Subscription activated                                     |
|     +-- Invoice generated                                          |
|     +-- Confirmation email sent                                    |
|     +-- Access to subscribed services                              |
|                                                                    |
+-------------------------------------------------------------------+
```

### 4.2 Admin Operations

See: `puml/admin-flow.puml`

- View/manage users and subscriptions
- Create/edit tariff plans
- View invoices and payment status
- Basic reporting and statistics

---

## 5. Subscription Lifecycle

See: `puml/subscription-lifecycle.puml`

### 5.1 Subscription States

| State       | Description                                      |
|-------------|--------------------------------------------------|
| `active`    | Subscription is valid and services accessible    |
| `inactive`  | Subscription not yet started or paused           |
| `cancelled` | User cancelled, may remain active until expiry   |
| `expired`   | Subscription period ended, services inaccessible |

### 5.2 State Transitions

```
                    +-- Payment Received
                    |
                    v
+----------+    +---------+    +------------+
| inactive | -> | active  | -> | cancelled  |
+----------+    +---------+    +------------+
                    |                |
                    |                | (grace period ends)
                    v                v
               +---------+    +---------+
               | expired |    | expired |
               +---------+    +---------+
```

### 5.3 Invoice States

| State       | Description                                      |
|-------------|--------------------------------------------------|
| `invoiced`  | Invoice created, awaiting payment                |
| `paid`      | Payment received and confirmed                   |
| `expired`   | Payment deadline passed, invoice void            |
| `cancelled` | Invoice cancelled by admin or system             |

---

## 6. Payment Integration

### 6.1 Architecture Overview

The payment system uses a **provider-agnostic plugin architecture** with **event-driven processing**:

- **Plugin System**: General-purpose plugin framework for extensibility
- **Payment Plugins**: Provider-specific implementations (Stripe, PayPal, Manual)
- **Payment Methods**: Strategy pattern for different payment types (Card, Invoice, Wallet)
- **Event Bus**: Decoupled event handling for payment workflows

See detailed documentation:
- [Payment Architecture](./payment-architecture.md) - Provider-agnostic payment platform
- [Plugin System](./plugin-system.md) - General-purpose plugin framework

### 6.2 Supported Providers & Methods

| Provider | Payment Methods | Integration Type |
|----------|-----------------|------------------|
| Stripe   | Card, SEPA      | SDK, Webhooks    |
| PayPal   | Card, Wallet    | REST API, Webhooks |
| Manual   | Invoice, Bank Transfer | Internal |

| Payment Method | Description | Redirect Required |
|----------------|-------------|-------------------|
| Card           | Credit/debit card | Yes (hosted checkout) |
| Invoice        | Pay later by invoice | No |
| Wallet         | Digital wallet (PayPal) | Yes |
| Bank Transfer  | Direct bank transfer | No |

### 6.3 Event-Driven Payment Flow

See: `puml/payment-flow.puml`, `puml/payment-architecture.puml`

```
┌─────────────────────────────────────────────────────────────────┐
│                    Event-Driven Payment Flow                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. User → CheckoutOrchestrator.create_checkout()               │
│           │                                                      │
│           ├─→ Create Subscription (inactive)                    │
│           ├─→ Create Invoice                                    │
│           ├─→ Publish InvoiceCreatedEvent                       │
│           └─→ Provider.create_checkout_session()                │
│                                                                  │
│  2. User completes payment on provider site                     │
│                                                                  │
│  3. Provider → Webhook Route                                    │
│           │                                                      │
│           └─→ PaymentWebhookHandler.handle_webhook()            │
│                    │                                            │
│                    ├─→ Verify signature                         │
│                    ├─→ Parse to normalized event                │
│                    └─→ Publish PaymentCompletedEvent            │
│                                                                  │
│  4. EventBus dispatches to handlers:                            │
│           │                                                      │
│           ├─→ PaymentCompletedHandler                           │
│           │        ├─→ InvoiceService.mark_paid()               │
│           │        └─→ SubscriptionService.activate()           │
│           │                                                      │
│           └─→ EmailHandler                                      │
│                    └─→ Send confirmation email                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.4 Plugin Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Plugin System Layers                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Service Layer (Provider-Agnostic)                       │   │
│  │  CheckoutOrchestrator, PaymentWebhookHandler             │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           │                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Payment Method Abstraction                              │   │
│  │  CardPayment, InvoicePayment, WalletPayment              │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           │                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Provider Adapter Layer                                  │   │
│  │  IPaymentProviderAdapter, PaymentProviderRegistry        │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           │                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Plugin System                                           │   │
│  │  StripePlugin, PayPalPlugin, ManualPaymentPlugin         │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.5 Webhook Handling

Webhooks are processed through the event-driven architecture:

1. Provider sends webhook to `/api/v1/webhooks/{provider}`
2. `PaymentWebhookHandler` verifies signature using provider adapter
3. Webhook payload parsed to normalized `WebhookEvent`
4. Converted to domain event (`PaymentCompletedEvent`, etc.)
5. Published to `EventBus`
6. Event handlers process business logic asynchronously

Supported webhook events:
- `payment.completed` - Payment successful
- `payment.failed` - Payment failed
- `payment.expired` - Session expired
- `refund.completed` - Refund processed

---

## 7. API Endpoints

### 7.1 Public Endpoints (No Auth)

| Method | Endpoint                    | Description                    |
|--------|----------------------------|--------------------------------|
| GET    | `/api/v1/tarif-plans`       | List active tariff plans       |
| GET    | `/api/v1/tarif-plans/{slug}`| Get single tariff plan         |
| POST   | `/api/v1/auth/register`     | User registration              |
| POST   | `/api/v1/auth/login`        | User login                     |

### 7.2 User Endpoints (Auth Required)

| Method | Endpoint                        | Description                  |
|--------|--------------------------------|------------------------------|
| GET    | `/api/v1/user/profile`          | Get user profile             |
| PUT    | `/api/v1/user/profile`          | Update user profile          |
| GET    | `/api/v1/user/details`          | Get user details             |
| PUT    | `/api/v1/user/details`          | Update user details          |
| GET    | `/api/v1/user/subscriptions`    | List user subscriptions      |
| GET    | `/api/v1/user/invoices`         | List user invoices           |
| POST   | `/api/v1/checkout/create`       | Create checkout session      |
| POST   | `/api/v1/checkout/confirm`      | Confirm payment              |

### 7.3 Admin Endpoints (Admin Auth Required)

| Method | Endpoint                        | Description                  |
|--------|--------------------------------|------------------------------|
| GET    | `/api/v1/admin/users`           | List all users               |
| GET    | `/api/v1/admin/users/{id}`      | Get user details             |
| PUT    | `/api/v1/admin/users/{id}`      | Update user                  |
| GET    | `/api/v1/admin/subscriptions`   | List all subscriptions       |
| PUT    | `/api/v1/admin/subscriptions/{id}` | Update subscription       |
| GET    | `/api/v1/admin/invoices`        | List all invoices            |
| PUT    | `/api/v1/admin/invoices/{id}`   | Update invoice               |
| GET    | `/api/v1/admin/tarif-plans`     | List all tariff plans        |
| POST   | `/api/v1/admin/tarif-plans`     | Create tariff plan           |
| PUT    | `/api/v1/admin/tarif-plans/{id}`| Update tariff plan           |

### 7.4 Webhook Endpoints

| Method | Endpoint                        | Description                  |
|--------|--------------------------------|------------------------------|
| POST   | `/api/v1/webhooks/paypal`       | PayPal webhook handler       |
| POST   | `/api/v1/webhooks/stripe`       | Stripe webhook handler       |

---

## 8. Directory Structure

```
vbwd-sdk/
+-- container/                 # Docker configuration per container
|   +-- frontend/
|   +-- python/
|   +-- postgres/
+-- data/                      # Persistent data & logs
|   +-- python/
|   |   +-- logs/
|   +-- frontend/
|   |   +-- logs/
|   +-- postgres/              # PostgreSQL binary data
+-- python/                    # Python backend root
|   +-- api/
|       +-- requirements.txt
|       +-- src/
|       |   +-- routes/        # API route handlers
|       |   |   +-- auth.py
|       |   |   +-- user.py
|       |   |   +-- checkout.py
|       |   |   +-- admin.py
|       |   |   +-- webhooks.py
|       |   +-- models/        # Data models
|       |   |   +-- user.py
|       |   |   +-- user_details.py
|       |   |   +-- user_case.py
|       |   |   +-- tarif_plan.py
|       |   |   +-- subscription.py
|       |   |   +-- user_invoice.py
|       |   +-- services/      # Business logic
|       |       +-- auth_service.py
|       |       +-- subscription_service.py
|       |       +-- payment_service.py
|       |       +-- invoice_service.py
|       +-- tests/
|           +-- unit/          # Unit tests
|           +-- integration/   # Integration tests
|           +-- fixtures/      # Test fixtures
+-- frontend/                  # Vue.js applications
|   +-- admin/
|   |   +-- vue/
|   |       +-- package.json
|   +-- user/
|       +-- vue/
|           +-- package.json
+-- docs/
|   +-- architecture/          # This documentation
|   |   +-- README.md
|   |   +-- puml/              # PlantUML diagrams
|   +-- devlog/                # Development logs (by date)
+-- docker-compose.yml
+-- CLAUDE.md
+-- README.md
+-- LICENSE
```

---

## 9. Development Principles

### 9.1 Core Practices

- **TDD First**: Tests are written before implementation
- **SOLID Principles**: Single responsibility, Open-closed, Liskov substitution, Interface segregation, Dependency inversion
- **DI**: Dependency Injection for loose coupling and testability
- **Clean Code**: Readable, maintainable, self-documenting code

### 9.2 Testing Strategy

- All tests run in Docker containers
- Tests must pass before any merge
- Integration tests verify container communication
- Unit tests cover business logic

```bash
# All test execution happens in containers
docker-compose run --rm python pytest
docker-compose run --rm frontend npm test
```

---

## 10. Security Considerations

- Password hashing with bcrypt
- JWT-based authentication
- Input validation on all endpoints
- SQL injection prevention via ORM
- HTTPS only in production
- Webhook signature verification (PayPal/Stripe)
- Rate limiting on public endpoints
- Sensitive data separation (user vs user_details)

---

## 11. PlantUML Diagrams

All architecture diagrams are available in PlantUML format:

| Diagram                | File                              | Description                       |
|------------------------|-----------------------------------|-----------------------------------|
| Data Model (ERD)       | `puml/data-model.puml`            | Entity relationship diagram       |
| System Architecture    | `puml/system-architecture.puml`   | Container and service overview    |
| User Flow              | `puml/user-flow.puml`             | End-user purchase journey         |
| Subscription Lifecycle | `puml/subscription-lifecycle.puml`| Subscription state machine        |
| Invoice Lifecycle      | `puml/invoice-lifecycle.puml`     | Invoice state machine             |
| Payment Flow           | `puml/payment-flow.puml`          | Payment processing sequence       |
| Payment Architecture   | `puml/payment-architecture.puml`  | Provider-agnostic payment layers  |
| Event-Driven Architecture | `puml/event-driven-architecture.puml` | Event bus and handlers     |

---

## 12. Related Documentation

### Architecture Documents
- [Payment Architecture](./payment-architecture.md) - Provider-agnostic payment platform
- [Plugin System](./plugin-system.md) - General-purpose plugin framework
- [Sprint Plans](./sprints/README.md) - Implementation sprints with TDD

### Other Documentation
- `docs/devlog/` - Daily development logs
- `CLAUDE.md` - Claude Code guidance
- `README.md` - Project overview
