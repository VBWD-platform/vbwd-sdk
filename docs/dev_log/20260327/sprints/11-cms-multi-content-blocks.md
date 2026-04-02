# Sprint 11 — CMS Multi-Content Blocks + Order Success Page

**Status:** Discussion
**Date:** 2026-04-02
**Principles:** TDD · SOLID · DRY · Clean Code · No over-engineering

---

## Problem

The order confirmation page needs:
1. **Dynamic invoice data** (line items, totals, payment method) — requires Vue logic
2. **Admin-customizable branding** (thank-you message, support info, FAQ, marketing blocks) — requires CMS content editing
3. **Agnostic** — same success page for shop, subscription, booking, GHRM

Currently the CMS supports **one content block per page**. The layout has a single `content` area that renders the page's `content_html`. This forces a choice: either the entire page is a Vue component (not admin-editable) or it's CMS HTML (no dynamic data).

---

## Options

### Option A — Mixed Layout (Recommended)

**Layout with both vue-component areas and content areas:**

```
Layout: checkout-confirmation
├── header (widget: header-nav)
├── thank-you (vue-component: CheckoutThankYou)     ← dynamic invoice data
├── content (content: page's content_html)           ← admin-editable HTML
├── footer (widget: footer-nav)
```

**How it works:**
- `CheckoutThankYou` vue-component widget fetches invoice from API, renders the thank-you header + invoice card using the HTML template (with CSS from the marketing snippet)
- The page's `content` area renders admin-edited HTML (login CTA, support info, FAQ, marketing blocks)
- Admin edits the content in the CMS page editor — no code changes needed
- Template variables in content: `{{invoice_number}}`, `{{user_email}}`, `{{total_amount}}`

**Pros:**
- Works today — no CMS changes needed
- Vue widget handles dynamic data reliably
- Admin customizes static content freely
- Clear separation: dynamic (widget) vs static (content)

**Cons:**
- Two editing surfaces (widget for invoice, page editor for content)
- Admin can't rearrange the invoice block position

---

### Option B — Fully Decoupled HTML with Variable Injection

**The entire page is CMS HTML content with template variables:**

```
Layout: checkout-confirmation
├── header (widget: header-nav)
├── content (content: page's content_html with {{variables}})
├── footer (widget: footer-nav)
```

The page content is the full HTML template (from the marketing snippet) with variables:
```html
<div class="thank-you">
  <h1>Thank you for your order!</h1>
  <p>Order <span class="order-number">{{invoice_number}}</span></p>
  <p>Confirmation sent to <strong>{{user_email}}</strong></p>
</div>
<div class="invoice-card">
  {{line_items_html}}
  <div class="invoice-line total">
    <span>Total</span><span>{{total_amount}}</span>
  </div>
</div>
```

**How it works:**
- A small "injector" vue-component widget sits invisibly in the layout
- It fetches invoice data from API and injects variables into the page's DOM
- Or: CmsPage.vue supports a `data-source` attribute on content areas that triggers variable replacement

**Pros:**
- Admin has full control — one editing surface
- Can rearrange everything
- Truly decoupled from Vue

**Cons:**
- Complex variable injection (DOM manipulation or template pre-processing)
- `{{line_items_html}}` is ugly — admin sees raw variable, not a preview
- Harder to handle loading/error states
- No type safety on variables

---

### Option C — CMS Multi-Content Blocks (CMS Enhancement)

**Upgrade CMS so a layout can have multiple `content` areas, each editable per page:**

```
Layout: checkout-confirmation
├── header (widget: header-nav)
├── content-above (content: "Thank you" block — admin-editable)
├── invoice-details (vue-component: CheckoutInvoice)
├── content-below (content: "Support & FAQ" block — admin-editable)
├── footer (widget: footer-nav)
```

**CMS model change:**
```python
# Current: CmsPage has ONE content field
class CmsPage:
    content_json = Column(JSON)      # TipTap content
    content_html = Column(Text)      # Rendered HTML

# New: CmsPage has MULTIPLE content blocks keyed by area name
class CmsPageContentBlock:
    page_id = Column(UUID, FK)
    area_name = Column(String)       # "content-above", "content-below"
    content_json = Column(JSON)
    content_html = Column(Text)
    sort_order = Column(Integer)
```

**Layout area types become:**
```
header    → widget (header-nav)
content-above → content (per-page editable block)
invoice   → vue (CheckoutInvoice widget)
content-below → content (per-page editable block)
footer    → widget (footer-nav)
```

**Admin experience:**
- Page editor shows multiple TipTap editors, one per content area
- Each block is independently editable
- Vue widgets sit between content blocks

**Pros:**
- Most flexible — works for any page type (product pages, landing pages, blog posts)
- Admin controls layout AND content
- Vue widgets coexist cleanly with content blocks
- No template variables needed for static content

**Cons:**
- Requires CMS model change (new table `cms_page_content_block`)
- Admin editor needs UI for multiple content blocks
- Migration from single content to multi-content
- More complex page editor

---

## Recommendation

**Start with Option A (mixed layout), plan Option C as a future CMS enhancement.**

### Why:

1. **Option A works today** — no CMS changes, the confirmation page is split into:
   - `CheckoutThankYou` widget: dynamic invoice card (Vue component)
   - Page content: static branding (support info, FAQ, marketing — admin-editable HTML)

2. **Option C is the right long-term solution** — multi-content blocks are useful everywhere:
   - Product pages: hero content + product widget + reviews content
   - Landing pages: multiple editable sections between widgets
   - Blog posts: content above + related posts widget + content below
   - But it's a CMS-level enhancement that benefits many features, not just checkout

3. **Option B is fragile** — DOM-based variable injection is brittle and hard to maintain

### Implementation Plan (Option A — now):

1. Create `CheckoutThankYou` vue-component widget using the marketing HTML template
2. Widget fetches invoice via API, renders thank-you header + invoice card
3. Update layout `checkout-confirmation` to have areas: header, thank-you (vue), content, footer
4. Admin puts support/FAQ/marketing HTML in the page content field
5. Populate the default content from the marketing snippet

### Future Sprint — Option C (CMS Multi-Content Blocks):

| # | Task |
|---|------|
| 1 | Create `cms_page_content_block` model + migration |
| 2 | Update CmsLayoutRenderer to render multiple content areas |
| 3 | Update admin page editor to show per-area content editors |
| 4 | Migrate existing single-content pages to multi-block |
| 5 | Update all page templates to use multi-block |

---

## Template Variables (for CheckoutThankYou widget)

The widget uses these variables internally (not exposed to CMS content):

| Variable | Source | Example |
|----------|--------|---------|
| `invoice_number` | API | `#SH-BCB8BA6C` |
| `user_email` | API | `customer@example.com` |
| `line_items` | API | Array of {description, quantity, unit_price, amount} |
| `subtotal` | API | `€18.99` |
| `tax_amount` | API | `€3.61` |
| `total_amount` | API | `€22.60` |
| `payment_method` | API | `Stripe` |
| `payment_date` | API | `April 2, 2026` |
| `status` | API | `paid` / `pending` |

For the CMS content area (admin-editable), these variables ARE available:
`{{invoice_number}}`, `{{total_amount}}`, `{{user_email}}`, `{{status}}`

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests for CheckoutThankYou widget rendering |
| **SOLID** | Widget is agnostic — works for shop, subscription, booking |
| **Liskov** | Any payment method → same confirmation flow |
| **DI** | Widget receives invoice_id from route, fetches data itself |
| **DRY** | One widget, one template, one API call |
| **Clean Code** | HTML template from marketing snippet — production-quality CSS |
| **No over-engineering** | Option A now, Option C later when needed |
| **i18n** | Widget labels in 8 languages |
