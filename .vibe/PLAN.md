# PLAN

## Stage 43 — Exact-head terminal reconciliation and publication

- Goal: prove all eight repairs together, reconcile committed Vibe truth without ignored receipts, refresh PR #13, and stop for independent merge review.
- Decision: represent the candidate as branch `HEAD` plus an exact resolved receipt to avoid an impossible self-referential commit SHA; set the terminal stop only after formal review/hygiene is complete.

### (DONE) 43.1 — Formal cross-finding review and fresh-checkout proof

- Status: `DONE`
- Objective:
  - Validate the unchanged committed repair candidate end-to-end and prove fresh-checkout Vibe and quality behavior before publication.
- Deliverables:
  - Full exactly once plus Package, Security, policy, pre-commit, and scope receipts.
  - Cross-finding adversarial review and directly related repairs only.
  - Disposable clean bootstrap/Fast and Vibe status/dispatcher proof.
  - Exact current-base PR-only path and protected-runtime blob proof.
- Acceptance:
  - [x] Full, Package, Security, release policy, applicable hooks, and all required tools pass; advisory tools remain honestly unavailable when absent.
  - [x] Fresh checkout bootstraps and passes Fast with no ignored dependency assumption.
  - [x] Fresh checkout Vibe validates the committed checkpoint/head/base without ignored LOOP_RESULT state.
  - [x] PR-only range remains infrastructure-only with zero protected runtime/TOC/runtime-test/artifact paths.
  - [x] All temporary package, archive, log, and checkout output is removed.
- Demo commands:
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Full -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Package -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Security -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `git diff --check d0681b6a885db447c94a75f40df7e81f60b74c55...HEAD`
- Evidence:
  - Compact exact-head summaries, fresh-checkout receipts, and protected-scope proof.

### 43.2 — Refresh PR #13 and stop at independent review

depends_on: [43.1]

- Status: `IN_REVIEW`
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
