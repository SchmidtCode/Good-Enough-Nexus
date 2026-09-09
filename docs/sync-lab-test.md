# Two-character leaderboard diagnostic test

Purpose: determine which of a peer's historical DPS records can be relayed,
which fail outbound validation, and which arrive but fail dependency recovery
or receiver validation. This is an explicit development tool, not a faster
production sync mode.

Reports marked `diagnostics=3 transport=CW2` use a pipe-free bulk envelope.
The lab requests `WLTQ|sender|target|lab-id|count|CW2`, acknowledged by the
unchanged four-field `WLTR`. Older lab receivers reject CW2 and time out safely.
Both clients must load this update. Normal production capabilities are unchanged.

The envelope is `WLTB:` followed by the canonical WLRB/WLD2 packet with
literal `~` encoded as `~0` and each pipe encoded as `~1`. Both direct and
channel-fallback bulk use it only during an explicitly negotiated lab session.
The decoder enforces the packet limit, peer, escape grammar and bulk-only scope;
the reconstructed packet still goes through normal validation. Chat filters
recognize these envelopes only in the armed lab. Chunk budgeting includes the
envelope overhead. ACKs still correlate the unchanged canonical bytes.
Control/handshake/ACK messages stay on the existing channel in their old formats.
Unknown clients ignore the new envelope. This does not bypass evidence checks
or deletion floors, and is not enabled for normal reconciliation.

Reports retain send exceptions, transport, chunk number,
and escaped byte length separately from the rolling events. After three
failures of the same channel packet, the lab stops and saves the report.
This is a failed test, not successful delivery. Normal sync retry behavior is
unchanged. If the lab stops this way, stop the other client too and export both
reports. Do not clear leaderboards or repeat the run before examining the error.
Updating an already installed lab to diagnostics 3 needs `/reload` on both
clients, not a full restart.

## Run once on Wrand and Daradorla

Restart both game clients after installing this build, which adds a new Lua
module. Stay resting in a city and out of combat. Do not run ordinary sync or
fight a dummy during this test.

On **Daradorla** first:

```text
/nexus syncmode manual
/nexuslab receive Wrand
```

On **Wrand** next, within about a minute:

```text
/nexus syncmode manual
/nexuslab send Daradorla 5
```

The request and reply require both endpoints to be locally armed. The test
temporarily enables direct sync, cancels queued normal sync work, and ignores
normal mesh requests. Stored builds and DPS records are retained. Each client
continues using the existing channel and normal 1.10-second sender pacing.
The test stops after ten minutes, on unsafe gameplay context, or on
`/nexuslab stop`. Direct transport is enabled only for the runtime lab session;
the saved direct setting is untouched. Reloading also ends the lab session.

After the sender says its steps completed, or after ten minutes, run this on
each client:

```text
/nexuslab log
```

Copy the full report from the log window. Send Daradorla's report first and
Wrand's second. The bounded report is saved in `NexusDB.syncLabReport`, so it
survives normal logout/reload. `/nexuslab normal` switches the Sync log view
back to ordinary diagnostics.

## What it tests

Wrand inventories up to 500 raw stored character-best rows using the same
record construction as normal reconciliation. It groups validation failures,
with twenty examples including class, duration, timestamp, level and Echo
availability. It selects up to five eligible third-party records, alternating
Dummy and Lich King when possible. Selection does not imply these records are
missing on Daradorla; an idempotent result is valuable evidence.

For each selected record, sequentially:

1. Send the normal compact relay directly, before providing its build.
2. Send the catalog build referenced by that record directly, if available.
3. Send the compact relay again.
4. Send the fully validated relay with its exact Echo evidence directly.
5. Repeat that full relay to test idempotent acceptance.
6. Send the compact relay over the channel as a compatibility comparison.

Full-evidence serialization is diagnostic-only. It keeps the existing v6 relay
shape and strict validation. Received relay evidence remains unverified. No
record is made valid by the test. New request codes `WLTQ` and `WLTR` are
optional channel control messages; old clients ignore them. Legacy packet
counts and formats remain unchanged.

The inventory can show why a visible stored row cannot be sent. `STEP` and
`ADMIT` identify outgoing tests. `RESULT` gives receiver acceptance or its
rejection reason. `ACK`, timeouts and fallbacks show delivery outcomes.
`PROGRESS` records queue and deferred counts every fifteen seconds. The most
recent 240 bounded event lines are retained; `dropped` reports overwritten
events. Encoded build bodies are excluded.

## Offline verification

`luajit tests/run_sync_lab.lua` runs two independent client environments with
the real sync, validation and capture modules. Five third-party historical
records reach the receiver as relayed evidence. A deliberately lost ACK causes
fallback. The test also checks duplicate acceptance, pacing, packet size,
wrong-peer/unarmed rejection, no-peer timeout, unsafe-context stop and retained
reports. It does not establish live Ebonhold convergence or bulk-whisper safety.
The receiver has a deletion floor that excludes the transmitted catalog builds;
full evidence still delivers all five records. One record has 63 Echoes. The
chat stub rejects legacy pipe-bearing bulk to exercise the negotiated envelope.

## Live test journal

This section records paired Ebonhold results so later work does not depend on
chat history. Detailed implementation decisions remain in
`tmp/sync-architecture-implementation-notes.md`. The production validation
checklist remains in `docs/sync-direct-ebonhold-validation.md`.

### 2026-09-08, normal CW2 reconciliation after long-response fixes

- Sender: Wrand. Recipient: Daradorla. Both reported Nexus v1.96.5 with CW2
  enabled. This was normal reconciliation, not the five-record lab script.
- Wrand transmitted 375 direct bulk chunks and Daradorla received 375. Wrand
  completed 19 logical transfers and received 19 content-matched ACKs. Neither
  endpoint recorded a direct timeout, API failure, or channel fallback.
- Transfer duration averaged 158.4 seconds and peaked at 210.0 seconds. The
  queue and send cadence remained at the existing conservative limits.
- Daradorla's board grew from the previous 70 Dummy and 40 Lich King rows to
  80 Dummy and 48 Lich King rows. The 18-row gain is close to the 19 completed
  logical transfers. Sixteen received relay records were accepted, one direct
  record was accepted, and 22 equivalent or weaker records were safe no-ops.
- No partial DPS transfer remained at capture time. The cumulative partial
  expiry counter was three on Daradorla and six on Wrand, so a clean before and
  after sample is still needed to attribute any new expiry to this run.
- Daradorla still had 46 deferred records waiting on exact-build recovery.
  Its last rejection was `legacy-build-hash-mismatch`. Wrand reported 543
  outbound validation failures and 1,869 queue-admission failures across all
  mesh work. These counters are cumulative and include requests from other
  peers, but they explain why Wrand's 256 visible rows are not all eligible for
  this direct response.
- Conclusion: CW2 delivery, reconstruction, idempotence, and ACK correlation
  worked for this sample. The remaining board-count gap is now primarily an
  evidence eligibility and dependency-recovery question, not observed direct
  packet loss. Do not weaken validation to force old rows through.
