---
name: pace:settings
description: View and manage PACE workflow settings
argument-hint: "[set <key> <value>]"
allowed-tools:
  - Read
  - Write
  - Edit
  - AskUserQuestion
---

<objective>
View current PACE settings and allow the user to modify them interactively or
via direct command arguments. Provides a menu-driven interface when called without
arguments, and a direct-set interface when called with `set <key> <value>`.
</objective>

<process>

## Step 1 — Parse arguments

Read the argument string.

If the argument starts with `set` (case-insensitive):
- Parse the remaining string as `<key> <value>` (flexible matching)
- Normalise the key — map common variations:
  - `plan-model`, `plan model`, `planmodel`, `planning model`, `plan_model` → `plan-model`
  - `execute-model`, `execute model`, `executemodel`, `execution model`, `execute_model` → `execute-model`
- Normalise the value — map common variations:
  - `sonnet`, `claude sonnet`, `claude-sonnet` → `sonnet`
  - `opus`, `claude opus`, `claude-opus` → `opus`
  - `haiku`, `claude haiku`, `claude-haiku` → `haiku`
  - `none`, `default`, `inherit`, `unset`, `clear`, `""`, `''` → `` (empty — clears the setting)
- If key or value cannot be parsed, tell the user and show the usage:
  ```
  Could not parse that. Usage: /pace:settings set <key> <value>

  Keys: plan-model, execute-model
  Values: sonnet, opus, haiku, none (to clear)

  Examples:
    /pace:settings set execute-model opus
    /pace:settings set plan model sonnet
    /pace:settings set execute-model none
  ```
  Then stop.
- Go to Step 3 (direct set).

If the argument is empty or does not start with `set`, go to Step 2 (interactive).

## Step 2 — Interactive mode

### 2a — Load current settings

Read `.pace/settings.md` if it exists. Extract:
- `plan-model:` value (or "not set" if empty/missing)
- `execute-model:` value (or "not set" if empty/missing)

### 2b — Display current settings

```
## Current Settings

| Setting | Value | Effect |
|---|---|---|
| plan-model | {value or "not set"} | {effect description} |
| execute-model | {value or "not set"} | {effect description} |
```

Effect descriptions:
- If set to a model: "Planning agents use {model}" / "Execution agents use {model}"
- If not set: "Planning agents inherit session model" / "Execution agents inherit session model"

Include a brief explanation of which agents fall into each category:
- **plan-model** affects: domain planners, synthesiser, research agents, codebase analyst
- **execute-model** affects: specialist implementers, verification, fix agents, documentation patches

### 2c — Ask what to change

Use AskUserQuestion:

```
question: "Which setting would you like to change?"
header: "Settings"
options:
  - label: "plan-model"
    description: "Model for planning agents (planners, synthesiser, research, codebase analyst)"
  - label: "execute-model"
    description: "Model for execution agents (specialists, verification, fixes, documentation)"
  - label: "Done"
    description: "No changes needed."
```

If they choose **Done**, stop.

If they choose a setting, use AskUserQuestion to pick the value:

```
question: "Set {key} to which model?"
header: "Choose model"
options:
  - label: "opus"
    description: "Most capable — best for complex reasoning and architectural decisions"
  - label: "sonnet"
    description: "Balanced — strong performance at lower cost"
  - label: "haiku"
    description: "Fastest and cheapest — best for simple, well-defined tasks"
  - label: "Clear (inherit session model)"
    description: "Remove the override — agents use whatever model the session runs on"
```

Map "Clear (inherit session model)" to empty string.

Set `key` and `value`, then go to Step 3.

After Step 3 completes, loop back to 2a to show updated settings and ask again.

## Step 3 — Apply the setting

### 3a — Ensure settings file exists

If `.pace/settings.md` does not exist, create it:

```markdown
# Settings
_Persistent configuration for the PACE workflow. This file is not cleared by /pace:complete._

## Model

<!-- plan-model: Model for planning-phase agents (planners, synthesiser,  -->
<!-- research, codebase analyst). Leave blank to inherit session model.    -->

<!-- execute-model: Model for execution-phase agents (specialists,        -->
<!-- verification, fixes, documentation). Leave blank to inherit session   -->
<!-- model.                                                                -->

plan-model:
execute-model:
```

### 3b — Update the setting

Read `.pace/settings.md`. Find the line starting with `{key}:` and replace the
value after the colon.

For example, if key is `execute-model` and value is `sonnet`:
- Find: `execute-model:` (with whatever follows on that line)
- Replace with: `execute-model: sonnet`

If value is empty (clearing the setting):
- Replace with: `execute-model:`

### 3c — Confirm

If in direct-set mode (from argument parsing):
```
Updated {key} to {value or "cleared (inherits session model)"}.
```

Show the current settings table (same format as 2b) and stop.

If in interactive mode, loop back to Step 2a.

</process>
