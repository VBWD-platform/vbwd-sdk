# S74 — User account type (private person / business)

**Area:** **core** `vbwd-backend` + `vbwd-fe-admin` (+ fe-user profile) · **Depends on:** core `UserDetails` (exists) · **Part of:** Shopware-parity follow-ups ([report 01](../reports/01-shopware-vs-vbwd-user-product-comparison.md)).
**Engineering requirements:** TDD-first, SOLID/DRY, no overengineering; core `--full` + fe-admin Vitest/ESLint green. See `docs/dev_log/20260526/sprints/_engineering-requirements.md`. **Not committed.**

## Decision context
vbwd is SaaS-first: the core user keeps a **single billing address** on `UserDetails` (rarely changed) — **multiple addresses and delivery addresses are a shop concern** (see [S75](s75-shop-address-book-delivery.md)), not core. What core *does* need is to know whether the customer is a **private person** or a **company**, because it drives invoice identity (company name + VAT id) and is reused by the shop.

## Problem
There is no account-type distinction. `UserDetails` has `company` and `tax_number` but nothing declares whether the account is a business (so the admin/UI can't require or surface company/VAT meaningfully, and invoices can't render the right party).

## Scope
**Core backend:**
- Add `account_type` to `UserDetails` (`vbwd_user_details`): `String(16)`, NOT NULL, `server_default='private'`, values `("private","business")` (single source of truth constant). Additive core migration; `down_revision` = current core head (`20260608_inv_admin_idx` — verify).
- `to_dict()` includes `account_type`. Create/update (admin + self-service profile) accept + validate it. **Validation:** when `account_type == "business"`, `company` is required (and `tax_number` recommended/validated if present).
- Expose in invoice/party rendering where the billing identity is built (use company + VAT for business, person name for private) — narrow, only where the party is already assembled.

**fe-admin:** `UserEdit.vue` Account tab — an Account type select (Private | Business); when Business, show/require Company + Tax number (reuse the existing fields).

**fe-user:** the profile/billing form gains the same Account type select with the same conditional company/VAT requirement.

## TDD
- `account_type` persists, defaults `private`, rejects unknown values; `business` without `company` → validation error.
- Invoice party uses company+VAT for business, person name for private.
- fe-admin/fe-user: selecting Business reveals + requires Company; save sends `account_type`.

## Definition of done
A user is private or business (default private); business requires a company name; the billing party renders accordingly; the single core billing address is unchanged (multi-address remains shop-only). core `--full` + fe Vitest/ESLint green. Not committed ([[feedback_no_commit_without_ask]]).
