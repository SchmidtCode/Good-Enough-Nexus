"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const workflowPath = path.resolve(__dirname, "..", ".github", "workflows",
    "crap-report.yml");
assert.ok(fs.existsSync(workflowPath), "production CRAP report workflow should exist");
const workflow = fs.readFileSync(workflowPath, "utf8");

assert.match(workflow, /node tools\/crap-report\.js --coverage/,
    "workflow should measure runtime CRAP with functional-test coverage");
assert.match(workflow, /GITHUB_STEP_SUMMARY/,
    "workflow should publish the CRAP Markdown summary");
assert.match(workflow, /actions\/upload-artifact@v7/,
    "workflow should retain the raw production scores");
assert.doesNotMatch(workflow, /tests\/.*crap|benchmarks\/.*crap/i,
    "workflow should not score tests or benchmarks");
assert.doesNotMatch(workflow, /--threshold|--fail-above|max-crap/i,
    "workflow should report current debt without a repository-wide gate");

console.log("production-only observational CRAP workflow -- OK");
