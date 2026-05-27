# Add User Authentication with JWT Tokens
_Created: 2025-11-14T09:32:00Z_

## Context

The application currently has no authentication — all API endpoints are publicly accessible and there is no concept of a user account. The database has no `users` table, and the frontend makes unauthenticated requests to every endpoint.

This plan adds JWT-based authentication end-to-end: a `users` table with bcrypt-hashed passwords, registration and login endpoints that issue signed JWTs, middleware that protects routes by validating the Bearer token, and end-to-end tests covering the full auth flow.

The JWT secret will be read from the `JWT_SECRET` environment variable. Refresh token support is explicitly out of scope — this plan covers single-token authentication only.

## Key Decisions

- **bcrypt over argon2:** The project already has a `bcrypt` dependency in `package.json`. Using the existing library avoids adding a new native dependency and keeps the install footprint unchanged.
- **JWT secret from environment:** The secret is read from `process.env.JWT_SECRET` with a hard startup error if absent. No fallback or default value — this prevents accidentally running with a weak secret.
- **No refresh tokens:** Refresh token support was excluded per user decision during the planning interview. Single JWT with a reasonable expiry (e.g. 24h) is sufficient for the current use case.
- **Cost factor 12 for bcrypt:** Balances security and performance. At cost factor 12, hashing takes ~250ms on modern hardware — acceptable for registration/login but not so slow that it degrades UX.

---

## Part 1: Backend

### 1a. Create User model and database migration
**Agent:** @Backend Architect
**Depends on:** none
**Files:** src/models/user.ts, src/db/migrations/001_create_users.sql

Create the `User` model and its backing database table.

File: `src/models/user.ts`
```typescript
export interface User {
  id: string;
  email: string;
  passwordHash: string;
  createdAt: Date;
  updatedAt: Date;
}
```

File: `src/db/migrations/001_create_users.sql`
```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_email ON users (email);
```

The `email` column has a unique constraint to prevent duplicate registrations. The index on `email` supports fast lookups during login.

**Success criteria:**
- `src/models/user.ts` exports a `User` interface with fields: `id`, `email`, `passwordHash`, `createdAt`, `updatedAt`
- `src/db/migrations/001_create_users.sql` creates a `users` table with the correct columns and runs without error against the local database
- Running `npm run db:migrate` exits 0 with no error output

### 1b. Add password hashing with bcrypt
**Agent:** @Backend Architect
**Depends on:** 1a
**Files:** src/lib/crypto.ts, src/services/auth.service.ts

Create a crypto utility module that wraps bcrypt for password hashing and verification.

File: `src/lib/crypto.ts`
```typescript
import bcrypt from 'bcrypt';

const COST_FACTOR = 12;

export async function hashPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, COST_FACTOR);
}

export async function verifyPassword(plain: string, hash: string): Promise<boolean> {
  return bcrypt.compare(plain, hash);
}
```

The cost factor of 12 produces hashes with the `$2b$12$` prefix, which is verifiable by inspecting stored values. These functions are used by the auth service (1c) during registration and login.

**Success criteria:**
- `src/lib/crypto.ts` exports `hashPassword(plain: string): Promise<string>` and `verifyPassword(plain: string, hash: string): Promise<boolean>`
- Passwords are never stored in plain text — `users` table rows contain only the bcrypt hash
- `hashPassword` uses a cost factor of 12 or higher (verifiable by inspecting the stored hash prefix `$2b$12$...`)

### 1c. Implement registration and login endpoints
**Agent:** @Backend Architect
**Depends on:** 1a, 1b
**Files:** src/routes/auth.ts, src/controllers/auth.controller.ts, src/services/auth.service.ts

Build the auth service, controller, and routes.

**Auth service** (`src/services/auth.service.ts`):

Key logic in `register()`:
1. Check if email already exists via `SELECT` — throw 409 if found
2. Hash password using `hashPassword()` from crypto module
3. Insert user row with hashed password
4. Sign a JWT with `{ id, email }` payload using `process.env.JWT_SECRET`
5. Return `{ id, email, token }`

Key logic in `login()`:
1. Find user by email — throw 401 if not found
2. Verify password using `verifyPassword()` — throw 401 if mismatch
3. Sign and return JWT

**Controller** (`src/controllers/auth.controller.ts`):

| Method | Path | Request Body | Success Response | Error Responses |
|--------|------|-------------|------------------|-----------------|
| POST | /api/auth/register | `{ email, password }` | 201 `{ id, email, token }` | 409 `{ error: "Email already in use" }` |
| POST | /api/auth/login | `{ email, password }` | 200 `{ token }` | 401 `{ error: "Invalid credentials" }` |

The JWT secret must be read from `process.env.JWT_SECRET`. If the variable is not set, the service should throw a startup error (not silently use a default).

**Success criteria:**
- `POST /api/auth/register` with `{email, password}` returns 201 and `{id, email, token}` when the email is not already registered
- `POST /api/auth/register` returns 409 with `{error: "Email already in use"}` when the email exists
- `POST /api/auth/login` with valid credentials returns 200 and `{token}` where `token` is a signed JWT
- `POST /api/auth/login` with invalid credentials returns 401 with `{error: "Invalid credentials"}`

### 1d. Implement JWT middleware for protected routes
**Agent:** @Backend Architect
**Depends on:** 1c
**Files:** src/middleware/auth.middleware.ts, src/routes/index.ts
**Allowed tools:** Read, Write, Edit, Bash, Glob, Grep

Create an Express middleware that validates the `Authorization: Bearer <token>` header and populates `req.user`.

File: `src/middleware/auth.middleware.ts`
```typescript
export function requireAuth(req: Request, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET!);
    req.user = { id: payload.id, email: payload.email };
    next();
  } catch {
    return res.status(401).json({ error: 'Token invalid or expired' });
  }
}
```

Apply the middleware to protected route groups in `src/routes/index.ts`. The auth routes (`/api/auth/*`) must remain unprotected.

**Success criteria:**
- `src/middleware/auth.middleware.ts` exports a `requireAuth` Express middleware function
- A request to any route wrapped with `requireAuth` without a `Authorization: Bearer <token>` header returns 401 with `{error: "Unauthorized"}`
- A request with a valid JWT passes through the middleware and has `req.user` populated with `{id, email}`
- A request with an expired or tampered JWT returns 401 with `{error: "Token invalid or expired"}`

---

## Part 2: Testing

### 2a. Write end-to-end authentication flow tests
**Agent:** @Software Architect
**Depends on:** 1c, 1d
**Files:** tests/e2e/auth.e2e.test.ts

Write e2e tests covering the full authentication lifecycle:

1. Register a new user → receive 201 with token
2. Register with duplicate email → receive 409
3. Login with valid credentials → receive 200 with token
4. Login with wrong password → receive 401
5. Access protected route with valid token → receive 200
6. Access protected route without token → receive 401
7. Access protected route with expired/tampered token → receive 401

Each test should use a fresh database state (transaction rollback or truncation between tests).

**Success criteria:**
- `tests/e2e/auth.e2e.test.ts` contains test cases covering: register → login → access protected route → receive 200
- Running `npm run test:e2e -- --testPathPattern=auth` exits 0
- Test output shows at least 5 passing tests under the `Authentication` describe block

---

## Part 3: Documentation

### 3a. Update API documentation for auth endpoints
**Agent:** @Technical Writer
**Depends on:** 1c, 1d
**Files:** docs/api/authentication.md, openapi.yaml
**Allowed tools:** Read, Write, Edit, Glob, Grep

Document both auth endpoints with:
- Request body schemas and validation rules
- Response schemas for success and error cases
- Example `curl` commands that work against a local server
- OpenAPI path entries in `openapi.yaml`

Follow the existing documentation style in `docs/api/` for formatting conventions.

**Success criteria:**
- `docs/api/authentication.md` documents `POST /api/auth/register` and `POST /api/auth/login` with request body schemas, response schemas, and example `curl` commands that match the implementation
- `openapi.yaml` contains path entries for `/api/auth/register` and `/api/auth/login` with request/response schemas matching the implemented controllers
- All code examples in `docs/api/authentication.md` are syntactically valid and runnable against a local server

---

## Implementation Order

1. User model and migration (1a)
2. Password hashing utility (1b)
3. Registration and login endpoints (1c)
4. JWT middleware (1d)
5. End-to-end tests (2a) and API documentation (3a) — can run in parallel

---

## Verification

1. Run migration: `npm run db:migrate` — exits 0, `users` table exists with correct schema
2. Start server: `npm start` — no startup errors (requires `JWT_SECRET` env var set)
3. Register: `curl -X POST localhost:3000/api/auth/register -H 'Content-Type: application/json' -d '{"email":"test@example.com","password":"secret123"}'` — returns 201 with `{id, email, token}`
4. Register duplicate: repeat the same curl — returns 409
5. Login: `curl -X POST localhost:3000/api/auth/login -H 'Content-Type: application/json' -d '{"email":"test@example.com","password":"secret123"}'` — returns 200 with `{token}`
6. Protected route without token: `curl localhost:3000/api/protected` — returns 401
7. Protected route with token: `curl -H 'Authorization: Bearer {token}' localhost:3000/api/protected` — returns 200
8. Run e2e tests: `npm run test:e2e -- --testPathPattern=auth` — exits 0, at least 5 passing tests
9. Inspect stored password: `SELECT password_hash FROM users WHERE email='test@example.com'` — hash starts with `$2b$12$`
