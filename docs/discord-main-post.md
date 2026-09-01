# Good Enough Nexus 1.96.5 Experimental

## Experimental warning

This release changes how stored leaderboard history moves between Nexus users.
Back up `NexusDB` and `WishlistRealizerDB` before testing it.

If Nexus causes stutter, long syncs, FPS loss, or unusual memory use, report it
to me with your Sync diagnostics and `/nexus perf` output, then reinstall
v1.96.4. Your existing SavedVariables remain compatible with the rollback.

## Download

https://github.com/SchmidtCode/Good-Enough-Nexus/releases/latest

Good Enough Nexus keeps Nexus working while Valentine finishes the official
Better Nexus 1.20 refactor. Use the official 1.20 release when it is ready.

## Installation

1. Remove the existing `Interface\AddOns\Nexus` folder.
2. Download and extract the release ZIP.
3. Confirm the final path is `Interface\AddOns\Nexus\Nexus.toc`.
4. Start the game or use `/reload`.
5. Left-click the Nexus minimap button to show the HUD.

Keep the addon folder named `Nexus`.

## Choose your HUD target

Open **Ebonhold Character Progression > Echoes**. Use the blue **Nexus HUD target**
menu above the Echo list to pick your wishlist. It drives Progress, Still Needed,
To Shed, and Auto decisions.

Boards are random except for banished choices. When two wanted Echoes appear,
Nexus freezes one before taking the other if possible.

## Level 80 and orbs

At level 80, Nexus compares your HUD target with the active Ebonhold Saved Build.

1. Activate the Saved Build you want to improve.
2. After a new 1 to 80 run, switch away from that build and back once.
3. Use an Orb of Lost Memories to forget one unwanted Echo.
4. Roll until you get the wanted replacement.
5. Save over the same active Saved Build.

Progress, Still Needed, and To Shed should update. If they do not, switch away
and back, reopen Echoes, or use `/reload`.

## What works

Wishlists and Auto, build sharing, DPS records, leaderboards, missing Echo and
tome tracking, Saved Build automation, and existing databases.

## Experimental leaderboard history sync

Your own addon still records only your highest DPS for each encounter. Each new
owner record receives a server timestamp. During sync, the newest owner snapshot
wins, while the owner's local capture continues to reject weaker attempts.

Current clients can relay stored records while the original player is offline.
This lets leaderboard history spread as more players install v1.96.5. Records
sent directly by v1.19.5 players remain compatible, but older clients cannot
relay third-party history and may keep showing an older highest score until they
update.

Relayed history is marked unverified until that character sends the record
directly. Sync uses bucket hashes and stops after two quiet unchanged passes, so
matching users do not resend the complete leaderboard.

## Support

This build completed a live run and the full offline suite. Maintenance covers
core blockers while 1.20 is developed.
