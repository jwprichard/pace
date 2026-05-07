---
name: pace:usage
description: Display token usage and cost breakdown for the current plan — grand total, per-phase subtotals, and per-task detail rows
allowed-tools:
  - Read
  - Bash
---

<objective>
Show a read-only token usage report for the current plan. Reads `.pace/usage.md`
and formats it into a full breakdown: grand total, per-phase subtotals (plan,
execute, verify, fix, amend, complete), and per-task detail rows within each phase.

Token counts are displayed with comma separators (e.g. `1,234,567`).
Costs are displayed with a dollar sign and two decimal places (e.g. `$1.23`).

This command is strictly read-only. It does not modify any files and does not
spawn any agents.
</objective>

<process>

## Step 1 — Check for usage data

Check whether `.pace/usage.md` exists:

```bash
test -f .pace/usage.md && echo "exists" || echo "missing"
```

If the file does not exist or the check returns `missing`, output exactly:

```
No usage data found. Token tracking begins when you run /pace:plan.
```

Then stop.

## Step 2 — Format and display

Run the formatter, passing the file path directly:

```bash
python3 ~/.claude/lib/pace/token-usage.py format detail .pace/usage.md
```

Display the output to the user as-is. The formatter produces:

- A `## Grand Total` section with a single row containing summed input tokens,
  output tokens, cache read tokens, cache write tokens, and total cost.
- A section per phase (Plan, Execute, Verify, Fix, Amend, Complete) with:
  - One row per task showing task ID, agent, model, and the four token counts
    plus cost.
  - A **Subtotal** row at the bottom of each phase.

If the formatter prints `No usage data found. Token tracking begins when you run /pace:plan.`
(which it does when the file is empty or unparseable), relay that message to the user.

</process>
