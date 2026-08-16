# HISTORY

This file is non-authoritative. Archive completed checkpoints, resolved issues, and consolidation notes here.

## Completed checkpoints

- Stage 38 established reproducible tracked Lua 5.1 tooling, deterministic Fast/Full/Package/Security profiles, VibeRun role/state integration, staged-artifact/static/security policy, exact-head GitHub Actions, and clean local review/publication receipts.
- Stage 39 reconciled PR #13 onto PR #10 base `d0681b6`, hardened current-base routing/diff/manual-smoke boundaries, and completed exact-head local review without product changes.
- Stage 40 refreshed the draft infrastructure branch, repaired cross-platform workflow policy defects found by CI, and stopped at green exact-head Quality Gate/Release Policy with zero reviews or threads.
- Stage 41 repaired rename/copy and policy routing (41.1), staged-artifact Git-path safety (41.2), and fail-closed summaries plus required Package CI (41.3). Focused reviews and bounded hygiene passed at each checkpoint.

## Resolved issues

- Git rename/copy discovery and workflow classification now use one NUL-safe record model and preserve both owners.
- Policy/legal/security Markdown no longer inherits ordinary-documentation routing.
- Staged/all-tracked artifact discovery no longer consumes Git-quoted lines and shares one fail-closed policy with Fast.
- Blocking skipped/malformed results fail aggregate validation, and Package is a required exact-base non-publishing CI job.

## Process notes

- Initialized by Vibe package 0.1.0+codex.20260812081901 using state schema 1.0.
- Stage 41 consolidation corrected stale PLAN status for reviewed checkpoint 41.1, pruned the hot work log to eight receipts, and retained only Stages 42–43 in active PLAN.
