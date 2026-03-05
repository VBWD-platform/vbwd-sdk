# Development Log - 2026-02-14

## Summary

Fixed database setup issues and created comprehensive database reset tooling.

## Work Completed

### 1. Database Setup & Configuration Fixes
- Resolved port 5000 conflict with macOS AirPlay Receiver
- Fixed Docker networking issues (localhost → service names)
- Rebuilt containers with correct dependencies
- Cleaned corrupted Python bytecode cache

### 2. Migration Fixes & Creation
- Fixed migrations trying to modify non-existent `addon_subscription` table
- Created migration for missing Subscription columns (`pending_plan_id`, `paused_at`)
- Created migration for missing Invoice tax columns (`subtotal`, `tax_amount`, `total_amount`)
- All 13 migrations now apply successfully

### 3. Database Reset Script
- Created `bin/reset-database.sh` with human confirmation requirements
- Integrates database drop, recreate, migrations, user creation, and demo data
- Supports custom admin/user credentials via environment variables
- Includes `--skip-demo-data` flag for minimal setup

### 4. Testing & Validation
- ✅ Full database reset works successfully
- ✅ All migrations apply without errors
- ✅ Demo data installation completes successfully
- ✅ Creates 2 currencies, 5 tarif plans, 4 users, 2 subscriptions, 10 invoices

## Files

- [database-setup-fixes.md](./database-setup-fixes.md) - Detailed technical documentation
- `/Users/dantweb/dantweb/vbwd-sdk/vbwd-backend/bin/reset-database.sh` - New database reset script
- `/Users/dantweb/dantweb/vbwd-sdk/vbwd-backend/alembic/versions/20260214_add_missing_subscription_columns.py` - New migration
- `/Users/dantweb/dantweb/vbwd-sdk/vbwd-backend/alembic/versions/20260214_add_invoice_tax_columns.py` - New migration

## Key Learnings

1. **Docker Networking**: Database connections inside containers must use service names, not `localhost`
2. **Schema Drift**: Models can drift from database schema when migrations aren't generated for new columns
3. **Migration Dependencies**: Be careful when migrations reference tables that might not exist yet
4. **Python Bytecode**: Corrupted `.pyc` files can cause mysterious import errors - clean cache when rebuilding

## Next Steps

1. Create migration for `addon_subscription` table
2. Update `alembic/env.py` to import all models
3. Audit remaining models for schema drift
4. Consider adding pre-commit hook to check for unmigrated model changes

## Quick Start

To reset the database and start fresh:

```bash
cd vbwd-backend
./bin/reset-database.sh
```

This will:
- Drop and recreate the database
- Run all migrations
- Create admin and test users
- Install demo data

Login credentials:
- Admin: `admin@example.com` / `AdminPass123@`
- Test: `test@example.com` / `TestPass123@`
- Demo: `user.free@demo.local` / `demo123`
- Demo: `user.pro@demo.local` / `demo123`
