# CONTEXT

## Architecture

- Repository `Viscerals/Better-Nexus`; isolated infrastructure worktree `.infra-viberun-quality-gate-worktree` on `infra/viberun-quality-gate`.
- Integration base is `origin/refactor/nexus-1.20-test17` at `d0681b6a885db447c94a75f40df7e81f60b74c55`; draft PR #13 targets draft PR #10's branch.
- Runtime addon identity is `Nexus`, WoW target is 3.3.5a, and sources/tests parse as Lua 5.1.
- `Invoke-QualityGate.ps1` owns Fast, Full, Package, and Security; successful summaries are compact and detailed logs remain ignored.
- Production Lua, runtime-test Lua, `Nexus.toc`, schemas, wire/gameplay/UI behavior, bundled data, version/protocol/author, and test.17 are immutable in this infrastructure workflow.

## Key Decisions (2026-08-16)

- Git change discovery uses one raw NUL-delimited record model; rename/copy source and destination ownership are unioned.
- Fast and staged/all-tracked scans share one fail-closed artifact path/content policy.
- Only blocking `pass` succeeds; Package is a required exact-base, non-publishing CI job with failure-log-only evidence.
- Stage 42 repairs the exact PSScriptAnalyzer baseline before editing bootstrap code, then validates archive layout/executable identity and Python distribution hashes together.
- Stage 43 runs Full once on the unchanged formal candidate, proves a fresh checkout, then refreshes PR #13/issue #12 and stops without merge.

## Gotchas

- Windows Git cannot represent tab/newline index names; use raw-byte parser fixtures locally and real disposable index fixtures on supporting platforms.
- LuaLS, Luacheck, and StyLua may remain advisory-unavailable; never report unavailable checks as passing.
- Use the exact PR #10 BaseRef for full-branch gates and the checkpoint parent for bounded checkpoint review.
- Vibe flags and routing are dispatcher-owned; maintenance scans must not move the product checkpoint pointer.
- Schema-valid state can still be semantically stale; verify status beneath the exact checkpoint heading and confirm fresh-checkout dispatcher truth at Stage 43.

## Hot Files

- Current checkpoint 42.1: `tools/Test-SecurityPolicy.ps1`, `tests/security-advisory-baseline.json`, `tests/run-security-policy.js`.
- Next checkpoint 42.2: `tools/Bootstrap-SecurityTools.ps1`, `tools/security-tools.json`, and the focused non-executing hostile fixtures.
- Workflow/gate: `.github/workflows/quality-gate.yml`, `tools/Invoke-QualityGate.ps1`, `tools/Write-ValidationSummary.js`.
- Path policy: `tools/GitPathRecords.ps1`, `tools/ArtifactPathPolicy.ps1`, `tools/Get-ChangedTestPlan.ps1`, `tools/Test-StagedArtifacts.ps1`.
- Vibe authority: `AGENTS.md`, `.vibe/STATE.md`, active `.vibe/PLAN.md`, this file, and append-only `.vibe/EVIDENCE.md`.

## Agent Notes

- Root, `.lag-hotfix-worktree`, and authoritative product worktree are independently owned and read-only for this task; preserve their existing status.
- PR #13 and issue #12 remain open; do not submit another `@codex review` because the prior request hit the account usage limit.
- Expected red must demonstrate the actual missing capability; use disposable repositories/archives and never place hostile fixtures in the real worktree.
- No addon install, WoW launch, live SavedVariables access, package retention/upload, rebase, force-push, merge, tag, release, publication, deployment, or settings change is authorized.
- Final offline/CI evidence does not prove native WoW behavior; stop at the refreshed independent-review boundary.

## Stage Retrospective Notes

- Stage 41 took 10 delivery loops: design plus implement/review/hygiene for three checkpoints, with no repeat review, split, skip, blocker, or decision-required issue.
- Keep checkpoint-range and current-base Fast evidence separate; preserve a base-wide failure as the next checkpoint's red boundary when ownership is explicit.
- Pair raw-byte path fixtures with real disposable Git index fixtures where the platform supports hostile names.
- Centralize a shared security policy before updating callers so false positives and bypasses cannot drift.
- Test local summary semantics and GitHub aggregate conditions in the same fail-closed checkpoint.
- After each Vibe transition, verify the status beneath the exact checkpoint heading rather than relying only on schema validation.
