# Sprint 09 — Checkout to Core + CMS Widget Pages

**Status:** Pending approval
**Date:** 2026-03-30
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · No over-engineering · DevOps-first

---

## Goal

1. Move checkout **registries** (extension points) to core `vue/src/registries/` — they're agnostic infrastructure
2. Keep checkout **views** in the checkout plugin — plugin registers them as CMS widgets
3. Add CMS imports: widgets (CheckoutForm, CheckoutConfirmation), layouts, pages
4. Rich success page with template variables (admin-customizable HTML)
5. Failed/cancelled payment returns user to checkout page with error message (no separate cancel page)

**Principle:** Core is agnostic. The registries are extension points (core). The views are plugin-specific (gnostic).

---

## Architecture — Core Agnostic, Plugin Gnostic

| Component | Location | Why |
|-----------|----------|-----|
| `stores/checkout.ts` | Core | Agnostic store — holds line items, doesn't know billing types |
| `EmailBlock`, `PaymentMethodsBlock`, `BillingAddressBlock`, `TermsCheckbox` | Core `components/checkout/` | Reusable checkout building blocks |
| `checkoutStepRegistry.ts` | **Core** `registries/` | Agnostic extension point — plugins inject steps |
| `checkoutContextRegistry.ts` | **Core** `registries/` | Agnostic extension point — plugins inject banners |
| `checkoutConfirmationRegistry.ts` | **Core** `registries/` | Agnostic extension point — plugins inject confirmation blocks |
| `PublicCheckoutView.vue` | **Plugin** `checkout/` | Gnostic — assembles checkout UI, registered as CMS widget |
| `CheckoutConfirmationView.vue` | **Plugin** `checkout/` | Gnostic — renders confirmation, registered as CMS widget |
| Backend `/api/v1/user/checkout` | Core | Agnostic — creates invoice from line items |

Old plugin re-exports from `plugins/checkout/*.ts` are preserved for backward compatibility.

---

## CMS Pages & Widgets

### Widgets (vue-component)

| Widget slug | Component | Purpose |
|-------------|-----------|---------|
| `checkout-form` | `CheckoutForm` | Full checkout flow (email, summary, billing, payment, terms) |
| `checkout-confirmation` | `CheckoutConfirmation` | Post-payment: invoice details, status, plugin confirmation blocks |

### Layouts

| Layout slug | Areas |
|-------------|-------|
| `checkout` | header, breadcrumbs, checkout-form, footer |
| `checkout-confirmation` | header, breadcrumbs, confirmation, footer |

### Pages

| Page slug | Layout | Purpose |
|-----------|--------|---------|
| `checkout` | checkout | Main checkout page |
| `checkout-confirmation` | checkout-confirmation | Thank-you / status page |

### Success Page — Rich Template Variables

The confirmation/success page is a CMS HTML widget with template variables that the admin can customize (responsive HTML with branding). Available variables:

| Variable | Example |
|----------|---------|
| `{{invoice_number}}` | `INV-20260330-A1B2C3` |
| `{{invoice_status}}` | `PAID` |
| `{{invoice_total}}` | `€99.00` |
| `{{invoice_currency}}` | `EUR` |
| `{{payment_method}}` | `Stripe` |
| `{{payment_date}}` | `2026-03-30` |
| `{{user_name}}` | `John Doe` |
| `{{user_email}}` | `john@example.com` |
| `{{line_items_html}}` | Rendered table of line items |
| `{{support_email}}` | From platform config |
| `{{support_phone}}` | From platform config |
| `{{company_name}}` | From platform config |
| `{{order_id}}` | For ecommerce orders |
| `{{booking_details_html}}` | Plugin-injected (booking plugin) |

The admin creates a rich responsive HTML template in the CMS widget editor. The CheckoutConfirmation widget injects these variables at render time. This allows the admin to fully customize the success page look, add branding, support info, upsells, etc.

### Flow

```
Cart/Plan → /checkout?source=shop OR /checkout?tarif_plan_id=xxx
  → CmsPage(slug='checkout') renders CheckoutForm widget
  → User logs in via EmailBlock (if not auth'd)
  → Fills billing + payment + terms
  → Submit → creates invoice → redirects to payment provider
  → Payment success → /checkout/confirmation?invoice={id}
  → Payment cancel/fail → /checkout?error=cancelled&invoice={id}
     → CheckoutForm shows error banner, invoice still available for retry
```

---

## Sub-Sprints

| # | Sprint | Scope |
|---|--------|-------|
| 09a | Move checkout to core | Move files, update imports, remove plugin, keep registries as core extension points |
| 09b | CMS widget pages | Register CheckoutForm + CheckoutConfirmation as CMS widgets, create layouts/pages, update routes |
| 09c | Error handling | Cancel/fail redirects back to checkout with error message, retry payment support |
| 09d | Tests + i18n | Fix missing i18n keys, add unit tests, pre-commit-check |

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before implementation. No step done without passing tests. |
| **SOLID** | CheckoutStepRegistry stays as core extension point. Plugins inject steps via Open/Closed. |
| **Liskov** | All checkout steps honour the `CheckoutStep` interface. |
| **DI** | Registries are singletons imported by reference. Store uses DI for API client. |
| **DRY** | One CheckoutForm widget, one flow. No duplicate success/cancel pages. |
| **Clean Code** | Fix all hardcoded English strings → i18n. Fix missing locale keys. |
| **No over-engineering** | Failed payment → same checkout page with error banner. No separate cancel page. |
| **DevOps-first** | `pre-commit-check.sh --full` passes in all 3 repos. |
| **i18n** | All UI text in 8 languages (en, de, es, fr, ja, ru, th, zh). |

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full
```
