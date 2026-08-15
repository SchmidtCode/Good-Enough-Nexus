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
- Checkpoint: 38.3
- Status: NOT_STARTED

## Objective (current checkpoint)

Bind installed VibeRun implementation, review, hygiene, and consolidation roles to the deterministic validation profiles while keeping hot context compact.

## Deliverables (current checkpoint)

- Compact `AGENTS.md` role policy for Fast implementation, one Full review, bounded hygiene, and consolidation.
- Compact branch-local `STATE`, active `PLAN`, and `CONTEXT` hot files.
- Bounded current-checkpoint evidence lookup and exact receipt policy.
- Supported installed VibeRun schema/prompt integration without another dispatcher or role schema.

## Acceptance (current checkpoint)

- [ ] VibeRun remains the only dispatcher, state owner, and roadmap owner.
- [ ] Implementation uses expected red, mapped checks, Fast, one clean commit, and review handoff.
- [ ] Review runs Full once and reads detailed logs only for failure or suspicion.
- [ ] Hygiene avoids Full when product/test bytes did not change.
- [ ] Evidence/history reads are bounded and no Stage 35–37 bulk is copied.
- [ ] No `.ai/**`, local prompt catalog, second plugin, or unsupported role field exists.

## Work log (current session)

- Bootstrapped compact branch-local Vibe state in the clean infrastructure worktree.
- Reconciled completed root Stage 37.1/product head `7aee1d9` with PR #10 publication tree and selected remote PR head `36f187824b8a24f6fb51562e6ec1101c300308ef` as the infrastructure base.
- Designed Stage 38 as six bounded infrastructure checkpoints tracked by issue #12.
- Implemented checkpoint 38.1 with exact root dependencies, tracked Lua 5.1/Fengari wrappers, one PowerShell bootstrap, a deterministic self-test, and updated validation documentation.
- Reviewed checkpoint 38.1 from a separate dependency-clean worktree; all focused gates and scope checks passed at committed `266d510` and the pointer advanced to 38.2.
- Completed bounded 38.1 hygiene with no code change, debt item, or acceptance defect; wrapper simplicity and exact dependency ownership are retained.
- Implemented 38.2 Fast/Full/Package/Security orchestration, deterministic changed-path mapping, compact summaries, logical package parity, complete Lua-suite aggregation, and adversarial self-tests.
- Reviewed 38.2 at exact `b71ee32`; repaired clean-worktree routing, ran Full once to 16/16 PASS, and advanced to 38.3.
- Completed bounded 38.2 hygiene: no duplication, stale marker, debug path, temporary output, or directly attributable debt justified another code change; the committed quality-gate bytes remain unchanged.

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
- 38.1 hygiene: CLEAN with no product/tool byte change; no new gate was needed because the reviewed committed bytes were unchanged.
- 38.2 Fast `11 pass / 0 fail / 0 unavailable / 0 skip`; Package `8/0/0/0`; self-tests PASS; Security intentionally fails `4 pass / 4 unavailable` pending checkpoint 38.4.
- 38.2 Package manifest: 70 files, 66 Lua, 5,049,868 bytes, SHA-256 `e7bda27ac7f638a4603d6068545264830220a91973da980a841440149a02f288`, no retained artifact.
- 38.2 Full exact-head: 16/16 checks, Lua `202/202`, parse `272/272`, integration `70/70`, hostile `4,000/4,000`, upvalue `60 pass / 61 fail`, duration 252.596s, no private path in compact output.
- 38.2 hygiene: bounded delivered-surface scan and `git diff --check` passed; no product/tool byte changed and Full was not repeated.

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

- Checkpoint 38.2 adversarial review passed after one clean-worktree repair and auto-advanced to 38.3.

## Recommended next action

- Implement 38.3 role/profile and hot-context policy without repeating Full.
