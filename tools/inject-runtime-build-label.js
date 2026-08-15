"use strict";

const fs = require("fs");

const SOURCE_LINE = '    buildLabel = "source",';

function validateRuntimeBuildLabel(value) {
    if (value === "source") return value;
    if (typeof value !== "string"
        || !/^test\.\d+-[0-9a-f]{7,12}$/.test(value)) {
        throw new Error("invalid runtime build label");
    }
    return value;
}

function injectRuntimeBuildLabel(source, value) {
    if (typeof source !== "string") {
        throw new Error("Release.lua source must be text");
    }
    const label = validateRuntimeBuildLabel(value);
    const normalizedSource = source.replace(/\r+\n/g, "\r\n");
    const anchorPattern = /(^|\r*\n)    buildLabel = "source",(?=\r*\n|$)/g;
    const occurrences = (normalizedSource.match(anchorPattern) || []).length;
    if (occurrences !== 1) {
        throw new Error(`expected exactly one runtime build label anchor; found ${occurrences}`);
    }
    return normalizedSource.replace(anchorPattern, (match, prefix) =>
        `${prefix}    buildLabel = "${label}",`);
}

if (require.main === module) {
    const [inputPath, outputPath, label] = process.argv.slice(2);
    if (!inputPath || !outputPath || !label) {
        throw new Error("usage: inject-runtime-build-label.js <input> <output> <label>");
    }
    const source = fs.readFileSync(inputPath, "utf8");
    fs.writeFileSync(outputPath, injectRuntimeBuildLabel(source, label), "utf8");
}

module.exports = {
    SOURCE_LINE,
    injectRuntimeBuildLabel,
    validateRuntimeBuildLabel,
};
