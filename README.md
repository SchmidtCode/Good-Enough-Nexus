# Better Nexus

Better Nexus is a public, community-maintained continuation of the deprecated
Nexus addon for Project Ebonhold.

The repository begins from the installed Nexus 1.19.3 player build. The in-game
addon name, folder name, slash commands, and SavedVariables remain `Nexus` for
compatibility with existing installations and user data.

## Project status

- Stable production release: Nexus 1.19.5.
- Experimental public prereleases are available through
  [GitHub Releases](https://github.com/Viscerals/Better-Nexus/releases). These
  builds are for testing and are not stable releases.
- Client target: World of Warcraft 3.3.5a / Project Ebonhold.
- Language target: Lua 5.1.
- Upstream author attribution is preserved in `Nexus.toc` and
  [UPSTREAM.md](UPSTREAM.md).

## What it does

Nexus provides Echo build automation, saved-build wishlists, community builds,
DPS records, and Snapshot convergence for Project Ebonhold.

## Requirements

- Project Ebonhold on World of Warcraft 3.3.5a.
- Details! for DPS capture and leaderboard records.

## Installation

1. Keep the runtime addon folder named `Nexus`.
2. Place it under `Interface\AddOns`.
3. Confirm `Interface\AddOns\Nexus\Nexus.toc` exists.
4. Start the game or use `/reload`.

Do not rename the installed addon folder to `Better-Nexus`; the repository name
is different from the runtime addon identity by design.

Back up `NexusDB` and `WishlistRealizerDB` before testing a prerelease. Better
Nexus preserves compatibility with these SavedVariables because existing user
data must survive upgrades and rollback testing.

## Reporting problems

Use the [structured issue
forms](https://github.com/Viscerals/Better-Nexus/issues/new/choose) to report a
bug, performance or stutter problem, or multiplayer Sync problem. Include the
exact prerelease build and the diagnostics requested by the selected form.

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
- `/nexus status` — show current build and loadout state

## Development rules

- Preserve Lua 5.1 and WoW 3.3.5a compatibility.
- Preserve `NexusDB` and `WishlistRealizerDB` migrations and user data.
- Keep policy decisions deterministic and data-driven.
- Do not include tests, backups, local logs, or development artifacts in player
  release archives.
- Validate changes offline and in game before claiming a live issue fixed.

See [CHANGELOG.md](CHANGELOG.md) for inherited release history and
[UPSTREAM.md](UPSTREAM.md) for provenance and redistribution notes.
