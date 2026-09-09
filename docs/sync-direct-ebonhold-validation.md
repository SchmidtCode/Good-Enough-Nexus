# Project Ebonhold sync validation

Direct bulk responses are experimental and default off. Enable them per client
with `/nexus syncdirect on`; disable them with `/nexus syncdirect off`.

## CW2 normal reconciliation candidate

Enabled clients now advertise `CW2` in the existing six-field WLXQ extension.
CW2 accepts the pipe-free `WLTB:` envelope tested in NexusLab. Literal tildes
become `~0`, pipes become `~1`. Decoding reconstructs the original WLRB/WLD2
before normal sender, evidence and chunk validation. An active CW2 request
is required to admit a responder. Once that responder delivers a canonical,
sender-matched CW2 packet, a bounded continuation lease keeps a long response
admitted for up to four hours, expiring after 30 seconds idle. The lease
retains the original request ID for ACK correlation and cannot be created or
refreshed by malformed, unsolicited, CW1, or legacy packets.

The responder keeps active CW2 reconciliation work under the same four-hour
hard limit. This prevents the legacy five-minute pending-work cutoff from
restarting a large mismatched bucket before its later records are reached.
CW1, C0, unknown, and legacy requests retain the five-minute limit. All routes
retain the existing 30-second inactivity expiry and transport pacing.
CW2 responders send full exact evidence for relayed DPS, so a removed catalog
build does not by itself prevent acceptance. Missing evidence is still rejected.

Envelope selection is retained on each queued transfer and channel fallback;
it does not affect concurrent legacy packets. ACKs hash canonical packet bodies.
Control, discovery, claims, ACKs and spontaneous owner publication remain on
their unchanged legacy paths. CW1 requests still select CW1; unknown clients
ignore CW2 and process unchanged WLRQ. Both senders and receivers must opt in
for normal CW2 direct delivery. This remains experimental, not a release.

For the next paired test: reload both clients, set manual mode and direct on
on both, then run `/nexus sync` on the recipient. Stay resting. After ten
minutes export `/nexus syncdebug` from both, using `/nexuslab normal` first if
the log viewer is still showing the saved lab report. Do not clear records.
The full catalog may take longer than ten minutes at unchanged pacing; this
is a progress sample, not a promised completion deadline.

Live checks still required:

- Run same-faction first, then cross-faction if Ebonhold permits it. Repeat with
  two characters on one account and on separate accounts where practical.
- Test ordinary character names and realm-qualified sender/target names. Verify
  an offline target and a target that ignores the sender both cause bounded ACK
  timeout and channel fallback.
- Verify old to old, old to new, new to old, and new to new convergence using a
  real Better Nexus v1.19.5 client. Let each pair reach two quiet passes.
- With direct transport off, confirm every pairing uses `wrbuildssync` and no
  loadout or DPS payload arrives by whisper.
- With direct transport on for both new clients, request a large build and DPS
  state. Confirm `WLRB`/`WLD2` use recipient whispers while WLXQ, WLRQ, claims,
  and ACKs remain on `wrbuildssync`.
- Repeat direct responses sized to 1, 10, 100, and 200 protocol messages. Record
  any server spam, throttle, mute, or delivery warning at each size.
- Keep a third new client in the channel during that direct transfer. Confirm
  its `Nexus.Sync.Stats().uninvolvedBulkRx` does not increase.
- Confirm protocol whispers do not appear in chat, while ordinary player
  whispers and malformed or unrelated `WL...` text remain visible.
- Reload the recipient during one transfer, then log out or disconnect it after
  the first chunk of another. Confirm the sender
  replays the complete logical transfer on `wrbuildssync` and the recipient can
  reconstruct it after returning.
- Suppress or lose the ACK after a completed direct transfer. Confirm the
  sender records one timeout and one fallback, and duplicate channel delivery
  does not duplicate or downgrade stored state.
- Exercise an invalid or truncated direct transfer. Confirm it produces no ACK
  and changes no build or leaderboard row.
- Verify an owner publication upgrades an equivalent relayed DPS row, and a
  later relay cannot replace the owner row. Confirm relayed rows display
  `Relayed` and `Unverified` in leaderboard/nameplate surfaces.
- Trigger the server's chat pacing warning during channel fallback. Confirm the
  existing pause/slow behavior remains in effect and no message is discarded.
- Reload the UI after toggling direct transport and confirm the setting
  persists without resetting any SavedVariables.
- Capture `Nexus.Sync.Stats()` after successful, timed-out, failed, and fallback
  transfers and compare channel/direct TX/RX, ACK, fallback, queue-depth, and
  transfer-duration counters with the observed traffic.
# Content-bound acknowledgments

Current receivers send the optional channel control packet
`WLA2|sender|requestId|B-or-D|logicalId|contentDigest` after complete validation
and acceptance, including validated idempotent merges. The digest covers the
original encoded object and build revision. It is a correlation checksum, not
authentication or proof of DPS. Sender identity still comes from the actual
transport sender.

WLA2 matches an outstanding completed send by recipient, kind, logical ID and
content, allowing the requester to start a later reconciliation pass before an
earlier transfer finishes. Original WLAK acknowledgments still require their
original request ID. Existing legacy packet formats remain unchanged. Earlier
experimental CW1 clients that ignore WLA2 retain timeout/channel fallback.

For the next live test, reload both clients, start one sync on each, and inspect
`content-matched ACK` alongside attempts, timeouts and deferred records. Verify
that ACKs continue succeeding when a later convergence pass starts. Full
historical convergence and heavy-control-traffic timeout behavior remain live
validation items.
