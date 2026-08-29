#!/usr/bin/env node
"use strict";

// Recover ordinary peer-posted community pages from an older SavedVariables
// snapshot without restoring the much larger automatic DPS-page cache.

const fs = require("fs");
const path = require("path");
const { parseNexusDb } = require("./export-bundled-builds.js");

function args(argv) {
    const out = {};
    for (let i = 0; i < argv.length; i += 1) {
        const key = argv[i];
        if (key === "--current") out.current = argv[++i];
        else if (key === "--source") out.source = argv[++i];
        else if (key === "--output") out.output = argv[++i];
        else if (key === "--dry-run") out.dryRun = true;
        else throw new Error(`unknown argument: ${key}`);
    }
    if (!out.current || !out.source || (!out.output && !out.dryRun)) {
        throw new Error("usage: restore-community-builds.js --current <Nexus.lua> --source <backup> [--output <file> | --dry-run]");
    }
    return out;
}

function table(value) {
    return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function stamp(value) {
    return Number(value && (value.lastModified || value.postedAt || value.ts)) || 0;
}

function luaString(value) {
    return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
        .replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t")}"`;
}

function keyOrder(left, right) {
    const ln = /^-?\d+(?:\.\d+)?$/.test(left) ? Number(left) : null;
    const rn = /^-?\d+(?:\.\d+)?$/.test(right) ? Number(right) : null;
    if (ln != null && rn != null) return ln - rn;
    if (ln != null) return -1;
    if (rn != null) return 1;
    return left.localeCompare(right);
}

function serialize(value, depth = 0) {
    if (value == null) return "nil";
    if (typeof value === "boolean") return value ? "true" : "false";
    if (typeof value === "number") {
        if (!Number.isFinite(value)) throw new Error("cannot serialize non-finite number");
        return String(value);
    }
    if (typeof value === "string") return luaString(value);
    if (typeof value !== "object" || Array.isArray(value)) {
        throw new Error(`cannot serialize ${typeof value}`);
    }
    const indent = "\t".repeat(depth);
    const childIndent = "\t".repeat(depth + 1);
    const keys = Object.keys(value).sort(keyOrder);
    if (keys.length === 0) return "{}";
    const rows = keys.map((key) => {
        const numeric = /^-?\d+(?:\.\d+)?$/.test(key);
        const renderedKey = numeric ? `[${key}]` : `[${luaString(key)}]`;
        return `${childIndent}${renderedKey} = ${serialize(value[key], depth + 1)},`;
    });
    return `{\n${rows.join("\n")}\n${indent}}`;
}

function main() {
    const options = args(process.argv.slice(2));
    const currentText = fs.readFileSync(options.current, "utf8");
    const current = parseNexusDb(currentText);
    const source = parseNexusDb(fs.readFileSync(options.source, "utf8"));
    current.communityBuilds = table(current.communityBuilds);
    const sourceBuilds = table(source.communityBuilds);
    const tombstones = table(current.syncTombstones);
    const evictions = table(current.communityRetentionEvictions);
    let restored = 0, existing = 0, automaticSkipped = 0, tombstonedSkipped = 0;
    for (const id of Object.keys(sourceBuilds).sort()) {
        const build = sourceBuilds[id];
        if (!build || typeof build !== "object") continue;
        if (build.autoDps === true) { automaticSkipped += 1; continue; }
        if (current.communityBuilds[id]) { existing += 1; continue; }
        const tombstone = tombstones[id];
        if (tombstone && stamp(tombstone) >= stamp(build)) {
            tombstonedSkipped += 1;
            continue;
        }
        current.communityBuilds[id] = build;
        delete evictions[id];
        restored += 1;
    }
    current.communityRetentionEvictions = evictions;
    current.communityBuildRetentionFloor = 0;
    const report = {
        currentBuildsBefore: Object.keys(table(parseNexusDb(currentText).communityBuilds)).length,
        sourceBuilds: Object.keys(sourceBuilds).length,
        restored, existing, automaticSkipped, tombstonedSkipped,
        outputBuilds: Object.keys(current.communityBuilds).length,
    };
    if (!options.dryRun) {
        const output = `NexusDB = ${serialize(current)}\nWishlistRealizerDB = nil\n`;
        fs.writeFileSync(options.output, output, "utf8");
        report.output = path.resolve(options.output);
        report.outputBytes = Buffer.byteLength(output, "utf8");
    }
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
}

main();
