# PLAN

## Stage 42 — Exact security ownership and deterministic bootstrap

- Goal: make advisory baselines owner-exact and make every downloaded security dependency and extracted executable deterministic.
- Decision: fingerprint reviewed findings by owner/rule/message and validate archive layout before extraction; no count-only or recursive-first-match fallback remains.

### 42.1 — Replace count-only static-analysis baseline (DONE)

- Status: `DONE`
- Objective:
  - Preserve only exact inherited PSScriptAnalyzer findings while detecting ownership drift and same-rule replacements.
- Deliverables:
  - Stable repository-relative path/rule/message fingerprints.
  - Explicit reviewed baseline entries and improvement reporting.
  - Synthetic inheritance, disappearance, move, duplicate, and stale-entry fixtures.
- Acceptance:
  - [x] Exact inherited findings remain advisory and removed findings report improvement.
  - [x] Same-rule findings in a new file or owner fail as new.
  - [x] Duplicate same-rule findings remain distinct.
  - [x] Stale baseline entries cannot hide real findings.
  - [x] Focused security policy, PSScriptAnalyzer, and Fast pass.
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
