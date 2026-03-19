# RISKS

Known risks, limitations, and open mitigations for PACE.

---

## R1 — Parallel agents conflicting on shared resources

**Status:** Open
**Affects:** `/pace:execute` — wave-based parallel task execution

When multiple agents run in the same wave, they may attempt to write to shared
resources simultaneously, causing corruption or failure.

**Known conflict sources:**
- `npm install` / `yarn` / `pnpm install` — writes to `node_modules/` and lockfiles
- `pip install` / `poetry install` / `bundle install` — writes to shared package dirs
- `docker compose up` / `docker build` — port conflicts, container naming conflicts
- Database migrations — sequential by nature, will fail or corrupt if run concurrently
- Any task writing to the same output file or directory

**Current mitigation:**
The synthesiser is responsible for detecting shared resource usage and setting
`Depends on:` to serialise conflicting tasks. This relies on the synthesiser's
judgement — it is not enforced mechanically.

**Proposed fix:**
Add an `**Environment:**` field to PLAN.md tasks declaring shared resources touched
(e.g. `docker`, `database`, `node_modules`). Execute can then detect conflicts
automatically and serialise tasks that share an environment, independent of explicit
code dependencies.
