# Sprint 3 Phase 3: Payment SDK Organization Review

**Date**: February 16, 2026
**Status**: REVIEW COMPLETE - DECISION DOCUMENTED
**Decision**: KEEP SDK IN CORE

---

## Executive Summary

After thorough analysis of the payment SDK architecture and its usage across payment provider plugins, the decision is to **maintain the current SDK structure in `/src/sdk/`** rather than move it to individual plugin directories.

**Rationale**: The SDK is shared infrastructure providing foundational payment abstraction that benefits all payment plugins equally. It is provider-agnostic and follows the Adapter design pattern for extensibility.

---

## Current Architecture

### Core SDK (`/src/sdk/`)

**Files**:
- `interface.py` - Defines contracts and data classes
- `base.py` - Common retry and idempotency logic
- `registry.py` - Adapter management and lookup
- `idempotency_service.py` - Response caching for idempotent operations
- `mock_adapter.py` - Test/demo adapter
- `__init__.py` - Public API exports

**Exports**:
```python
- ISDKAdapter (abstract interface)
- SDKConfig (dataclass for configuration)
- SDKResponse (standardized response format)
- BaseSDKAdapter (implements retry + idempotency)
- TransientError (for retryable failures)
- MockSDKAdapter (testing)
- SDKAdapterRegistry (provider registration)
```

### Payment Plugins

**Plugins**: Stripe, PayPal, Yookassa
**Plugin Location**: `/plugins/{stripe,paypal,yookassa}/`

**SDK Usage Pattern**:
```python
# Each plugin implements ISDKAdapter
from src.sdk.base import BaseSDKAdapter
from src.sdk.interface import SDKConfig, SDKResponse

class StripeSDKAdapter(BaseSDKAdapter):
    def create_payment_intent(...) -> SDKResponse: ...
    def capture_payment(...) -> SDKResponse: ...
    def refund_payment(...) -> SDKResponse: ...
    def get_payment_status(...) -> SDKResponse: ...
```

---

## Analysis

### Option 1: Move SDK to Plugins (REJECTED)

**Structure if moved**:
```
plugins/stripe/src/sdk/     # Stripe-specific SDK
plugins/paypal/src/sdk/     # PayPal-specific SDK
plugins/yookassa/src/sdk/   # Yookassa-specific SDK
```

**Disadvantages**:
1. **Duplication**: Each plugin would duplicate the same interface, base class, and utility functions
2. **Inconsistency**: Different plugins might implement common features differently
3. **Maintenance Burden**: Updates to retry logic or idempotency require changes in 3 places
4. **Versioning Complexity**: SDK versions become decoupled between plugins
5. **Testing Burden**: Mock adapters and test utilities duplicated across plugins
6. **Extensibility**: New payment providers must reinvent the wheel

### Option 2: Keep SDK in Core (SELECTED)

**Current Structure**:
```
src/sdk/                     # Shared payment infrastructure
├── interface.py             # ISDKAdapter contract
├── base.py                  # BaseSDKAdapter + helpers
├── registry.py              # Adapter registry
├── idempotency_service.py   # Request caching
└── mock_adapter.py          # Test adapter

plugins/stripe/sdk_adapter.py    # Implements ISDKAdapter
plugins/paypal/sdk_adapter.py    # Implements ISDKAdapter
plugins/yookassa/sdk_adapter.py  # Implements ISDKAdapter
```

**Advantages**:
1. **Single Source of Truth**: One definition of payment adapter interface
2. **DRY Principle**: Common retry logic, idempotency, and utilities shared
3. **Consistency**: All payment providers follow the same pattern
4. **Maintainability**: Updates to infrastructure benefit all plugins automatically
5. **Extensibility**: New payment providers easily added by implementing interface
6. **Liskov Substitution**: Any adapter can be swapped without breaking code
7. **Testing**: Shared mock adapter and test utilities

**Justification**:
The SDK is **foundational payment infrastructure**, not payment-provider-specific code. Similar to how:
- Flask routes are shared across plugins
- Database models are shared across plugins
- Authentication middleware is shared across plugins

The SDK defines a contract (ISDKAdapter) that ensures all payment providers follow the same pattern, enabling loose coupling and extensibility.

---

## Dependency Analysis

### Who Imports SDK?

**Payment Plugins** (all three):
- `stripe/sdk_adapter.py` - Imports `BaseSDKAdapter`, `SDKConfig`, `SDKResponse`
- `paypal/sdk_adapter.py` - Imports `BaseSDKAdapter`, `SDKConfig`, `SDKResponse`
- `yookassa/sdk_adapter.py` - Imports `BaseSDKAdapter`, `SDKConfig`, `SDKResponse`

**Payment Plugin Tests**:
- All three plugins test their adapters by importing from `src.sdk`

**Core Code**:
- Payment handler middleware may use SDK for orchestration

### Design Pattern

This follows the **Adapter Pattern** with a **Registry Pattern**:

```python
# Core defines the interface
ISDKAdapter (interface)

# Plugins implement the interface
StripeSDKAdapter(ISDKAdapter)
PayPalSDKAdapter(ISDKAdapter)
YookassaSDKAdapter(ISDKAdapter)

# Core provides registry for lookup
SDKAdapterRegistry().register("stripe", StripeSDKAdapter(...))
```

This is the **correct usage of core SDK** - plugins depend on core contracts, not vice versa.

---

## Architecture Principle

### Clean Dependency Direction

**✅ Allowed** (current):
```
Plugins → SDK (core contracts)
Plugins → Service Layer (core business logic)
Plugins → Models (core entities)
```

**❌ Not Allowed** (prevents):
```
Core → Plugins (core should be plugin-agnostic)
```

**This Design Achieves**:
- Core remains plugin-agnostic
- Plugins can be added/removed without core changes
- SDK provides stable contracts for plugin developers
- New payment providers can be onboarded without core modifications

---

## Maintenance Impact

### Current (SDK in Core)
- Retry logic: 1 location → All plugins benefit from improvements
- Idempotency: 1 location → Shared across all plugins
- Interface: 1 contract → All adapters follow same pattern
- Test utilities: 1 set → All plugins reuse mock adapter

### If SDK Moved to Plugins
- Retry logic: 3 locations → Risk of inconsistency
- Idempotency: 3 locations → Maintenance burden grows
- Interface: 3 contracts → Risk of divergence
- Test utilities: 3 sets → Duplication

---

## Recommendations

### Keep SDK in Core ✅
No changes required. The current architecture is correct.

### Ensure Clean Separation
- ✅ **SDK** (`/src/sdk/`) - Provider-agnostic payment contracts and utilities
- ✅ **Plugins** (`/plugins/{provider}/`) - Provider-specific implementations

### Document the Pattern
For future payment provider plugins:
```python
# 1. Create plugin in /plugins/newprovider/
# 2. Implement sdk_adapter.py that extends BaseSDKAdapter
# 3. Register adapter with SDKAdapterRegistry
# 4. Don't duplicate SDK infrastructure
```

### Consider for Future
If multiple other SDK types emerge (SMS providers, notification services, etc.), consider creating a `/src/adapters/` directory for common adapter patterns. But for now, `/src/sdk/` is correct and specific to payment services.

---

## Test Coverage

The SDK is well-tested through:
- Direct SDK tests in `/src/tests/unit/sdk/`
- Adapter tests in `/plugins/{provider}/tests/test_sdk_adapter.py`
- E2E tests exercising SDK through payment flows

**Current Test Coverage**:
- StripeSDKAdapter: Fully tested
- PayPalSDKAdapter: Fully tested
- YookassaSDKAdapter: Fully tested
- Retry logic: Tested
- Idempotency: Tested
- Error handling: Tested

---

## Decision Summary

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| **Location** | Keep in `/src/sdk/` | Shared infrastructure |
| **Ownership** | Core team | Cross-plugin concern |
| **Updates** | Coordinated releases | All plugins benefit |
| **New Providers** | Implement interface | Use existing SDK |
| **Maintenance** | Centralized | Single source of truth |

---

## Conclusion

**The current SDK organization is correct and should not be changed.**

The `/src/sdk/` directory contains provider-agnostic payment adapter infrastructure that all payment plugins depend on. Moving this to individual plugins would create duplication, maintenance burden, and violate DRY principles.

This is an example of **proper plugin architecture**: the core provides stable contracts and utilities, while plugins implement provider-specific behavior.

**Status**: ✅ APPROVED - NO ACTION REQUIRED

---

## Sign-Off

**Sprint 3 Phase 3**: Payment SDK Review Complete
**Decision**: CONFIRMED - Keep SDK in core
**Date**: February 16, 2026
**Status**: Ready for Phase Completion
