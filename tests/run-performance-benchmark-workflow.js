"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const workflowPath = path.join(root, ".github", "workflows", "performance-benchmarks.yml");

assert.ok(fs.existsSync(workflowPath), "performance benchmark workflow should exist");
const workflow = fs.readFileSync(workflowPath, "utf8");

assert.match(workflow, /workflow_dispatch:/, "workflow should support manual runs");
assert.match(workflow, /pull_request:/, "workflow should run for pull requests");
assert.match(workflow, /node tools\/run-performance-benchmarks\.js/, "workflow should run the benchmark reporter");
assert.match(workflow, /GITHUB_STEP_SUMMARY/, "workflow should publish the Markdown summary");
assert.match(workflow, /actions\/upload-artifact@v4/, "workflow should retain benchmark artifacts");
assert.doesNotMatch(workflow, /threshold|regression|budget/i,
    "workflow should not turn observations into timing gates");

console.log("observational performance benchmark workflow -- OK");
