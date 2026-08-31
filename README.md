# Good Enough Nexus

Good Enough Nexus is a public, community-maintained continuation of the deprecated
Nexus addon for Project Ebonhold.

The repository begins from the installed Nexus 1.19.3 player build. The in-game
addon name, folder name, slash commands, and SavedVariables remain `Nexus` for
compatibility with existing installations and user data.

## Project status

- Repository visibility: public.
- Official stable base: Nexus 1.19.5.
- Current community compatibility line: Nexus 1.96.x.
- Intended handoff: the official Better Nexus 1.20 release from Viscerals.
- Client target: World of Warcraft 3.3.5a / Project Ebonhold.
- Language target: Lua 5.1.
- Upstream author attribution is preserved in `Nexus.toc` and
  [UPSTREAM.md](UPSTREAM.md).

## What it does

Nexus provides Echo build automation, saved-build wishlists, community builds,
DPS records, and Snapshot convergence for Project Ebonhold.

Current Ebonhold Echo boards are fully random except for banished choices. Saved
Builds are comparison targets only; they do not guarantee prior-run Echoes or a
particular board slot. When two usable wishlist Echoes appear together, Nexus
freezes one before taking the other when Freeze is available.

## Requirements

- Project Ebonhold on World of Warcraft 3.3.5a.
- Details! for DPS capture and leaderboard records.

## Installation

1. Keep the runtime addon folder named `Nexus`.
2. Place it under `Interface\AddOns`.
3. Confirm `Interface\AddOns\Nexus\Nexus.toc` exists.
4. Start the game or use `/reload`.

Do not rename the installed addon folder to `Good-Enough-Nexus`; the repository
name is different from the runtime addon identity by design.

Back up `NexusDB` and `WishlistRealizerDB` before installing a new build. Good
Enough Nexus preserves compatibility with these SavedVariables so existing user
data survives upgrades and rollback testing.

## Reporting problems

Use the [structured issue
forms](https://github.com/SchmidtCode/Good-Enough-Nexus/issues/new/choose) to
report a bug, performance or stutter problem, or multiplayer Sync problem.
Include the exact Nexus version and the diagnostics requested by the form.

## Commands

- `/nexus` — show commands
- `/nexus builds` — open Community Builds
- `/nexus leaderboard` — open the DPS Leaderboard
- `/nexus editor` — open the Wishlist Editor
- `/nexus sync` — request builds and records
- `/nexus dps` — show DPS capture status
- `/nexus auto` — toggle automation
- `/nexus panel` — toggle the HUD
- `/nexus overlay` — toggle the wishlist overlay
- `/nexus log` — open the diagnostic log
- `/nexus log errors` — open the newest 20 structured errors
- `/nexus perf` — open bounded performance aggregates for this session
- `/nexus perf reset` — clear session aggregates before reproducing a slow action
- `/nexus err` — print the newest retained error
- `/nexus status` — show current build and loadout state

## Development rules

- Preserve Lua 5.1 and WoW 3.3.5a compatibility.
- Preserve `NexusDB` and `WishlistRealizerDB` migrations and user data.
- Keep policy decisions deterministic and data-driven.
- Do not include tests, backups, local logs, or development artifacts in player
  release archives.
- Validate changes offline and in game before claiming a live issue fixed.
- Update notices come only from versions on already accepted Nexus Sync traffic.
  Nexus never downloads or installs updates; the notice exposes the stable
  releases page for manual use.

The release build catalog is generated, not hand-edited. Run
`node tools/export-bundled-builds.js --help` for the local export command. The
exporter parses SavedVariables as data, includes only complete shareable builds,
and writes deterministic catalog metadata plus an exclusion report.
`node tools/analyze-savedvariables.js --input <Nexus.lua>` uses the same literal
parser in read-only mode and prints aggregate compaction metrics without
evaluating Lua, exposing record contents, or writing the input.

For the repository's local offline gate, run these commands from PowerShell:

```powershell
node .tools/fengari/parse-lua51.js . --tests
Get-ChildItem -LiteralPath tests -Filter 'run_*.lua' | Sort-Object Name | ForEach-Object { node .tools/fengari/run-lua.js $_.FullName; if ($LASTEXITCODE -ne 0) { throw "failed: $($_.Name)" } }
node tests/run-bundled-build-export.js
node tests/run-savedvariables-analyzer.js
node tests/run-performance-benchmark-runner.js
node tests/run-performance-benchmark-workflow.js
node tests/run-crap-report.js
node tests/run-crap-workflow.js
git diff --check
```

These checks do not prove in-game behavior; `/reload` and live Project Ebonhold
verification must still be reported separately.

## Community release packaging

The `v1.96.4` tag workflow accepts only a tag on the exact remote tip of
`main`. It runs the offline release checks, builds a `Nexus` ZIP
from the tagged commit, writes a SHA-256 checksum and commit manifest, records a
GitHub build-provenance attestation, and creates a draft GitHub release. A human
must inspect and publish the draft.

The player ZIP contains `Nexus.toc` and only the runtime Lua files it lists.
Tests, benchmarks, tools, reports, dependency caches, and repository metadata
do not enter the archive.

In-addon update notices continue to point to Visceral's official releases page.
The release ignores peer advertisements from the interim `1.96.x` line, while
an official `1.20.0` peer can still trigger the handoff notice.

## Performance benchmarks

Run the observational benchmark suite with LuaJIT:

```powershell
node tools/run-performance-benchmarks.js --runtime luajit
```

The suite measures idle automation heartbeats, dirty and level-80 recovery
steps, cached and rebuilt browser refreshes, debounced Community search bursts,
virtual scrolling, leaderboard category switches, scheduler operations, Sync
request admission and response work, and idle update cost. It reports average,
median, p95, and maximum latency alongside work-item throughput. Results are written to
`benchmark-results/results.json` and `benchmark-results/summary.md`.

The figures are measurements, not timing gates. Compare runs made with the same
runtime and similar hardware. GitHub Actions runs the suite on pushes, pull
requests, a weekly schedule, and manual dispatches, then publishes the Markdown
summary and retains both report files as artifacts. A broken benchmark run still
returns an error because it produced no usable observation.

Use `--quick` for a shorter local smoke run.

## CRAP report

Run the production CRAP report with LuaJIT:

```powershell
npm ci
node tools/crap-report.js --coverage --runtime luajit --output-dir crap-results
```

The reporter scores only addon runtime files listed in `Nexus.toc`. It excludes
tests, benchmarks, development tooling, and generated bundled-build data. Lua
tests supply statement coverage, but test and benchmark functions never receive
CRAP scores. Benchmark-specific test programs are also excluded from functional
coverage collection.

The report writes raw JSON and a Markdown summary. CI publishes both without a
repository-wide score gate while the existing debt is being reduced.

See [CHANGELOG.md](CHANGELOG.md) for inherited release history and
[UPSTREAM.md](UPSTREAM.md) for provenance and redistribution notes.
