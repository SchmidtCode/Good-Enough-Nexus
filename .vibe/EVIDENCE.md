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

## Checkpoint 39.1 - post-publication base reconciliation

- Expected red: `git merge-base --is-ancestor origin/refactor/nexus-1.20-test17 HEAD` exited `1`; the published infrastructure head `91c962e` was behind the current PR #10 head `d0681b6` by nine commits, with merge base `36f1878`.
- Live ownership: PR #10 remained open/draft/mergeable at `d0681b6`; merged PR #11 supplied the nine base commits; PR #13 remained open/draft/mergeable at `91c962e` with zero reviews or threads; issue #12 remained open.
- Normal merge: `5a66cded072f2afff8b1853e7a4c461694d5f3bc` has parents `4f6abfc0fed2b530a354eed1223dc39649efae77` and `d0681b6a885db447c94a75f40df7e81f60b74c55`; no rebase, force-push, or textual conflict occurred.
- Scope proof: the exact current-base-to-merge diff remains the same 38 Stage 38 infrastructure/workflow/tooling/configuration/documentation paths and contains zero production Lua, `Nexus.toc`, bundled data, runtime-test Lua, ZIP, test.17, or other addon-artifact paths.
- Focused validation: the repository-pinned Node `24.13.1` portable runtime was checksum-verified outside the repository; tracked `npm ci` and checksum-verified security bootstrap passed; Fast passed `5/5`. The initial missing-Node result remained a failure and was not represented as a pass.
- Ownership proof: root remains at `2ec508f`, lag-hotfix remains at `97cc6af` with its existing independent status, and the product worktree remains clean at `7aee1d9`; none was modified.
- Review expected red at `791a635`: Full ran 206 discovered Lua programs and failed `205/206`; the only failure was `tests/run_legacy_backup_smoke.lua: SavedVariables path required`. PR #11 labels that program optional/read-only and its release workflow excludes it from the 205-test normal regression. No SavedVariables file was supplied, read, or created.
- Review decision: FAIL pending a narrow infrastructure-only classifier repair that preserves the PR #11 test byte and reports the manual program as skipped with its authorization requirement.
- Focused red-to-green: `.github/**` initially lost its dot, deletion discovery omitted `D`, clean-checkout `git diff --check` ignored committed defects, and doubled-CR fixtures lost bytes. Existing self-test owners now cover hidden/tooling/artifact paths, working/staged/range deletions, invalid/missing bases, committed/staged/working whitespace, and LF/CRLF/mixed/doubled-CR label fixtures.
- Smallest coherent repairs: exact `./` removal preserves hidden dots; `ACMRD` plus `deleted_paths` routes deletions without parsing absent Lua; `Test-GitDiffCheck.ps1` emits separate range/staged/working results; CI passes the full-history preflight base to Fast/Full/Security; label injection replaces only one active `source` token.
- Manual regression policy: the current base contains 206 `run_*.lua` files; 205 automatic programs are run, while `run_legacy_backup_smoke.lua` is explicitly skipped with the reason that it requires a separately authorized SavedVariables backup path. The Lua file was not changed or executed with data.
- Focused validation at `4c3bcd8`: routing/diff, package metadata, workflow policy, security policy, and toolchain self-tests passed; parser `278/278`, integration, PSScriptAnalyzer 0 blocking / 6 inherited advisory / 0 new, Fast `15/15`, strict Vibe validation, and range/staged/working diff checks passed.
- Scope delta: prior PR-only path count 38; current count 40. Added only `tests/run-package-metadata.js` for byte-level fixtures and `tools/Test-GitDiffCheck.ps1` for reusable range checks; removed none. Exact current-base diff contains no `Nexus.toc`, production/runtime Lua, `tests/run_*.lua`, bundled data, ZIP, or test.17 path.
- Current normalized release-policy workflow SHA-256 is `83f44f2d8835bce08fd89f4ab4b04bb93bd4323a8523388cce71713c4e2a42a8`, matching the current PR #10 base byte after PR #11.
- Replacement formal review PASS at exact `9708c5879c46dd6cfb13cbc9457c925192bf6116`: Full passed 18 blocking checks in 260.352 seconds with Lua `205/205`, parser `278/278`, integration `70/70`, and one authorization-dependent legacy-backup smoke program explicitly skipped rather than passed; Package passed `10/10`; Security passed `12/12` with LuaLS, Luacheck, and StyLua honestly unavailable; Fast passed `15/15`.
- Direct release-policy, current-base committed-range/staged/working diff checks, immutable runtime/TOC scope, and all applicable pre-commit hooks passed. The pre-commit mixed-line-ending red in `tests/run-package-metadata.js` was repaired by normalizing the working copy to its existing indexed text, leaving no blob change and no new commit.
- Clean-checkout proof PASS at exact `9708c58`: a detached dependency-clean worktree completed tracked `npm ci`, checksum-verified security bootstrap, and Fast `15/15`; its ignored dependencies, logs, and worktree were removed afterward.
- Review boundary: root stayed at `2ec508f`, lag-hotfix at `97cc6af`, and product at clean `7aee1d9`; no production Lua, `Nexus.toc`, runtime test, bundled data, test.17, package, install, live SavedVariables, WoW, release, merge, force-push, or settings action occurred.
- Checkpoint 39.1 hygiene: the bounded 15-path reconciliation surface was scanned for duplication, unnecessary branches, stale/debug markers, temporary output, and avoidable coupling. No hot spot, quick win, debt item, best-practice gap, or correctness/security issue was identified; current-base `git diff --check` and clean status passed, and Full was not repeated because hygiene changed no product, test, or tooling byte.
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

## Checkpoint 38.7 - draft publication and exact-head CI boundary

- Expected red: live GitHub branch search still finds no `infra/viberun-quality-gate` branch, so the draft PR and exact-head CI are correctly absent before the authorized publication step.
- Live base reconciliation: PR #10 remains open, draft, and mergeable at `36f187824b8a24f6fb51562e6ec1101c300308ef`; no base movement or ownership conflict was detected.
- Implementation validation at `98add8cbfd5ccc31fd3df7a486a3802822c6fd5b`: Fast passed `5/5` and base-range `git diff --check` passed. No remote or product mutation occurred.
- Formal pre-publication review PASS at exact `ddcc6dfa71cd594c486611fe5644614e2cb7171d`: Full passed `16/16` in 250.675 seconds; Security passed 10 checks with three advisory-unavailable checks; release policy, zero-forbidden-path scope, and base-range `git diff --check` passed.
- Adversarial review reconfirmed immutable PR #10 base ownership, no pre-existing remote infrastructure branch, no production/test/artifact path escape, and no checkpoint-hygiene signal. Remote mutation remains deferred until hygiene completes.

## Checkpoint 38.7 hygiene

- Bounded scope: the publication checkpoint plan plus its compact STATE/EVIDENCE receipts only.
- Hot spots, quick wins, and debt items: none. Branch, base, URL, validation, and stop-boundary wording remain explicit without another publication helper or state layer.
- Validation: stale/temporary/debug marker scan, strict Vibe validation, and base-range `git diff --check` passed. No product or test byte changed, so Full was not repeated.

## Checkpoint 38.7 CI portability repair

- Expected red: exact-head Quality gate run `31919314063`, Fast job `95096491463`, failed 12/13 because `run-quality-workflow-policy.js` hashed checkout-specific bytes. Windows CRLF produced `e625c623...`; Ubuntu LF produced `13648de3...`; the underlying release-policy Git blob and workflow behavior were unchanged.
- Isolation: the failing log identified only the release-policy ownership assertion. Preflight and release-policy run `31919314018` passed, and the CI checkout retained read-only permissions plus immutable action pins.
- Smallest coherent repair: normalize CRLF/CR to LF in the workflow-policy self-test before hashing and assert the stable normalized digest. No workflow, release-policy, product, package, or runtime file changed.
- Focused validation PASS: workflow policy self-test and Fast passed `13/13`, including the mapped workflow/security/tooling tests.
- Formal repair review PASS at exact `bf359cc8c917d0f783dd119d5169f4cf3b4ad9e2`: Full passed `16/16` in 263.399 seconds; Security passed 10 blocking checks with three advisory-unavailable checks; release policy, strict Vibe validation, and `git diff --check` passed.
- Repair hygiene: bounded scan of the one self-test found no duplication, stale/debug marker, abstraction debt, or behavior change. The direct CRLF/CR-to-LF normalization and stable digest remain the smallest portable ownership check; Full was not repeated.
- Second expected red: replacement Quality gate run `31919930699`, Security job `95098093181`, passed 9 blocking checks with three honest advisory-unavailable results but failed the staged-artifact scan because Ubuntu PowerShell required `Get-Item -Force` for tracked `.gitattributes`.
- Isolation: the scan's preceding `Test-Path` found the dotfile; the metadata read alone failed. Adding `-Force` preserves content scanning for dotfiles rather than excluding, skipping, or advisory-downgrading them.
- Focused repair validation PASS: all-files artifact policy, Security 10 pass / 3 advisory-unavailable, and Fast `13/13` passed.
- Formal dotfile-repair review PASS at exact `a3a574a6b43288e85eb769393306ab7470d0b6ca`: Full passed `16/16` in 261.112 seconds; Security passed 10 blocking checks with three advisory-unavailable checks; strict Vibe validation and `git diff --check` passed.
- Dotfile-repair hygiene: the single `-Force` flag is the direct cross-platform PowerShell fix, preserves the blocking content scan, and introduces no suppression, helper, stale marker, or debt. Full was not repeated.

## Checkpoint 40.1 - reconciled draft publication boundary

- Expected red: remote `infra/viberun-quality-gate` remains at the previously published `91c962e99e75df430b6eded256f27e5657a74a80`, while the clean local branch reached reviewed Stage 39 plus compact Stage 40 design head `b48b506828294aa9d68f25ccbf000d6e4711679d`.
- Pre-publication validation at `b48b506`: Fast passed `15/15`; current-base `git diff --check` passed; all 40 changed paths remain authorized infrastructure/workflow/tooling/configuration/documentation paths; forbidden production Lua, `Nexus.toc`, runtime-test Lua, bundled-data, test.17, ZIP, build, and dist path count is zero.
- Ownership boundary: root remains at `2ec508f`, lag-hotfix at `97cc6af` with its independently owned status, product remains clean at `7aee1d9`, and the infrastructure worktree alone is being published.
- Dispatcher discrepancy: the authoritative Stage 40.1 STATE pointer and implementation prompt are current, while the auxiliary ready list still names historical 38.7. Per `AGENTS.md`, the returned implementation route is followed without moving the product pointer backward or manufacturing a reset.
- First exact-head CI at `1c6e3c9`: Release policy run `31924278239` passed; Quality gate run `31924278205` failed in preflight job `95109260914` after checkout and tracked bootstrap passed. Ubuntu PowerShell sent an invalid range from `git diff --name-only $base...HEAD`, so dependent jobs were correctly skipped and the aggregate failed.
- Direct repair: the inline range is now `"${base}...HEAD"`, and the workflow-policy self-test requires that delimited form. Focused local proof enumerated 40 paths from the exact current base; workflow policy, Security 12 pass / 3 advisory-unavailable, Fast `15/15`, and `git diff --check` passed.
- Replacement exact-head CI PASS at `21db9ae313c9d708fd541ea5eee4a8b1060ae957`: Quality gate run `31924436571` passed preflight, Fast, Security, Full, and final aggregate; Release policy run `31924436622` passed. Compact CI results match local: Fast 15 pass / 0 unavailable / 0 skipped, Full 18 pass / 1 explicit manual skip, Security 12 pass / 3 advisory-unavailable.
- GitHub state at implementation handoff: local and remote branch heads equal `21db9ae`; PR #13 is open, draft, mergeable, based on `refactor/nexus-1.20-test17` at `d0681b6`, with 40 changed files and zero reviews/threads; issue #12 is open and contains the reconciled draft coordination update.
- Exact implementation-receipt CI PASS at `c4997a75249652b45c53e03cd92652c6a607a4a8`: Quality gate run `31924926793` and Release policy run `31924926788` both passed after normal push. Independent review re-ran Fast `15/15`, verified current-base ancestry, local/remote SHA equality, 40 authorized paths, zero forbidden paths, clean status, and zero reviews/threads. Full was not repeated locally because exact-head CI already ran it once.
- Review verdict: PASS with high-confidence evidence for publication correctness, scope control, compact local/CI parity, state transition, and protected boundaries. No unresolved finding, active issue, or checkpoint-hygiene signal was identified.
- Review-receipt exact-head CI PASS at `db178282e1ac583e63b6315215286078f969cc0d`: Quality gate run `31925298936` and Release policy run `31925298955` succeeded; the aggregate and all required jobs passed.
- Checkpoint 40.1 hygiene: bounded scan of `.github/workflows/quality-gate.yml`, `tests/run-quality-workflow-policy.js`, and the three compact Vibe receipt files found no hot spot, quick win, debt item, best-practice gap, stale/debug marker, or scope defect. Current-base `git diff --check` and clean status passed; Full was not repeated because hygiene changed no product, test, tooling, or workflow byte.

## Checkpoint 41.1 - rename/copy and policy routing

- Expected red at prior head `0793f26`: `node tests/run-quality-gate-self-tests.js` failed because `AGENTS.md` was classified as ordinary documentation (`documentation_only=true`).
- Repair: `tools/GitPathRecords.ps1` reads raw Git stdout, requires NUL-terminated valid UTF-8 tokens, parses `--name-status -z` records, and expands both sides of renames/copies. `Get-ChangedTestPlan.ps1` now shares that model for working, staged, untracked, and BaseRef discovery, while the workflow delegates BaseRef parsing directly to the planner.
- Routing: ordinary documentation is limited to `README.md`, `CHANGELOG.md`, and Markdown under `docs/`; agent, AI, legal, security, release, upstream, contract, and `.vibe/` paths have explicit policy/security/workflow/package ownership and require Full.
- Focused green: workflow policy and quality-gate self-tests passed. Fixtures cover add/modify/delete, runtime/workflow/policy-to-doc renames, ordinary-doc rename, copy, case-only rename, spaces, tabs, and newlines; rename sources are deleted while copy sources are retained.
- Checkpoint-scoped Fast PASS: 14 passed, 0 failed, 0 unavailable, 0 skipped. `git diff --check` passed and the product/runtime-test changed-path list is empty.
- Honest next-boundary evidence: current-base Fast reached 279 passes and failed only `artifact-paths` on the legitimate analyzer paths `tests/run-savedvariables-analyzer.js` and `tools/analyze-savedvariables.js`. That scanner defect remains owned by checkpoint 41.2.
- Formal review PASS at exact `4129105`: workflow-policy and quality-gate self-tests passed; Fast against checkpoint parent `0793f26` passed 14 checks with zero failed/unavailable/skipped; malformed records missing the final NUL or using an unknown status were rejected; `git diff --check` passed; and the checkpoint changed no production or runtime-test path. The seven remaining review findings stay assigned to later checkpoints, and no 41.1 hygiene signal was identified.
- Checkpoint 41.1 hygiene: bounded inspection of the nine delivered files found one shared parser owner, direct route data, compact fixtures, and no duplicate implementation, fragile cleanup branch, best-practice gap, or larger debt attributable to this checkpoint. No code changed, so the already-passing focused and Fast gates were not repeated; strict Vibe validation and receipt diff checks passed.

## Checkpoint 41.2 - staged artifact path safety

- Expected red: the prior line-delimited scanner accepted the Git-quoted path `".codex/context\\n.txt"` with exit 0.
- Repair: staged and all-tracked enumeration now reads raw `-z` output through `GitPathRecords.ps1`; normalization and forbidden/content checks live in one `ArtifactPathPolicy.ps1` owner shared by Fast and `Test-StagedArtifacts.ps1`.
- Hostile matrix PASS: disposable repositories reject `.codex` newline, `.ai` tab, `.chatgpt` space, lowercase/uppercase build ZIPs, backslash variants, and a force-added ignored ZIP while accepting an ordinary source. Windows Git cannot represent tab/newline index names, so those two local cases use exact argv paths plus the 41.1 raw-byte parser fixture; non-Windows runs exercise real index entries. Fixture cleanup completed and no hostile path exists in the real worktree.
- Focused and gate evidence: scanner self-test passed 5 rejected / 4 allowed; all 346 tracked paths passed; security-policy and quality-gate self-tests passed; exact current-base Fast passed 15 checks with zero failed, unavailable, or skipped; `git diff --check` passed.
- Formal review PASS at exact implementation head `f769d52`: the hostile matrix and scanner self-test passed; exact current-base Fast passed 15/15; outside-root `../outside.txt` was rejected; and code review tightened centralized content reads from `SilentlyContinue` to `Stop` so unreadable required content fails closed. Cleanup, worktree scope, and diff checks passed; no 41.2 hygiene signal was identified.
- Checkpoint 41.2 hygiene: bounded inspection of the scanner, shared path policy, Fast integration, and hostile fixtures found no remaining duplicate policy owner, unnecessary branch, cleanup gap, or actionable debt. No code changed after the reviewed fail-closed cleanup, so code gates were not repeated; strict Vibe validation and receipt diff checks passed.

## Checkpoint 41.3 - fail-closed summaries and Package CI

- Expected red: a blocking result of `skipped` normalized to an aggregate PASS. The focused matrix now proves blocking pass succeeds while skipped, unavailable, fail, error, missing, and unknown fail; advisory unavailable remains nonblocking and multiple failures remain sorted and visible.
- Workflow repair: `package-quality` checks out full history with immutable actions, consumes the verified preflight BaseRef, runs the real Package profile, verifies no retained root/archive, writes the compact summary, and uploads only bounded logs on failure. The aggregate requires Package success, so failed or skipped Package fails.
- Focused and gate evidence: summary/quality-gate self-tests and workflow-policy tests passed; exact current-base Package passed 10 checks and Fast passed 15 checks with zero failed/unavailable/skipped. After the run, `build/package-root` was absent, build archives were zero, and temporary `better-nexus-package-*` roots were zero; `git diff --check` passed.
- Formal review PASS at exact implementation head `4364db4`: workflow and summary self-tests passed with added case/whitespace/null coverage; Package passed 10/10; Fast passed 15/15; actionlint passed; package root/archive/temp counts remained zero; and diff checks passed. Aggregate Package non-success uses `-ne 'success'`, so both skipped and failed jobs block. No 41.3 hygiene signal was identified.
- Checkpoint 41.3 hygiene: bounded inspection of summary normalization, Package workflow/aggregate wiring, and their fixtures found no duplicate status model, stale condition, unnecessary abstraction, or actionable debt. Package intentionally follows the existing explicit job shape for auditable conditions; no code changed after review, and strict Vibe validation/diff checks passed.

## Stage 42 maintenance refactor scan

- `[MAJOR]` safety / medium risk / medium effort: extract owner-exact PSScriptAnalyzer comparison into a pure helper during 42.1 so inheritance, disappearance, move, duplicate, and stale-entry fixtures do not need to mock module execution. Equivalence proof: current six reviewed findings remain advisory and new owner/rule/message fingerprints fail.
- `[MODERATE]` safety / medium risk / medium effort: extract archive entry validation and exact executable resolution into non-executing pure helpers during 42.2, while the bootstrap caller retains checksum/download/install ownership. Equivalence proof: valid pinned archives resolve the declared path and hostile layouts fail before extraction/execution.
- Discarded candidate: deduplicating explicit GitHub Actions jobs would broaden scope and reduce condition auditability without helping findings 6–7. No code changed in this scan; the existing 42.1 then 42.2 order is the rollback-safe plan.

## Checkpoint 42.1 - exact PSScriptAnalyzer ownership

- Expected red: the reviewed head had six rule-count allowances. On the Stage 41 candidate, two reviewed findings disappeared while eight new helper findings appeared; count comparison reported only two over-limit rules, proving that owner replacement can be hidden by equal or lower counts.
- Smallest coherent repair: `PSScriptAnalyzerBaseline.ps1` normalizes repository-relative path plus exact rule and whitespace-normalized message SHA-256, uses occurrence indices to preserve identical duplicates, ignores line-only movement, rejects malformed/duplicate baseline records, and reports inherited/new/resolved sets.
- Baseline reconciliation is explicit rather than regenerated: all six findings from reviewed head `0793f26` remain recorded, the four current findings are owned by `tools/Invoke-QualityGate.ps1` and `tools/Test-ReleasePolicy.ps1`, and the two removed `Get-ChangedTestPlan.ps1` findings report as improvements. Eight Stage 41 helper findings were fixed with precise output types and singular function names instead of being accepted.
- Synthetic fixtures PASS for exact inheritance, line movement, disappearance/improvement, owner move, same-rule message replacement, identical duplicates, and stale entries. Current PSScriptAnalyzer PASS: 0 blocking, 4 advisory, 4 inherited, 0 new, 2 improvements.
- Focused security-policy self-tests PASS, including exact schema/fingerprint validation and hostile staged-artifact fixtures. Exact-base Fast PASS: 15 passed, 0 failed, 0 unavailable, 0 skipped. The first Fast attempt honestly failed unavailable because Node was not on this shell PATH; exposing the bundled Node runtime produced the reported pass without changing repository policy.
- Formal review PASS at exact implementation head `5601c61`: the full six-finding reviewed baseline reports 4 inherited / 0 new / 2 improvements; focused baseline and security-policy suites pass; outside-repository owners and duplicate baseline fingerprints fail closed; exact-base Fast passes `15/15`; strict Vibe validation and diff checks pass. No unresolved review finding remains.
- Checkpoint 42.1 hygiene: bounded inspection of the exact comparison helper, explicit baseline data, caller, and fixtures found one owner for identity/comparison, no unnecessary branch or coupling, and no actionable debt. Review already applied the only clear quick wins; no code changed, so focused gates were not repeated and strict Vibe validation remained the hygiene gate.
- Dispatcher discrepancy before 42.2: the current pointer and returned role were correctly 42.2 implementation, but the auxiliary ready list still named 42.1 because its `(DONE)` marker followed the title rather than preceding the checkpoint ID as the installed parser requires. The repository-owned PLAN marker was corrected; the 42.2 route was followed without moving the pointer backward.

## Checkpoint 42.2 - security bootstrap integrity

- Expected red: the prior bootstrap extracted checksum-valid archives without inspecting entries, recursively selected the first matching executable, removed extraction roots only on success, and invoked pip with exact versions but no distribution hashes. The focused fixture initially failed because the policy helper did not exist.
- Archive repair: one pure helper reads ZIP and gzip-tar records without line splitting, rejects control/absolute/drive/traversal/alternate-separator/unexpected-root/case-conflict/link layouts, requires exactly one manifest-declared executable path, and wraps bounded temporary directories in `finally`. ZIP and tar valid fixtures pass; eight hostile layouts fail without executing fixture contents.
- Python repair: all ten expected pre-commit distributions have explicit reviewed wheel SHA-256 values in `tools/pre-commit-requirements.txt`; bootstrap validates the lock then uses pip `--require-hashes --only-binary=:all: --no-deps`. Missing and incorrect hash fixtures fail closed, and `pip check` plus pre-commit `4.6.2` pass.
- Real bootstrap: the first run failed honestly on a signed ZIP external-attribute conversion; the parser was corrected without suppression. The replacement run verified all pinned Windows archives/layouts and Python distributions, installed the exact executables, and left 0 bootstrap roots, 0 extraction roots, and no download directory. Legacy cached downloads were removed by the same bounded cleanup owner.
- Focused security-policy and exact-baseline suites pass. Direct Gitleaks reports no leaks, actionlint passes, and offline high-severity zizmor reports no findings with one default suppression. Exact-base Security passes 12 blocking checks with LuaLS/Luacheck/StyLua explicitly advisory-unavailable; Fast passes `15/15`.
- Formal review PASS at exact implementation head `905cb00`: all three pinned Linux tarballs independently pass checksum, entry, root, and exact-executable validation (3/11/1 entries); cleanup removes the review downloads; executable links are rejected; security-policy self-tests, Security 12 pass / 3 advisory-unavailable, and exact-base Fast `15/15` pass. No checkpoint-hygiene signal or unresolved finding was identified.
- Checkpoint 42.2 hygiene: bounded inspection found entry parsing, layout resolution, file/lock hash enforcement, and temporary-directory cleanup separated at useful audit boundaries, with no recursive fallback or parallel policy owner. No clear quick win, larger debt, or best-practice gap remained; no code changed and strict Vibe validation remained the hygiene gate.

## Stage 43 maintenance test-gap scan

- `[MAJOR]` Fresh-checkout Linux bootstrap/Fast is the remaining integration-risk probe that proves tar layout validation and hash-locked pip work without ignored dependencies; checkpoint 43.1 already owns it.
- `[MAJOR]` Fresh-checkout Vibe status/dispatcher without `.vibe/LOOP_RESULT.json` is the remaining regression probe for finding 8; 43.1 establishes the candidate truth and 43.2 owns the terminal stop receipt.
- Discarded candidates: duplicating the focused rename, artifact, aggregate, exact-baseline, and hostile-archive matrices would add a second inspection surface without reducing a distinct regression risk. No code or PLAN item changed, and the 43.1 pointer remains `NOT_STARTED`.

## Checkpoint 43.1 - formal candidate preflight

- Clean-bootstrap expected red: after removing ignored `node_modules` and `.tools`, tracked `npm ci` passed but bootstrap rejected the pinned PSScriptAnalyzer archive because its exact `Microsoft.Windows.PowerShell.ScriptAnalyzer.*` roots were absent from the manifest allowlist. The outer temporary bootstrap root was removed, and Full did not run.
- Direct reconciliation downloaded the same checksum-pinned nupkg (`14e634c...`) into a bounded review root, enumerated all 21 unique top-level entries, corrected only the two assembly names, added an exact allowlist fixture, and removed the review root.
- Replacement clean tracked bootstrap PASS: npm added 5 packages; Windows ZIP layouts, the PSScriptAnalyzer nupkg, and all ten hash-locked Python distributions verified; Node `v24.19.0` and pre-commit `4.6.2` installed with no retained bootstrap/download/extraction roots. This replacement head supersedes the first frozen candidate before the single local Full.
- Formal candidate `4c1002e` Full PASS exactly once: 18 blocking checks passed in 267.420 seconds with 0 failed/unavailable, plus one explicit nonblocking manual legacy-backup smoke skip requiring separately authorized SavedVariables. Lua suite passed `205/205`, Lua 5.1 parse `278/278`, integration `70/70`, hostile Sync `4,000/4,000`, and the upvalue/TOC audit passed the 60/61 boundary across 68 TOC files / 3,030 functions (maximum 60 at `ui/Panel.lua:385 EnsureFrame`; `AutomationRuntime.Step=16`).
- The same unchanged candidate passed Package `10/10` and Security 12 blocking checks with LuaLS/Luacheck/StyLua honestly advisory-unavailable. Package/source parity produced one `Nexus` root with 72 files / 68 Lua / 5,150,732 bytes, no substitutions, manifest SHA-256 `0a289e77...`, and no retained package root/archive.
- Focused proof PASS: tracked dependency/toolchain, changed-path/quality-gate/workflow/security policy, runtime-label byte parity/package metadata, release policy, all-files staged-artifact scan (352 paths), and all applicable pre-commit hooks. Gitleaks found no leaks; actionlint passed; offline high-severity zizmor had no findings with one default suppression; PSScriptAnalyzer reported 0 blocking / 4 inherited advisory / 0 new / 2 improvements.
- Exact-base scope PASS: 47 PR paths, consisting of the reviewed 40 plus seven new infrastructure helpers/fixtures/lock files and zero removed paths. Protected production Lua, runtime-test Lua, `Nexus.toc`, bundled data, test.17, package/archive/install, and build/dist path count is zero; range/staged/working diff checks pass.
- Disposable detached checkout PASS at exact `4c1002e`: it began without `node_modules`, `.tools`, or LOOP_RESULT; tracked npm/security bootstrap and Fast `15/15` passed. Vibe dry-run bootstrap preserved all committed state, strict validation reported Stage 43.1 `IN_PROGRESS`, and read-only dispatcher preview selected `implement` without creating an ignored receipt. The checkout, validation logs, hook cache, temporary runtime wrapper, bootstrap roots, downloads, extraction roots, and package output were removed.
- Formal 43.1 review PASS at receipt head `49801d5`: exact delta from formal code/tool candidate `4c1002e` contains only `.vibe/EVIDENCE.md`, `.vibe/PLAN.md`, and `.vibe/STATE.md`; no code/tooling byte changed after Full. Exact-base Fast passes `15/15`, PR-only scope remains 47 infrastructure paths with zero protected paths, range diff checks pass, and generated Fast logs were removed. Full was intentionally not repeated.
- Checkpoint 43.1 hygiene: bounded inspection of the receipt-only delta found one compact evidence owner, no stale/debug marker, duplicate proof path, unnecessary abstraction, best-practice gap, or actionable debt. No code, tooling, workflow, or test byte changed, so Full and focused gates were not repeated; strict Vibe validation and clean receipt-diff checks remain the hygiene gates.
- Checkpoint 43.2 first publication at `8c4d977`: normal non-force push advanced remote `infra/viberun-quality-gate` from reviewed `0793f26`. Quality Gate run `31957168510` passed preflight, Package, Fast, Security, Full, and aggregate; Package verified no retained output, all four success-only failure-log uploads skipped, and the run produced zero artifacts. Release Policy run `31957168563` passed its `release-policy` job but failed `lua-regression` at `tests/run_startup_catalog_cost.lua:103` (`Community projection materialized full bundled Echo arrays`). The reviewed 40-path head and current 47-path repair head have identical product/runtime-test Lua bytes; earlier run `31925777820` passed the same LuaJIT test, so the failure is recorded as an unresolved nondeterministic runtime-test boundary rather than repaired outside authorization.
- Checkpoint 43.2 replacement exact-head PASS at `bc0b61a`: Quality Gate `31957769884` passed preflight, Fast, Full, Package, Security, and aggregate; Package asserted no retained output, success-only failure-log uploads were skipped, and artifact count is zero. Release Policy `31957769870` passed both release-policy and all 205 LuaJIT regression programs with zero artifacts and no product/runtime-test byte change after the prior failure. PR #13 remains open/draft/mergeable/unmerged with 47 changed infrastructure paths, zero reviews, and zero threads; issue #12 remains open and received comment `5308409291`. PR body and issue disclose the first-run flake, exact runs, eight repairs, seven added/zero removed paths, and zero protected runtime paths; no additional Codex review request was made.
