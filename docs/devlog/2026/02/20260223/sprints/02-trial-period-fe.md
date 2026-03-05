# Sprint 02: Trial Period — Frontend (Admin) + Backend Fix

**Date:** 2026-02-23
**Branch:** `feature/macfix`
**Depends on:** Sprint 01 (trial backend — DONE)
**Approach:** TDD-first (Red → Green → Refactor)
**Principles:** SOLID, DI, DRY, Liskov, Clean Code, no overengineering, drop deprecated stubs

---

## Goal

Update the admin frontend so that:
1. Plans can have a `trial_days` integer field (set per plan)
2. Subscription creation auto-reads trial_days from the selected plan (no manual input)
3. Subscription details shows trial end date + days remaining when TRIALING
4. All 8 i18n locales updated
5. Backend subscription detail endpoint returns `trial_end_at`

---

TDD (Test-Driven Development) - Write failing tests first, then implementation
SOLID Principles - Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion
Clean Code - Meaningful names, small functions (15-25 lines), no else expressions (use early returns), DRY
Dependency Injection - Depend on abstractions, not concretions
DRY do not repeat yourself - extract common code

Use pre-commit-check.sh with arguments to test results in the backend and the frontend modules

## Decisions

| # | Question | Answer |
|---|----------|--------|
| 1 | Trial input on SubscriptionCreate | Remove input, auto from plan |
| 2 | Plans list column | No |
| 3 | SubscriptionDetails trial info | Trial end + days remaining |
| 4 | i18n scope | All 8 languages (en, de, es, fr, ja, ru, th, zh) |
| 5 | Backend scope | Include fix for subscription detail endpoint |

---

## Current State Analysis

### Files to modify

| File | Current State | Action |
|------|--------------|--------|
| `vbwd-fe-admin/vue/src/stores/planAdmin.ts` | `AdminPlan` has no `trial_days` | Add `trial_days: number` field |
| `vbwd-fe-admin/vue/src/views/PlanForm.vue` | No trial field | Add `trial_days` integer input |
| `vbwd-fe-admin/vue/src/stores/subscriptions.ts` | `Subscription` missing `trial_end_at` | Add `trial_end_at?: string` |
| `vbwd-fe-admin/vue/src/views/SubscriptionCreate.vue` | Manual `trial_days` input when TRIALING | Remove input, auto from plan; fix 3 broken i18n keys |
| `vbwd-fe-admin/vue/src/views/SubscriptionDetails.vue` | No trial display | Add trial end + days remaining |
| `vbwd-fe-admin/vue/src/i18n/locales/*.json` (x8) | Partial trial keys | Add missing plan/subscription trial keys |
| `vbwd-backend/src/routes/admin/subscriptions.py` | Detail endpoint missing `trial_end_at` | Add to response |

### Known bugs to fix

1. **SubscriptionCreate.vue**: Validation checks lowercase `'trialing'` but `formData.status` is uppercase `'TRIALING'` — validation always fails
2. **SubscriptionCreate.vue**: 3 i18n keys referenced but not defined: `subscriptions.searchUserByEmail`, `subscriptions.enterEmailToSearch`, `subscriptions.selectAPlan`

---

## Steps

### Step 1: Backend — Add `trial_end_at` to subscription detail endpoint

**File:** `vbwd-backend/src/routes/admin/subscriptions.py`

In the GET `/<subscription_id>` endpoint, add `trial_end_at` to the response dict:
```python
"trial_end_at": subscription.trial_end_at.isoformat() if subscription.trial_end_at else None,
"is_trialing": subscription.is_trialing,
```

**Test:** Unit test that GET subscription detail returns `trial_end_at` for a TRIALING subscription.

---

### Step 2: Plan store — Add `trial_days` to interfaces

**File:** `vbwd-fe-admin/vue/src/stores/planAdmin.ts`

Add `trial_days` to `AdminPlan` interface:
```typescript
trial_days?: number;
```

Include `trial_days` in `createPlan()` and `updatePlan()` payloads.

**Test:** Unit test that store serializes `trial_days` in create/update payloads.

---

### Step 3: PlanForm.vue — Add `trial_days` input

**File:** `vbwd-fe-admin/vue/src/views/PlanForm.vue`

Add integer input field for trial_days:
- Label: `{{ $t('plans.trialDays') }}`
- Type: `number`, min 0, default 0
- Placed after billing_period field
- 0 means "no trial" (no special validation needed)

**Test:** Unit test that PlanForm renders trial_days input and binds to form data.

---

### Step 4: Subscription store — Add `trial_end_at` to interface

**File:** `vbwd-fe-admin/vue/src/stores/subscriptions.ts`

Add to `Subscription` interface:
```typescript
trial_end_at?: string;
is_trialing?: boolean;
```

---

### Step 5: SubscriptionCreate.vue — Remove manual trial_days, auto from plan

**File:** `vbwd-fe-admin/vue/src/views/SubscriptionCreate.vue`

Changes:
1. Remove the `trial_days` input field (the `v-if="formData.status === 'TRIALING'"` block)
2. Remove `trial_days` from `formData` ref
3. Remove `trial_days` validation block
4. When status is TRIALING, the backend already reads `trial_days` from the plan — no need to send it
5. Fix status case mismatch: validation at line 313 checks `'trialing'` but should check `'TRIALING'`
6. Fix 3 missing i18n key references (add keys in Step 8)

**Test:** Unit test that SubscriptionCreate does NOT render trial_days input.

---

### Step 6: SubscriptionDetails.vue — Add trial info display

**File:** `vbwd-fe-admin/vue/src/views/SubscriptionDetails.vue`

Add trial info section (visible when `subscription.is_trialing || subscription.trial_end_at`):
- **Trial End Date:** formatted `trial_end_at`
- **Days Remaining:** computed as `Math.max(0, Math.ceil((trialEnd - now) / 86400000))`

Place in the subscription info card, after status.

**Test:** Unit test that SubscriptionDetails shows trial info when is_trialing is true.

---

### Step 7: i18n — Update all 8 locales

**Files:** `vbwd-fe-admin/vue/src/i18n/locales/{en,de,es,fr,ja,ru,th,zh}.json`

New keys to add:

**plans section:**
```json
"trialDays": "Trial Days"
```

**subscriptions section:**
```json
"searchUserByEmail": "Search user by email",
"enterEmailToSearch": "Enter email to search",
"selectAPlan": "Select a plan",
"trialEndDate": "Trial End Date",
"daysRemaining": "Days Remaining"
```

All keys translated per locale:
| Key | en | de | es | fr | ja | ru | th | zh |
|-----|----|----|----|----|----|----|----|----|
| plans.trialDays | Trial Days | Probetage | Dias de prueba | Jours d'essai | 試用日数 | Пробные дни | จำนวนวันทดลอง | 试用天数 |
| subscriptions.searchUserByEmail | Search user by email | Benutzer per E-Mail suchen | Buscar usuario por email | Rechercher un utilisateur par email | メールでユーザーを検索 | Поиск пользователя по email | ค้นหาผู้ใช้ด้วยอีเมล | 通过邮箱搜索用户 |
| subscriptions.enterEmailToSearch | Enter email to search | E-Mail eingeben | Ingrese email | Entrez l'email | メールアドレスを入力 | Введите email | กรอกอีเมลเพื่อค้นหา | 输入邮箱搜索 |
| subscriptions.selectAPlan | Select a plan | Plan auswählen | Seleccionar un plan | Sélectionner un plan | プランを選択 | Выберите план | เลือกแผน | 选择方案 |
| subscriptions.trialEndDate | Trial End Date | Probeende | Fecha fin de prueba | Date de fin d'essai | 試用終了日 | Дата окончания пробного периода | วันสิ้นสุดทดลอง | 试用结束日期 |
| subscriptions.daysRemaining | Days Remaining | Verbleibende Tage | Dias restantes | Jours restants | 残り日数 | Дней осталось | วันที่เหลือ | 剩余天数 |

---

## Execution Order

```
Step 1: Backend fix (subscription detail endpoint)
  ↓
Step 2: Plan store (interfaces)
  ↓
Step 3: PlanForm.vue (trial_days input)
  ↓
Step 4: Subscription store (trial_end_at)
  ↓
Step 5: SubscriptionCreate.vue (remove input, fix bugs)  ← can parallel with Step 6
Step 6: SubscriptionDetails.vue (trial display)           ← can parallel with Step 5
  ↓
Step 7: i18n (all 8 locales)
```

---

## Out of Scope

- User-facing frontend (vbwd-fe-user) trial display
- Trial start/cancel from admin UI (already works via subscription create with status "trialing")
- Email notifications
- Cron job for `expire_trials()`
