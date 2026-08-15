"use strict";

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const root = path.resolve(__dirname, "..");
const runner = path.join(root, "tools", "run-lua.js");
const tests = fs.readdirSync(path.join(root, "tests"))
    .filter((name) => /^run_.*\.lua$/.test(name))
    .sort();
const failures = [];

for (const name of tests) {
    const relative = `tests/${name}`;
    const result = spawnSync(process.execPath, [runner, relative], {
        cwd: root,
        encoding: "utf8",
    });
    process.stdout.write(`== ${relative} ==\n${result.stdout || ""}`);
    if (result.stderr) process.stderr.write(result.stderr);
    if (result.status !== 0) failures.push(`${relative}: exit ${result.status}`);
}

for (const failure of failures) process.stderr.write(`${failure}\n`);
process.stdout.write(`Lua suite: ${tests.length - failures.length}/${tests.length} passed\n`);
process.exit(failures.length === 0 ? 0 : 1);
