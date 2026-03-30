# Sprint 06j — Product Reviews & Ratings

**Status:** Pending
**Date:** 2026-03-29
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Goal

Users can rate and review purchased products. Reviews appear on product detail pages. Admin moderates reviews. Average rating displayed on product cards in catalog.

---

## Models

**ProductReview:**
```python
class ProductReview(BaseModel):
    __tablename__ = "ecommerce_product_review"

    product_id: UUID (FK)
    user_id: UUID (FK)
    order_id: UUID (FK, nullable)       # Link to purchase (verified buyer badge)
    rating: int                          # 1-5 stars
    title: str                           # "Great headphones!"
    body: str                            # Review text
    status: ReviewStatus                 # PENDING, APPROVED, REJECTED
    is_verified_purchase: bool           # True if user has a completed order with this product
    admin_response: str                  # Optional admin reply
    helpful_count: int                   # "X people found this helpful"
```

**ReviewStatus enum:**
```python
PENDING = "PENDING"         # Awaiting moderation
APPROVED = "APPROVED"       # Visible on product page
REJECTED = "REJECTED"       # Hidden, reason stored in metadata
```

**ReviewHelpful** (prevents duplicate votes):
```python
class ReviewHelpful(BaseModel):
    __tablename__ = "ecommerce_review_helpful"

    review_id: UUID (FK)
    user_id: UUID (FK)
    # Unique constraint: (review_id, user_id)
```

---

## Services

**ReviewService:**
```python
class ReviewService:
    def create_review(self, user_id, product_id, rating, title, body) -> ProductReview
    def approve_review(self, review_id) -> ProductReview
    def reject_review(self, review_id, reason) -> ProductReview
    def get_product_reviews(self, product_id, status=APPROVED, page, per_page) -> list
    def get_product_rating_summary(self, product_id) -> { average, count, distribution }
    def mark_helpful(self, review_id, user_id) -> None
    def admin_respond(self, review_id, response_text) -> ProductReview
    def check_verified_purchase(self, user_id, product_id) -> bool
```

**Events:**
```python
"review.created"    → { review_id, product_id, user_id, rating }
"review.approved"   → { review_id, product_id }
"review.rejected"   → { review_id, product_id, reason }
```

---

## API Routes

**Public:**
- `GET /api/v1/shop/products/<slug>/reviews` — approved reviews + rating summary
- `POST /api/v1/shop/products/<slug>/reviews` — submit review (auth required)
- `POST /api/v1/shop/reviews/<id>/helpful` — mark as helpful (auth required)

**Admin:**
- `GET /api/v1/admin/shop/reviews` — all reviews with status filter
- `PUT /api/v1/admin/shop/reviews/<id>/approve` — approve
- `PUT /api/v1/admin/shop/reviews/<id>/reject` — reject
- `PUT /api/v1/admin/shop/reviews/<id>/respond` — admin response
- `DELETE /api/v1/admin/shop/reviews/<id>` — delete

---

## Frontend

### Fe-user
- **ProductDetail.vue** — reviews section: star rating summary, review list, "Write a review" form
- **ProductCard.vue** — average star rating (★★★★☆ 4.2)
- **Widget:** `ProductReviewForm` — embeddable review form (CMS widget registry)
- **Widget:** `ProductRatingStars` — star rating display component

### Fe-admin
- **Reviews.vue** — review moderation list (pending/approved/rejected filter)
- **ReviewDetail.vue** — review detail with approve/reject/respond actions
- Nav: added to Shop section as "Reviews" item

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Models + repos | Model tests |
| 2 | ReviewService | Service tests |
| 3 | Routes (public + admin) | Route tests |
| 4 | Fe-user: review list + form on product detail | Unit tests |
| 5 | Fe-user: star rating on product cards | Unit tests |
| 6 | Fe-admin: moderation views | Unit tests |
| 7 | CMS widgets: ProductReviewForm, ProductRatingStars | — |
| 8 | Events + email templates (review.created → admin notification) | — |
| 9 | i18n: all 8 languages | — |
| 10 | `pre-commit-check.sh --full` | — |

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before implementation. No step done without passing tests. |
| **SOLID** | ReviewService handles business logic, routes handle HTTP only. |
| **Liskov** | ReviewStatus transitions enforced in service (can't approve a rejected review without re-pending). |
| **DI** | ReviewService injected via container. |
| **DRY** | Star rating component reused across card and detail. |
| **Clean Code** | No magic numbers. Rating 1-5 validated in service. |
| **No over-engineering** | No ML-based spam detection. Simple moderation queue. |
| **DevOps-first** | `pre-commit-check.sh --full` passes. |
| **i18n** | All UI text in 8 languages (en, de, es, fr, ja, ru, th, zh). |

---

## Integration Tests (real PostgreSQL)

```
Review lifecycle:
- test_create_review_sets_pending_status
- test_verified_purchase_flag_set_when_user_has_order
- test_approve_review_changes_status
- test_reject_review_changes_status
- test_only_approved_reviews_returned_by_public_api
- test_rating_summary_calculates_average_and_distribution
- test_mark_helpful_increments_count
- test_mark_helpful_prevents_duplicate_vote
- test_admin_respond_adds_response_text
- test_user_cannot_review_same_product_twice
```

## Playwright E2E

```
User flow:
- test_product_detail_shows_reviews_section
    → /shop/product/:slug → scroll to reviews → see star summary + review list
- test_submit_review_on_purchased_product
    → product detail → "Write Review" → fill stars + text → submit → "Pending moderation" message
- test_mark_review_helpful
    → click "Helpful" on a review → count increments

Admin:
- test_admin_review_moderation_list
    → /admin/shop/reviews → see pending reviews → filter by status
- test_admin_approve_review
    → click "Approve" → review appears on product page
- test_admin_reject_review
    → click "Reject" → review hidden from product page
- test_admin_respond_to_review
    → click "Respond" → type reply → visible under review on product page

Product cards:
- test_product_card_shows_average_star_rating
    → catalog → product card displays ★★★★☆ 4.2
```

---

## Pre-commit Validation

Run after every step and before marking sprint as done:

```bash
# Backend (models, services, routes)
cd vbwd-backend && ./bin/pre-commit-check.sh --full

# Admin frontend (management views)
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full

# User frontend (checkout / catalog integration)
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full
```
