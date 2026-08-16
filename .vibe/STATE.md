# STATE

- Schema version: 1.0
- Vibe package version: 0.1.0+codex.20260812081901
- Prompt catalog version: 1.1.0

## Current focus

- Stage: 38
- Checkpoint: 38.5
- Status: NOT_STARTED
- Branch: `infra/viberun-quality-gate`
- Candidate head: `b792c82b75c176151ded62568f82788cb18f654f`
- Worktree: `.infra-viberun-quality-gate-worktree`
- Base: `origin/refactor/nexus-1.20-test17` at `36f187824b8a24f6fb51562e6ec1101c300308ef`

## Objective (current checkpoint)

Add an exact-head GitHub Actions quality gate using the tracked profiles, least privilege, immutable actions, visible policy skips, and deterministic final aggregation.

## Deliverables (current checkpoint)

- `.github/workflows/quality-gate.yml` with preflight, Fast, Security, conditional Full, and final aggregation jobs.
- In-workflow changed-path classification and compact summary/artifact policy.
- Workflow self-tests for triggers, permissions, pins, concurrency, credentials, conditions, and final results.

## Acceptance (current checkpoint)

- [ ] Pull requests, main pushes, and dispatch run without trigger path filters.
- [ ] Permissions are `contents: read`, credentials do not persist, and every external action uses a complete SHA.
- [ ] Full runs for relevant paths/main/manual full and documentation-only skips are visible.
- [ ] Final `if: always()` job rejects required failures and unexpected skips.
- [ ] Detailed logs upload only on failure or explicit dispatch with short retention.
- [ ] Existing `release-policy.yml` remains present and byte-unchanged.

## Evidence

- path: .vibe/EVIDENCE.md
- 38.2 local Fast/Full/Package/Security orchestration and compact summaries are committed and reviewed.
- 38.3 role-specific validation and 23.7% hot-context reduction are reviewed.
- 38.4 exact-head `b792c82` passed Full `16/16`, Security 10 pass / 3 advisory-unavailable, artifact/self-tests, and pre-commit.
- Existing release-policy workflow is unchanged from selected base and its run `31857811990` passed.

## Work log

- Checkpoint 38.4 review passed and auto-advanced to 38.5; all exact security pins, baselines, and honest advisory status are preserved.
- The installed dispatcher DAG marks 38.1–38.4 done and 38.5 ready.

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

- LuaLS, Luacheck, and StyLua remain advisory-unavailable and are not represented as passes.
- Native test.17 and all install/live/release activity remain outside this infrastructure stage.

## Decisions

- Use installed VibeRun as sole orchestrator and the same tracked local gate beneath CI.
- Keep release-policy ownership separate and unchanged.
- Target the infrastructure PR at `refactor/nexus-1.20-test17` while PR #10 remains open and authoritative.

## Last completed loop

- Checkpoint 38.4 adversarial review passed at exact `b792c82` and advanced to 38.5.

## Recommended next action

- Run mandatory bounded 38.4 hygiene, then implement the deterministic quality-gate workflow.
