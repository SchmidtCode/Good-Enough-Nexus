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

- Status: `DONE`
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

## Stage 39 — Post-publication PR #10 base reconciliation

- Goal: refresh draft PR #13 onto the exact current PR #10 branch head without rewriting history, changing PR #11 product bytes, or reopening Stage 38 implementation.
- Base transition: `36f187824b8a24f6fb51562e6ec1101c300308ef` -> `d0681b6a885db447c94a75f40df7e81f60b74c55`.
- Decision: use one normal merge commit because PR #13 is already published; rebase and force-push remain prohibited.

### (DONE) 39.1 — Merge current base and refresh exact-head review

- Status: `DONE`
- Objective:
  - Merge the current remote PR #10 base into the infrastructure branch while preserving PR #11 exactly and retaining the 38-path infrastructure-only PR surface.
- Deliverables:
  - Normal base-reconciliation merge with conservative conflict handling.
  - Leading-dot and deleted-path routing with deterministic focused regression coverage.
  - Base-range/staged/working diff checks plus byte-exact runtime-label injection.
  - Honest manual-smoke classification, current-base scope proof, and exact-head validation receipts.
  - Updated draft PR #13, issue #12, CI, review-thread, and parity evidence.
- Acceptance:
  - [ ] Merge ancestry includes both `91c962e` and `d0681b6` without rebase or force-push.
  - [ ] Hidden/deleted paths retain correct routing and committed/staged/working whitespace defects fail truthfully.
  - [ ] Runtime-label substitution preserves every byte except the single authorized label value.
  - [ ] PR #11 production, TOC, bundled-data, runtime-test, version, protocol, author, SavedVariables, and artifact bytes match the current base.
  - [ ] Local clean bootstrap and required quality/security/policy gates pass or report advisory tools unavailable honestly.
  - [ ] Exact-head CI matches local compact summaries; PR #13 remains draft and unmerged.
- Demo commands:
  - `pwsh -NoProfile -File tools/Bootstrap-QualityTools.ps1`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Full`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Package; pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Security`
  - `pre-commit run --all-files`
- Evidence:
  - Merge parents and current-base changed-path list.
  - Compact local summaries and immutable-runtime blob comparison.
  - Remote head, exact-head workflow run IDs, draft/review state, and issue comment URL.

## Stage 40 — Reconciled draft publication boundary

- Goal: publish only the reviewed Stage 39 reconciliation, refresh draft coordination, and stop after exact-head CI/review inspection.
- Base: `origin/refactor/nexus-1.20-test17` at `d0681b6a885db447c94a75f40df7e81f60b74c55`.
- Decision: update the existing draft PR #13 with a normal non-force push; do not create a replacement PR or merge either PR.

### (DONE) 40.1 — Refresh draft PR and inspect exact-head CI

- Status: `DONE`
- Objective:
  - Publish the exact reviewed infrastructure head and leave PR #13 as an accurate draft against the current PR #10 branch.
- Deliverables:
  - Final exact-head Fast and committed-range scope receipts.
  - Normal branch push with local/remote head equality.
  - Factual PR #13 body and issue #12 coordination update.
  - Exact-head Quality gate, release-policy, mergeability, and review-thread inspection.
- Acceptance:
  - [x] Final local head contains only the reviewed infrastructure range plus compact Vibe receipts and passes Fast/diff validation.
  - [x] Remote infrastructure branch equals the validated local head after a non-force push.
  - [x] PR #13 remains open and draft against `refactor/nexus-1.20-test17`; issue #12 remains open with current status.
  - [x] Exact-head Quality gate and release-policy CI pass with local/CI summary parity, or an exact blocking result is recorded.
  - [x] Review/thread count and mergeability are inspected without merge.
  - [x] Root, lag-hotfix, product, runtime, artifact, install, live, release, tag, and settings boundaries remain unchanged.
- Demo commands:
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `git diff --check d0681b6a885db447c94a75f40df7e81f60b74c55...HEAD`
  - `git push origin infra/viberun-quality-gate`
- Evidence:
  - Final local/remote SHA, compact local summary, PR/issue URLs, exact-head workflow run IDs/conclusions, and review/thread state.

## Stage 41 — Git-path-safe and fail-closed validation routing

- Goal: close the independent review's path-classification, artifact, summary, and Package-CI gaps without changing addon runtime bytes.
- Base: `origin/refactor/nexus-1.20-test17` at `d0681b6a885db447c94a75f40df7e81f60b74c55`.
- Decision: use one normalized Git record model for local, staged, and committed discovery; retain narrow policy ownership instead of broad Markdown assumptions.

### 41.1 — Preserve rename/copy ownership and policy routing

- Status: `IN_REVIEW`
- Objective:
  - Classify both sides of every Git record so a rename or copy cannot weaken required validation.
- Deliverables:
  - Shared NUL-delimited `--name-status --find-renames` record parser.
  - Local, staged, BaseRef, and explicit-fixture discovery through one record model.
  - Narrow ordinary-documentation allowlist with explicit policy/legal/security ownership.
  - Hostile rename/copy/case/space/tab/newline regression fixtures.
- Acceptance:
  - [x] Runtime, workflow, and policy sources renamed into docs retain their original required groups and Full requirement.
  - [x] Ordinary-doc-to-ordinary-doc rename remains documentation-only.
  - [x] Added, modified, deleted, renamed, copied, case-only, space, tab, and newline records round-trip without line splitting.
  - [x] `AGENTS.md`, `AI_POLICY.md`, legal/security/release docs, and `tests/validation-map.json` route to their owners.
  - [x] Focused routing tests and checkpoint-scoped Fast pass with zero production/runtime-test changes; the current-base Fast scan separately exposes the already planned 41.2 artifact-policy defect.
- Demo commands:
  - `node tests/run-quality-gate-self-tests.js`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `git diff --check`
- Evidence:
  - Expected-red/green hostile record matrix and compact Fast summary.

### 41.2 — Make staged-artifact enumeration Git-path safe

depends_on: [41.1]

- Status: `IN_REVIEW`
- Objective:
  - Reject forbidden staged paths from exact NUL-delimited Git records, including force-added and quoted hostile names.
- Deliverables:
  - NUL-safe staged/all tracked-path enumeration.
  - Exact repository-relative normalization after record extraction.
  - Disposable hostile filename and `git add -f` fixtures.
- Acceptance:
  - [x] `.codex` newline, `.ai` tab, `.chatgpt` space, build ZIP, case variant, and separator-hostile paths fail.
  - [x] Force-added ignored artifacts fail while an ordinary safe source passes.
  - [x] No hostile filename is created in the real worktree.
  - [x] Security-policy focused tests and Fast pass.
- Demo commands:
  - `node tests/run-security-policy.js`
  - `pwsh -NoProfile -File tools/Test-StagedArtifacts.ps1 -SelfTest`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
- Evidence:
  - Hostile-path expected-red/green matrix and unchanged worktree status.

### 41.3 — Fail closed and require Package in exact-head CI

depends_on: [41.2]

- Status: `NOT_STARTED`
- Objective:
  - Make every blocking non-pass fail and make Package a required exact-base CI job.
- Deliverables:
  - Fail-closed summary normalization for missing, malformed, unknown, skipped, unavailable, and failed blocking results.
  - Exact-base Package workflow job with compact summary and failure-only logs.
  - Aggregate dependency and condition coverage for required Package.
  - Package cleanup/no-publication regression coverage.
- Acceptance:
  - [ ] Only blocking `pass` can produce blocking success; advisory unavailable remains advisory.
  - [ ] Multiple failures remain visible in deterministic compact output.
  - [ ] Package receives BaseRef, full history, and the real Package profile.
  - [ ] Failed or skipped Package fails aggregate; successful Package uploads and retains no package.
  - [ ] Summary, workflow-policy, Package, and Fast checks pass.
- Demo commands:
  - `node tests/run-quality-gate-self-tests.js`
  - `node tests/run-quality-workflow-policy.js`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Package -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
- Evidence:
  - Blocking-status matrix, workflow job/aggregate proof, and compact Package/Fast summaries.

## Stage 42 — Exact security ownership and deterministic bootstrap

- Goal: make advisory baselines owner-exact and make every downloaded security dependency and extracted executable deterministic.
- Decision: fingerprint reviewed findings by owner/rule/message and validate archive layout before extraction; no count-only or recursive-first-match fallback remains.

### 42.1 — Replace count-only static-analysis baseline

- Status: `NOT_STARTED`
- Objective:
  - Preserve only exact inherited PSScriptAnalyzer findings while detecting ownership drift and same-rule replacements.
- Deliverables:
  - Stable repository-relative path/rule/message fingerprints.
  - Explicit reviewed baseline entries and improvement reporting.
  - Synthetic inheritance, disappearance, move, duplicate, and stale-entry fixtures.
- Acceptance:
  - [ ] Exact inherited findings remain advisory and removed findings report improvement.
  - [ ] Same-rule findings in a new file or owner fail as new.
  - [ ] Duplicate same-rule findings remain distinct.
  - [ ] Stale baseline entries cannot hide real findings.
  - [ ] Focused security policy, PSScriptAnalyzer, and Fast pass.
- Demo commands:
  - `node tests/run-security-policy.js`
  - `pwsh -NoProfile -File tools/Test-SecurityPolicy.ps1 -Check PSScriptAnalyzer`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
- Evidence:
  - Fingerprint fixture matrix and current exact baseline reconciliation.

### 42.2 — Harden archive and Python bootstrap integrity

depends_on: [42.1]

- Status: `NOT_STARTED`
- Objective:
  - Reject unsafe archive layouts and require exact distribution hashes before installing bootstrap dependencies.
- Deliverables:
  - Archive entry/root/traversal/case-conflict validation before extraction.
  - Exact executable paths from verified metadata with failure-safe cleanup.
  - Hash-pinned Python distribution lock and enforced hash installation.
  - Non-executing hostile archive/hash fixture suite.
- Acceptance:
  - [ ] Traversal, absolute, drive-qualified, alternate-separator, wrong-root, duplicate, decoy, and missing-executable archives fail closed.
  - [ ] Bad archive checksum and missing/incorrect Python hashes fail closed.
  - [ ] Valid archives resolve only the declared executable path.
  - [ ] Success and failure remove temporary extraction/probe output.
  - [ ] Bootstrap, security-policy, Security, and Fast pass with required tools available.
- Demo commands:
  - `node tests/run-security-policy.js`
  - `pwsh -NoProfile -File tools/Bootstrap-QualityTools.ps1`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Security -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
- Evidence:
  - Hostile archive/hash matrix, verified tool paths, cleanup proof, and compact Security/Fast summaries.

## Stage 43 — Exact-head terminal reconciliation and publication

- Goal: prove all eight repairs together, reconcile committed Vibe truth without ignored receipts, refresh PR #13, and stop for independent merge review.
- Decision: represent the candidate as branch `HEAD` plus an exact resolved receipt to avoid an impossible self-referential commit SHA; set the terminal stop only after formal review/hygiene is complete.

### 43.1 — Formal cross-finding review and fresh-checkout proof

- Status: `NOT_STARTED`
- Objective:
  - Validate the unchanged committed repair candidate end-to-end and prove fresh-checkout Vibe and quality behavior before publication.
- Deliverables:
  - Full exactly once plus Package, Security, policy, pre-commit, and scope receipts.
  - Cross-finding adversarial review and directly related repairs only.
  - Disposable clean bootstrap/Fast and Vibe status/dispatcher proof.
  - Exact current-base PR-only path and protected-runtime blob proof.
- Acceptance:
  - [ ] Full, Package, Security, release policy, applicable hooks, and all required tools pass; advisory tools remain honestly unavailable when absent.
  - [ ] Fresh checkout bootstraps and passes Fast with no ignored dependency assumption.
  - [ ] Fresh checkout Vibe validates the committed checkpoint/head/base without ignored LOOP_RESULT state.
  - [ ] PR-only range remains infrastructure-only with zero protected runtime/TOC/runtime-test/artifact paths.
  - [ ] All temporary package, archive, log, and checkout output is removed.
- Demo commands:
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Full -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Package -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Security -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `git diff --check d0681b6a885db447c94a75f40df7e81f60b74c55...HEAD`
- Evidence:
  - Compact exact-head summaries, fresh-checkout receipts, and protected-scope proof.

### 43.2 — Refresh PR #13 and stop at independent review

depends_on: [43.1]

- Status: `NOT_STARTED`
- Objective:
  - Publish the reviewed repair head normally, record exact CI/review truth, and leave Vibe at a clean terminal external-review boundary.
- Deliverables:
  - Truthful committed terminal STATE/PLAN/CONTEXT/EVIDENCE without ignored receipt dependency.
  - Normal non-force push and exact local/remote head equality.
  - PR #13 body and issue #12 repair/validation updates.
  - Replacement Quality Gate, Release Policy, artifact, mergeability, review, and thread inspection.
- Acceptance:
  - [ ] Committed STATE identifies branch `HEAD`, exact base, checkpoint DONE, completed acceptance, and next role stop.
  - [ ] Fresh checkout dispatcher preview agrees with committed terminal state.
  - [ ] PR #13 remains open/draft/unmerged and exact-head required workflows pass with local/CI parity.
  - [ ] Issue #12 remains open with the exact final repair/CI status.
  - [ ] Review/thread counts and all independently owned worktree statuses are unchanged except authorized PR/issue updates.
  - [ ] No additional Codex review request, merge, release, install, live, or settings action occurs.
- Demo commands:
  - `git push origin infra/viberun-quality-gate`
  - `python <installed-vibe>/scripts/vibe.py --repo-root . status`
  - `git diff --check d0681b6a885db447c94a75f40df7e81f60b74c55...HEAD`
- Evidence:
  - Final SHA, workflow run IDs/conclusions, PR/issue URLs, review/thread state, terminal Vibe status, and boundary recheck.
