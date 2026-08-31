"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const root = path.resolve(__dirname, "..");
const result = childProcess.spawnSync(process.execPath,
    ["tools/crap-report.js", "--list-files", "--json"], {
        cwd:root, encoding:"utf8",
    });

assert.strictEqual(result.status, 0,
    `CRAP reporter file discovery failed:\n${result.stdout}${result.stderr}`);
const files = JSON.parse(result.stdout);

assert.ok(files.includes("core/Main.lua"),
    "CRAP reporter should score addon runtime code");
assert.ok(files.includes("ui/CommunityBuilds.lua"),
    "CRAP reporter should score addon UI runtime code");
assert.ok(!files.includes("data/BundledBuilds.lua"),
    "CRAP reporter should exclude generated build data");
assert.ok(files.every((file) => !/^tests\//.test(file)
    && !/^benchmarks\//.test(file) && !/^tools\//.test(file)),
    "CRAP reporter should never score tests, benchmarks, or tooling");

const staticResult = childProcess.spawnSync(process.execPath,
    ["tools/crap-report.js", "--static", "--json"], {
        cwd:root, encoding:"utf8", maxBuffer:16 * 1024 * 1024,
    });
assert.strictEqual(staticResult.status, 0,
    `static CRAP report failed:\n${staticResult.stdout}${staticResult.stderr}`);
const report = JSON.parse(staticResult.stdout);
assert.ok(report.summary.functions > 1000,
    "static CRAP report should include runtime functions");
assert.ok(report.functions.every((entry) => files.includes(entry.file)),
    "every scored function should come from the production-only file list");
const known = report.functions.find((entry) => entry.complexity === 4
    && entry.coverage === 0);
assert.ok(known && known.crap === 20,
    "CRAP should use complexity^2 * uncovered^3 + complexity");

const coverageResult = childProcess.spawnSync(process.execPath, [
    "tools/crap-report.js", "--coverage", "--runtime", "luajit",
    "--test", "tests/run_data_revisions.lua", "--json",
], {cwd:root,encoding:"utf8",maxBuffer:16 * 1024 * 1024});
assert.strictEqual(coverageResult.status, 0,
    `instrumented CRAP report failed:\n${coverageResult.stdout}${coverageResult.stderr}`);
const coveredReport = JSON.parse(coverageResult.stdout);
assert.strictEqual(coveredReport.summary.coverageTests, 1,
    "instrumented report should state how many functional tests supplied coverage");
assert.ok(coveredReport.functions.some((entry) => entry.covered > 0),
    "instrumented report should include executed production statements");
assert.ok(coveredReport.functions.every((entry) => !entry.file.startsWith("tests/")
    && !entry.file.startsWith("benchmarks/")),
    "instrumented coverage should not add scores for tests or benchmarks");

const outputDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-crap-report-test-"));
try {
    const artifactResult = childProcess.spawnSync(process.execPath, [
        "tools/crap-report.js", "--coverage", "--runtime", "luajit",
        "--test", "tests/run_data_revisions.lua", "--output-dir", outputDirectory,
    ], {cwd:root,encoding:"utf8",maxBuffer:16 * 1024 * 1024});
    assert.strictEqual(artifactResult.status, 0,
        `CRAP artifact report failed:\n${artifactResult.stdout}${artifactResult.stderr}`);
    assert.ok(fs.existsSync(path.join(outputDirectory, "results.json"))
        && fs.existsSync(path.join(outputDirectory, "summary.md")),
        "CRAP reporter should publish JSON and Markdown artifacts");
    const markdown = fs.readFileSync(path.join(outputDirectory, "summary.md"), "utf8");
    assert.match(markdown, /Tests and benchmarks are never scored\./,
        "CRAP summary should make its production-only scope explicit");
} finally {
    fs.rmSync(outputDirectory, {recursive:true,force:true});
}

console.log("production-only CRAP file discovery -- OK");
