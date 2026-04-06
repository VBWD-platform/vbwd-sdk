# Sprint 02: Booking Plugin Bundle — Overview

**Date:** 2026-03-18
**Status:** Planned

---

## Bundle Structure

| Module | Sprint Doc | Repo |
|--------|-----------|------|
| Payment Auth/Capture | [02d-payment-authorize-capture.md](02d-payment-authorize-capture.md) | `vbwd-backend` + payment plugins |
| Backend | [02a-booking-be.md](02a-booking-be.md) | `vbwd-plugin-booking` |
| Admin Frontend | [02b-booking-fe-admin.md](02b-booking-fe-admin.md) | `vbwd-fe-admin-plugin-booking` |
| User Frontend | [02c-booking-fe-user.md](02c-booking-fe-user.md) | `vbwd-fe-user-plugin-booking` |
| Import/Export + Event Export | [02e-booking-import-export.md](02e-booking-import-export.md) | `vbwd-plugin-booking` + admin plugin |
| Custom Schemas | [02f-booking-custom-schemas.md](02f-booking-custom-schemas.md) | `vbwd-plugin-booking` + both frontend plugins |
| Resource Image Gallery | [02g-booking-resource-image-gallery.md](02g-booking-resource-image-gallery.md) | `vbwd-plugin-booking` + admin + user plugins |
| Availability Editor | [02h-booking-availability-editor.md](02h-booking-availability-editor.md) | `vbwd-fe-admin-plugin-booking` + backend (minor) |

## Engineering Principles (all modules)

- **TDD-first** — write tests before implementation. Red → Green → Refactor.
- **SOLID** — Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion
- **DRY** — extract shared logic, no copy-paste
- **Dependency Injection** — services receive repositories via constructor, not via global imports
- **Clean Code** — meaningful variable and function names, no single-letter vars, no cryptic abbreviations
- **No Overengineering** — minimum code for the current requirement, no hypothetical abstractions
- **Liskov Substitution** — `BookingPlugin(BasePlugin)` / `bookingPlugin: IPlugin` must be fully interchangeable

## Implementation Order

| Step | Module | What | Tests |
|------|--------|------|-------|
| 0 | Core + Payment Plugins | Authorize/capture support (Stripe, PayPal, YooKassa) | ~28 |
| 1 | Core | Add `CUSTOM` to `LineItemType` + `metadata` column | ~5 |
| 2 | BE | Models, repositories, services, routes, events, scheduler | ~90 |
| 3 | FE-Admin | Stores, views, extension registry | ~30 |
| 4 | FE-User | Stores, views, CMS integration | ~37 |
| 5 | Import/Export | Manual export/import + event-driven + cron-driven export | ~41 |
| **Total** | | | **~231** |

## Estimated Effort

| Module | Effort |
|--------|--------|
| Payment authorize/capture (core + 3 plugins) | 4 days |
| Core change (CUSTOM line item) | 0.5 day |
| Backend plugin | 3-4 days |
| Admin frontend | 2-3 days |
| User frontend | 2-3 days |
| Import/Export + Event/Cron Export | 9.5 days |
| E2E + polish | 1-2 days |
| **Total** | **22-27 days** |
