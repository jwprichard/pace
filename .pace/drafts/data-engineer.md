# Draft Plan — Data Engineer

## Domain Focus
Designing the data ingestion pipeline, transaction storage schema, and aggregation layer needed to power automatic transaction import and chart features.

## Proposed Tasks

### Task: Transaction data model and database schema
**Priority:** high
**Files likely affected:** db/schema.sql, models/transaction.py, migrations/001_initial.sql
**Agent:** @backend-engineer
**Success criteria:**
- A `transactions` table exists with fields: id, account_id, amount, currency, description, category, imported_at, transaction_date, source, external_id (for deduplication)
- A `accounts` table exists linking transactions to users
- A unique constraint on (account_id, external_id) prevents duplicate imports
- Schema is version-controlled via a migration file

### Task: Automatic transaction import pipeline
**Priority:** high
**Files likely affected:** services/import_service.py, api/routes/import.py, workers/import_worker.py
**Agent:** @backend-engineer
**Success criteria:**
- An import endpoint or background worker accepts raw transaction data (e.g. CSV or bank API payload) and normalises it into the schema
- Duplicate transactions are detected via external_id and skipped without error
- Each import run is atomic: either all records in a batch are committed or none are
- Import errors are logged with enough context to retry or debug

### Task: Aggregation queries for chart data
**Priority:** medium
**Files likely affected:** api/routes/charts.py, services/aggregation_service.py
**Agent:** @backend-engineer
**Success criteria:**
- An API endpoint returns spending-by-category totals for a given date range
- An API endpoint returns spending-over-time series data (e.g. daily or monthly totals) suitable for a line/bar chart
- Queries use indexed columns (transaction_date, account_id, category) and return results in under 200 ms on a dataset of 10 000 rows
- Response shape is documented and agreed with the frontend consumer

## Constraints & Decisions
- **Deduplication strategy:** The schema assumes each imported transaction carries a stable `external_id` from the source (bank reference, CSV row hash, etc.). If the source does not provide one, the import pipeline must generate a deterministic hash from (account_id, date, amount, description) before insertion.
- **Currency handling:** All `amount` values should be stored as integers in the minor unit (cents/pence) to avoid floating-point rounding errors. A `currency` column (ISO 4217) must accompany every row.
- **Timezone:** transaction_date should be stored as UTC; display conversion is a frontend/API concern.
- **ORM vs raw SQL:** For a 1-2 day scope, lightweight raw SQL or a minimal ORM (e.g. SQLAlchemy Core) is preferred over a heavy abstraction to keep the data layer transparent and fast to iterate on.

## Notes
- The aggregation queries are the most latency-sensitive part; adding a composite index on (account_id, transaction_date) and (account_id, category) at schema creation time is low-cost and avoids retrofitting later.
- If a third-party bank API is used for import (e.g. Plaid, TrueLayer), the normalisation step is critical — field names and date formats vary significantly between providers.
- Chart data endpoints should support optional `account_id` filtering so multi-account users can see per-account or aggregate views without schema changes.
