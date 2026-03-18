# General

| Name | Description |
|---|---|
| @code-review-agent | When you are asked to review a PR. |
| @gsd-codebase-mapper | Explores codebase and writes structured analysis documents. Spawned by map-codebase with a focus area (tech, arch, quality, concerns). Writes documents directly to reduce orchestrator context load. |
| @gsd-debugger | Investigates bugs using scientific method, manages debug sessions, handles checkpoints. Spawned by /gsd:debug orchestrator. |
| @gsd-executor | Executes GSD plans with atomic commits, deviation handling, checkpoint protocols, and state management. Spawned by execute-phase orchestrator or execute-plan command. |
| @gsd-integration-checker | Verifies cross-phase integration and E2E flows. Checks that phases connect properly and user workflows complete end-to-end. |
| @gsd-nyquist-auditor | Fills Nyquist validation gaps by generating tests and verifying coverage for phase requirements |
| @gsd-phase-researcher | Researches how to implement a phase before planning. Produces RESEARCH.md consumed by gsd-planner. Spawned by /gsd:plan-phase orchestrator. |
| @gsd-plan-checker | Verifies plans will achieve phase goal before execution. Goal-backward analysis of plan quality. Spawned by /gsd:plan-phase orchestrator. |
| @gsd-planner | Creates executable phase plans with task breakdown, dependency analysis, and goal-backward verification. Spawned by /gsd:plan-phase orchestrator. |
| @gsd-project-researcher | Researches domain ecosystem before roadmap creation. Produces files in .planning/research/ consumed during roadmap creation. Spawned by /gsd:new-project or /gsd:new-milestone orchestrators. |
| @gsd-research-synthesizer | Synthesizes research outputs from parallel researcher agents into SUMMARY.md. Spawned by /gsd:new-project after 4 researcher agents complete. |
| @gsd-roadmapper | Creates project roadmaps with phase breakdown, requirement mapping, success criteria derivation, and coverage validation. Spawned by /gsd:new-project orchestrator. |
| @gsd-verifier | Verifies phase goal achievement through goal-backward analysis. Checks codebase delivers what phase promised, not just that tasks completed. Creates VERIFICATION.md report. |
