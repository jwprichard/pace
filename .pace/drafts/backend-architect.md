# Draft Plan — Backend Architect

## Domain Focus
Designing the REST API, data models, and transaction import pipeline for the budget tracking application.

## Proposed Tasks

### Task: Define core data models and database schema
**Priority:** high
**Files likely affected:** src/models/transaction.ts, src/models/account.ts, src/models/category.ts, migrations/
**Agent:** @backend-engineer
**Success criteria:**
- Schema covers transactions (amount, date, description, category, account), accounts, and categories
- Migrations are versioned and reproducible
- Indexes exist on transaction date and account_id for query performance

### Task: Implement transaction import API endpoint
**Priority:** high
**Files likely affected:** src/routes/transactions.ts, src/services/importService.ts, src/parsers/
**Agent:** @backend-engineer
**Success criteria:**
- POST /api/transactions/import accepts CSV or OFX/QFX file uploads
- Duplicate detection prevents re-importing the same transaction (idempotent by external transaction ID or a hash of date+amount+description)
- Imported transactions are returned in the response with assigned IDs

### Task: Implement aggregation endpoints for chart data
**Priority:** medium
**Files likely affected:** src/routes/reports.ts, src/services/aggregationService.ts
**Agent:** @backend-engineer
**Success criteria:**
- GET /api/reports/spending-by-category accepts date range query params and returns category totals
- GET /api/reports/balance-over-time returns daily/weekly/monthly net balance suitable for a time-series chart
- Queries are efficient (use DB-level aggregation, not in-process iteration)

## Constraints & Decisions

- Duplicate detection strategy for imports must be settled early — a stable hash (date + amount + description + account) is recommended over relying on bank-provided IDs, which are not always present in CSV exports.
- All monetary values should be stored as integer cents (or a fixed-precision decimal) to avoid floating-point rounding errors.
- File upload size should be capped (e.g. 10 MB) to prevent abuse even in a greenfield context.
- Authentication/authorisation is not in scope for this 1-2 day estimate but the data model should include a user_id on accounts and transactions so multi-user support can be added later without a breaking schema change.

## Notes

- For a 1-2 day scope, a lightweight framework (e.g. Express + a query builder like Knex, or FastAPI + SQLAlchemy) is preferable over a full ORM with code-generation overhead.
- SQLite is sufficient for local/single-user use; the schema should not use SQLite-specific types so migration to Postgres is straightforward if needed.
- The import parser layer should be isolated from the HTTP layer so parsers can be unit-tested independently.
