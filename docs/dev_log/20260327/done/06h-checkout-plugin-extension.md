# Sprint 06h — Checkout Plugin Extension Architecture

**Status:** Pending — **must be done BEFORE 06e**
**Date:** 2026-03-29
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Goal

Extend the existing `checkout` fe-user plugin with a step-based extension system so that ecommerce (and future plugins) can inject additional checkout steps (shipping address, shipping method) without modifying the checkout plugin's core code.

---

## Problem

Current checkout plugin has a fixed flow: select plan → payment → done. Ecommerce needs: cart review → shipping address → shipping method → payment → order confirmation. The checkout plugin has no mechanism for plugins to inject steps.

---

## Design

### CheckoutStepRegistry

A new registry (like `checkoutContextRegistry` but for steps) that plugins register steps into:

```typescript
interface CheckoutStep {
  id: string;                    // "shipping-address", "shipping-method"
  label: string;                 // "Shipping Address"
  component: Component;          // Vue component to render
  order: number;                 // Sort order (10, 20, 30...)
  validate?: () => Promise<boolean>;  // Optional validation before proceeding
  plugin: string;                // Owning plugin name
}

interface CheckoutContext {
  plugin: string;
  steps: CheckoutStep[];
  cartSummary?: Component;       // Replaces default plan/bundle summary
  beforePayment?: () => Promise<void>;  // Hook before payment is initiated
  afterPayment?: (invoiceId: string) => Promise<void>;  // Hook after payment succeeds
}

class CheckoutStepRegistry {
  register(context: CheckoutContext): void
  unregister(plugin: string): void
  getSteps(): CheckoutStep[]      // Sorted by order
  getCartSummary(): Component | null
  hasSteps(): boolean
}
```

### Updated Checkout Flow

```
Without ecommerce (subscription/token):
  Step 1: Plan/Bundle summary → Payment → Done

With ecommerce:
  Step 1: Cart review (CartLineItems)
  Step 2: Shipping Address (ShippingAddressStep, order: 10)
  Step 3: Shipping Method (ShippingMethodStep, order: 20)
  Step 4: Payment → Order Confirmation
```

Steps from different plugins merge by `order` value. Core payment step is always last.

### Checkout.vue / PublicCheckoutView.vue Updates

- Render steps dynamically from `CheckoutStepRegistry.getSteps()`
- Step indicator (breadcrumb: Cart → Address → Shipping → Payment)
- "Next" / "Back" navigation between steps
- Each step's `validate()` called before proceeding
- Cart summary component overridable via `getCartSummary()`
- `beforePayment` hook called before creating payment session
- `afterPayment` hook called on success (ecommerce commits stock, creates order)

---

## Files

```
plugins/checkout/                     (existing plugin — EXTEND)
├── checkoutStepRegistry.ts           NEW: step registration system
├── PublicCheckoutView.vue            MODIFY: step-based flow
├── components/
│   ├── CheckoutStepIndicator.vue     NEW: step breadcrumb
│   └── CheckoutStepContainer.vue     NEW: wraps each step with next/back
└── tests/unit/
    ├── test_checkout_step_registry.spec.ts   NEW
    └── test_checkout_steps.spec.ts           NEW
```

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | `CheckoutStepRegistry` class | `test_checkout_step_registry.spec.ts` |
| 2 | `CheckoutStepIndicator.vue` — step breadcrumb | Unit test |
| 3 | `CheckoutStepContainer.vue` — step wrapper with next/back | Unit test |
| 4 | Update `PublicCheckoutView.vue` — dynamic step rendering | Unit test |
| 5 | Wire registry: export from checkout plugin, available to other plugins | — |
| 6 | Verify existing subscription checkout flow still works (no steps = direct payment) | — |
| 7 | `pre-commit-check.sh --full` | — |

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before implementation. No step done without passing tests. |
| **SOLID** | Open/Closed — plugins add steps without modifying checkout code. |
| **Liskov** | All CheckoutStep components honour the step interface (validate, render). |
| **DI** | Steps injected via registry, checkout reads from registry. |
| **DRY** | Single step rendering loop, no per-plugin conditionals. |
| **Clean Code** | Meaningful names. No hardcoded plugin references in checkout. |
| **No over-engineering** | Steps are simple Vue components. No state machine library. |
| **DevOps-first** | `pre-commit-check.sh --full` passes. |
| **i18n** | Step labels translatable via `$t()`. |

---

## Integration Tests

```
- test_checkout_with_no_steps_renders_direct_payment (subscription flow unchanged)
- test_checkout_with_registered_steps_renders_step_indicator
- test_step_navigation_forward_calls_validate
- test_step_navigation_backward_preserves_state
- test_cart_summary_override_renders_plugin_component
- test_before_payment_hook_called_before_payment_session
- test_after_payment_hook_called_on_success
```

## Playwright E2E

```
- test_subscription_checkout_flow_unchanged (no steps → direct payment)
- test_step_indicator_shows_all_registered_steps
- test_can_navigate_between_steps_with_next_back_buttons
- test_validation_prevents_proceeding_to_next_step
- test_payment_step_always_last
```

---

## Pre-commit Validation

Run after every step and before marking sprint as done:

```bash
cd vbwd-fe-user && ./bin/pre-commit-check.sh --style      # ESLint + TypeScript
cd vbwd-fe-user && ./bin/pre-commit-check.sh --unit       # Vitest unit tests
cd vbwd-fe-user && ./bin/pre-commit-check.sh --e2e        # Playwright E2E tests
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full       # All of the above
```
