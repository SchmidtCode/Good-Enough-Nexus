# Good Enough Nexus 1.96.4

## Download the latest version

https://github.com/SchmidtCode/Good-Enough-Nexus/releases/latest

Good Enough Nexus keeps the current Nexus addon working while Valentine finishes
the full Nexus 1.20 refactor. This is a temporary, community-maintained bridge,
not a replacement for the official 1.20 work. Move back to the official release
when 1.20 is ready.

## Installation

1. Disable **Project Ebonhold Enhanced**. It conflicts with Nexus Saved Builds,
   wishlist creation, and automation.
2. Remove the existing `Interface\AddOns\Nexus` folder.
3. Download and extract the release ZIP.
4. Confirm the final path is `Interface\AddOns\Nexus\Nexus.toc`.
5. Start the game or use `/reload`.
6. Left-click the Nexus minimap button to show the HUD.

Keep the addon folder named `Nexus`.

## Set your Nexus HUD target

Open **Character Progression**, then **Echoes**. Above the Echo list, use the
blue **Nexus HUD target** menu to choose the wishlist you want to reach. During
a level 1 to 79 run, Nexus compares it with the current run. At level 80, first
choose the Ebonhold Saved Build you are using in the normal loadout menu.

That target controls:

- **Progress**, the wanted Echoes your current run or loadout already has.
- **Still Needed**, the wanted Echoes the current run or loadout is missing.
- **To Shed**, removable extras and off-wishlist Echoes.
- **Auto**, which uses the same wishlist for rolls, Freeze, Banish, and Reroll.

Saved Builds no longer guarantee previous Echoes or a specific board slot.
Offerings are random except for banished choices. If two wanted Echoes appear at
once, Nexus freezes one before taking the other when Freeze is available.

## Level 80 and orbs

The current Ebonhold level-80 flow is awkward. Nexus compares your HUD target
with the active Ebonhold Saved Build, and Ebonhold does not always refresh that
loadout immediately.

1. Activate the Saved Build you want to improve.
2. After a new level 1 to 80 run, switch away from that build and back once.
3. Use an Orb of Lost Memories to forget one unwanted Echo.
4. Roll until you get the wanted replacement.
5. Save over the same active Saved Build.

Nexus should then update Progress, Still Needed, and To Shed. If it still shows
the old Echoes, switch away and back, reopen Echoes, or use `/reload`.

## What still works

- Exact Echo wishlists and automatic roll selection
- Community build sharing
- Training Dummy and Lich King DPS records
- Exact-loadout leaderboards
- Missing Echo and tome tracking
- Saved Build and wishlist automation
- Existing `NexusDB` and `WishlistRealizerDB` data

## Support scope

The random-board behavior completed a full live run, and the release passed the
offline suite. Maintenance focuses on problems that block core addon behavior.
Larger redesigns should wait for Valentine's official 1.20 refactor.

Thanks to everyone who built and maintained Nexus, and to Valentine for continuing
the full 1.20 work.
