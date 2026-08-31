# Release Security

## Core principles

Release authority remains a human and repository control function; AI assistance does not replace review, merge, or branch protections.

## Required controls

Checked-in policy files are validated together with GitHub branch protections and review controls:

- `.github/CODEOWNERS` for policy/release-critical ownership;
- `.github/workflows/validation.yml` for the complete Lua and Node suite;
- `.github/workflows/community-release.yml` for tag-bound draft packaging;
- branch and PR review rules configured in GitHub settings.

## Required release artifacts

Each tagged community release must produce:

- `Nexus-vX.Y.Z.zip`
- `Nexus-vX.Y.Z.zip.sha256`
- `Nexus-vX.Y.Z-build.json`

The ZIP must contain a top-level `Nexus` folder with `Nexus.toc` and only the runtime files selected by the release packager. Tests, tools, repository metadata, dependency caches, and local data must not be included.

## Offline checks

Before release:

1. verify the source commit is reviewed and clean;
2. run the full Lua and Node suites, static Lua parsing, packaging tests, and `git diff --check`;
3. verify the packaged archive, checksum, build manifest, attestation, tag target, and runtime version identity;
4. require explicit human approval before publishing the draft.

## Incident response

On suspected takeover, unauthorized release, or credential compromise:

- stop publish actions;
- preserve evidence and logs;
- rotate affected credentials;
- remove compromised collaborators/apps;
- notify the maintainer via the private security path and recover safely.
