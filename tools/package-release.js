"use strict";

const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");

function optionValue(args, name, fallback) {
    const index = args.indexOf(name);
    if (index < 0) return fallback;
    if (!args[index + 1]) throw new Error(`${name} requires a value`);
    return args[index + 1];
}

function git(args) {
    const result = childProcess.spawnSync("git", args, {
        cwd:root,
        encoding:"utf8",
        maxBuffer:16 * 1024 * 1024,
    });
    if (result.error) throw result.error;
    if (result.status !== 0) {
        throw new Error(`git ${args.join(" ")} failed\n${result.stdout}${result.stderr}`);
    }
    return result.stdout.trim();
}

function safeRuntimePath(value) {
    const normalized = String(value || "").replace(/\\/g, "/");
    if (!normalized || normalized.startsWith("/") || /^[A-Za-z]:/.test(normalized)
        || normalized.split("/").includes("..")
        || path.posix.normalize(normalized) !== normalized) {
        throw new Error(`unsafe runtime path in Nexus.toc: ${value}`);
    }
    return normalized;
}

function parseToc(source) {
    const files = [];
    const seen = new Set();
    for (const raw of String(source || "").replace(/^\uFEFF/, "").split(/\r?\n/)) {
        const line = raw.trim();
        if (!line || line.startsWith("#")) continue;
        const file = safeRuntimePath(line);
        if (!file.endsWith(".lua")) {
            throw new Error(`non-Lua runtime entry in Nexus.toc: ${file}`);
        }
        if (seen.has(file)) throw new Error(`duplicate runtime entry in Nexus.toc: ${file}`);
        seen.add(file);
        files.push(file);
    }
    if (files.length === 0) throw new Error("Nexus.toc contains no runtime files");
    return files;
}

function tocVersion(source) {
    const match = String(source || "").match(/^##\s*Version:\s*(\S+)\s*$/m);
    if (!match) throw new Error("Nexus.toc has no Version metadata");
    return match[1];
}

function releaseIdentity(source) {
    const text = String(source || "");
    const field = (name) => {
        const match = text.match(new RegExp(`\\b${name}\\s*=\\s*"([^"]+)"`));
        if (!match) throw new Error(`data/Release.lua has no ${name} field`);
        return match[1];
    };
    return {
        version:field("version"),
        baseVersion:field("baseVersion"),
        releasesUrl:field("releasesUrl"),
        published:/\bpublished\s*=\s*true\b/.test(text),
    };
}

function validateIdentity(tag, repository, tocSource, releaseSource) {
    if (!/^v[0-9A-Za-z][0-9A-Za-z.-]*$/.test(tag)) {
        throw new Error(`invalid release tag: ${tag}`);
    }
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository)) {
        throw new Error(`invalid GitHub repository: ${repository}`);
    }
    const version = tocVersion(tocSource);
    const release = releaseIdentity(releaseSource);
    if (tag !== `v${version}`) {
        throw new Error(`tag ${tag} does not match Nexus.toc version ${version}`);
    }
    if (release.version !== version) {
        throw new Error(`data/Release.lua version ${release.version} does not match ${version}`);
    }
    if (!release.published) throw new Error("data/Release.lua must set published = true");
    const handoffUrl = "https://github.com/Viscerals/Better-Nexus/releases";
    if (release.releasesUrl !== handoffUrl) {
        throw new Error(`official handoff URL must be ${handoffUrl}`);
    }
    return {version,release};
}

function validateRuntimeIdentity(version, mainSource, changelogSource) {
    if (!String(mainSource || "").includes(`or "${version}"`)) {
        throw new Error(`core/Main.lua fallback does not match version ${version}`);
    }
    if (!String(changelogSource || "").includes(`local VERSION = "${version}"`)
        || !String(changelogSource || "").includes(`local RELEASE_KEY = "${version}"`)) {
        throw new Error(`ui/Changelog.lua does not match version ${version}`);
    }
}

function sourceAt(commit, file) {
    return git(["show", `${commit}:${file}`]);
}

function packageRelease(options) {
    const commit = git(["rev-parse", "--verify", `${options.commit}^{commit}`]);
    const tree = git(["rev-parse", "--verify", `${commit}^{tree}`]);
    const tocSource = sourceAt(commit, "Nexus.toc");
    const releaseSource = sourceAt(commit, "data/Release.lua");
    const identity = validateIdentity(options.tag, options.repository,
        tocSource, releaseSource);
    validateRuntimeIdentity(identity.version,
        sourceAt(commit, "core/Main.lua"), sourceAt(commit, "ui/Changelog.lua"));
    const runtimeFiles = parseToc(tocSource);
    const files = ["Nexus.toc", ...runtimeFiles];
    for (const file of files) git(["cat-file", "-e", `${commit}:${file}`]);

    fs.mkdirSync(options.outputDirectory, {recursive:true});
    const archiveName = `Nexus-${options.tag}.zip`;
    const archivePath = path.join(options.outputDirectory, archiveName);
    const checksumPath = `${archivePath}.sha256`;
    const manifestPath = path.join(options.outputDirectory,
        `Nexus-${options.tag}-build.json`);
    for (const output of [archivePath,checksumPath,manifestPath]) {
        if (fs.existsSync(output)) throw new Error(`refusing to overwrite ${output}`);
    }

    git(["archive", "--format=zip", "--prefix=Nexus/", `--output=${archivePath}`,
        commit, "--", ...files]);
    const sha256 = crypto.createHash("sha256")
        .update(fs.readFileSync(archivePath)).digest("hex");
    fs.writeFileSync(checksumPath, `${sha256}  ${archiveName}\n`);
    const manifest = {
        schemaVersion:1,
        addon:"Nexus",
        version:identity.version,
        tag:options.tag,
        commit,
        tree,
        repository:options.repository,
        source:`https://github.com/${options.repository}/tree/${commit}`,
        updateReleasesUrl:identity.release.releasesUrl,
        archive:archiveName,
        sha256,
        runtimeFiles:runtimeFiles.length,
    };
    fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    process.stdout.write(`${JSON.stringify(manifest, null, 2)}\n`);
    return {archivePath,checksumPath,manifestPath,manifest};
}

function main(args) {
    const tag = optionValue(args, "--tag", process.env.GITHUB_REF_NAME);
    const commit = optionValue(args, "--commit", process.env.GITHUB_SHA || "HEAD");
    const repository = optionValue(args, "--repository", process.env.GITHUB_REPOSITORY);
    const outputDirectory = path.resolve(root,
        optionValue(args, "--output-dir", "dist"));
    if (!tag) throw new Error("--tag is required");
    if (!repository) throw new Error("--repository is required");
    return packageRelease({tag,commit,repository,outputDirectory});
}

module.exports = {
    parseToc,
    releaseIdentity,
    safeRuntimePath,
    tocVersion,
    validateIdentity,
    validateRuntimeIdentity,
    packageRelease,
    main,
};

if (require.main === module) {
    try {
        main(process.argv.slice(2));
    } catch (error) {
        process.stderr.write(`release package: ${error.message}\n`);
        process.exitCode = 1;
    }
}
