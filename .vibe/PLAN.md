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

### (DONE) 38.4 — Add staged-artifact, static-analysis, and security policy

depends_on: [38.3]

- Receipt: verified cross-platform pins, artifact/self-tests, Lua 5.1/static policy, exact-head Full `16/16`, Security 10 pass / 3 advisory-unavailable, and pre-commit passed without normalization. See `.vibe/EVIDENCE.md` and `b792c82`.

### (DONE) 38.5 — Add exact-head GitHub Actions quality gate

depends_on: [38.4]

- Receipt: immutable least-privilege jobs, internal path classification, conditional Full, final aggregation, compact/failure-only logs, actionlint/zizmor, and exact-head Full `16/16` passed while release-policy bytes remained unchanged. See `.vibe/EVIDENCE.md` and `7633a4c`.

### (DONE) 38.6 — Adversarial local exact-head review

depends_on: [38.5]

- Status: `DONE`
- Objective:
  - Prove infrastructure-only scope and deterministic validation at one clean local head before publication.
- Deliverables:
  - Base-to-head invariant proof and clean-checkout bootstrap.
  - Exact-head Fast, Full, Package, Security, release-policy, pre-commit, and diff receipts.
  - Adversarial source-scope review and compact Vibe review/hygiene receipts.
- Acceptance:
  - [ ] Changed paths remain within authorized infrastructure categories and all relevant worktrees retain ownership/cleanliness expectations.
  - [ ] Required local checks pass or remain honestly advisory/unavailable at the reviewed head.
  - [ ] No runtime, artifact, install, live, release, or GitHub mutation occurs.
- Demo commands:
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Full`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Security`
  - `pre-commit run --all-files`
  - `git diff --check origin/refactor/nexus-1.20-test17..HEAD`
- Evidence:
  - Exact-head summaries plus scope and clean-checkout proofs.

### 38.7 — Draft publication and exact-head CI boundary

depends_on: [38.6]

- Status: `NOT_STARTED`
- Objective:
  - Publish only the validated infrastructure branch as a draft PR against PR #10, link issue #12, and stop after exact-head CI/review inspection.
- Deliverables:
  - Final local exact-head validation and non-force branch push.
  - Draft PR with factual validation/scope/limitations and an issue #12 coordination comment.
  - Exact-head workflow run, review-thread, mergeability, and local/CI parity receipts.
- Acceptance:
  - [ ] Local and remote branch heads equal the final validated commit.
  - [ ] The PR is draft against `refactor/nexus-1.20-test17` and issue #12 remains open with a linking comment.
  - [ ] Exact-head required CI passes or an exact blocking result is recorded without merge.
  - [ ] Root, lag-hotfix, product, runtime, artifact, install, release, and GitHub-setting boundaries remain unchanged.
- Demo commands:
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Full`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Security`
  - `git diff --check origin/refactor/nexus-1.20-test17..HEAD`
- Evidence:
  - Final local summaries, remote ref, draft PR/issue URLs, workflow run IDs/conclusions, review-thread count, and parity result.

## Deferred backlog

- [DEFERRED] Native test.17 follow-up remains owned by the completed product workflow.
- [DEFERRED] Release, installation, live SavedVariables, WoW validation, and artifact publication require separate authorization.
