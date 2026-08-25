"use strict";

const fs = require("fs");
const childProcess = require("child_process");
const os = require("os");
const path = require("path");
const luaparse = require("luaparse");

const root = path.resolve(__dirname, "..");

function runtimeFiles() {
    return fs.readFileSync(path.join(root, "Nexus.toc"), "utf8")
        .split(/\r?\n/)
        .map((line) => line.trim().replace(/\\/g, "/"))
        .filter((line) => line && !line.startsWith("##"))
        .filter((line) => line.endsWith(".lua"))
        .filter((line) => line !== "data/BundledBuilds.lua")
        .filter((line) => !/^(tests|benchmarks|tools)\//.test(line));
}

const decisionTypes = new Set([
    "IfClause", "ElseifClause", "WhileStatement", "RepeatStatement",
    "ForNumericStatement", "ForGenericStatement",
]);

function expressionName(identifier) {
    if (!identifier) return null;
    if (identifier.type === "Identifier") return identifier.name;
    if (identifier.type === "MemberExpression") {
        return `${expressionName(identifier.base) || "?"}.${expressionName(identifier.identifier) || "?"}`;
    }
    if (identifier.type === "IndexExpression") {
        return `${expressionName(identifier.base) || "?"}[...]`;
    }
    return null;
}

function functionName(node, parent, ordinal) {
    const declared = expressionName(node.identifier);
    if (declared) return declared;
    if (parent && (parent.type === "AssignmentStatement"
        || parent.type === "LocalStatement")) {
        const index = parent.init.indexOf(node);
        return expressionName(parent.variables[index]) || `<anonymous ${ordinal}>`;
    }
    return `<anonymous ${ordinal}>`;
}

function inspectFunction(node) {
    let complexity = 1;
    const statementLines = new Set();
    function walk(value) {
        if (!value || typeof value !== "object") return;
        if (value !== node && value.type === "FunctionDeclaration") return;
        if (decisionTypes.has(value.type)) complexity += 1;
        if (value.type === "LogicalExpression") complexity += 1;
        if (value.type && value.type.endsWith("Statement")
            && value.type !== "FunctionDeclaration" && value.loc) {
            statementLines.add(value.loc.start.line);
        }
        for (const [key, child] of Object.entries(value)) {
            if (key === "loc" || key === "range") continue;
            if (Array.isArray(child)) child.forEach(walk);
            else walk(child);
        }
    }
    node.body.forEach(walk);
    return {complexity,statementLines};
}

function analyze(hitLines) {
    const functions = [];
    for (const file of runtimeFiles()) {
        const source = fs.readFileSync(path.join(root, file), "utf8");
        const ast = luaparse.parse(source, {locations:true,luaVersion:"5.1"});
        let ordinal = 0;
        function visit(value, parent) {
            if (!value || typeof value !== "object") return;
            if (value.type === "FunctionDeclaration") {
                ordinal += 1;
                const measured = inspectFunction(value);
                const hits = hitLines.get(file.toLowerCase()) || new Set();
                let covered = 0;
                for (const line of measured.statementLines) {
                    if (hits.has(line)) covered += 1;
                }
                const statements = measured.statementLines.size;
                const coverage = statements === 0 ? 1 : covered / statements;
                const crap = measured.complexity * measured.complexity
                    * Math.pow(1 - coverage, 3) + measured.complexity;
                functions.push({
                    file,line:value.loc.start.line,
                    name:functionName(value, parent, ordinal),
                    complexity:measured.complexity,
                    statements,covered,coverage,crap,
                });
            }
            for (const [key, child] of Object.entries(value)) {
                if (key === "loc" || key === "range") continue;
                if (Array.isArray(child)) child.forEach((item) => visit(item, value));
                else visit(child, value);
            }
        }
        visit(ast, null);
    }
    functions.sort((left, right) => right.crap - left.crap
        || right.complexity - left.complexity
        || left.file.localeCompare(right.file) || left.line - right.line);
    const total = functions.reduce((sum, entry) => sum + entry.crap, 0);
    const sortedScores = functions.map((entry) => entry.crap).sort((a,b) => a-b);
    return {
        summary:{
            formula:"complexity^2 * (1 - statementCoverage)^3 + complexity",
            scoredFiles:runtimeFiles().length,
            functions:functions.length,
            below10:functions.filter((entry) => entry.crap < 10).length,
            atOrAbove10:functions.filter((entry) => entry.crap >= 10).length,
            meanCrap:total / functions.length,
            medianCrap:sortedScores[Math.floor(sortedScores.length / 2)],
            maximumCrap:functions[0] ? functions[0].crap : 0,
        },
        functions,
    };
}

function optionValues(args, name) {
    const values = [];
    for (let index = 0; index < args.length; index += 1) {
        if (args[index] === name) {
            if (!args[index + 1]) throw new Error(`${name} requires a value`);
            values.push(args[index + 1]);
            index += 1;
        }
    }
    return values;
}

function optionValue(args, name, fallback) {
    const values = optionValues(args, name);
    return values.length > 0 ? values[values.length - 1] : fallback;
}

function functionalTests(requested) {
    if (requested.length > 0) return requested;
    return fs.readdirSync(path.join(root, "tests"))
        .filter((file) => /^run_.*\.lua$/.test(file))
        .filter((file) => !/(benchmark|performance)/i.test(file))
        .sort()
        .map((file) => `tests/${file}`);
}

function readHits(directory) {
    const hits = new Map();
    for (const filename of fs.readdirSync(directory)) {
        const content = fs.readFileSync(path.join(directory, filename), "utf8");
        for (const row of content.split(/\r?\n/)) {
            if (!row) continue;
            const separator = row.lastIndexOf("\t");
            if (separator < 0) continue;
            const source = row.slice(0, separator).replace(/\\/g, "/").toLowerCase();
            const line = Number(row.slice(separator + 1));
            const lines = hits.get(source) || new Set();
            lines.add(line);
            hits.set(source, lines);
        }
    }
    return hits;
}

function coverageReport(args) {
    const runtime = optionValue(args, "--runtime", process.env.LUA_RUNTIME || "luajit");
    const tests = functionalTests(optionValues(args, "--test"));
    const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-crap-"));
    try {
        tests.forEach((test, index) => {
            const output = path.join(temporary, `${String(index + 1).padStart(3, "0")}.tsv`);
            const result = childProcess.spawnSync(runtime, [
                "tools/crap-coverage.lua", path.resolve(root, test), output, root,
            ], {cwd:root,encoding:"utf8",maxBuffer:16 * 1024 * 1024});
            if (result.error) throw result.error;
            if (result.status !== 0) {
                throw new Error(`coverage test failed: ${test}\n${result.stdout}${result.stderr}`);
            }
        });
        const report = analyze(readHits(temporary));
        report.summary.coverageTests = tests.length;
        report.summary.coverageStatements = report.functions.reduce(
            (sum, entry) => sum + entry.covered, 0);
        report.summary.statements = report.functions.reduce(
            (sum, entry) => sum + entry.statements, 0);
        report.summary.statementCoverage = report.summary.statements > 0
            ? report.summary.coverageStatements / report.summary.statements : 1;
        return report;
    } finally {
        fs.rmSync(temporary, {recursive:true,force:true});
    }
}

function renderMarkdown(report) {
    const summary = report.summary;
    const lines = [
        "# CRAP report",
        "",
        `Scored files: ${summary.scoredFiles}`,
        `Functional test programs used for coverage: ${summary.coverageTests}`,
        "Tests and benchmarks are never scored.",
        "Generated build data and development tooling are also excluded.",
        "",
        `Formula: \`${summary.formula}\``,
        "",
        "| Metric | Value |",
        "| --- | ---: |",
        `| Functions | ${summary.functions} |`,
        `| Statement coverage | ${(summary.statementCoverage * 100).toFixed(2)}% |`,
        `| Mean CRAP | ${summary.meanCrap.toFixed(2)} |`,
        `| Median CRAP | ${summary.medianCrap.toFixed(2)} |`,
        `| Maximum CRAP | ${summary.maximumCrap.toFixed(2)} |`,
        `| Functions below 10 | ${summary.below10} |`,
        `| Functions at least 10 | ${summary.atOrAbove10} |`,
        "",
        "## Highest production scores",
        "",
        "| Function | Complexity | Coverage | CRAP |",
        "| --- | ---: | ---: | ---: |",
    ];
    for (const entry of report.functions.slice(0, 50)) {
        lines.push(`| ${entry.file}:${entry.line} ${entry.name} | ${entry.complexity} | ${(entry.coverage * 100).toFixed(1)}% | ${entry.crap.toFixed(2)} |`);
    }
    return `${lines.join("\n")}\n`;
}

function writeReport(report, outputDirectory) {
    const resolved = path.resolve(root, outputDirectory);
    fs.mkdirSync(resolved, {recursive:true});
    fs.writeFileSync(path.join(resolved, "results.json"),
        `${JSON.stringify(report, null, 2)}\n`);
    fs.writeFileSync(path.join(resolved, "summary.md"), renderMarkdown(report));
    return resolved;
}

function main(argv) {
    if (argv.includes("--list-files")) {
        const files = runtimeFiles();
        process.stdout.write(argv.includes("--json")
            ? `${JSON.stringify(files, null, 2)}\n`
            : `${files.join("\n")}\n`);
        return;
    }
    if (argv.includes("--static")) {
        const report = analyze(new Map());
        if (!argv.includes("--json")) {
            throw new Error("static reports currently require --json");
        }
        process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
        return;
    }
    if (argv.includes("--coverage")) {
        const report = coverageReport(argv);
        if (argv.includes("--json")) {
            process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
        } else {
            const output = writeReport(report,
                optionValue(argv, "--output-dir", "crap-results"));
            process.stdout.write(`${renderMarkdown(report)}Reports written to ${output}\n`);
        }
        return;
    }
    throw new Error("no CRAP report operation selected");
}

module.exports = {runtimeFiles,analyze,coverageReport,renderMarkdown,writeReport,main};

if (require.main === module) {
    try {
        main(process.argv.slice(2));
    } catch (error) {
        process.stderr.write(`CRAP report: ${error.message}\n`);
        process.exitCode = 1;
    }
}
