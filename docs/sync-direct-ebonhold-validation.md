# Project Ebonhold sync validation

Direct bulk responses are experimental and default off. Enable them per client
with `/nexus syncdirect on`; disable them with `/nexus syncdirect off`.

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
