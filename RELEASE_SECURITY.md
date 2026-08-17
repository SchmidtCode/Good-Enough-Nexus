# Release Security

## Core principles

Release authority remains a human and repository control function; AI assistance does not replace review, merge, or branch protections.

## Required local controls

Checked-in policy files should be validated together with GitHub branch protections and review controls:

- `.github/CODEOWNERS` for policy/release-critical ownership;
- `tools/Test-ReleasePolicy.ps1` for archive and source policy checks;
- branch and PR review rules configured in GitHub settings.

## Required release archive contents

Release archives must include, in the top-level `Nexus` folder:

- `Nexus.toc`
- `LICENSE.md`
- `AI_POLICY.md`
- `UPSTREAM.md`

`RELEASE_SECURITY.md`, `SECURITY.md`, and `README.md` are required in source but are not substitutes for the three mandatory archive files.

## Offline checks

Before release:

1. verify the source commit is reviewed and clean;
2. run `tools/Test-ReleasePolicy.ps1 -Archive <artifact>`;
3. record commit, artifact SHA-256, and validation outcome in release notes.

## Incident response

On suspected takeover, unauthorized release, or credential compromise:

- stop publish actions;
- preserve evidence and logs;
- rotate affected credentials;
- remove compromised collaborators/apps;
- notify the maintainer via the private security path and recover safely.
