# STATE

- Schema version: 1.0
- Vibe package version: 0.1.0+codex.20260812081901
- Prompt catalog version: 1.1.0

## Session read order

1. `AGENTS.md`
2. `.vibe/STATE.md`
3. active checkpoint in `.vibe/PLAN.md`
4. `.vibe/CONTEXT.md`

## Current focus

- Stage: 38
- Checkpoint: 38.2
- Status: NOT_STARTED

## Objective (current checkpoint)

Provide one deterministic local quality-gate entry point with Fast, Full, Package, and Security profiles, changed-path routing, compact summaries, and self-tests.

## Deliverables (current checkpoint)

- Fast, Full, Package, and Security orchestration in `tools/Invoke-QualityGate.ps1`.
- Changed-path routing from `tests/validation-map.json` through `tools/Get-ChangedTestPlan.ps1`.
- Compact deterministic `summary.json`, `summary.md`, and separate check logs.
- Temporary package parity/manifest/checksum validation with no retained artifact.
- Self-tests covering modes, failure propagation, ordering, portability, unavailable tools, and summary bounds.

## Acceptance (current checkpoint)

- [ ] Fast selects focused changed-path checks without suppressing final Full review.
- [ ] Full covers every current repository gate required by issue #12.
- [ ] Package validates safe one-root source parity and cleans all temporary output.
- [ ] Security reports blocking, advisory, skipped, and unavailable states honestly.
- [ ] Compact output is deterministic, private-data-safe, and preserves multiple failure evidence with a failing exit status.

## Work log (current session)

- Bootstrapped compact branch-local Vibe state in the clean infrastructure worktree.
- Reconciled completed root Stage 37.1/product head `7aee1d9` with PR #10 publication tree and selected remote PR head `36f187824b8a24f6fb51562e6ec1101c300308ef` as the infrastructure base.
- Designed Stage 38 as six bounded infrastructure checkpoints tracked by issue #12.
- Implemented checkpoint 38.1 with exact root dependencies, tracked Lua 5.1/Fengari wrappers, one PowerShell bootstrap, a deterministic self-test, and updated validation documentation.
- Reviewed checkpoint 38.1 from a separate dependency-clean worktree; all focused gates and scope checks passed at committed `266d510` and the pointer advanced to 38.2.

## Evidence

- path: .vibe/EVIDENCE.md
- PR #10: open, draft, mergeable; head `refactor/nexus-1.20-test17` at `36f187824b8a24f6fb51562e6ec1101c300308ef`.
- Issue #12: open; infrastructure-only coordination owner.
- Product commit `7aee1d9` and PR publication commit `f63a49d` have identical tree `f0dd136dbaf07270cf2ecf14f97cda2ab8151133`; PR head adds licensing/release-policy commits only.
- Existing release-policy workflow run `31857811990` passed at the selected PR head.
- Root coordination state and independently owned `.lag-hotfix-worktree` are read-only and outside this worktree.
- 38.1 expected red: tracked parser/runner/manifests absent and `node` unavailable on PATH; no product test failed.
- 38.1 focused green: parse `272/272`, integration `70/70`, upvalue `60 pass / 61 fail`, toolchain self-test PASS, and diff check PASS.
- 38.1 clean-review green: exact `266d510`, bootstrap PASS, clean status, no forbidden runtime/TOC/artifact/cache path, and no checkpoint-hygiene signal beyond preserving deterministic wrapper simplicity.

## Workflow state

- [ ] RUN_STOPPED
- [ ] RUN_CONTEXT_CAPTURE
- [x] STAGE_DESIGNED
- [x] MAINTENANCE_CYCLE_DONE
- [x] RETROSPECTIVE_DONE
- [x] PROCESS_IMPROVEMENTS_DONE

## Active issues

- None.

## Blockers

- None.

## Deferred work

- Native test.17 evidence remains owned by the completed product checkpoint and does not block infrastructure work.
- Release, installation, live SavedVariables, and WoW execution remain outside authorization.

## Decisions

- Use Stage 38 because authoritative read-only coordination state completed Stage 37.1.
- Bootstrap compact branch-local Vibe state; do not copy historical Stage 35–37 bulk.
- Keep installed VibeRun as the sole dispatcher and use deterministic scripts only as validation workers.
- Target the infrastructure PR at `refactor/nexus-1.20-test17` while PR #10 remains open and authoritative.

## Last completed loop

- Checkpoint 38.1 adversarial review passed and auto-advanced Stage 38 to checkpoint 38.2.

## Recommended next action

- Run the required bounded checkpoint-hygiene pass for 38.1, then implement 38.2 expected-red orchestration and self-tests.
