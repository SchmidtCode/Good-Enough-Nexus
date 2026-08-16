# EVIDENCE

Record concise command/result receipts here. A skipped or unavailable command is not a pass.

## Bootstrap

- Generated project-aware Vibe state with package 0.1.0+codex.20260812081901, state schema 1.0, and prompt catalog 1.1.0.
- Working tree dirty before bootstrap: no.

## 38.1 - Tracked Lua 5.1 validation bootstrap

- Expected red on the exact clean PR #10 base: `node` was unavailable on PATH and tracked `tools/run-lua.js`, `tools/parse-lua51.js`, `package.json`, and `package-lock.json` were absent. This is a missing development-toolchain capability, not a product-test failure.
- The ignored historical runner uses Fengari `0.1.5`, `luaparse` `0.3.1`, a custom `io.open`, and the `unpack`/`math.atan2`/empty-`bit` prelude. The tracked wrappers preserve those semantics while resolving dependencies from the root lockfile.
- `tools/Bootstrap-QualityTools.ps1` completed `npm ci` with Node `v24.19.0`; local npm `11.6.2` was provisioned only under ignored `.tools/npm` because the bundled Node runtime omits npm.
- Focused validation passed: Lua 5.1 parse `272/272`; integration `70/70`; upvalue boundary `60 pass / 61 fail`, 66 TOC files, 2,893 functions, maximum 60 at `ui/Panel.lua:385 EnsureFrame`, `AutomationRuntime.Step=16`; toolchain self-test passed; `git diff --check` passed.
- Formal review PASS at committed `266d51032f806083b40d4167071c47a70685280a`: a separate detached dependency-clean worktree completed the tracked bootstrap, then repeated parse `272/272`, integration `70/70`, upvalue boundary `60/61`, and the toolchain self-test with clean status.
- Adversarial scope proof found no production/test Lua, `Nexus.toc`, build output, ZIP, `.tools`, or dependency cache in the commit. The tracked runner differs from the historical ignored runner only in its usage path; the parser adds deterministic traversal and excludes generated/dependency directories.
- Bounded checkpoint hygiene at unchanged product/tool head found no redundant wrapper, unnecessary compatibility branch, stale marker, or high-ROI simplification. No product/tool byte changed; the committed focused and clean-checkout results remain applicable.

## 38.2 - Deterministic local quality-gate profiles

- Expected red: `tools/Invoke-QualityGate.ps1`, `tools/Get-ChangedTestPlan.ps1`, `tools/Write-ValidationSummary.js`, and `tests/validation-map.json` were absent at clean checkpoint start.
- Fast PASS: 11 checks, zero failures/unavailable/skips; changed-path routing selected tooling/package/integration checks, package metadata and release policy passed, and the compact summary contained no absolute local path or successful log body.
- Package PASS: 8 checks, zero failures/unavailable/skips; logical package has one `Nexus` root, 70 files, 66 Lua files, 5,049,868 bytes, no substitutions, and manifest SHA-256 `e7bda27ac7f638a4603d6068545264830220a91973da980a841440149a02f288`; no ZIP or package tree was retained.
- Security correctly FAILS before checkpoint 38.4: 4 passed and 4 required checks marked `unavailable` (`gitleaks`, `actionlint`, `zizmor`, `psscriptanalyzer`) with reasons. No unavailable check was reported as passed.
- Quality-gate self-tests PASS for modes, changed-path mapping, path portability, deterministic ordering, failure exit status, two-failure retention, unavailable-tool failure, compact summary generation, and successful-log omission.
- Review repair `b71ee3240d52d39aa7a1b9a476cb722cf4116653` permits a clean committed worktree to supply an empty changed-path collection; focused self-tests and Fast passed after the one-line fix.
- Formal Full review PASS at exact clean `b71ee32`: 16 checks passed in 252.596 seconds; complete Lua `202/202`, Lua 5.1 parse `272/272`, integration `70/70`, hostile Sync `4,000/4,000`, and exact upvalue `60 pass / 61 fail` across 66 TOC files / 2,893 functions with maximum 60 at `ui/Panel.lua:385 EnsureFrame` and `AutomationRuntime.Step=16`.
- Full also passed exporter, read-only SavedVariables analyzer, package metadata/source parity, module contracts, privacy, StutterAlert, release policy, and diff checks. Compact summaries contained no absolute user path, raw record data, packets, credentials, or successful log bodies.
## Checkpoint 38.2 hygiene

- Bounded scope: the files delivered by `1b096cb` plus the clean-worktree repair in `b71ee32`.
- Hot spots: none; the profile registry, deterministic writer, path mapper, and package verifier remain intentionally direct and independently testable.
- Quick wins: none; no behavior-preserving simplification had enough value to justify churn after the passing exact-head review.
- Debt items: none; checkpoint 38.4 already owns the explicitly unavailable security tools.
- Validation: status clean, stale/debug marker scan clean except the intentional self-test result line, and `git diff --check` passed. No product or test byte changed, so Full was not repeated.

## Checkpoint 38.3 - VibeRun roles and compact hot context

- Expected red: branch-local `AGENTS.md` had no role-to-profile behavior, `CONTEXT.md` retained unresolved bootstrap placeholders, and hot context totaled 334 lines / 18,653 bytes across `AGENTS.md`, `STATE.md`, `PLAN.md`, and `CONTEXT.md`.
- Dispatcher discrepancy: after 38.2 hygiene, the authoritative pointer selected implementation at 38.3 while the auxiliary ready list named 38.1 because completed headings used an unsupported suffix marker. Headings now use the installed schema's `(DONE) <checkpoint>` form; no flag or pointer was manufactured.
- Implementation: installed VibeRun remains the sole dispatcher; Fast/Full/hygiene/consolidation behavior, bounded evidence/history reads, current invariants, and the supported state chain are documented without local prompts, role metadata, or another namespace.
- Hot-context result: 267 lines / 15,414 bytes, down from 334 lines / 18,653 bytes (20.1% fewer lines and 17.4% fewer bytes) while retaining current stage, base, acceptance, invariants, evidence references, and all four remaining checkpoint boundaries.
- Focused validation: strict Vibe schema/plan validation passed; the dependency DAG reports 38.1/38.2 done, 38.3 ready, and later checkpoints correctly dependency-blocked; Fast passed `6/6`; prohibited namespace scan and `git diff --check` passed.
- Handoff expected red: the dispatcher front end rejected shortened STATE section names that the lower-level strict validator accepted. The repair restores exact supported `Objective (current checkpoint)`, `Deliverables (current checkpoint)`, `Acceptance (current checkpoint)`, and `Evidence` headings without changing role policy or product/tool bytes.
- Formal review PASS at exact `8bab598eb3296b8655bfb897393598d3c8ccf1b5`: Full passed `16/16` in 250.397 seconds with zero failures, skips, or unavailable checks; only the compact summary was inspected because no check was failing or suspicious.
- Adversarial scope review: `0bbd6d4..8bab598` changes only `AGENTS.md`, `README.md`, and four `.vibe` hot/state files; strict Vibe validation and range `git diff --check` passed. No checkpoint-hygiene signal was identified beyond retaining exact required schema headings.
- Final post-advance hot context is 255 lines / 14,231 bytes, down from 334 lines / 18,653 bytes (23.7% fewer lines and bytes). This final supported-schema measurement supersedes the interim implementation count.

## Checkpoint 38.3 hygiene

- Bounded scope: `AGENTS.md`, `README.md`, `STATE.md`, `PLAN.md`, and `CONTEXT.md` delivered by 38.3; no repository-wide or runtime scan was performed.
- Hot spots, quick wins, and debt items: none. The README's operator summary and AGENTS role directives serve different audiences and do not justify another abstraction.
- Validation: stale/bootstrap/debug marker scan and `git diff --check` passed. No product, test, or tool byte changed, so Full was not repeated.

## Checkpoint 38.4 - Staged artifacts, static analysis, and security

- Expected red: Security reported Gitleaks, actionlint, zizmor, and PSScriptAnalyzer as four blocking unavailable checks. The first all-files pre-commit run also exposed three inherited mixed-line-ending files; none was normalized.
- Pinned bootstrap: official Gitleaks `8.30.1`, actionlint `1.7.12`, zizmor `1.29.0`, and PSScriptAnalyzer `1.25.0` Windows/Linux assets are recorded with SHA-256 values and verified before extraction. Pre-commit `4.6.2` and immutable pre-commit-hooks commit `3e8a8703264a2f4a69428a0aa4dcb512790b2c8c` are pinned.
- Artifact/static self-tests PASS: five forbidden paths rejected, two approved paths allowed, all 323 tracked paths clean, Lua 5.1 diagnostics configured, Project Ebonhold global use constrained to five explicit adapter/presentation exception files, and no formatting was performed.
- Security PASS: 10 checks pass, zero fail/skip, with LuaLS, Luacheck, and StyLua explicitly advisory-unavailable. Gitleaks, actionlint, high-severity offline zizmor, release policy, artifact policy, and policy self-tests pass.
- PSScriptAnalyzer baseline: zero blocking findings, six inherited advisory findings across four rules, and zero new advisory rules/counts. The exact baseline makes excess warnings blocking without claiming legacy style passed.
- Pre-commit all-files PASS after adding a narrow three-file mixed-ending baseline; illegal-Windows-name hook reported no applicable files and is not claimed as a pass. No line ending was rewritten.
- Implementation validation: Fast `12/12`, strict Vibe validation, and `git diff --check` passed.
- Formal review PASS at exact `b792c82b75c176151ded62568f82788cb18f654f`: Full passed `16/16` in 248.900 seconds; Security passed 10 checks with the three Lua advisory tools explicitly unavailable; zero failures/skips occurred.
- Adversarial review: quality-gate multiple-failure/unavailable propagation and staged-artifact 5-reject/2-allow probes passed. Exact-head pre-commit passed all applicable hooks with the illegal-Windows-name no-files skip visible. No checkpoint-hygiene signal was identified.

## Checkpoint 38.4 hygiene

- Bounded scope: security bootstrap, local policy wrappers, static/editor configs, pre-commit config, baselines, and their self-tests only.
- Hot spots, quick wins, and debt items: none. Direct per-tool wrappers keep unavailable/blocking/advisory semantics inspectable and do not justify another abstraction.
- Validation: floating-version/unsafe-command/debug marker scan and `git diff --check` passed. No product or test byte changed, so Full was not repeated.

## Checkpoint 38.5 - GitHub Actions quality gate

- Expected red: only `.github/workflows/release-policy.yml` existed; there was no source-quality workflow, in-CI changed-path classifier, or exact-head final quality aggregation.
- Immutable actions: checkout `3d3c42e5aac5ba805825da76410c181273ba90b1`, setup-node `820762786026740c76f36085b0efc47a31fe5020`, and upload-artifact `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` were resolved from official release tags and pinned as complete commits.
- Workflow policy PASS: pull request/main push/dispatch triggers have no path filter; permissions are `contents: read`; four checkouts disable persisted credentials; concurrency cancels superseded workflow/ref runs; all five jobs and final `if: always()` aggregation are present.
- Full selection is computed inside preflight from reviewed paths and forced for main pushes/manual full. Documentation-only Full skips remain visible to the final aggregator; required failures or unexpected skips fail the final job.
- Detailed logs upload only on failure or explicit dispatch, retain five days, and exclude packages, SavedVariables, prompts, transcripts, and credentials by path policy.
- Existing release-policy workflow SHA-256 remains `e625c6232917092f16b9acd421e5641bb3a9527ef5a9402be50bc90e1e203b93`.
- Implementation validation: workflow self-test, actionlint, high-severity offline zizmor, Fast `13/13`, Security 10 pass / 3 advisory-unavailable, pre-commit, and `git diff --check` passed.
- Formal review PASS at exact `7633a4ca967ee37560fa0cda1ee9be6930bfc156`: Full passed `16/16` in 253.631 seconds; workflow policy, actionlint, high-severity offline zizmor, release-policy hash, and `git diff --check` passed.
- Adversarial workflow review confirmed required-Full cannot accept a skipped Full job, documentation-only policy may accept the classifier-proven skip, required Fast/Security/preflight skips fail, and the final job always runs. No checkpoint-hygiene signal was identified.

## Checkpoint 38.5 hygiene

- Bounded scope: `quality-gate.yml` and its workflow policy self-test only.
- Hot spots, quick wins, and debt items: none. The explicit jobs keep selected policy and failure ownership visible without a helper abstraction.
- Validation: floating-action/write-permission/credential/trigger/debug scan and `git diff --check` passed. No product or test byte changed, so Full was not repeated.

## Checkpoint 38.6 - exact-head scope and publication boundary

- Expected red: GitHub branch search found no `infra/viberun-quality-gate` branch, so no draft infrastructure PR or exact-head CI exists before publication.
- Live reconciliation: draft PR #10 remains open and mergeable at exact head `36f187824b8a24f6fb51562e6ec1101c300308ef`; issue #12 remains open with zero comments.
- Base-to-head scope at implementation head `2b412686c62a25114bf56bec53007537105e0c47`: 38 changed paths, all in authorized infrastructure/workflow/tooling/configuration/documentation categories, and zero production Lua, `Nexus.toc`, bundled data, runtime-test Lua, ZIP, or historical artifact paths.
- Immutable identity proof: base and head have identical `Nexus.toc` blob identity and identical tracked Lua tree listings. Public version `1.20.0-beta.1`, protocol 7, `Author: Valentine`, and SavedVariables declarations therefore remain byte-unchanged.
- Ownership reconciliation: repository root remains at `2ec508f00377532bcf2b260eef1e228dff62c467` with its pre-existing workflow changes; `.lag-hotfix-worktree` remains at `97cc6afa5ecc032619623e04ffb5b1662ad556d9` with its pre-existing independently owned changes; product worktree remains clean at `7aee1d9f389954dd31abae94b7eaa9cf216bffc3`.
- Implementation validation: Fast passed `5/5` after exposing the bundled Node runtime; the initial unavailable-Node result was retained as an environment red and was not claimed as pass. `git diff --check` passed.
- Formal local review PASS at exact `34d84facb3f5d9c278510a8f39fbe160b6cd1b68`: Full passed `16/16` in 254.545 seconds; Security passed 10 checks with LuaLS, Luacheck, and StyLua explicitly advisory-unavailable; Package passed `8/8`; release-policy and base-range `git diff --check` passed.
- Pre-commit all-files PASS: all applicable hooks passed and illegal-Windows-name remained an explicit no-files skip. The first sandbox-ownership/cache attempt failed unavailable and was corrected with repository-scoped Git trust plus an ignored local hook cache; no hook was weakened.
- Clean-checkout proof PASS at exact `34d84fa`: tracked bootstrap ran `npm ci`, installed checksum-verified pinned security tools, Lua 5.1 parsed `272/272`, the integration runner passed, and Fast passed `5/5`. The exact disposable worktree and generated dependencies were removed after proof.
- Adversarial review rechecked 38 base-to-head paths, zero forbidden runtime/artifact paths, immutable Lua/TOC identity, compact summaries, no retained package, and unchanged root/lag/product ownership. No checkpoint-hygiene signal was identified.

## Checkpoint 38.6 hygiene

- Bounded scope: the exact-head scope and formal review receipts in `.vibe/STATE.md` and append-only `.vibe/EVIDENCE.md` only.
- Hot spots, quick wins, and debt items: none. The receipts are compact, preserve the external publication boundary, and do not duplicate historical Stage 35-37 detail.
- Validation: stale-marker/temporary-path/debug scan, strict Vibe validation, and base-range `git diff --check` passed. No product or test byte changed, so Full was not repeated.
