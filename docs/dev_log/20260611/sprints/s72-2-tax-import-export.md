# S72.2 — Tax import/export (JSON + CSV)

**Part of:** [S72 — Taxes & Countries (umbrella)](s72-taxes.md) · **Area:** **core** `vbwd-backend` + `vbwd-fe-admin` · **Depends on:** unified data-exchange (exists; framework already supports `{"json","csv"}`), S72.1 (the tab to embed controls in — soft dep).
**Engineering requirements:** TDD-first, SOLID/DI/DRY, no overengineering; core `--full` + fe-admin Vitest/ESLint green. **Not committed.**

## Problem
There is **no `taxes` exchanger**. Tax classes/rates can't be moved between instances; the user wants them exportable/importable as **JSON and CSV** from `/admin/import-export` and from the Taxes&Countries tab. (`countries` already has an exchanger — confirm it's listed, add CSV if missing.)

## Scope (core backend — `vbwd/services/data_exchange/core_exchangers.py`)
Register two new exchangers in `build_core_exchangers` / `register_core_exchangers`:
1. **`tax_classes`** — `BaseModelExchanger`, `model_class=TaxClass`, `natural_key="code"`, `cluster=CLUSTER_SETTINGS`, `supported_formats=frozenset({"json","csv"})`, `public_fields=[name, code, description, default_rate, is_default]`, perms `settings.view`/`settings.manage`. Must import **before** `taxes`.
2. **`taxes`** — `BaseModelExchanger`, `model_class=Tax`, `natural_key="code"`, json+csv, `public_fields=[name, code, description, rate, country_code, region_code, is_active, is_inclusive]`. Carry the FK `tax_class_id` by **tax-class `code`** (thin subclass / `fk_natural_key_map`) so import is portable across instances and resolves the class created in step 1.
3. Confirm `countries` is in the manifest; add `"csv"` to its `supported_formats` if it's json-only today.

## Scope (fe-admin)
Embed the core `ImportExportControls` (from `vbwd-view-component`) on the **Taxes&Countries** tab (S72.1), scoped to `taxes` / `tax_classes` / `countries`, reusing the same manifest + export/import endpoints as the Import/Export page — so admins import/export without leaving the tab.

## TDD (core)
- Export `taxes` as **json** and as **csv**; round-trip import re-creates rows by `code`, with `tax_class_id` resolved via class `code`.
- CSV columns == `public_fields`; import is **idempotent** (upsert by `code`); a tax referencing an unknown class code is reported, not a 500.
- Manifest lists `taxes` / `tax_classes` / `countries` with the right `supported_formats` + permission flags.

## Definition of done
`taxes` + `tax_classes` (and `countries`) export/import as **JSON and CSV** from both `/admin/import-export` and the Taxes&Countries tab; class resolved by code; idempotent; core `--full` + fe-admin Vitest/ESLint green. Not committed.
