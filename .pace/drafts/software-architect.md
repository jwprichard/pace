# Draft Plan — Software Architect

## Domain Focus
Design the backend API, data model, and transaction import architecture for a greenfield budget tracking application.

## Proposed Tasks

### Task: Define core data model and API contract
**Priority:** high
**Files likely affected:** `schema.sql` (or equivalent ORM models), `openapi.yaml` (or `api-spec.md`)
**Agent:** @Backend Architect
**Success criteria:**
- A documented schema covering at minimum: `accounts`, `transactions`, `categories`, and `import_jobs` entities with clear relationships and constraints
- A REST (or GraphQL) API surface defined for CRUD on transactions, account management, and import job status — agreed upon before implementation begins
- All monetary amounts stored as integer cents (or equivalent) to avoid floating-point errors

### Task: Design automatic transaction import pipeline
**Priority:** high
**Files likely affected:** `src/importers/`, `src/jobs/`, `src/models/import_job.ts` (or equivalent)
**Agent:** @Data Engineer
**Success criteria:**
- An import pipeline design that handles at least one external source (e.g., CSV upload or bank API/OFX) with a clear extension point for adding further sources
- Idempotent ingestion: re-running an import for the same source data does not create duplicate transactions (deduplication key defined per transaction)
- Import jobs are tracked with status (`pending`, `processing`, `completed`, `failed`) so the UI can poll or receive a notification

### Task: Select and justify the persistence and backend framework stack
**Priority:** medium
**Files likely affected:** `README.md`, `package.json` / `requirements.txt` / `go.mod` (depending on language choice), `docker-compose.yml`
**Agent:** @Software Architect
**Success criteria:**
- A single ADR (Architecture Decision Record) or equivalent short document records the chosen language/framework, database (e.g., PostgreSQL), and ORM/query layer with rationale
- Local development can be stood up with one command (e.g., `docker compose up`) including the database
- Decision explicitly addresses how chart/aggregation queries (sum by category, balance over time) will be served efficiently — either via SQL views/materialized views or a dedicated aggregation endpoint

## Constraints & Decisions
- **Greenfield, small scope (1-2 days):** Avoid over-engineering. A monolithic API with a single relational database (PostgreSQL recommended) is preferred over microservices or event-driven architecture at this scale.
- **Deduplication is a hard requirement** for transaction import; the chosen deduplication strategy (content hash vs. external transaction ID) must be decided before the import pipeline is built.
- **Chart data** must be considered at schema design time — ensure aggregation-friendly indexing (e.g., index on `transaction_date`, `account_id`, `category_id`) is included in the initial schema rather than retrofitted.
- **Security baseline:** Even at small scope, API endpoints that touch financial data should require authentication. The auth mechanism (JWT, session, API key) should be chosen in the ADR.

## Notes
- The import pipeline task and the data model task have a hard dependency: the schema must be defined first before the import pipeline is built.
- If the team has existing language/framework preferences, the stack ADR task can be reduced to a lightweight note rather than a formal document — but the decisions still need to be explicit.
- Chart aggregations can initially be served via straightforward SQL GROUP BY queries; a caching or materialized-view layer is not needed at this scope but the schema should not preclude it later.
