"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const Packager = require(path.join(root, "tools", "package-release.js"));
const toc = fs.readFileSync(path.join(root, "Nexus.toc"), "utf8");
const release = fs.readFileSync(path.join(root, "data", "Release.lua"), "utf8");
const runtimeFiles = Packager.parseToc(toc);

assert.strictEqual(Packager.tocVersion(toc), "1.96.5",
    "TOC should carry the community release version");
assert.ok(runtimeFiles.includes("core/Main.lua")
    && runtimeFiles.includes("ui/Leaderboard.lua"),
"packager should include runtime files from Nexus.toc");
assert.ok(runtimeFiles.every((file) => !/^(tests|benchmarks|tools)\//.test(file)),
    "packager should exclude development files");
assert.deepStrictEqual(Packager.validateIdentity("v1.96.5",
    "SchmidtCode/Good-Enough-Nexus", toc, release).version, "1.96.5");
Packager.validateRuntimeIdentity("1.96.5",
    fs.readFileSync(path.join(root, "core", "Main.lua"), "utf8"),
    fs.readFileSync(path.join(root, "ui", "Changelog.lua"), "utf8"));
assert.throws(() => Packager.validateIdentity("v1.96.2",
    "SchmidtCode/Good-Enough-Nexus", toc, release), /does not match/,
"packager should reject a tag and addon version mismatch");
assert.throws(() => Packager.safeRuntimePath("../tests/harness.lua"), /unsafe/,
    "packager should reject TOC path traversal");
assert.throws(() => Packager.validateRuntimeIdentity("1.96.5", "", ""),
    /does not match/, "packager should reject stale runtime release identities");

const workflowPath = path.join(root, ".github", "workflows", "community-release.yml");
const workflow = fs.readFileSync(workflowPath, "utf8");
assert.match(workflow, /tags:\s*\n\s*- "v1\.96\.5"/,
    "release workflow should run only for the intended tag");
assert.match(workflow, /refs\/remotes\/origin\/main/,
    "release workflow should require the branch tip");
assert.match(workflow, /actions\/attest@v4/,
    "release workflow should attest the ZIP provenance");
assert.match(workflow, /--draft/,
    "release workflow should leave the GitHub release unpublished for review");
assert.match(workflow, /--prerelease/,
    "experimental release should be marked as a GitHub prerelease");
assert.match(workflow, /Nexus-\$\{\{ github\.ref_name \}\}\.zip\.sha256/,
    "release workflow should attach the generated checksum");

console.log("tag-bound draft community release packaging -- OK");
