# CONTEXT

## Current Git and coordination truth

- Repository: `Viscerals/Better-Nexus`.
- Infrastructure worktree: `.infra-viberun-quality-gate-worktree` on `infra/viberun-quality-gate`.
- Integration base: `origin/refactor/nexus-1.20-test17` at `d0681b6a885db447c94a75f40df7e81f60b74c55`, merged normally into the infrastructure branch at `5a66cde`.
- Draft refactor PR #10 is open and authoritative; draft infrastructure PR #13 and GitHub issue #12 own the current coordination boundary.
- The repository-root coordination worktree and `.lag-hotfix-worktree` are independently owned and read-only for this work.
- Branch-local Vibe state is compact by design; completed product Stage 37.1 remains authoritative in the root and is not copied here.

## Architecture invariants

- Runtime folder/addon identity is `Nexus`; target is WoW 3.3.5a and Lua 5.1.
- Public version remains `1.20.0-beta.1`, protocol remains 7, and `Author: Valentine` remains unchanged.
- `NexusDB` and `WishlistRealizerDB` schemas/behavior, Sync wire behavior, gameplay/UI behavior, and bundled build data are outside Stage 38.
- Production Lua, `Nexus.toc`, runtime tests, historical artifacts, and test.17 are immutable in this infrastructure stage.
- Development bootstrap may use the network; the addon never does so for tooling or updates.

## Workflow invariants

- Installed VibeRun package `0.1.0+codex.20260812081901`, state schema 1.0, and prompt catalog 1.1.0 are authoritative.
- VibeRun dispatches roles; `Invoke-QualityGate.ps1` supplies Fast, Full, Package, and Security workers.
- Expected red is a missing capability or focused failing check, not a fabricated product failure.
- Successful summaries stay compact. Detailed logs remain ignored under `build/verify/logs/` and are opened only for failures or suspicious results.
- Evidence is append-only and bounded on read; history is non-authoritative and read only for reconciliation.

## Hot files and commands

- Workflow policy: `AGENTS.md`, `.vibe/STATE.md`, active `.vibe/PLAN.md` checkpoint, `.vibe/CONTEXT.md`.
- Gate entry point: `tools/Invoke-QualityGate.ps1`.
- Changed-path routing: `tools/Get-ChangedTestPlan.ps1`, `tests/validation-map.json`.
- Compact output: `tools/Write-ValidationSummary.js`, `build/verify/summary.json`.
- Bootstrap: `tools/Bootstrap-QualityTools.ps1` using tracked `package-lock.json` and `npm ci`.
- Release policy remains owned by `.github/workflows/release-policy.yml` and `tools/Test-ReleasePolicy.ps1`.

## Offline and native limits

- Offline Lua parsing, Fengari tests, packaging parity, static analysis, and GitHub Actions do not prove native WoW behavior.
- Native test.17 evidence remains owned by the completed product checkpoint. Stage 38 neither creates test.18 nor resolves native follow-up questions.
- Addon installation, WoW launch, live SavedVariables access, artifact publication, merging, tagging, and release are outside authorization.
