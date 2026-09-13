# Pre-release validation

Last updated: 2026-09-12

This file records stable release criteria and anonymized field evidence.
Sync-lab results remain in `docs/sync-lab-test.md`; implementation details and
raw reports remain in ignored local notes.

## Current release decision

Candidate preparation is in progress. Publishing remains contingent on the
live checks below. No tag, push, or public release is performed by this pass.

The updated candidate passes 148/148 Lua tests, 7/7 Node tests, static Lua 5.1
parsing, and diff checks. Its changed runtime files are installed locally with
matching hashes and a backup. The sync and HUD/safety changes are in separate
signed commits. The exact-commit archive remains pending until the final live
checks pass.
See [release-candidate-1.96.5.md](release-candidate-1.96.5.md) for the next tests.

- Keep version 1.96.5. The maintainer confirmed no 1.96.5 release package has
  been published. Development builds with that number do not require a bump.
- Canonical WLRB/WLD2 channel fallback now covers CW2 timeout, immediate failure,
  and deferred queue admission. An explicit false channel send retains the
  packet under the existing retry delay.
- Full exact relay evidence is selected by enhanced reconciliation, independent
  of whether direct transport is enabled. New peers can recover valid history
  over the channel even when the historical catalog build is absent.
- Direct chat whispers remain experimental and default OFF. Automatic Saved
  Build updates now default OFF for missing settings; existing explicit ON/OFF
  choices remain intact. Auto-lock stays OFF by default.
- Sync Lab is excluded from the player TOC/package. Developer source and tests
  remain available. Public documentation keeps anonymized aggregate evidence;
  detailed historical observations remain in ignored local notes.
- The real-state compatibility tests cover quiet old/new reconciliation despite
  generation/evidence differences, outgoing canonical WLD2, and a real owner
  upgrade followed by an unchanged enhanced pass.
- Later live CW2 delivery sent 384 direct bulk messages with 17 content ACKs and
  no failure in that sample. Receiver reload then produced two timeouts and two
  canonical channel fallbacks with no duplicate-row damage.
- Before publication: complete the disposable-slot safety check, default-off
  channel history check, and old/new coexistence. Wanted-Echo refresh passed.
  Full whisper failure and fanout validation remains necessary before claiming
  direct transport production-ready or enabling it by default.
- Quality-table consolidation and a larger Sync.lua module split are deferred.
  The explicitly requested safety/UI fixes are included in separate commits.

The maintainer explicitly approved including the level-80 sensing, Saved Build
safety control, imported-lock, tooltip, and clipping fixes in this release.
That is a deliberate exception to the 1.96 compatibility-line feature freeze;
the changes are additive, default-off where state-changing, and separately
tested. Direct transport remains an experimental default-off exception.

## v1.96.4 field reports reviewed

At the initial review, HUD and level-80 ownership code still matched v1.96.4.
The fixes and validation status for those reports are recorded below.

Follow-up received 2026-09-08: the respondent personally observed the list and
text cutoffs, unclear quality display, partial sync, imported-lock behavior,
missing build-preview tooltips, and stale HUD updates. They did not personally
lose a build. Their build-loss information came from guild members who have
since uninstalled Nexus, so no affected SavedVariables or diagnostic log is
currently available.

### Level-80 orb changes do not refresh the HUD

Status: passed live. A second live check found a quality-accounting bug when
Rare Unbridled Fury remained missing against the stored lower-quality sibling.
The new regression reproduces that exact Orb case. After the fix and reload,
the live HUD increased Progress, removed Unbridled Fury from Still Needed, and
kept the qualifying Rare variant out of To Shed.

At level 80 the HUD correctly reads `GetActiveEchoLoadout()`, but the polling
signature that invalidates the HUD only compares granted Echoes, locked Echoes,
and discovered Echoes. It does not compare the active level-80 loadout. The
level-80 fallback recompute is 300 seconds. That matches the report that the
display stays stale until the build is resaved or another event forces a
refresh. Existing tests cover the correct level-80 data source and tome/Echo
learning, but not an orb replacement changing the visible HUD while it is open.

First live retest: SourcePlayer used an orb at level 80 with the Nexus HUD open. Neither
Still Needed nor To Shed changed, although the Saved Build safety check passed
and the attached diagnostic reported no runtime errors. The first fix did cause
HUD recomputation, but each rebuild called `CurrentOwned()`, which replaced the
changed `GetGrantedPerks()` result with the unchanged persisted
`GetActiveEchoLoadout()` mirror. The changing board snapshots were therefore a
false positive for visible progress.

Revised fix: the adapter tracks which populated level-80 source changed most
recently. Initial login and a later Saved Build activation prefer
`GetActiveEchoLoadout()`. An Orb result that changes `GetGrantedPerks()` takes
precedence while the persisted mirror stays unchanged. The existing five-second
local fallback remains, and the existing board callback requests an immediate
comparison without increasing the automation or sync send rate. The regression
now reproduces the split source state and checks the visible Still Needed and To
Shed FontStrings, not only the panel model. A companion test proves a later
Saved Build activation takes precedence again.

Second live retest, 2026-09-09: after `/reload`, selecting a bad Echo during a
level-80 Orb run made it appear in To Shed without resaving or reopening Nexus.
This confirms the revised source selection and visible HUD repaint on the live
client. The matching Still Needed removal remains to be observed when a wanted
Echo is offered.

Final live retest, 2026-09-12: the already-owned Rare Unbridled Fury satisfied
the stored lower-quality target after `/reload`. Progress and Still Needed
updated correctly, and the Rare copy did not appear in To Shed.

### Truncated HUD text and tooltips

Status: fixed offline; visual in-game check required.

- `STILL NEEDED`, `TO SHED`, and `MISSING TOMES` tooltips stop after 25 items
  and display a `+N more` line.
- The HUD uses fixed-width FontStrings for its status, three card descriptions,
  recommendation, Still Needed, and To Shed text. The clipped screenshot is
  consistent with those limits, and the status/card/recommendation lines do not
  provide full-text hover fallbacks.
- Missing Echoes already include an exact quality breakdown in the Still Needed
  tooltip when the progress model supplies it. The tooltip renders those lines
  in fixed gray rather than Common, Uncommon, Rare, and Epic colors.
- The two-line visible Still Needed summary deliberately strips the parenthesized
  quality breakdown. A user who does not discover or cannot read the capped
  tooltip therefore has no visible indication of the requested quality.

Fix: visible Still Needed and To Shed entries retain their exact quality and use
WoW item-quality colors. Still Needed, To Shed, Missing Tomes, and To Lock no
longer stop at 25 entries. Status, card, and recommendation lines expose full
text on hover. The UI regression covers 30 entries and each hover target. A
live screen-edge check remains because the headless UI cannot measure WoW's
tooltip clamping.

### Auto button disappears

Status: not reproduced.

The button exists, but the layout deliberately hides it when Nexus sees no
associated build, or when the build is complete at level 80 and no live roll is
visible. It should remain visible during an active roll even at level 80. The
report could be a bad visibility condition, stale panel state, or a footer that
is off-screen. `/nexus auto` uses the same session switch and can separate a
missing button from broken automation.

Release impact: reproduce the exact state before changing the condition.

### Imported builds do not lock their locked Echoes

Status: full code path proven offline; live server timing remains.

The current importer carries locked Echoes into the Wishlist Editor as designed
locked slots. Saving commits those targets. Actual `LockPerk` and `UnlockPerk`
automation is controlled by a separate "Automate locked Echo slots" checkbox
that defaults off. A user can therefore import a build, see no locking attempt,
and reasonably conclude that import lost the lock intent. Existing tests prove
that a locked imported entry reaches the editor draft and that the checkbox
requests recomputation. They do not prove the full import, save, association,
owned-Echo, and server lock sequence.

The new regression drives the visible editor Save button and confirmation,
uploads the ordinary wishlist separately from the locked-slot design, models
server readback, and runs Main automation through `GameAdapter.LockPerk`. The
owned imported target produces exactly one real service call. Live testing must
still confirm Ebonhold's designed-wishlist readback and lock acknowledgement.

### Build preview Echoes have no tooltips

Status: fixed offline; visual in-game check required.

Normal and locked preview icons now have mouse hit regions. Hovering opens the
spell tooltip and adds quality, stack count, and locked-state context. The UI
test covers both icon groups.

### v1.96.4 sync was partial or misleading

Status: v1.96.4 report is superseded by the current work, but live full-history
convergence remains open.

The current branch has extensive reconciliation, evidence, direct-transfer,
ACK, fallback, and diagnostic changes after v1.96.4. Recent paired tests prove
reliable delivery for eligible records. The offline mixed-version and quiet
convergence matrix now passes. Do not claim full leaderboard convergence until
the live matrix distinguishes transport delivery from unsendable evidence.

### Builds reported as auto-deleted

Status: unproven, high severity, release blocker.

New or missing settings now default `autoSave` to false. Existing explicit true
settings remain true. When enabled, after a completed observed run passes the
save gate, it overwrites the server-confirmed active Saved Build slot and aligns
that slot's name with the associated wishlist. The HUD settings menu now exposes
`Automatic Saved Build updates: ON/OFF`, and integration coverage proves Off
blocks even a dominating completed run from calling the save API. A renamed or overwritten active
slot may be described as a deleted build, but a separate reconciliation path
also removes an imported Nexus view when the corresponding server slot is no
longer present. We must distinguish these cases before deciding on a fix:

1. A Project Ebonhold Saved Build slot was removed, overwritten, or renamed.
2. A Nexus My Account or Community Builds entry disappeared while the server
   Saved Build remained intact.
3. A wishlist or its association disappeared.

Do not dismiss this as user confusion. Multiple independent reports of lost
setups make it unsafe to release without a disposable-slot reproduction and a
user-accessible way to disable automatic saving.

Follow-up requested from the reporting user: identify whether the missing item
was a Project Ebonhold Saved Build, a Nexus build entry, or a wishlist; whether
its old slot was renamed or overwritten; and what action immediately preceded
the loss. Keep this item open until that answer or a disposable-slot reproduction
is available.

The latest respondent explicitly did not experience the loss and saved the same
build into every slot as a precaution. The affected guild members reportedly
uninstalled Nexus and are unlikely to reproduce it. This lowers the quality of
the available evidence, not the possible severity. Release safety must come from
our own disposable-slot test. The visible auto-save opt-out is now implemented.

## Required manual tests

### 1. Build-loss test on a disposable character

1. Log out and back up both Nexus SavedVariables files.
2. Create two disposable server Saved Builds with visibly different Echoes,
   named `NX-KEEP` and `NX-AUTO`. Record every slot, its name, Echoes, active
   slot, Nexus build entries, wishlist, and association.
3. Enable Automatic Saved Build updates only for this disposable test.
   Activate `NX-AUTO`, associate its wishlist, and complete one orb/run flow
   that Nexus considers an improvement. Do not manually resave or rename it.
4. Capture `/nexus log` immediately before the run and immediately after Nexus
   reports a save result. Recheck all three kinds of data listed above.
5. Open the Nexus HUD settings menu and set `Automatic Saved Build updates` to
   `OFF`. Repeat the same run. Neither server Saved Build should change in this
   pass. Re-enable it from the same menu after testing if desired.

Stop the test and preserve SavedVariables if `NX-KEEP` changes or any unrelated
slot disappears.

### 2. Orb live-refresh test

1. At level 80, activate a Saved Build with an associated wishlist. Open the
   Nexus HUD and record Still Needed and To Shed.
2. Replace one Echo with an orb. Do not resave, reload, reopen the UI, or run a
   Nexus command. Wait ten seconds.
3. The visible counts, Echo names, and qualities should update. If they do not,
   capture the full panel and `/nexus log`, then resave once and record whether
   that alone refreshes it.

### 3. Missing Auto button test

1. Capture the whole Nexus panel, including its bottom edge, and record level,
   active server slot, associated wishlist, whether an Echo offering is visible,
   and whether Builds and Leaderboard buttons are visible.
2. Run `/nexus auto` twice. Record the chat responses and whether automation
   changes even though the button is absent.
3. Repeat once during a live roll below level 80 and once on the level-80 orb
   view. This separates panel placement from the visibility predicate.

### 4. Text and quality presentation test after a fix

Use a wishlist with more than 25 missing entries and several exact qualities.
Hover Still Needed, To Shed, and Missing Tomes near the top and bottom of the
screen. Confirm every entry is reachable, the tooltip remains on-screen, each
quality uses the intended color, and every clipped HUD line has a full-text
hover fallback.

### 5. Imported locked-Echo test

1. On a disposable character, own one unlocked Echo that is marked locked in a
   known import. Keep at least one permanent lock slot free.
2. Import the build into the Nexus Wishlist Editor. Verify the Echo appears in
   the designed locked-slot row before saving.
3. Save and associate the wishlist. With "Automate locked Echo slots" off,
   verify Nexus makes no lock write and clearly reports that automation is off.
4. Turn the setting on. Verify Nexus attempts exactly one safe lock write, then
   confirms the server state without unlocking an unrelated Echo.
5. Reload and verify the committed lock target and association survive.

## Review checks run

The 2026-09-09 pre-release fix pass ran 144 Lua programs and all passed on the
second complete run. The first run found one brittle menu-index assertion after
the new auto-save item shifted later entries; the test now locates the action by
its label and passes. All seven Node tests pass, including the release packager.
`node tools/crap-report.js --static --json` parsed the production Lua using the
CI-equivalent Lua 5.1 parser, and `git diff --check` passes.

New red-to-green regressions cover level-80 orb refresh, the visible auto-save
control and hard save guard, full quality/list/clipped-text HUD behavior, normal
and locked build-preview tooltips, imported locked Echoes through `LockPerk`,
direct inactivity lifetime, fallback bounds, and the explicit mixed-version
route matrix.

The revised level-80 source regression first failed twice with the live symptom,
then passed after source arbitration was added. An attempted one-second granted
poll caused three existing integration decision failures, so it was removed.
The conservative five-second fallback and event-driven prompt pass all 144 Lua
programs, all seven Node tests, static Lua 5.1 parsing, and `git diff --check`.
