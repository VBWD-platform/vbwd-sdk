# Sprint 03 — Add i18n to User App (EN + DE only)

**Priority:** HIGH

## Problem

Admin app has vue-i18n with 8 languages (en, de, ru, th, zh, es, fr, ja). User app has no i18n at all.

## Plan

1. Add vue-i18n to user app following admin app pattern
2. **Active languages: EN and DE only**
3. Keep all other translation files (ru, th, zh, es, fr, ja) in the codebase but do not load/register them as available
4. Copy i18n setup structure from `vbwd-frontend/admin/vue/src/i18n/`

## Files to Create / Modify
- `vbwd-frontend/user/vue/src/i18n/index.ts` — i18n configuration (EN + DE active)
- `vbwd-frontend/user/vue/src/i18n/locales/en.ts` — English translations
- `vbwd-frontend/user/vue/src/i18n/locales/de.ts` — German translations
- `vbwd-frontend/user/vue/src/main.ts` — register i18n plugin
- `vbwd-frontend/user/vue/src/views/*.vue` — replace hardcoded strings with `$t()` calls
- `vbwd-frontend/user/vue/src/components/**/*.vue` — replace hardcoded strings

## Acceptance Criteria
- [ ] vue-i18n installed and configured in user app
- [ ] EN and DE available as active languages
- [ ] Other language files preserved but not active
- [ ] All user-visible strings use `$t()` keys
- [ ] Language persists in localStorage
- [ ] Pre-commit checks pass
