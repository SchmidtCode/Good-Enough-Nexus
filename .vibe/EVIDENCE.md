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
