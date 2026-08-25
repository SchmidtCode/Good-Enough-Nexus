"use strict";

const assert = require("assert");
const runner = require("../tools/run-performance-benchmarks.js");

const line = [
    "BENCHMARK", "sync.request", "request", "requests", "5", "5",
    "20.000000", "1.000000", "4.000000", "3.000000", "10.000000",
    "10.000000", "250.000000",
].join("\t");
const parsed = runner.parseBenchmarkLine(line);
assert.deepStrictEqual(parsed, {
    name:"sync.request", latencyUnit:"request", throughputUnit:"requests",
    iterations:5, workItems:5, totalMs:20, minimumMs:1, averageMs:4,
    medianMs:3, p95Ms:10, maximumMs:10, throughputPerSecond:250,
});

const markdown = runner.renderMarkdown([parsed], {
    runtime:"luajit", platform:"test", commit:"abc123",
});
assert(markdown.includes("| Benchmark | Avg request | Median | P95 | Max | Throughput |")
    && markdown.includes("sync.request")
    && markdown.includes("250.00 requests/s")
    && !markdown.toLowerCase().includes("pass")
    && !markdown.toLowerCase().includes("fail"),
    "benchmark Markdown added a threshold verdict or omitted timing fields")

console.log("performance benchmark parser and observational report -- OK");
