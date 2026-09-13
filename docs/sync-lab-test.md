# Sync lab and release validation

The player package excludes `core/SyncLab.lua`. Normal synchronization and
its diagnostics remain available through `/nexus sync` and `/nexus log`.
The lab source and its automated tests remain in the development repository.

## Developer lab

To use the lab in a development installation, add `core\SyncLab.lua` to the
local development TOC after `core\DpsCapture.lua`, then restart both clients.
Do not include that TOC edit in a player package.

Both characters must be resting and out of combat. Replace SourcePlayer and
ReceiverPlayer with their actual names. On the receiver:

```text
/nexus syncmode manual
/nexuslab receive SourcePlayer
```

On the source within one minute:

```text
/nexus syncmode manual
/nexuslab send ReceiverPlayer 5
```

The lab pauses normal mesh work, uses the existing 1.10-second pace, and
selects up to five eligible historical third-party records. It compares compact
and full evidence, build dependencies, replay, and channel delivery. It never
turns invalid evidence into valid evidence or promotes a relay to owner status.
A ten-minute deadline, gameplay-context checks, and `/nexuslab stop` bound it.

Use `/nexuslab log` on each client after completion. Bounded reports survive
logout in `NexusDB.syncLabReport`. Keep detailed reports in local ignored notes.
`/nexuslab normal` returns the log view to normal diagnostics.

## Wire behavior

The lab uses `WLTQ|sender|target|lab-id|count|CW2` and
`WLTR|sender|target|lab-id` on the channel. Ordinary current-client negotiation
uses WLXQ and WLRQ. Unknown clients safely ignore the optional lab codes.

Direct bulk wraps canonical WLRB/WLD2 in `WLTB:`, escaping tilde as `~0` and
pipe as `~1`. Channel fallback replays canonical WLRB/WLD2 with the established
channel escaping. ACK digests refer to canonical contents, independent of route.
Full exact Echo evidence is available to enhanced channel and whisper requests.

Three repeated failures of a channel packet stop the lab and retain the error.
This means delivery failed. Normal reconciliation retains failed channel sends
for paced retry.

## Recorded live evidence

A same-faction normal reconciliation run on 2026-09-08 delivered 375 of 375
direct bulk chunks and received 19 of 19 content ACKs. Neither endpoint reported
a direct timeout, API failure, or fallback in that sample. The receiver gained
18 leaderboard rows. Transfer duration averaged 158.4 seconds and peaked at
210.0 seconds. This proves successful delivery in that sample, not complete
historical convergence or the behavior of failed transfers.

The later level-80 orb retest confirmed that selecting an unwanted Echo updated
To Shed automatically. Saved Build safety, the matching Still Needed update,
and the remaining native transport cases require separate observations.

## Offline coverage

`luajit tests/run_sync_lab.lua` uses independent client environments and the
real sync, validation, and DPS modules. It exercises five historical records,
a deleted-build floor, a 63-Echo record, lost ACK, idempotent replay, bounds,
normal CW2 reconciliation, and default-off enhanced channel reconciliation.

`luajit tests/run_sync_v1_19_5_fixture.lua` checks frozen legacy packet and
digest facts, actual outgoing owner WLD2 chunks, and repeated quiet passes over
real saved state whose generation/provenance differs.

Current release status and remaining manual checks are maintained in
[pre-release-validation.md](pre-release-validation.md) and
[sync-direct-ebonhold-validation.md](sync-direct-ebonhold-validation.md).
# Live channel failure follow-up, 2026-09-11

## Confirmed trigger and candidate fix

Probe v2 isolated lowercase `n` immediately after the final pipe separator:
firstByte=110, Base64 alphabet valid, first-only failed, replacing the first
byte or shifting the body passed. Removing the final separator also passed.
The candidate now shifts chunk boundaries backwards to avoid leading `n`, for
both WLRB and WLD2. It does not replace any data bytes, append fields, wrap
channel packets, increase pacing, or change validation. Direct transfers use
the same chunk plan so their canonical channel fallback remains safe.
An input that cannot be safely partitioned under existing limits fails closed.

Retest on both clients: reload, set manual mode and direct off, run sync once.
Do not arm the diagnostic probe. After five minutes export both syncdebug logs.
Expect zero channel send failures and check accepted DPS/partial-transfer
progress. Full convergence is not yet proven, especially with large queues.
SavedVariables must not be cleared. Native validation passed: both clients had
zero send failures, completed WLD2 transfers, and accepted new relayed rows.
The temporary probe was then removed from production code.

## Direct success after boundary fix

Two current clients ran manual sync with CW1/CW2 enabled for about five minutes.
They exchanged 384 direct bulk messages and completed 17 content-matched ACKs.
There were zero direct timeouts, immediate API failures, fallbacks, channel send
failures, and pending fallbacks. Direct transfer durations averaged 126.8s on
one client and 115.4s on the other, with maxima near 206s. The smaller library
accepted five relayed DPS records and moved from 78/49 to 79/51 Dummy/LK.

The high `outbound validation/queue fail` queue component reflected repeated
bounded backpressure retries while logical transfers occupied the direct lane.
Responder bucket work remained pending and the event log showed later records
starting after content ACKs freed slots. It did not demonstrate dropped state.
Full historical convergence still needs a longer quiet run. Ordinary chat
WHISPER payloads remain visible on this server, so direct stays default off.

Next live case: reload the receiver during an active direct WLD2 transfer. The
sender must record an ACK timeout and a channel fallback for that logical object;
the receiver must accept the canonical fallback idempotently after reconnecting.
Do not use visible chat whispers as the trigger. A later attempt showed active
direct TX/RX and content ACKs while no protocol whispers appeared in chat. On
the receiver, poll `Nexus.Sync.Stats().directBulkRx`; reload after it rises by at
least five packets. Hidden protocol chat is desirable and may depend on the
client's chat filters or event handling.

The live reload case produced 3 ACK timeouts and 3 fallbacks on the sender,
zero API/channel failures, zero pending ACK/fallback entries, and continued
idempotent processing on the receiver. It also exposed scheduler ordering:
after the receiver opened a new request, fresh direct packets could run before
canonical fallback packets already moved to the ordinary channel queue. The
fix sends fallback batches through the existing bounded priority-channel queue.
This changes scheduling only. Canonical WLRB/WLD2 bytes, channel escaping,
validation, pacing, and all queue limits remain unchanged.

The post-fix reload retest passed. The sender recorded 2 ACK timeouts and 2
fallbacks, sent 77 channel bulk packets and 130 direct packets, and ended with
zero pending ACK/fallback work and zero channel/API send failures. Event order
showed canonical channel WLRB recovery chunks completing before direct WLD2
traffic resumed. The receiver recorded 44 idempotent WLD2 no-ops, completed
fallback build transfers, and produced no duplicate public rows. Reloading
earlier while direct whispers were active gave a clean lost-chunk test.

Subsequent logs identified `Invalid escape code in chat message` for a WLD2
packet with 236 raw / 240 escaped bytes. Manual short and 240-byte probes with
`A` or `H` following a doubled pipe all returned success. These do not reproduce
the failed packet and do not establish that channel encoding is generally safe.

The temporary probe used unknown-code NXEP messages to isolate the native
failure without creating replicated records. It reported only lengths and byte
classes, never payload bodies. It was removed after the candidate fix passed
the native retest.

Both current clients connected with direct transport off, but neither accepted
new DPS records. Receiver remained at 74 Dummy / 48 Lich King. Both repeatedly
reported channel SendChatMessage failure and retained the queue head; queue peaks
were 8,185 and 8,192 packets. This is not a passing convergence result.

Added bounded normal-mode failure diagnostics with exception/refusal, packet
type, queue lane, raw/wire lengths, and sanitized error text. Pacing, queue
retention, validation, and transport selection are unchanged. The API cause is
still unknown until a live retest. Regression covers false return and exception.

Next live check: reload both, set manual mode and direct off, then run sync on
both. Manual idle may be disconnected before the sync command. After 30-60
seconds export syncdebug from both, including `last channel failure`.
