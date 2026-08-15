# PLAN

## Stage 38 — Reproducible VibeRun quality-gate infrastructure

- Goal: satisfy GitHub issue #12 with deterministic validation workers beneath VibeRun while preserving all addon runtime, metadata, protocol, storage, bundled-data, and artifact bytes.
- Base: `origin/refactor/nexus-1.20-test17` at `36f187824b8a24f6fb51562e6ec1101c300308ef`; draft PR #10 remains open and authoritative.
- Branch/worktree: `infra/viberun-quality-gate` / `.infra-viberun-quality-gate-worktree`.
- Stage boundary: infrastructure, tooling, workflow, static-analysis configuration, documentation, and compact branch-local Vibe state only.
- Hard exclusions: production Lua, `Nexus.toc`, bundled data, runtime tests, historical artifacts, test.17, installation, live SavedVariables, WoW launch, release, and publication.

### 38.1 — Bootstrap the tracked Lua 5.1 validation toolchain (DONE)

- Status: `DONE`
- Objective:
  - Replace ignored `.tools/fengari` dependency state with one exact lockfile-backed bootstrap that works from a clean checkout.
- Deliverables:
  - Exact `package.json` and `package-lock.json` dependencies using `npm ci`.
  - Tracked Lua 5.1 parser and Fengari test-runner wrappers preserving the current prelude and test semantics.
  - `tools/Bootstrap-QualityTools.ps1` as the documented bootstrap entry point.
  - Toolchain self-tests and concise usage documentation.
- Acceptance:
  - [ ] Current tracked-only setup reproduces a missing `luaparse`/runner expected red before implementation.
  - [ ] Bootstrap succeeds from a dependency-clean checkout using only tracked manifests.
  - [ ] Parser covers production and test Lua as Lua 5.1 and the existing integration runner executes.
  - [ ] Existing 60-pass/61-fail upvalue boundary remains unchanged.
  - [ ] No dependency cache, generated output, runtime/test/TOC, or artifact byte is committed.
- Demo commands:
  - `pwsh -NoProfile -File tools/Bootstrap-QualityTools.ps1`
  - `node tools/parse-lua51.js . --tests`
  - `node tools/run-lua.js tests/run_integration.lua`
  - `node tests/run-upvalue-compatibility.js`
- Evidence:
  - Expected-red missing dependency receipt; clean-bootstrap result; focused parser/runner/upvalue totals.

### 38.2 — Add deterministic local quality-gate profiles and compact summaries

- Status: `NOT_STARTED`
- Objective:
  - Provide one local entry point whose Fast, Full, Package, and Security profiles route exact checks and retain compact deterministic results.
- Deliverables:
  - `tools/Invoke-QualityGate.ps1`, `tools/Get-ChangedTestPlan.ps1`, and narrowly required helpers.
  - `tests/validation-map.json` mapping product, tooling, workflow, and documentation paths to focused groups.
  - `tools/Write-ValidationSummary.js` writing ignored `build/verify/summary.json`, `summary.md`, and per-check logs.
  - Package dry-run validation with safe paths, one `Nexus` root, source parity, manifest, and checksum evidence.
  - Quality-gate self-tests for routing, ordering, exit status, unavailable tools, compact output, and multiple failures.
- Acceptance:
  - [ ] Fast runs mapped changed-path tests without replacing final Full review.
  - [ ] Full covers every current repository gate required by issue #12.
  - [ ] Package uses temporary output only and retains no ZIP or package tree.
  - [ ] Security reports blocking, advisory, skipped, and unavailable states honestly.
  - [ ] Summary JSON is deterministic, path-portable, private-data-safe, and points failures to exact logs and commands.
  - [ ] Multiple safe-to-continue failures are retained and produce a failing exit status.
- Demo commands:
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Full`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Package`
  - `node tests/run-quality-gate-self-tests.js`
- Evidence:
  - Compact summaries for all modes; self-test totals; temporary-package cleanup proof.

### 38.3 — Bind VibeRun roles to validation profiles and compact hot context

- Status: `NOT_STARTED`
- Objective:
  - Make VibeRun implementation, review, hygiene, and consolidation roles select the correct deterministic gate without adding another orchestrator or unsupported schema.
- Deliverables:
  - Compact `AGENTS.md` role policy for Fast implementation, one Full review, bounded hygiene, and non-product consolidation.
  - Compact branch-local `.vibe/STATE.md`, `PLAN.md`, and `CONTEXT.md` containing only Stage 38 execution state.
  - Evidence lookup policy using current-checkpoint search, bounded tail, and exact referenced receipts.
  - Documented role-to-profile behavior using only installed VibeRun prompt/schema mechanisms.
- Acceptance:
  - [ ] VibeRun remains the only dispatcher, state owner, and roadmap owner.
  - [ ] Implementation stops after one reviewed clean commit and Fast validation.
  - [ ] Review runs Full once, inspects the compact summary, and opens detailed logs only for failures or suspicion.
  - [ ] Hygiene does not repeat Full when product/test bytes did not change.
  - [ ] No `.ai/**`, local prompt catalog, second plugin, or unsupported role field exists.
  - [ ] Completed Stage 35–37 detail is not duplicated in branch-local hot context.
- Demo commands:
  - `python "<installed-vibe-run>/skills/vibe-run/scripts/vibe.py" --repo-root . validate`
  - `git diff --check`
- Evidence:
  - Strict Vibe validation; before/after hot-context byte and line counts; prohibited-namespace scan.

### 38.4 — Add staged-artifact, editor, static-analysis, and security policy

- Status: `NOT_STARTED`
- Objective:
  - Reject unsafe staged material and establish pinned, honest Lua, PowerShell, secret, and workflow analysis without rewriting repository source.
- Deliverables:
  - Pinned `.pre-commit-config.yaml` plus `tools/Test-StagedArtifacts.ps1` and staged-policy tests.
  - `.luarc.json`, `.luacheckrc`, and check-only/advisory StyLua configuration.
  - PSScriptAnalyzer settings and blocking/advisory result handling.
  - Version/checksum manifest and bootstrap for Gitleaks, actionlint, and zizmor.
  - Security-profile integration with explicit baseline/severity policy.
- Acceptance:
  - [ ] Staged ZIPs, build output, SavedVariables, logs, prompts/transcripts, local caches, dependency trees, credentials, and private paths are rejected.
  - [ ] LuaLS/Luacheck target Lua 5.1 with narrow WoW/Project Ebonhold globals; StyLua remains check-only/advisory.
  - [ ] PSScriptAnalyzer parse errors and high-confidence security findings block; lower-severity style is reported honestly.
  - [ ] Gitleaks, actionlint, and zizmor versions are pinned and downloaded bytes are checksum-verified.
  - [ ] Secret/private-key, workflow syntax, and high-confidence workflow-security findings block.
  - [ ] No repository-wide line-ending or formatting rewrite occurs.
- Demo commands:
  - `pwsh -NoProfile -File tools/Test-StagedArtifacts.ps1`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Security`
  - `pre-commit run --all-files`
- Evidence:
  - Artifact-policy fixtures; static-analysis baseline summary; pinned-tool checksum and Security summary.

### 38.5 — Add the exact-head GitHub Actions quality gate

- Status: `NOT_STARTED`
- Objective:
  - Run the same tracked profiles on GitHub Actions with least privilege, immutable dependencies, visible policy skips, and one final gate result.
- Deliverables:
  - `.github/workflows/quality-gate.yml` with preflight, fast-quality, security-quality, full-quality, and final quality-gate jobs.
  - In-workflow changed-path classification and full-gate selection without trigger path filtering.
  - Compact summaries and failure-only or explicit-dispatch log uploads with short retention.
  - Workflow-focused self-tests for permissions, action pins, concurrency, credentials, conditions, and final aggregation.
- Acceptance:
  - [ ] Triggers are pull request, push to main, and workflow dispatch; permissions are `contents: read` and checkout does not persist credentials.
  - [ ] Every third-party action uses a full commit SHA and superseded runs cancel by workflow/ref.
  - [ ] Full runs for runtime/test/tool/package/workflow/policy changes, main pushes, and explicit full dispatch.
  - [ ] Documentation-only Full skips are classifier-proven and visible in the final summary.
  - [ ] Final job uses `if: always()` and fails required failures or unexpected skips.
  - [ ] Existing `.github/workflows/release-policy.yml` remains present and unchanged.
- Demo commands:
  - `node tests/run-quality-workflow-policy.js`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Security`
- Evidence:
  - Workflow-policy test totals; exact workflow diff; compact local summaries.

### 38.6 — Perform adversarial exact-head review and publish the draft PR

- Status: `NOT_STARTED`
- Objective:
  - Prove infrastructure-only scope at one exact clean head, publish a draft PR targeting PR #10, and link issue #12 without merging or releasing.
- Deliverables:
  - Exact base-to-head scope and invariant proof for runtime, TOC, version, protocol, author, SavedVariables, bundled data, tests, and artifacts.
  - Clean-checkout bootstrap plus Fast, Full, Package, Security, release-policy, pre-commit, and diff validation receipts.
  - Independent adversarial source/workflow review with directly related repairs completed before publication.
  - Draft infrastructure PR and issue #12 coordination comment with exact branch/base/head and validation state.
  - Exact-head GitHub Actions, review-thread, mergeability, and local/CI summary-parity inspection.
- Acceptance:
  - [ ] Changed paths are limited to authorized infrastructure, workflow, configuration, documentation, and compact Vibe files.
  - [ ] Both product and infrastructure worktrees are clean; root and `.lag-hotfix-worktree` remain byte-untouched.
  - [ ] Every required local check passes or is reported unavailable/blocked without being called a pass.
  - [ ] Remote branch head equals the exact locally validated head and the new PR remains draft.
  - [ ] Issue #12 is updated but not closed unless every acceptance item is satisfied.
  - [ ] Neither PR is merged and no artifact, tag, release, install, live action, publication, or GitHub-setting mutation occurs.
- Demo commands:
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Full`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Security`
  - `pre-commit run --all-files`
  - `git diff --check origin/refactor/nexus-1.20-test17..HEAD`
- Evidence:
  - Exact-head summaries, clean-checkout receipt, scope proof, CI run IDs, draft PR URL, and issue-comment URL.

## Deferred backlog

- [DEFERRED] Native test.17 results remain owned by the product workflow; revisit only after owner-supplied native evidence.
- [DEFERRED] Release, installation, live SavedVariables, and WoW validation remain outside issue #12 and require separate authorization.
