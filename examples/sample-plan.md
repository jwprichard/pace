# PLAN: Add user authentication with JWT tokens
_Created: 2025-11-14T09:32:00Z_

## Objective
Implement JWT-based authentication so users can register, log in, and access protected API endpoints using a Bearer token.

## Tasks

### Task 1: Create User model and database migration
**Agent:** @backend-engineer
**Depends on:** none
**Files:** src/models/user.ts, src/db/migrations/001_create_users.sql
**Success criteria:**
- `src/models/user.ts` exports a `User` interface with fields: `id`, `email`, `passwordHash`, `createdAt`, `updatedAt`
- `src/db/migrations/001_create_users.sql` creates a `users` table with the correct columns and runs without error against the local database
- Running `npm run db:migrate` exits 0 with no error output

### Task 2: Implement registration and login endpoints
**Agent:** @backend-engineer
**Depends on:** 1
**Files:** src/routes/auth.ts, src/controllers/auth.controller.ts, src/services/auth.service.ts
**Success criteria:**
- `POST /api/auth/register` with `{email, password}` returns 201 and `{id, email, token}` when the email is not already registered
- `POST /api/auth/register` returns 409 with `{error: "Email already in use"}` when the email exists
- `POST /api/auth/login` with valid credentials returns 200 and `{token}` where `token` is a signed JWT
- `POST /api/auth/login` with invalid credentials returns 401 with `{error: "Invalid credentials"}`
- All four cases are exercised by integration tests in `src/routes/auth.test.ts` that exit 0

### Task 3: Implement JWT middleware for protected routes
**Agent:** @backend-engineer
**Depends on:** 2
**Files:** src/middleware/auth.middleware.ts, src/routes/index.ts
**Allowed tools:** Read, Write, Edit, Bash, Glob, Grep
**Success criteria:**
- `src/middleware/auth.middleware.ts` exports a `requireAuth` Express middleware function
- A request to any route wrapped with `requireAuth` without a `Authorization: Bearer <token>` header returns 401 with `{error: "Unauthorized"}`
- A request with a valid JWT passes through the middleware and has `req.user` populated with `{id, email}`
- A request with an expired or tampered JWT returns 401 with `{error: "Token invalid or expired"}`

### Task 4: Add password hashing with bcrypt
**Agent:** @backend-engineer
**Depends on:** 1
**Files:** src/services/auth.service.ts, src/lib/crypto.ts
**Success criteria:**
- `src/lib/crypto.ts` exports `hashPassword(plain: string): Promise<string>` and `verifyPassword(plain: string, hash: string): Promise<boolean>`
- Passwords are never stored in plain text — `users` table rows contain only the bcrypt hash
- `hashPassword` uses a cost factor of 12 or higher (verifiable by inspecting the stored hash prefix `$2b$12$...`)

### Task 5: Write end-to-end authentication flow tests
**Agent:** @qa-engineer
**Depends on:** 2, 3, 4
**Files:** tests/e2e/auth.e2e.test.ts
**Success criteria:**
- `tests/e2e/auth.e2e.test.ts` contains test cases covering: register → login → access protected route → receive 200
- Running `npm run test:e2e -- --testPathPattern=auth` exits 0
- Test output shows at least 5 passing tests under the `Authentication` describe block

### Task 6: Update API documentation for auth endpoints
**Agent:** @technical-writer
**Depends on:** 2, 3
**Files:** docs/api/authentication.md, openapi.yaml
**Allowed tools:** Read, Write, Edit, Glob, Grep
**Success criteria:**
- `docs/api/authentication.md` documents `POST /api/auth/register` and `POST /api/auth/login` with request body schemas, response schemas, and example `curl` commands that match the implementation
- `openapi.yaml` contains path entries for `/api/auth/register` and `/api/auth/login` with request/response schemas matching the implemented controllers
- All code examples in `docs/api/authentication.md` are syntactically valid and runnable against a local server

## Notes
- bcrypt was chosen over argon2 because the project already has a `bcrypt` dependency — task 4 confirmed this in `package.json`
- JWT secret is expected to be set via `JWT_SECRET` environment variable; agents must read from `process.env.JWT_SECRET` and throw a startup error if it is absent
- Refresh token support was out of scope for this plan per user decision during planning interview
- No agent was available for database schema review — the Backend Architect covered this in lieu of a dedicated DBA agent
