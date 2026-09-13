# 1.96.5 release candidate

Prepared 2026-09-11 from base
`be1168e3598608bc945a673548a00678aaac1efe` on `codex/sync-architecture`.
Version 1.96.5 is retained because no player release with this number has been
published. The generated package manifest records its exact commit and SHA-256.

The maintainer approved bundling the requested level-80 sensing, Saved Build
safety control, imported-lock, tooltip, and clipping fixes with the sync work as
an explicit exception to the 1.96 compatibility-line feature freeze. Keep them
as separate signed commits so the scope remains reviewable.

## Verified changes

- Failed or unacknowledged CW2 objects replay canonical WLRB/WLD2 over
  `wrbuildssync`, including deferred fallback. Explicit false channel sends
  retain the packet with the existing paced retry delay.
- Full exact relay evidence follows enhanced request metadata independently of
  transport. Capable clients recover valid history with absent catalog builds
  over either channel or whisper. Unknown peers retain legacy behavior.
- Owner evidence upgrades equivalent relay evidence; relay never downgrades an
  equivalent owner row. Relays remain visibly unverified on either transport.
- Legacy digests match v1.19.5 and ignore generation/provenance. Enhanced digests
  track both. Tests now use real saved state and actual outgoing owner packets.
- Orb changes use the latest live Echo source. HUD and preview tooltips expose
  quality/full text. HUD progress now follows the picker's asymmetric quality
  rule, so a qualifying better sibling satisfies a lower stored target but
  never the reverse.
  Imported locked-Echo intent has an offline editor-to-service regression;
  actual locking remains separately opt-in.
- Direct chat whispers and automatic locking default OFF. Automatic Saved Build
  updates now default OFF for missing settings. Existing explicit preferences
  survive. The HUD menu exposes the automatic-save control.
- SyncLab is excluded from the player TOC/archive; developer source/tests remain.
  Detailed live reports stay in ignored local notes; public results are anonymous.

This preparation pass adds no packet codes. Existing optional controls are
`WLXQ|sender|requestId|1|capability|enhancedDpsHash`,
`WLAK|sender|requestId|B-or-D|logicalId`, and
`WLA2|sender|requestId|B-or-D|logicalId|contentDigest`. Capabilities are C0, CW1,
and CW2. Only direct CW2 bulk uses WLTB encoding. Legacy field counts are intact.
Control, claims, ACKs and spontaneous owner publications remain on the channel.
There is no addon-message WHISPER dependency or increased send rate.

## Offline validation

All 148 `tests/run_*.lua` programs passed under LuaJIT. All seven
`tests/run-*.js` programs passed under Node. Static Lua 5.1 parsing with
`node tools/crap-report.js --static --json` and `git diff --check` passed.

Focused checks include:

```text
luajit tests/run_sync_direct_transport.lua
luajit tests/run_sync_v1_19_5_fixture.lua
luajit tests/run_sync_lab.lua
luajit tests/run_sync_compatibility_matrix.lua
luajit tests/run_release_defaults.lua
luajit tests/run_integration.lua
luajit tests/run_store_additive_migrations.lua
luajit tests/run_sync_fanout_harness.lua
node tests/run-release-package.js
```

The 100-peer/200-chunk model gives 19,800 channel bulk receives versus 200 direct
receives. At 250 peers the comparison is 49,800 versus 200. Uninvolved peers
receive zero direct bulk events. These are simulated results.

Live same-faction CW2 testing later delivered 384 direct bulk messages with 17
content-matched ACKs and no timeout, API failure, or fallback in that sample.
A receiver-reload test then produced two timeouts and two canonical channel
fallbacks, drained pending work, and retained idempotent rows. Live level-80
tests passed both unwanted-Echo To Shed refresh and qualifying wanted-Echo
Progress/Still Needed refresh. Full historical convergence and cross-faction
cases remain open.

## Before publishing

1. Restart both clients with the candidate. On each run `/nexus syncmode manual`,
   `/nexus syncdirect off`, then `/nexus sync` on BOTH clients. Manual mode is
   disconnected while idle; the sync command opens the session. Wait ten seconds
   then run `/nexus syncdebug` and check `connected : true`.
2. Keep both resting for five to ten
   minutes; export both Sync diagnostics. Direct counters must stay zero while
   channel counters and eligible history progress. Do not clear existing data.
3. Check Automatic Saved Build updates in the HUD menu. Existing users can still
   have ON. On disposable slots `NX-KEEP` and `NX-AUTO`, verify OFF prevents an
   otherwise save-eligible run from changing either slot. With ON, only the
   confirmed active `NX-AUTO` may update. An unrelated slot must remain intact.
4. Level-80 wanted and unwanted Echo refresh passed live. Check preview
   tooltips and full clipped text near screen edges on the packaged build.
5. With a real v1.19.5 client present, check for safe coexistence with no errors
   or response flood. The maintainer does not require receipt of all unsupported
   old history. Equivalent legacy state should reach quiet reconciliation.

## Before treating direct transport as production-ready

Enable `/nexus syncdirect on` on both current clients and request once on the
receiver. Compare direct TX/RX and content ACKs. Protocol whispers should stay
hidden and normal player whispers remain visible.

Repeat with receiver reload/logout mid-transfer and a lost completion ACK.
Check bounded fallback and idempotent acceptance. A third client's uninvolved
bulk counter must not increase during successful direct delivery. Check offline
and ignored targets, qualified names where applicable, and server warnings at
sustained 1/10/100/200-message loads. Cross-faction requires its own validation
before advertising support.

Full 200-record convergence and private-server throttling remain unproven.
Direct stays default off. The build-loss report remains open until the
disposable-slot check passes. Quality-table consolidation and a larger Sync.lua
module split are deferred.

The HUD's top-left settings menu exposes the persistent
`Direct sync (experimental): ON/OFF` control. It calls the same setter as the
`/nexus syncdirect` command; direct remains default off.

## Package provenance

The existing packager archives only the TOC and listed runtime files from an
exact commit. It produces the ZIP, SHA-256 checksum and commit/tree manifest.
The release workflow requires the tag at the main-branch tip and creates an
unpublished prerelease. Local preparation does not tag, push, or publish.
