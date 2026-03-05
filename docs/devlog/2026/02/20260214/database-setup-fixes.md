# Database Setup Fixes - 2026-02-14

## Summary

Fixed multiple database setup and migration issues to enable successful database reset and demo data installation.

## Issues Resolved

### 1. Port Conflict (Port 5000)
**Problem:** macOS ControlCenter (AirPlay Receiver) was using port 5000, preventing the API container from starting.

**Solution:** User disabled AirPlay Receiver in System Settings → General → AirDrop & Handoff

### 2. Missing Python Dependencies
**Problem:** API container crashed with `ModuleNotFoundError: No module named 'flask_limiter'`

**Solution:**
- Rebuilt Docker image with `docker compose up -d --build`
- Cleaned Python cache files (`__pycache__` and `.pyc`)

### 3. Incorrect Database Connection
**Problem:** `.env` file configured database connections to `localhost` instead of Docker service names

**Solution:** Updated `/Users/dantweb/dantweb/vbwd-sdk/vbwd-backend/.env`:
```diff
-DATABASE_URL=postgresql://vbwd:vbwd@localhost:5432/vbwd
+DATABASE_URL=postgresql://vbwd:vbwd@postgres:5432/vbwd

-REDIS_URL=redis://localhost:6379/0
+REDIS_URL=redis://redis:6379/0
```

### 4. Migration Issues - Missing `addon_subscription` Table
**Problem:** Two migrations tried to modify `addon_subscription` table that doesn't exist:
- `20260211_add_stripe_customer_id_to_user.py`
- `20260212_rename_provider_columns.py`

**Solution:** Commented out operations on non-existent table with TODO notes

**Files Modified:**
- `/Users/dantweb/dantweb/vbwd-sdk/vbwd-backend/alembic/versions/20260211_add_stripe_customer_id_to_user.py`
- `/Users/dantweb/dantweb/vbwd-sdk/vbwd-backend/alembic/versions/20260212_rename_provider_columns.py`

### 5. Missing Subscription Columns
**Problem:** Subscription model had `pending_plan_id` and `paused_at` columns not present in database

**Solution:** Created new migration `20260214_add_missing_subscription_columns.py`

**Added columns:**
- `pending_plan_id` (UUID, nullable, FK to tarif_plan)
- `paused_at` (DateTime, nullable)

### 6. Missing Invoice Tax Columns
**Problem:** UserInvoice model had tax-related columns not present in database

**Solution:** Created new migration `20260214_add_invoice_tax_columns.py`

**Added columns:**
- `subtotal` (Numeric, nullable)
- `tax_amount` (Numeric, nullable, default 0)
- `total_amount` (Numeric, nullable)

**Data migration:** Copied existing `amount` values to `subtotal` and `total_amount` for existing records

## New Script Created

### `bin/reset-database.sh`
Comprehensive database reset script with human confirmation requirements.

**Location:** `/Users/dantweb/dantweb/vbwd-sdk/vbwd-backend/bin/reset-database.sh`

**Features:**
- Double confirmation (type "RESET", then "YES")
- Clear warning messages about destructive operation
- Drops and recreates database
- Runs all migrations
- Creates admin and test users
- Optional demo data installation

**Usage:**
```bash
# Full reset with demo data
./bin/reset-database.sh

# Reset without demo data
./bin/reset-database.sh --skip-demo-data

# Custom credentials
ADMIN_EMAIL=admin@company.com ADMIN_PASSWORD=Pass123 ./bin/reset-database.sh
```

**Default Credentials:**
- Admin: `admin@example.com` / `AdminPass123@`
- Test User: `test@example.com` / `TestPass123@`

**Demo Users (if installed):**
- `user.free@demo.local` / `demo123` (Free plan)
- `user.pro@demo.local` / `demo123` (Pro plan)

## Migration Order

Final migration chain:
1. `20251221_1227_initial_schema_with_uuid.py` (e3bb91853ab7)
2. `20260109_add_user_details_fields.py` (a1b2c3d4e5f6)
3. `20260113_add_token_bundle_table.py` (b2c3d4e5f6g7)
4. `20260113_add_addon_table.py` (c3d4e5f6g7h8)
5. `20260122_add_payment_method_tables.py` (d4e5f6g7h8i9)
6. `20260122_add_country_table.py` (e5f6g7h8i9j0)
7. `20260207_add_plugin_config_table.py` (e5f6g7h8i9j1)
8. `20260208_add_addon_tarif_plans_table.py` (f6g7h8i9j0k1)
9. `20260211_add_stripe_customer_id_to_user.py` (g7h8i9j0k1l2) *modified*
10. `20260212_add_paypal_fields.py` (20260212_paypal)
11. `20260212_rename_provider_columns.py` (20260212_rename) *modified*
12. `20260214_add_missing_subscription_columns.py` (h8i9j0k1l2m3) *new*
13. `20260214_add_invoice_tax_columns.py` (i9j0k1l2m3n4) *new*

## Testing Results

✅ All services start successfully
✅ All 13 migrations apply successfully
✅ Admin and test users created
✅ Demo data installs successfully (2 currencies, 5 plans, 4 users, 2 subscriptions, 10 invoices)
✅ Database reset script works with both `--skip-demo-data` and full installation

## Files Created/Modified

**Created:**
- `bin/reset-database.sh` (executable)
- `alembic/versions/20260214_add_missing_subscription_columns.py`
- `alembic/versions/20260214_add_invoice_tax_columns.py`
- `docs/devlog/20260214/database-setup-fixes.md` (this file)

**Modified:**
- `.env` (database connection URLs)
- `alembic/versions/20260211_add_stripe_customer_id_to_user.py` (commented out addon_subscription operations)
- `alembic/versions/20260212_rename_provider_columns.py` (commented out addon_subscription operations)

## Known Issues & TODOs

1. **Missing `addon_subscription` table**: The AddOnSubscription model exists but no migration creates the table. Two migrations have operations commented out waiting for this table to be created.

2. **Model imports in `alembic/env.py`**: Not all models are imported (e.g., AddOnSubscription, InvoiceLineItem, PaymentMethod, etc.), which prevents Alembic from auto-generating migrations for them.

## Recommendations

1. **Create `addon_subscription` migration**: Generate a migration to create the addon_subscription table based on the AddOnSubscription model, then uncomment the operations in the two modified migrations.

2. **Update `alembic/env.py`**: Import all models to ensure Alembic can detect schema changes:
   - AddOnSubscription
   - InvoiceLineItem
   - PaymentMethod
   - Country
   - PluginConfig
   - TokenBundle
   - AddOn

3. **Review model-database alignment**: Run a comprehensive audit to identify any other models with columns not reflected in the database schema.

4. **Development workflow**: Use `alembic revision --autogenerate` regularly when models change to catch schema drift early.
