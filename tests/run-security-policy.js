"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const root = path.resolve(__dirname, "..");
const pwsh = process.platform === "win32" ? "pwsh.exe" : "pwsh";

function run(script, args) {
    return spawnSync(pwsh, ["-NoProfile", "-File", path.join(root, script), ...args], {
        cwd: root,
        encoding: "utf8",
    });
}

const artifact = run("tools/Test-StagedArtifacts.ps1", ["-SelfTest"]);
assert.strictEqual(artifact.status, 0, `${artifact.stdout}\n${artifact.stderr}`);
assert.match(artifact.stdout, /5 rejected \/ 2 allowed/);

const manifest = JSON.parse(fs.readFileSync(path.join(root, "tools/security-tools.json"), "utf8"));
assert.strictEqual(manifest.schema, 1);
for (const tool of ["gitleaks", "actionlint", "zizmor"]) {
    for (const platform of ["windows-x64", "linux-x64"]) {
        const asset = manifest.tools[tool][platform];
        assert.match(asset.url, /^https:\/\/github\.com\//);
        assert.match(asset.sha256, /^[0-9a-f]{64}$/);
        assert(!asset.url.includes("/latest/"));
    }
}
assert.match(manifest.psscriptanalyzer.sha256, /^[0-9a-f]{64}$/);
assert.strictEqual(manifest.pre_commit.packages[0], `pre-commit==${manifest.pre_commit.version}`);
assert(manifest.pre_commit.packages.every((entry) => /^[A-Za-z0-9_-]+==[^=]+$/.test(entry)), "pre-commit dependency is not exact");
const advisory = JSON.parse(fs.readFileSync(path.join(root, "tests/security-advisory-baseline.json"), "utf8"));
assert.strictEqual(Object.values(advisory.psscriptanalyzer).reduce((sum, count) => sum + count, 0), 6);
assert.deepStrictEqual(advisory.mixed_line_endings, [
    ".gitignore",
    "tools/check-lua51-upvalues.js",
    "tools/inject-runtime-build-label.js",
]);

const luarc = JSON.parse(fs.readFileSync(path.join(root, ".luarc.json"), "utf8"));
assert.strictEqual(luarc["runtime.version"], "Lua 5.1");
for (const diagnostic of ["undefined-global", "duplicate-local", "unreachable-code", "unbalanced-assignments", "unused-local"]) {
    assert.strictEqual(luarc["diagnostics.neededFileStatus"][diagnostic], "Any");
}

const exceptions = JSON.parse(fs.readFileSync(path.join(root, "tests/static-policy-exceptions.json"), "utf8"));
const ebonhold = exceptions.project_ebonhold_globals;
const allowed = new Set(ebonhold.allowed_paths);
const sourceRoots = ["core", "logic", "ui", "data"];
for (const sourceRoot of sourceRoots) {
    const directory = path.join(root, sourceRoot);
    for (const name of fs.readdirSync(directory)) {
        if (!name.endsWith(".lua")) continue;
        const relative = `${sourceRoot}/${name}`;
        const text = fs.readFileSync(path.join(directory, name), "utf8");
        const usesEbonholdGlobal = ebonhold.patterns.some((pattern) => text.includes(pattern));
        if (usesEbonholdGlobal) assert(allowed.has(relative), `unapproved Project Ebonhold global use: ${relative}`);
    }
}
for (const relative of allowed) assert(fs.existsSync(path.join(root, relative)), `stale static exception: ${relative}`);

const preCommit = fs.readFileSync(path.join(root, ".pre-commit-config.yaml"), "utf8");
assert.match(preCommit, /rev: [0-9a-f]{40}/);
assert.match(preCommit, /mixed-line-ending[\s\S]*--fix=no/);
assert.match(preCommit, /exclude: \^\(\\\.gitignore\|tools\//);
assert.match(preCommit, /stages: \[pre-push\]/);
assert(!preCommit.includes("rev: v"));

const stylua = fs.readFileSync(path.join(root, "stylua.toml"), "utf8");
assert(!stylua.includes("format"));
console.log("security policy self-tests: artifacts, pins, Lua 5.1, pre-commit, advisory formatting -- OK");
