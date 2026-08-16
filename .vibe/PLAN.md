# PLAN

## Stage 38 — Reproducible VibeRun quality-gate infrastructure

- Goal: satisfy issue #12 with deterministic validation workers beneath VibeRun while preserving every addon runtime, metadata, protocol, storage, bundled-data, test, and artifact byte.
- Base: `origin/refactor/nexus-1.20-test17` at `36f187824b8a24f6fb51562e6ec1101c300308ef`.
- Branch/worktree: `infra/viberun-quality-gate` / `.infra-viberun-quality-gate-worktree`.
- Scope: infrastructure, tooling, workflow, static-analysis configuration, development documentation, and compact branch-local Vibe state only.

### (DONE) 38.1 — Bootstrap tracked Lua 5.1 validation

- Receipt: exact lockfile/bootstrap and tracked wrappers passed clean-checkout parse `272/272`, integration `70/70`, and the 60-pass/61-fail upvalue boundary. See `.vibe/EVIDENCE.md` and `266d510`.

### (DONE) 38.2 — Add deterministic local quality profiles

depends_on: [38.1]

- Receipt: Fast `11/11`, Package `8/8`, Full `16/16`, compact summaries, deterministic routing, and self-tests passed. Security correctly retained four unavailable owners for 38.4. See `.vibe/EVIDENCE.md`, `1b096cb`, and `b71ee32`.

### (DONE) 38.3 — Bind VibeRun roles and compact hot context

depends_on: [38.2]

- Receipt: supported role/profile policy, exact schema-v1 headings, bounded evidence/history reads, strict dispatcher validation, Fast `6/6`, and exact-head Full `16/16` passed. See `.vibe/EVIDENCE.md`, `232a552`, and `8bab598`.

### 38.4 — Add staged-artifact, static-analysis, and security policy

depends_on: [38.3]

- Status: `IN_REVIEW`
- Objective:
  - Reject unsafe staged material and establish pinned, honest Lua, PowerShell, secret, and workflow analysis without rewriting source.
- Deliverables:
  - Pinned pre-commit hooks and staged-artifact policy with self-tests.
  - LuaLS, advisory Luacheck, check-only StyLua, and PSScriptAnalyzer policies.
  - Checksum-verified Gitleaks, actionlint, and zizmor bootstrap integrated with Security mode.
- Acceptance:
  - [x] Forbidden artifacts, credentials, private paths, caches, and generated data are rejected.
  - [x] Lua tooling targets 5.1 with narrow globals and no repository reformat.
  - [x] Blocking versus advisory findings and unavailable tools are reported honestly.
  - [x] Security tools are exact-versioned and downloaded bytes are checksum-verified.
- Demo commands:
  - `pwsh -NoProfile -File tools/Test-StagedArtifacts.ps1`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Security`
  - `pre-commit run --all-files`
- Evidence:
  - Policy fixture totals, pinned checksum receipt, static-analysis baseline, and compact Security summary.

### 38.5 — Add exact-head GitHub Actions quality gate

depends_on: [38.4]

- Status: `NOT_STARTED`
- Objective:
  - Run the tracked profiles in GitHub Actions with least privilege, immutable dependencies, visible policy skips, and one final gate result.
- Deliverables:
  - `preflight`, `fast-quality`, `security-quality`, `full-quality`, and final `quality-gate` jobs.
  - In-workflow path classification, compact summaries, and failure-only/explicit logs with short retention.
  - Workflow self-tests for triggers, permissions, pins, concurrency, checkout credentials, conditions, and aggregation.
- Acceptance:
  - [ ] Pull requests, main pushes, and dispatch are covered without trigger path filtering.
  - [ ] Permissions are read-only, credentials do not persist, and all actions use complete SHAs.
  - [ ] Required Full runs and documentation-only skips are deterministic and visible.
  - [ ] Existing `release-policy.yml` remains unchanged.
- Demo commands:
  - `node tests/run-quality-workflow-policy.js`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Security`
- Evidence:
  - Workflow-policy totals, exact workflow diff, and compact local summaries.

### 38.6 — Adversarial exact-head review and draft publication

depends_on: [38.5]

- Status: `NOT_STARTED`
- Objective:
  - Prove infrastructure-only scope at one clean head, publish a draft PR targeting PR #10, link issue #12, and inspect exact-head CI without merging.
- Deliverables:
  - Base-to-head invariant proof and clean-checkout bootstrap.
  - Exact-head Fast, Full, Package, Security, release-policy, pre-commit, and diff receipts.
  - Draft PR, issue #12 comment, CI/review/mergeability inspection, and local/CI summary comparison.
- Acceptance:
  - [ ] Changed paths remain within authorized infrastructure categories and all relevant worktrees retain ownership/cleanliness expectations.
  - [ ] Remote head equals validated local head; the new PR remains draft and issue #12 is not prematurely closed.
  - [ ] No merge, force-push, artifact, tag, release, install, live action, publication, or settings mutation occurs.
- Demo commands:
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Full`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Security`
  - `pre-commit run --all-files`
  - `git diff --check origin/refactor/nexus-1.20-test17..HEAD`
- Evidence:
  - Exact-head summaries, scope/clean-checkout proofs, CI run IDs, draft PR URL, and issue-comment URL.

## Deferred backlog

- [DEFERRED] Native test.17 follow-up remains owned by the completed product workflow.
- [DEFERRED] Release, installation, live SavedVariables, WoW validation, and artifact publication require separate authorization.
