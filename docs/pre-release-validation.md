# Pre-release validation log

Last updated: 2026-09-08

This file records release blockers and field reports that should survive chat
history. Sync-lab results remain in `docs/sync-lab-test.md`; implementation
details remain in `tmp/sync-architecture-implementation-notes.md`.

## Current release decision

Do not publish the current worktree yet.

- The offline gate passed 138 Lua programs, seven JavaScript tests, packaging,
  static analysis, and `git diff --check` in the last complete run.
- A live normal CW2 run delivered all 375 direct chunks and received 19 of 19
  content-bound ACKs with no timeout, API failure, or fallback. Daradorla gained
  18 leaderboard rows. The remaining row-count gap is mainly unsendable or
  deferred evidence, not observed packet loss.
- The tested state is split between staged, unstaged, and untracked files.
  `core/SyncLab.lua` is referenced by `Nexus.toc` but is still untracked, so a
  commit or tag made carelessly would omit required code.
- The candidate still identifies itself as 1.96.5 even though it contains
  substantial work after the published 1.96.5 commit. Give a public package a
  successor version.
- Direct-transfer admission time is also used as its absolute expiry time. A
  healthy transfer waiting behind a large paced queue can therefore reach the
  600-second limit before its last chunk is sent and fall back unnecessarily.
- Channel fallbacks expire, but the fallback collection still lacks the hard
  global and per-peer count bounds required by the sync architecture document.
- The live compatibility matrix is incomplete. Old/new combinations, direct
  disabled, lost ACK with channel fallback, reload or disconnect mid-transfer,
  a third uninvolved peer, cross-faction behavior, and quiet full convergence
  still need live Project Ebonhold checks.

## v1.96.4 field reports reviewed

The HUD and level-80 ownership code did not change between the v1.96.4 tag and
the current candidate, so these reports still apply to the release candidate.

Follow-up received 2026-09-08: the respondent personally observed the list and
text cutoffs, unclear quality display, partial sync, imported-lock behavior,
missing build-preview tooltips, and stale HUD updates. They did not personally
lose a build. Their build-loss information came from guild members who have
since uninstalled Nexus, so no affected SavedVariables or diagnostic log is
currently available.

### Level-80 orb changes do not refresh the HUD

Status: confirmed live on v1.96.5 on 2026-09-08.

At level 80 the HUD correctly reads `GetActiveEchoLoadout()`, but the polling
signature that invalidates the HUD only compares granted Echoes, locked Echoes,
and discovered Echoes. It does not compare the active level-80 loadout. The
level-80 fallback recompute is 300 seconds. That matches the report that the
display stays stale until the build is resaved or another event forces a
refresh. Existing tests cover the correct level-80 data source and tome/Echo
learning, but not an orb replacement changing the visible HUD while it is open.

Live result: Wrand used an orb at level 80 with the Nexus HUD open. The To Shed
list did not update automatically. The attached diagnostic reported no runtime
errors. It does not log an orb mutation event, which is consistent with the
missing active-loadout dirty signal rather than a failed HUD render. This is now
a reproduction, not merely a field-report hypothesis.

Release impact: fix and add a focused regression test before release.

### Truncated HUD text and tooltips

Status: confirmed in current code.

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

Release impact: the clipping is a usability defect. Removing the 25-item cap
and adding quality colors are bounded presentation changes, but long tooltips
must be tested against screen height instead of simply becoming unbounded.

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

Status: intended data path exists, but the user-facing workflow and end-to-end
behavior are not proven.

The current importer carries locked Echoes into the Wishlist Editor as designed
locked slots. Saving commits those targets. Actual `LockPerk` and `UnlockPerk`
automation is controlled by a separate "Automate locked Echo slots" checkbox
that defaults off. A user can therefore import a build, see no locking attempt,
and reasonably conclude that import lost the lock intent. Existing tests prove
that a locked imported entry reaches the editor draft and that the checkbox
requests recomputation. They do not prove the full import, save, association,
owned-Echo, and server lock sequence.

Release impact: add an end-to-end regression and make the import result state
plainly whether locked slots were imported and whether automatic locking is off.

### Build preview Echoes have no tooltips

Status: confirmed in current code.

The build detail preview creates its normal and locked Echo icons as textures.
It does not create mouse-enabled hit frames or attach `OnEnter` handlers to the
icons, so hovering cannot identify an Echo. Add spell tooltips to both icon
groups and cover at least one normal and one locked Echo in a UI test.

### v1.96.4 sync was partial or misleading

Status: credible for v1.96.4; superseded by the current experimental work but
not yet closed for release.

The current branch has extensive reconciliation, evidence, direct-transfer,
ACK, fallback, and diagnostic changes after v1.96.4. Recent paired tests prove
reliable delivery for eligible records, but not full leaderboard convergence.
Do not use the newer transport success to claim the old report was fixed until
the remaining compatibility matrix and quiet-convergence tests pass.

### Builds reported as auto-deleted

Status: unproven, high severity, release blocker.

Nexus defaults `autoSave` to true. After a completed observed run passes the
save gate, it overwrites the server-confirmed active Saved Build slot and aligns
that slot's name with the associated wishlist. There is no normal user-facing
control for the existing `autoSave` setting. A renamed or overwritten active
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
our own disposable-slot test and a visible auto-save opt-out.

## Required manual tests

### 1. Build-loss test on a disposable character

1. Log out and back up both Nexus SavedVariables files.
2. Create two disposable server Saved Builds with visibly different Echoes,
   named `NX-KEEP` and `NX-AUTO`. Record every slot, its name, Echoes, active
   slot, Nexus build entries, wishlist, and association.
3. Activate `NX-AUTO`, associate its wishlist, and complete one orb/run flow
   that Nexus considers an improvement. Do not manually resave or rename it.
4. Capture `/nexus log` immediately before the run and immediately after Nexus
   reports a save result. Recheck all three kinds of data listed above.
5. Repeat after running this on the test character:

   `/run NexusDB.settings.autoSave=false; print("Nexus autoSave", tostring(NexusDB.settings.autoSave))`

   Neither server Saved Build should change in this pass. Re-enable it after
   testing with the same command using `true` if desired.

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

The focused HUD, panel, level-80 ownership, overlay, and build-lifecycle tests
all passed on 2026-09-08. Eleven Lua programs were run, followed by
`git diff --check`. These passing tests show the current coverage gap: none
changes `GetActiveEchoLoadout()` after initial render and asserts that an open
level-80 HUD refreshes without another event. Add that exact red-capable test
before fixing the orb defect.
