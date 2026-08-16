"use strict";

const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const workflow = fs.readFileSync(path.join(root, ".github/workflows/quality-gate.yml"), "utf8");
const release = fs.readFileSync(path.join(root, ".github/workflows/release-policy.yml"), "utf8")
    .replace(/\r\n?/g, "\n");

assert.match(workflow, /\non:\s*\n\s+pull_request:\s*\n\s+push:[\s\S]*branches:[\s\S]*- main[\s\S]*workflow_dispatch:/);
assert(!workflow.includes("pull_request_target"));
assert.match(workflow, /permissions:\s*\n\s+contents: read/);
assert.match(workflow, /group: better-nexus-quality-\$\{\{ github\.workflow \}\}-\$\{\{ github\.ref \}\}/);
assert.match(workflow, /cancel-in-progress: true/);
for (const job of ["preflight", "fast-quality", "security-quality", "full-quality",
    "package-quality", "quality-gate"]) {
    assert.match(workflow, new RegExp(`^  ${job}:`, "m"), `missing job: ${job}`);
}
const uses = [...workflow.matchAll(/^\s+uses:\s+([^\s]+)$/gm)].map((match) => match[1]);
assert(uses.length > 0);
for (const use of uses) assert.match(use, /^[^@]+@[0-9a-f]{40}$/, `non-immutable action: ${use}`);
assert.strictEqual((workflow.match(/persist-credentials: false/g) || []).length, 5);
assert.strictEqual((workflow.match(/fetch-depth: 0/g) || []).length, 5);
for (const mode of ["Fast", "Full", "Security", "Package"]) {
    assert.match(workflow, new RegExp(`Invoke-QualityGate\\.ps1 -Mode ${mode} -BaseRef \\$env:BASE_REF`),
        `${mode} does not inspect the committed base range`);
}
assert.match(workflow, /Get-ChangedTestPlan\.ps1 -BaseRef \$base/,
    "workflow must delegate base-range parsing to the shared path classifier");
assert(!workflow.includes("git diff --name-only"),
    "workflow bypasses the shared binary-safe path classifier");
assert.match(workflow, /full-quality:[\s\S]*if: needs\.preflight\.outputs\.full_required == 'true'/);
assert.match(workflow, /quality-gate:[\s\S]*if: always\(\)/);
assert.match(workflow, /quality-gate:[\s\S]*needs: \[preflight, fast-quality, security-quality, full-quality, package-quality\]/);
assert.match(workflow, /PACKAGE_RESULT: \$\{\{ needs\.package-quality\.result \}\}/);
assert.match(workflow, /\$env:PACKAGE_RESULT -ne 'success'/,
    "failed or skipped Package must fail aggregation");
const packageJob = workflow.match(/^  package-quality:[\s\S]*?(?=^  quality-gate:)/m)?.[0] || "";
assert.match(packageJob, /if: failure\(\)[\s\S]*name: package-quality-logs[\s\S]*path: build\/verify\/logs/);
assert(!/inputs\.upload_logs/.test(packageJob),
    "successful Package workflow dispatch can upload evidence");
assert(!/path: .*\.(?:zip|7z|rar)/i.test(packageJob), "Package job uploads a package archive");
assert.match(packageJob, /Verify no package output was retained[\s\S]*Test-Path build\/package-root[\s\S]*-Filter \*\.zip/);
assert.match(workflow, /failure\(\) \|\| \(github\.event_name == 'workflow_dispatch' && inputs\.upload_logs\)/);
assert.strictEqual((workflow.match(/retention-days: 5/g) || []).length, 4);
assert(!/^\s+paths(?:-ignore)?:/m.test(workflow));
assert.strictEqual(crypto.createHash("sha256").update(release, "utf8").digest("hex"), "83f44f2d8835bce08fd89f4ab4b04bb93bd4323a8523388cce71713c4e2a42a8");

console.log("quality workflow policy: triggers, permissions, pins, concurrency, jobs, skips, artifacts, release ownership -- OK");
