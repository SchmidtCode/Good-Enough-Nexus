"use strict";

const fs = require("fs");
const path = require("path");
const childProcess = require("child_process");

const root = path.resolve(__dirname, "..");
const scenarios = ["community", "leaderboard", "scheduler", "sync"];

function finite(text, field) {
    const value = Number(text);
    if (!Number.isFinite(value)) throw new Error(`invalid ${field}: ${text}`);
    return value;
}

function parseBenchmarkLine(line) {
    const fields = String(line || "").split("\t");
    if (fields[0] !== "BENCHMARK" || fields.length !== 13) return null;
    return {
        name:fields[1], latencyUnit:fields[2], throughputUnit:fields[3],
        iterations:finite(fields[4], "iterations"),
        workItems:finite(fields[5], "workItems"),
        totalMs:finite(fields[6], "totalMs"),
        minimumMs:finite(fields[7], "minimumMs"),
        averageMs:finite(fields[8], "averageMs"),
        medianMs:finite(fields[9], "medianMs"),
        p95Ms:finite(fields[10], "p95Ms"),
        maximumMs:finite(fields[11], "maximumMs"),
        throughputPerSecond:finite(fields[12], "throughputPerSecond"),
    };
}

function displayMs(value) {
    if (value >= 10) return `${value.toFixed(2)} ms`;
    if (value >= 1) return `${value.toFixed(3)} ms`;
    return `${value.toFixed(4)} ms`;
}

function renderMarkdown(results, metadata) {
    const lines = [
        "# Performance benchmark report",
        "",
        `Runtime: ${metadata.runtime}`,
        `Platform: ${metadata.platform}`,
        `Commit: ${metadata.commit}`,
        "",
        "These numbers describe this run. The report has no performance thresholds.",
    ];
    const groups = new Map();
    for (const result of results) {
        const group = groups.get(result.latencyUnit) || [];
        group.push(result);
        groups.set(result.latencyUnit, group);
    }
    for (const [unit, rows] of groups) {
        lines.push("", `## ${unit} latency`, "",
            `| Benchmark | Avg ${unit} | Median | P95 | Max | Throughput |`,
            "| --- | ---: | ---: | ---: | ---: | ---: |");
        for (const result of rows) {
            lines.push(`| ${result.name} | ${displayMs(result.averageMs)} | ${displayMs(result.medianMs)} | ${displayMs(result.p95Ms)} | ${displayMs(result.maximumMs)} | ${result.throughputPerSecond.toFixed(2)} ${result.throughputUnit}/s |`);
        }
    }
    return `${lines.join("\n")}\n`;
}

function optionValue(args, name, fallback) {
    const index = args.indexOf(name);
    if (index < 0) return fallback;
    if (!args[index + 1]) throw new Error(`${name} requires a value`);
    return args[index + 1];
}

function currentCommit() {
    if (process.env.GITHUB_SHA) return process.env.GITHUB_SHA;
    const result = childProcess.spawnSync("git", ["rev-parse", "--short", "HEAD"], {
        cwd:root, encoding:"utf8",
    });
    return result.status === 0 ? result.stdout.trim() : "unknown";
}

function runScenario(runtime, scenario, quick) {
    const env = {...process.env};
    if (quick) env.NEXUS_BENCHMARK_QUICK = "1";
    const result = childProcess.spawnSync(runtime,
        ["benchmarks/run-scenario.lua", scenario], {
            cwd:root, env, encoding:"utf8", maxBuffer:16 * 1024 * 1024,
        });
    if (result.error) throw result.error;
    if (result.status !== 0) {
        throw new Error(`${scenario} benchmark exited ${result.status}\n${result.stdout}${result.stderr}`);
    }
    process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    return result.stdout.split(/\r?\n/)
        .map(parseBenchmarkLine).filter(Boolean);
}

function main(argv) {
    const runtime = optionValue(argv, "--runtime", process.env.LUA_RUNTIME || "luajit");
    const outputDirectory = path.resolve(root,
        optionValue(argv, "--output-dir", "benchmark-results"));
    const quick = argv.includes("--quick");
    const results = scenarios.flatMap((scenario) =>
        runScenario(runtime, scenario, quick));
    if (results.length === 0) throw new Error("no benchmark observations were produced");
    const metadata = {
        runtime,
        platform:`${process.platform}-${process.arch}`,
        commit:currentCommit(),
        generatedAt:new Date().toISOString(),
        quick,
    };
    fs.mkdirSync(outputDirectory, {recursive:true});
    const report = {metadata,results};
    fs.writeFileSync(path.join(outputDirectory, "results.json"),
        `${JSON.stringify(report, null, 2)}\n`);
    const markdown = renderMarkdown(results, metadata);
    fs.writeFileSync(path.join(outputDirectory, "summary.md"), markdown);
    process.stdout.write(`\n${markdown}`);
    process.stdout.write(`Reports written to ${outputDirectory}\n`);
    return report;
}

module.exports = {parseBenchmarkLine,renderMarkdown,main};

if (require.main === module) {
    try {
        main(process.argv.slice(2));
    } catch (error) {
        process.stderr.write(`performance benchmarks: ${error.message}\n`);
        process.exitCode = 1;
    }
}
