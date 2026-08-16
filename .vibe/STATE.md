# STATE

- Schema version: 1.0
- Vibe package version: 0.1.0+codex.20260812081901
- Prompt catalog version: 1.1.0

## Current focus

- Stage: 38
- Checkpoint: 38.4
- Status: NOT_STARTED
- Branch: `infra/viberun-quality-gate`
- Candidate head: `8bab598eb3296b8655bfb897393598d3c8ccf1b5`
- Worktree: `.infra-viberun-quality-gate-worktree`
- Base: `origin/refactor/nexus-1.20-test17` at `36f187824b8a24f6fb51562e6ec1101c300308ef`

## Objective (current checkpoint)

Add staged-artifact protection and exact, honest Lua, PowerShell, secret, and GitHub workflow security policy without changing source behavior.

## Deliverables (current checkpoint)

- Pinned pre-commit configuration and staged-artifact policy with self-tests.
- LuaLS, advisory Luacheck, and check-only StyLua configuration.
- PSScriptAnalyzer blocking/advisory policy.
- Checksum-verified Gitleaks, actionlint, and zizmor bootstrap integrated with Security mode.

## Acceptance (current checkpoint)

- [ ] Forbidden artifacts, credentials, private paths, caches, and generated data are rejected.
- [ ] Lua tools target Lua 5.1 with narrow globals and no source reformat.
- [ ] PSScriptAnalyzer parse/security failures block while lower-severity style remains advisory.
- [ ] Secret, workflow syntax, and high-confidence workflow-security findings block.
- [ ] Security tools use exact versions and verified checksums.
- [ ] Skipped, advisory, or unavailable checks remain visibly non-passing.

## Evidence

- path: .vibe/EVIDENCE.md
- 38.1 clean bootstrap passed parse `272/272`, integration `70/70`, and the 60-pass/61-fail upvalue boundary.
- 38.2 Fast `11/11`, Package `8/8`, and Full `16/16` passed; Security's four unavailable tools are the expected-red boundary for 38.4.
- 38.3 role/hot-context policy passed strict dispatcher validation, Fast `6/6`, and exact-head Full `16/16` at `8bab598`.
- VibeRun remains the sole dispatcher; no alternate state namespace, local prompt catalog, role schema, or plugin was added.

## Work log

- Checkpoint 38.3 review passed and auto-advanced to 38.4; its required schema-heading repair and final Full receipt are preserved in evidence.
- The installed dispatcher dependency DAG now marks 38.1–38.3 done and 38.4 ready.

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

- Native test.17 follow-up remains owned by the completed product checkpoint.
- Release, installation, live SavedVariables, WoW execution, and artifact publication remain outside authorization.

## Decisions

- Use installed VibeRun prompts/schema only; deterministic checks remain subordinate workers.
- Treat LuaLS/Luacheck/StyLua legacy output honestly and avoid repository-wide formatting or warning-flood changes.
- Target the infrastructure PR at `refactor/nexus-1.20-test17` while PR #10 remains open and authoritative.

## Last completed loop

- Checkpoint 38.3 adversarial review passed at exact `8bab598` and advanced the pointer to 38.4.

## Recommended next action

- Run mandatory bounded 38.3 hygiene, then implement 38.4 from the expected-red unavailable Security profile.
