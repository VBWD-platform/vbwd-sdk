# Sprint 06k — Wishlist / Favorites

**Status:** Pending
**Date:** 2026-03-29
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Goal

Users can save products to a wishlist. Heart icon on product cards and detail pages. Wishlist page in user dashboard. "Move to cart" action from wishlist. Guest wishlist in localStorage, syncs on login.

---

## Models

**WishlistItem:**
```python
class WishlistItem(BaseModel):
    __tablename__ = "ecommerce_wishlist_item"

    user_id: UUID (FK)
    product_id: UUID (FK)
    variant_id: UUID (FK, nullable)     # Specific variant if applicable
    added_at: DateTime
    # Unique constraint: (user_id, product_id, variant_id)
```

---

## Services

**WishlistService:**
```python
class WishlistService:
    def add(self, user_id, product_id, variant_id=None) -> WishlistItem
    def remove(self, user_id, product_id, variant_id=None) -> None
    def get_user_wishlist(self, user_id, page, per_page) -> list[WishlistItem]
    def is_in_wishlist(self, user_id, product_id, variant_id=None) -> bool
    def get_count(self, user_id) -> int
    def move_to_cart(self, user_id, product_id, variant_id=None) -> None
    def merge_guest_wishlist(self, user_id, guest_items: list) -> None
```

---

## API Routes

**User (auth required):**
- `GET /api/v1/shop/wishlist` — user's wishlist (paginated, with product details)
- `POST /api/v1/shop/wishlist` — add item `{ product_id, variant_id? }`
- `DELETE /api/v1/shop/wishlist/<product_id>` — remove item
- `POST /api/v1/shop/wishlist/<product_id>/move-to-cart` — move to cart
- `POST /api/v1/shop/wishlist/merge` — merge guest localStorage wishlist on login

---

## Frontend

### Fe-user
- **WishlistButton.vue** — heart icon (♡ / ♥), toggles wishlist state, shows on ProductCard + ProductDetail
- **Wishlist.vue** — full wishlist page at `/shop/wishlist`: product grid with "Move to Cart" and "Remove" actions
- **WishlistBadge.vue** — count badge in topbar/nav (like CartWidget but for wishlist)
- **Dashboard extension** — "My Wishlist" block via `sdk.addComponent('DashboardWishlist', ...)`
- **Guest storage** — localStorage `vbwd_guest_wishlist` array of `{ product_id, variant_id }`
- **Login merge** — on login, prompt: "You have X items in your wishlist. Merge with your account?"

### Fe-admin
- No admin UI needed (wishlist is user-only). Optionally: analytics widget showing "Most wishlisted products".

### Widgets (CMS registry)
- `WishlistButton` — embeddable heart icon for any product reference
- `WishlistGrid` — embeddable wishlist product grid

---

## Routes

```typescript
sdk.addRoute({ path: '/shop/wishlist', name: 'wishlist', component: Wishlist });
```

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | WishlistItem model + repo | Model tests |
| 2 | WishlistService | Service tests |
| 3 | Routes | Route tests |
| 4 | Fe-user: WishlistButton (heart toggle) | Unit tests |
| 5 | Fe-user: Wishlist.vue page | Unit tests |
| 6 | Fe-user: WishlistBadge in nav | Unit tests |
| 7 | Guest localStorage + login merge | Unit tests |
| 8 | Dashboard extension widget | — |
| 9 | CMS widgets: WishlistButton, WishlistGrid | — |
| 10 | i18n: all 8 languages | — |
| 11 | `pre-commit-check.sh --full` | — |

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before implementation. No step done without passing tests. |
| **SOLID** | WishlistService handles logic, components handle display. |
| **DI** | WishlistService injected via container. |
| **DRY** | WishlistButton reused on cards, detail, and CMS layouts. |
| **Clean Code** | Unique constraint prevents duplicates at DB level. |
| **No over-engineering** | Simple add/remove. No "collections" or "boards". |
| **DevOps-first** | `pre-commit-check.sh --full` passes. |
| **i18n** | All UI text in 8 languages (en, de, es, fr, ja, ru, th, zh). |

---

## Integration Tests (real PostgreSQL)

```
Wishlist service:
- test_add_to_wishlist_creates_record
- test_add_duplicate_prevented_by_unique_constraint
- test_remove_from_wishlist_deletes_record
- test_get_user_wishlist_paginated
- test_is_in_wishlist_returns_true_for_added_product
- test_move_to_cart_removes_from_wishlist_and_adds_to_cart
- test_merge_guest_wishlist_on_login
- test_get_count_returns_correct_number
```

## Playwright E2E

```
User flow:
- test_add_to_wishlist_from_product_card
    → catalog → click heart icon → icon fills (♥) → badge count updates
- test_add_to_wishlist_from_product_detail
    → product detail → click "Add to Wishlist" → heart fills
- test_remove_from_wishlist
    → wishlist page → click "Remove" → item disappears
- test_wishlist_page_shows_saved_products
    → /shop/wishlist → see all wishlisted products with images and prices
- test_move_to_cart_from_wishlist
    → wishlist → "Move to Cart" → item in cart, removed from wishlist
- test_guest_wishlist_persists_in_localstorage
    → add item as guest → reload page → heart still filled
- test_guest_wishlist_merge_prompt_on_login
    → add items as guest → login → prompt "Merge X items?" → merge → items in account wishlist
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
