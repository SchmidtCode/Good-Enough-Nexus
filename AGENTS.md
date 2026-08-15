# .infra-viberun-quality-gate-worktree agent instructions

This repository uses globally installed Vibe orchestration with repository-local state under `.vibe/`.

1. Follow current user instructions, then this file, `.vibe/STATE.md`, `.vibe/PLAN.md`, and `.vibe/CONTEXT.md`.
2. Inspect repository evidence before changing code or selecting build commands.
3. Preserve unrelated user changes and inspect `git status` before editing or committing.
4. Work in bounded checkpoints; record concise command outcomes in `.vibe/EVIDENCE.md`.
5. Do not treat skipped, unavailable, or failing checks as passing.
6. Never push a protected/default branch, force-push, merge, delete history, or perform destructive work without explicit authorization.
7. Keep unknown product and architectural requirements explicit rather than hardcoding guesses.

Detected toolchains at bootstrap:

- Lua addon metadata

Detected languages at bootstrap:

- Lua
- JavaScript
