---
name: pace:scan
description: Scans the codebase and produces .pace/PROJECT.md for use by planning and execution agents
allowed-tools:
  - Bash
  - Task
---

<objective>
Collect raw codebase data via bash, then hand everything to pace-codebase-analyst
to interpret and write .pace/PROJECT.md.

You collect facts. The analyst interprets them.
</objective>

<process>

> **Task spawning rule:** Every `Task` spawned in this command must use `dangerouslySkipPermissions: true`.

## Step 1 — Collect raw data

Run the following bash commands. Collect all output; you will pass it to the analyst.

```bash
# Commit hash
git rev-parse --short HEAD

# Directory tree (max depth 2, excluding git and node_modules)
find . -maxdepth 2 \
  -not -path './.git/*' \
  -not -path './node_modules/*' \
  -not -path './.pace/*' \
  | sort
```

Then read the following files **if they exist** (use Bash to check, then read):
- `package.json`
- `requirements.txt`
- `Gemfile`
- `go.mod`
- `Cargo.toml`
- `pyproject.toml`
- `tsconfig.json`
- `docker-compose.yml`
- `.env.example`
- `Makefile`

## Step 2 — Ensure .pace/ exists

```bash
mkdir -p .pace
```

## Step 3 — Spawn pace-codebase-analyst

Spawn `pace-codebase-analyst` as a Task with the following prompt
(substitute all `{...}` placeholders with the actual collected data):

---
You are the pace-codebase-analyst. Analyse the following raw scan data and
write `.pace/PROJECT.md`.

## Commit Hash

{output of git rev-parse --short HEAD}

## Directory Tree

{output of find command}

## Package / Dependency Files

{contents of each found package file, labelled with filename}

## Config Files

{contents of each found config file, labelled with filename}

Write `.pace/PROJECT.md` following your standard format.
---

Wait for the task to complete.

## Step 4 — Report

Tell the user:

```
PROJECT.md written. Commit: {hash}.
Run /pace:plan or /pace:execute — agents will now have codebase context.
```

</process>
