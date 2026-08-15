"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { normalizeSourcePath } = require("../tools/Test-PackageSource.js");

const root = path.resolve(__dirname, "..");
const pwsh = process.platform === "win32" ? "pwsh.exe" : "pwsh";

function runPowerShell(script, args = []) {
    return spawnSync(pwsh, ["-NoProfile", "-File", path.join(root, script), ...args], {
        cwd: root,
        encoding: "utf8",
    });
}

function changedPlan(paths) {
    const result = runPowerShell("tools/Get-ChangedTestPlan.ps1", ["-Paths", ...paths]);
    assert.strictEqual(result.status, 0, `${result.stdout}\n${result.stderr}`);
    return JSON.parse(result.stdout);
}

const syncPlan = changedPlan(["core\\Sync.lua"]);
assert.deepStrictEqual(syncPlan.paths, ["core/Sync.lua"]);
assert(syncPlan.groups.includes("sync"));
assert(syncPlan.tests.includes("tests/run_sync_hostile_fuzz.lua"));
assert.strictEqual(syncPlan.full_required, true);

const docsPlan = changedPlan(["README.md", "docs/QUALITY.md"]);
assert.strictEqual(docsPlan.documentation_only, true);
assert.strictEqual(docsPlan.full_required, false);
assert.deepStrictEqual(docsPlan.tests, []);

const toolingPlan = changedPlan(["tools/Invoke-QualityGate.ps1", "package-lock.json"]);
assert(toolingPlan.groups.includes("tooling"));
assert(toolingPlan.tests.includes("tests/run-quality-gate-self-tests.js"));
assert.strictEqual(toolingPlan.full_required, true);

for (const unsafe of ["../Nexus.lua", "/root/Nexus.lua", "C:/Nexus.lua", "a//b.lua"]) {
    assert.throws(() => normalizeSourcePath(unsafe), /unsafe package source path/);
}
assert.strictEqual(normalizeSourcePath("core\\Main.lua"), "core/Main.lua");

const scratch = path.join(root, "build", "quality-gate-self-test");
fs.rmSync(scratch, { recursive: true, force: true });
fs.mkdirSync(path.join(scratch, "logs"), { recursive: true });
fs.writeFileSync(path.join(scratch, "logs", "a.log"), "SUCCESS-DETAIL-MUST-NOT-LEAK\n");
fs.writeFileSync(path.join(scratch, "logs", "z.log"), "failure detail\n");
const payload = {
    schema: 1,
    mode: "Full",
    head: "abcdef0123456789",
    duration_seconds: 1.25,
    checks: [
        { id: "z-fail", result: "fail", count: "0/1", duration_seconds: 1,
            log: "logs/z.log", command: "node C:\\Users\\Private\\fail.js", blocking: true,
            reason: "command exited 9" },
        { id: "a-pass", result: "pass", count: "1/1", duration_seconds: 0.25,
            log: "logs/a.log", command: "node pass.js", blocking: true },
    ],
};
const payloadPath = path.join(scratch, "payload.json");
fs.writeFileSync(payloadPath, JSON.stringify(payload));
const summaryResult = spawnSync(process.execPath, [
    path.join(root, "tools", "Write-ValidationSummary.js"),
    "--input", payloadPath,
    "--output-dir", scratch,
], { cwd: root, encoding: "utf8" });
assert.strictEqual(summaryResult.status, 0, summaryResult.stderr);
const summary = JSON.parse(fs.readFileSync(path.join(scratch, "summary.json"), "utf8"));
assert.strictEqual(summary.result, "fail");
assert.deepStrictEqual(summary.checks.map((check) => check.id), ["a-pass", "z-fail"]);
assert(summary.checks[1].command.includes("<local-path>"));
const markdown = fs.readFileSync(path.join(scratch, "summary.md"), "utf8");
assert(!markdown.includes("SUCCESS-DETAIL-MUST-NOT-LEAK"));
assert(markdown.includes("logs/z.log"));

if (process.env.BETTER_NEXUS_QUALITY_GATE_ACTIVE !== "1") {
    const multiple = runPowerShell("tools/Invoke-QualityGate.ps1",
        ["-Mode", "Fast", "-SelfTestScenario", "MultipleFailures"]);
    assert.notStrictEqual(multiple.status, 0, "multiple failing checks returned success");
    const multipleSummary = JSON.parse(fs.readFileSync(
        path.join(root, "build", "verify", "summary.json"), "utf8"));
    assert.strictEqual(multipleSummary.failed, 2);
    assert.strictEqual(multipleSummary.passed, 1);
    assert.deepStrictEqual(multipleSummary.checks.map((check) => check.id),
        ["self-fail-a", "self-fail-b", "self-pass"]);

    const unavailable = runPowerShell("tools/Invoke-QualityGate.ps1",
        ["-Mode", "Security", "-SelfTestScenario", "UnavailableTool"]);
    assert.notStrictEqual(unavailable.status, 0, "unavailable blocking tool returned success");
    const unavailableSummary = JSON.parse(fs.readFileSync(
        path.join(root, "build", "verify", "summary.json"), "utf8"));
    assert.strictEqual(unavailableSummary.result, "fail");
    assert.strictEqual(unavailableSummary.unavailable, 1);
    assert.match(unavailableSummary.checks[0].reason, /required tool missing/);
}

fs.rmSync(scratch, { recursive: true, force: true });
console.log("quality gate self-tests: routing, modes, failures, unavailable tools, compact summaries, ordering, portability, exit status -- OK");
