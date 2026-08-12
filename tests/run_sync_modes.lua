local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
dofile("core/DiagnosticHistory.lua")
dofile("core/Codec.lua")
dofile("core/SyncPolicy.lua")
dofile("core/Sync.lua")

NexusDB = { settings={syncMode="off"}, chars={} }
Nexus.Store.Init()
local Sync = Nexus.Sync
Sync.Init(Nexus.Codec, nil)

assert(Sync.Mode() == "off" and not Sync.IsConnected()
    and H.joinedChannels[Sync.ChannelName()] == nil,
    "Off joined the Sync channel")
assert(not Sync.BroadcastDps("build", "Boganic", 1000, 80, "dummy")
    and Sync.WorkState().outbound == 0,
    "Off admitted outbound traffic")
assert(not Sync.HandleIncoming("WLNP|Peer|1.20.0", "Peer"),
    "Off accepted inbound traffic")

Sync.SetMode("manual")
assert(Sync.GetEffectiveState().key == "manual-idle" and not Sync.IsConnected(),
    "Manual mode did background transport work")
H.resting = false
assert(not Sync.RequestSync() and not Sync.IsConnected(),
    "Manual Sync started while not resting")
H.resting = true
assert(Sync.RequestSync() and Sync.IsConnected()
    and Sync.WorkState().outbound > 0,
    "Manual Sync did not start after an explicit safe request")

H.inCombat = true
Sync.ContextChanged("combat")
assert(not Sync.IsConnected() and Sync.WorkState().outbound == 0
    and Sync.GetEffectiveState().key == "suspended",
    "combat suspension retained a channel or queued burst")

Sync.SetMode("automatic")
assert(not Sync.IsConnected(), "Automatic joined while combat-blocked")
H.inCombat = false
H.resting = false
Sync.ContextChanged("left combat")
assert(not Sync.IsConnected()
    and Sync.GetEffectiveState().reason == "not resting",
    "Automatic did not wait for a resting area")
H.resting = true
Sync.ContextChanged("resting")
assert(Sync.IsConnected(), "Automatic did not connect after entering a resting area")
H.Advance(7)
Sync.OnUpdate(6.1)
assert(Sync.WorkState().outbound > 0,
    "Automatic did not schedule one safe convergence pass")

H.inInstance, H.instanceType = true, "party"
Sync.ContextChanged("instance")
assert(not Sync.IsConnected() and Sync.WorkState().outbound == 0,
    "configured instance suspension retained queued transport")

H.instanceType = "housing"
Sync.ContextChanged("unconfigured instance")
assert(Sync.IsConnected(), "unconfigured instance type suspended Sync")

Sync.SetMode("off")
H.inInstance, H.instanceType = false, "none"
Sync.ContextChanged("left instance")
assert(not Sync.IsConnected() and Sync.GetEffectiveState().key == "off",
    "Off resumed after a context transition")

print("Off, Manual, Automatic, resting, combat, and instance Sync policy -- OK")
