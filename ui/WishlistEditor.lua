-- Nexus: ui/WishlistEditor.lua
-- The wishlist BUILDER window -- browse the full echo catalog, see at a
-- glance which ones you own/need/have the tome for, and build your
-- target list right here instead of in the Echo Journal.
--
-- Modeled closely on the EchoWishlist addon's two-panel layout (left:
-- browsable catalog with status labels; right: your current picks with
-- per-item stack steppers), rebuilt against OUR OWN live data sources
-- (Adapter.Catalog/Owned/Wishlist) instead of a separate reverse-
-- engineered catalog scan.
--
-- STATUS (2026-07-24): fully live for BROWSING -- search, filters,
-- pagination, and the Owned/Locked/Tome/Base status labels are all real
-- data. Clicking a row DOES add/remove/adjust it in a local, in-memory
-- pending list. The editor can create a new server wishlist or edit the
-- exact server wishlist selected by Nexus' loadout association panel.

Nexus = Nexus or {}
local M = {}
M._fulfilledDraftTargets = {}
Nexus.WishlistEditor = M

local MAX_ROWS = 19
local PICK_ROWS = 18
local ROW_HEIGHT = 24
local MAX_WISHLIST_ECHOES = 79
local MAX_LOCK_SLOTS = 6

local QUALITY_COLORS = {
    [0] = { 1, 1, 1 },          -- Common
    [1] = { 0.12, 1, 0.12 },    -- Uncommon
    [2] = { 0.2, 0.6, 1 },      -- Rare
    [3] = { 0.72, 0.36, 0.98 }, -- Epic
    [4] = { 1, 0.65, 0 },       -- Legendary
}

-- Closure-captured widgets.
local frame, rows, pickRows
local searchBox, classCheck, applyBtn, footerText, pickFooterText
local trackingText, candidateButtons
local titleText, editContextText
local wishlistNameLabel, wishlistNameBox
local wishlistSwitchBtn, newWishlistBtn, wishlistSwitchMenu
local loadoutSwitchBtn, loadoutSwitchMenu, pendingLoadoutOpen
local displayPopup, displayCheck, displayLockBtn
local lockedLabel, lockedIcons, lockedNeedIcons
local autoLockCheck
-- Slot-picker mode: after clicking an empty locked slot, the NEXT click on
-- any Echo row (either list) assigns it, instead of that row's normal
-- click behavior (AddPending on the left, nothing on the right). Global,
-- not per-slot -- slots are interchangeable, so "assign the next click" is
-- all that's needed regardless of which specific empty slot was clicked.
local assigningLockSlot = false
-- Set alongside assigningLockSlot when the click that started assign mode
-- was a RIGHT-click on an already-real-locked slot: the pending assignment
-- then designs a REPLACEMENT for that specific spellId (Nexus pursues the
-- new one while the old one stays locked and useful) rather than claiming
-- a fresh slot. Nil for an ordinary empty-slot assignment.
local replacingSpellId = nil
-- Locked-slot design storage key for the wishlist currently open in this
-- editor session -- a content fingerprint (see LockSlotKey below), snapshot
-- ONCE per session (LoadPendingEchoes/NewWishlist) and only ever updated
-- again by a successful Save. Deliberately NOT recomputed live as `pending`
-- changes mid-edit -- see LockSlotKey's comment for why.
local currentLockKey = 0
local HideServerEchoUI
local Adapter, Model   -- injected via Init so this file has no direct
                        -- dependency on module load order

-- Local, in-memory ordinary server wishlist. Keyed by Echo family.
--   pending[family] = { spellId, family, quality, stacks, maxStack, lockIntent }
-- Normal entries consume the server's 79-copy budget and are uploaded. A
-- lockIntent entry is a locked-slot design temporarily represented in this
-- table for UI compatibility; it is NOT counted toward 79 and is NOT uploaded.
-- Its exact spellId is committed separately and core/Main.lua injects it into
-- the live automation plan until LockPerk succeeds.
local pending = {}
local pendingSeeded = false

-- Locked-slot designs that are not represented by a pending row (for example,
-- a catalog pick assigned directly to a lock slot, or the final six records of
-- a legacy 85-entry import). These are active automation targets immediately
-- after Save; they do not wait for or consume ordinary wishlist capacity.
--   pendingLock[family] = { spellId, family, quality, name, replaces }
local pendingLock = {}

-- nil for a new wishlist. When editing, this identifies the exact server
-- designed-wishlist slot and name that were selected in the association UI.
local editingContext = nil
-- When creating a new wishlist from an active Saved Build, remember that
-- build so the successful save can associate the new wishlist automatically.
local createTargetContext = nil

local scrollOffset, pickOffset = 0, 0

------------------------------------------------------------------------
-- Data helpers
------------------------------------------------------------------------

local function IsKnownSpell(spellId)
    spellId = tonumber(spellId)
    if not spellId or spellId <= 0 then return false end
    if type(IsSpellKnown) == "function" then
        local ok, known = pcall(IsSpellKnown, spellId)
        if ok and known then return true end
    end
    if type(IsPlayerSpell) == "function" then
        local ok, known = pcall(IsPlayerSpell, spellId)
        if ok and known then return true end
    end
    return false
end

-- "base" (no tome needed) | "tome" (needs a tome you know) |
-- "locked" (needs a tome you don't know yet)
local function RollStatus(row, catalog)
    local req = tonumber(row.requiredSpell) or 0
    if req <= 0 then return "base" end
    if IsKnownSpell(req) then return "tome" end
    return "locked"
end

local function NormalizeEchoName(name)
    name = tostring(name or ""):lower()
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    return name
end

-- Editor uniqueness must match what the player sees as one Echo. The server's
-- groupId alone is broader than quality variants and collapsed unrelated Echoes;
-- displayed name alone can also collide across distinct Echoes. Combine both so
-- genuine quality siblings merge without losing same-name, different-group entries.
local function PendingFamily(spellId, catalog)
    spellId = tonumber(spellId)
    local row = catalog and catalog.rows and catalog.rows[spellId]
    local nameKey = row and NormalizeEchoName(row.name) or ""
    if nameKey ~= "" then
        -- Name alone is not a lossless identity: the live catalog can contain
        -- distinct Echoes with the same displayed name. groupId alone is also
        -- too broad (it previously collapsed unrelated Echoes). Combining both
        -- keeps genuine quality siblings together without destroying same-name
        -- entries during an EBH1 import/export round-trip.
        local groupId = tonumber(row and row.groupId) or 0
        if groupId > 0 then return "ng:" .. nameKey .. ":" .. tostring(groupId) end
        return "n:" .. nameKey
    end
    return "s:" .. tostring(spellId or 0)
end

local function PendingMaxStack(spellId, catalog)
    local row = catalog and catalog.rows and catalog.rows[tonumber(spellId)]
    return math.max(1, tonumber(row and row.maxStack) or 1)
end

-- The server cap is 79 total Echo copies, not 79 distinct names. A build with
-- 66 rows can still be full when stackable Echoes account for the other 13.
local function EchoListTotal(echoes)
    local total = 0
    for _, e in ipairs(echoes or {}) do
        total = total + math.max(1, tonumber(e and e.stacks) or 1)
    end
    return total
end

-- Only ordinary server-wishlist copies consume the 79-slot budget.
-- Entries tagged lockIntent are a separate, local locked-slot design and are
-- injected into the live automation plan by core/Main.lua; they must not
-- reduce how many normal Echo copies the player can select.
local function PendingTotal()
    local total = 0
    for _, p in pairs(pending) do
        if not (p and p.lockIntent) then
            total = total + math.max(1, tonumber(p and p.stacks) or 1)
        end
    end
    return total
end

-- Which Echoes the player has chosen to eventually lock survives independently
-- of any single wishlist edit -- keyed by spellId in NexusDB (this addon's own
-- SavedVariables), NOT sent to the server: the upload payload's shape is a
-- third-party server function (UploadServerBuildSlot) whose tolerance for
-- extra fields per-echo is unverified, so this stays entirely local rather
-- than risk that live write path. Purely a reminder of intent -- it changes
-- nothing about how an entry rolls; only Adapter.LockedOwned() (a real,
-- in-game lock) ever removes an Echo from consideration.
--
-- A value is either `true` (a fresh target, headed for an open slot) or a
-- spellId (this target is designed to REPLACE that already-real-locked
-- Echo once acquired -- see LockBudgetUsed and replacingSpellId below).
--
-- Locked-slot designs are per-WISHLIST, not one global set -- a single
-- shared table meant switching wishlists left the previous one's designs
-- bleeding into the new one's TO LOCK / automation. Identity is
-- Adapter.WishlistKey(echoes) -- a content fingerprint -- NOT
-- editingContext.slot (the server's designed-slot NUMBER, tried in Dev
-- Test 42-49). Slot number turned out unstable across delete+recreate: the
-- server reuses a freed slot number for the next wishlist created, so
-- deleting a wishlist and creating an unrelated new one that happened to
-- land on that same now-freed number showed the DELETED wishlist's locked
-- designs on the new one (confirmed live). Content fingerprint has no such
-- reuse hazard.
--
-- currentLockKey is a SNAPSHOT, not recomputed live -- see its declaration
-- above. Reseeding at LoadPendingEchoes time needs the fingerprint of what
-- the SERVER currently has saved (so it matches whatever the last Save
-- committed under); recomputing it live off the constantly-changing
-- in-progress `pending` edits would make mid-session lookups (the
-- fulfilled-design cleanup in M.Refresh()) target a moving, not-yet-saved
-- key instead of the one that's actually persisted right now.
local function LockSlotKey()
    return currentLockKey or 0
end

-- NexusDB is ACCOUNT-WIDE (## SavedVariables has no "PerCharacter"). A
-- Dev Test 42-47 bucket keyed only by slot number lived at NexusDB's own
-- top level and collided across different characters on the same account
-- sharing the same server slot number (reported live: a design from
-- another character bleeding into a brand-new wishlist here). Nest it
-- inside Nexus.Store.State() instead -- this codebase's existing,
-- already-battle-tested per-character subtable (NexusDB.chars[UnitName()],
-- see core/Store.lua) -- which makes it correctly per-character for free.
-- Accessed via the global Nexus table rather than an injected upvalue
-- (M.Init only wires up Adapter/Model) -- safe since Store.Init() always
-- runs at ADDON_LOADED, long before the editor can ever be opened.
--
-- One-time, self-guarding migration off the old flat `lockDesignTargets`
-- table (Dev Test 37-41) into the currently-open wishlist's own
-- per-character bucket -- see the matching migration in core/Main.lua for
-- the full rationale. The Dev Test 42-47 account-wide lockDesignTargetsBySlot
-- bucket is deliberately NOT migrated forward -- its contents can't be
-- reliably attributed to any one character, so carrying it over would just
-- reintroduce the same cross-character bleed one more time. It's left in
-- place, orphaned and never read again.
--
-- DRAFT vs COMMITTED: this returns the COMMITTED set -- the one the Panel
-- HUD's TO LOCK row and TryAutoLock's actual LockPerk/UnlockPerk automation
-- both read (core/Main.lua). While the editor is open, ordinary edits
-- (importing a build, tagging/untagging a design, right-click replace) only
-- ever touch the in-memory DRAFT -- pending[fam].lockIntent/.replaces and
-- pendingLock[fam].replaces -- never this table directly. It's read once,
-- to seed the draft when a saved wishlist is opened, and written once, by
-- CommitLockDesignTargets() below on a successful Save -- so a design the
-- player is only previewing (an imported leaderboard/community build they
-- haven't saved yet) never starts getting pursued or shown as "still need
-- to acquire" before they've actually committed to it. The one exception is
-- the "this design was fulfilled" cleanup further down in M.Refresh(),
-- which writes here immediately -- removing something already DONE can't
-- retroactively un-happen by not saving, so there's nothing to defer.
local function LockDesignTargets()
    local state = Nexus.Store.State()
    local old = NexusDB.lockDesignTargets
    state.lockDesignTargetsBySlot = state.lockDesignTargetsBySlot or {}
    if type(old) == "table" then
        local key = LockSlotKey()
        if not state.lockDesignTargetsBySlot[key] then
            state.lockDesignTargetsBySlot[key] = old
        end
        NexusDB.lockDesignTargets = nil
    end
    local key = LockSlotKey()
    state.lockDesignTargetsBySlot[key] = state.lockDesignTargetsBySlot[key] or {}
    return state.lockDesignTargetsBySlot[key]
end

-- The account only ever has MAX_LOCK_SLOTS (6) real locked slots, full stop
-- -- shared across everything already locked, everything designed toward a
-- lock (active lockIntent entries), and everything still queued waiting for
-- room. All three draw from the same budget. A real-locked Echo that has an
-- active REPLACEMENT designed for it is excluded from the "already locked"
-- side of the count -- together the old (still locked, for now) and the new
-- (being pursued) represent ONE slot being swapped, not two occupied at
-- once. `excludeRealLockedId`, when given, is ALSO excluded even before its
-- replacement is designated -- needed at the moment a replacement is first
-- being designated, when the budget check has to already treat it as exempt
-- or a swap on a full 6/6 account could never be started at all.
-- Replacement pairing (`.replaces`) lives on the pending/pendingLock entry
-- itself now, not a separate table -- see the draft-vs-committed note above
-- LockDesignTargets.
local function LockBudgetUsed(excludeRealLockedId)
    local realLocked = {}
    if Adapter and Adapter.LockedOwned then
        local locked = Adapter.LockedOwned()
        if locked and type(locked.bySpell) == "table" then
            for id in pairs(locked.bySpell) do realLocked[tonumber(id)] = true end
        end
    end
    if excludeRealLockedId then realLocked[tonumber(excludeRealLockedId)] = nil end
    local function ExemptReplaced(p)
        local replaces = p and p.replaces
        if type(replaces) == "number" then realLocked[replaces] = nil end
    end
    for _, p in pairs(pending) do if p.lockIntent then ExemptReplaced(p) end end
    for _, p in pairs(pendingLock) do ExemptReplaced(p) end
    local used = 0
    for _ in pairs(realLocked) do used = used + 1 end
    for _, p in pairs(pending) do if p.lockIntent then used = used + 1 end end
    for _ in pairs(pendingLock) do used = used + 1 end
    return used
end

-- Locked Echoes (the account's up-to-6 permanent picks) can share the same
-- server wishlist slot as the normal 79-cap selections -- a raw ImportEchoLoadout
-- string captures both together (confirmed live: an 85-entry string, 79 + 6
-- locked, broke the editor). Locked entries are permanently secured and never
-- need to be re-rolled for, so they must never consume wishlist capacity or
-- cause an unrelated entry to be silently dropped.
local lastLockedSkipped, lastOverflowSkipped, lastUntrustedOverflowSkipped = 0, 0, 0
local lastLockDesignCollisions = 0
local lastLockBudgetExceeded = 0

-- Canonicalize imported/server data. Exact duplicate records are combined and
-- clamped. Sibling quality variants collapse to the highest quality, preserving
-- the largest requested stack count rather than inflating it by summing qualities.
--
-- trustOrder (default true): whether "whatever comes after the 79-cap fill,
-- in array order" can safely be assumed to be the source's intended locked
-- picks (see the plain-overflow branch below). True for a string this
-- session just decoded (Import button) or a fresh Leaderboard/Community
-- Builds candidate (those tag their locked entries explicitly via e.locked
-- instead, so order never matters for them). False for echoes read back
-- from a live server wishlist (GetWishlistCandidates/Adapter.Slots) --
-- confirmed live: a build imported through the game's own native
-- ImportEchoLoadout box (not Nexus's Import button) came back with its
-- Echoes in a different order than pasted, so the "last N are the locked
-- ones" convention grabbed the wrong Echoes entirely once round-tripped
-- through the server. Nexus's own uploads never trigger this (CanonicalEchoes
-- caps every upload at 79, so there's nothing beyond it to reorder), but
-- nothing guarantees a native import -- or any other addon writing to the
-- same server slot -- preserves paste order.
local function LoadPendingEchoes(echoes, trustOrder)
    if trustOrder == nil then trustOrder = true end
    pending = {}
    pendingLock = {}
    M._fulfilledDraftTargets = {}
    -- Snapshot this session's lock-design storage key from whatever's being
    -- loaded (see currentLockKey's declaration and LockSlotKey). For a
    -- brand-new import this won't exactly match what CommitLockDesignTargets
    -- eventually computes (the saved 79 only, never the locked extras) --
    -- harmless, since nothing could have been committed yet under any key
    -- for content that's never been saved before; the reseed check just
    -- below correctly finds nothing to reapply.
    currentLockKey = (Adapter and Adapter.WishlistKey and Adapter.WishlistKey(echoes)) or 0
    local catalog = Adapter and Adapter.Catalog and Adapter.Catalog()
    local lockedBySpell = {}
    if Adapter and Adapter.LockedOwned then
        local locked = Adapter.LockedOwned()
        if locked and type(locked.bySpell) == "table" then lockedBySpell = locked.bySpell end
    end

    -- Importing a build (EBH1 string, community build, saved-loadout mirror)
    -- whose locked-slot goal differs from what this character currently has
    -- really locked is the main reason this feature exists at all: any
    -- currently-real-locked Echo the import's OWN .locked entries don't ask
    -- for is a swap-out candidate, auto-paired with one of the import's new
    -- targets so the budget treats this as a REPLACEMENT of up to 6, not an
    -- addition on top of what's already locked. The player still has to do
    -- the actual swap manually once each replacement is acquired -- Nexus
    -- has no write API for locking.
    local importedLockedIds = {}
    for _, e in ipairs(echoes or {}) do
        if e and e.locked then
            local eid = tonumber(e.spellId)
            if eid then importedLockedIds[eid] = true end
        end
    end
    -- An import can signal "this wants locked slots" two ways: an explicit
    -- e.locked flag on some entries (native server data, or a 4-field EBH1
    -- string), OR simply having more than 79 total Echo copies with none
    -- flagged at all -- the same positional convention the plain-overflow
    -- branch below relies on (a build export always puts its real locked
    -- Echoes after the 79-cap picks). Gating swap-candidate computation on
    -- explicit e.locked alone meant a plain positional import (every EBH1
    -- string this addon has ever produced -- EncodeEBH1 never emits the 4th
    -- field) never got ANY .replaces pairing at all, no matter how many
    -- real-locked Echoes it didn't want: confirmed live, an 85-Echo import
    -- with 4 queued "awaiting lock" targets and 5/6 real slots locked showed
    -- zero pairings, because this check alone always came back empty.
    local wantsLockedSlots = next(importedLockedIds) ~= nil
    if not wantsLockedSlots and trustOrder and EchoListTotal(echoes) > MAX_WISHLIST_ECHOES then
        wantsLockedSlots = true
    end
    local swapCandidates = {}
    if wantsLockedSlots then
        for spellId in pairs(lockedBySpell) do
            local id = tonumber(spellId)
            if id and not importedLockedIds[id] then
                swapCandidates[#swapCandidates + 1] = id
            end
        end
        table.sort(swapCandidates)
    end
    local swapIdx = 1

    local remaining = MAX_WISHLIST_ECHOES
    local lockDesignCount = 0
    lastLockedSkipped, lastOverflowSkipped, lastUntrustedOverflowSkipped = 0, 0, 0
    lastLockDesignCollisions = 0
    lastLockBudgetExceeded = 0
    for _, e in ipairs(echoes or {}) do
        local id = tonumber(e and e.spellId)
        if id and e and e.locked and (tonumber(lockedBySpell[id]) or 0) > 0 then
            -- The import explicitly says this real locked Echo belongs to the
            -- build. It must remain part of the draft lock design even though
            -- it is intentionally omitted from the ordinary 79-slot list.
            M._fulfilledDraftTargets[id] = true
        end
        if id and (tonumber(lockedBySpell[id]) or 0) > 0 then
            -- Already permanently secured -- leave it out of the 79-cap
            -- wishlist entirely rather than let it eat capacity or, worse,
            -- crowd out a later real entry once `remaining` hits 0.
            lastLockedSkipped = lastLockedSkipped + 1
        elseif id and e.locked and lockDesignCount < MAX_LOCK_SLOTS and remaining > 0 then
            -- The source explicitly designed this Echo as one of the up to 6
            -- locked slots (EBH1 4th field, or a mirrored saved loadout's
            -- real server `locked` flag) even though this character hasn't
            -- locked it yet, AND there's still room to actively pursue it --
            -- becomes a completely normal active wishlist entry, just
            -- tagged, so it keeps rolling like anything else until the
            -- player actually locks it in-game.
            local row = catalog and catalog.rows and catalog.rows[id]
            local family = PendingFamily(id, catalog)
            local maxStack = PendingMaxStack(id, catalog)
            local swap = swapCandidates[swapIdx]
            if swap then swapIdx = swapIdx + 1 end
            pending[family] = { spellId = id, family = family,
                -- Catalog first, e.quality only as a last resort: a known
                -- spellId's quality is fixed (different quality tiers of the
                -- "same" Echo are different spellIds, not a variable roll
                -- result), so the catalog is always authoritative once it
                -- has the row. Previously e.quality won this even when it
                -- was a literal 0 -- true for almost every EBH1 string this
                -- addon has ever produced, since quality is nominal on a
                -- designed build's wire format (see EchoesToWishlist's
                -- comment) -- and 0 is truthy in Lua, so the catalog
                -- fallback never ran. Confirmed live: freshly imported
                -- Echoes displayed white/Common in the Selected Echoes list
                -- regardless of their real quality.
                quality = tonumber(row and row.quality) or tonumber(e.quality) or 0,
                stacks = 1, maxStack = maxStack, lockIntent = true, replaces = swap }
            lockDesignCount = lockDesignCount + 1
            remaining = MAX_WISHLIST_ECHOES - PendingTotal()
        elseif id and e.locked and lockDesignCount < MAX_LOCK_SLOTS then
            -- Designed as locked, but no wishlist room right now -- queue it.
            -- M.Refresh promotes it into `pending` automatically the moment
            -- room frees up (a family gets satisfied, or something else on
            -- the wishlist gets locked in-game).
            local row = catalog and catalog.rows and catalog.rows[id]
            local family = PendingFamily(id, catalog)
            local quality = tonumber(row and row.quality) or tonumber(e.quality) or 0
            local existing = pendingLock[family]
            if not existing then
                local swap = swapCandidates[swapIdx]
                if swap then swapIdx = swapIdx + 1 end
                pendingLock[family] = { spellId = id, family = family, quality = quality,
                    name = (row and row.name) or ("spell " .. tostring(id)), replaces = swap }
                lockDesignCount = lockDesignCount + 1
            elseif id ~= existing.spellId then
                -- Two different spellIds under the same locked-design family
                -- (quality siblings of the same Echo) -- previously the
                -- second one just vanished with no trace anywhere: not
                -- shown, not counted, no chat warning, eating one of the
                -- source's up to 6 intended locked picks for nothing. Keep
                -- whichever is the higher catalog quality, same tie-break
                -- the normal 79-list uses below.
                lastLockDesignCollisions = lastLockDesignCollisions + 1
                if quality > (tonumber(existing.quality) or 0) then
                    existing.spellId, existing.quality = id, quality
                    existing.name = (row and row.name) or ("spell " .. tostring(id))
                end
            end
        elseif id and remaining <= 0 and trustOrder then
            -- Part of the imported build, doesn't fit the 79 cap, and isn't
            -- locked yet -- keep it visible as "still needs to be locked"
            -- instead of dropping it. M.Refresh reconciles this out the
            -- moment LockedOwned() confirms it's actually locked. This is
            -- exactly the same "designed lock" intent as the explicit
            -- e.locked branches above (a build export always puts its real
            -- locked Echoes after the 79-cap picks, whether or not the 4th
            -- EBH1 field is present -- see Codec.EncodeEBH1) -- previously
            -- this branch only updated the editor's own in-memory pendingLock
            -- view with no lock-design tag at all, so these entries showed as
            -- "awaiting lock" here but never reached the Panel HUD's TO LOCK
            -- row or TryAutoLock's automation, even after a Save.
            lastOverflowSkipped = lastOverflowSkipped + 1
            local row = catalog and catalog.rows and catalog.rows[id]
            local family = PendingFamily(id, catalog)
            local quality = tonumber(row and row.quality) or tonumber(e.quality) or 0
            local existing = pendingLock[family]
            if existing then
                if id ~= existing.spellId then
                    -- Same collision case as the explicit e.locked branch
                    -- above -- see its comment. Equally reachable here: the
                    -- entries past the 79-cap in a plain positional import
                    -- can just as easily be quality siblings of each other.
                    lastLockDesignCollisions = lastLockDesignCollisions + 1
                    if quality > (tonumber(existing.quality) or 0) then
                        existing.spellId, existing.quality = id, quality
                        existing.name = (row and row.name) or ("spell " .. tostring(id))
                    end
                end
            elseif lockDesignCount < MAX_LOCK_SLOTS then
                local swap = swapCandidates[swapIdx]
                if swap then swapIdx = swapIdx + 1 end
                lockDesignCount = lockDesignCount + 1
                pendingLock[family] = { spellId = id, family = family, quality = quality,
                    name = (row and row.name) or ("spell " .. tostring(id)), replaces = swap }
            else
                -- The account only ever has MAX_LOCK_SLOTS (6) real slots,
                -- full stop -- a NEW family beyond that budget has nowhere to
                -- go, ever. Previously this created a pendingLock entry
                -- regardless of the budget check (only the swap-pairing part
                -- was gated), so a source with more than 6 distinct overflow
                -- families could show more than 6 "awaiting lock" entries --
                -- the account can never actually secure more than 6, however
                -- many the editor showed.
                lastLockBudgetExceeded = lastLockBudgetExceeded + 1
            end
        elseif id and remaining <= 0 then
            -- Same situation as above, but this echoes array's order isn't
            -- trusted (trustOrder false -- see LoadPendingEchoes' header
            -- comment): guessing that "whatever's left over" is this
            -- source's intended locked picks would just as likely grab the
            -- wrong Echoes as the right ones. Drop instead of mis-tagging --
            -- lastUntrustedOverflowSkipped's warning below tells the player
            -- exactly why and points at the known-safe fix.
            lastUntrustedOverflowSkipped = lastUntrustedOverflowSkipped + 1
        elseif id then
            local row = catalog and catalog.rows and catalog.rows[id]
            local family = PendingFamily(id, catalog)
            local quality = tonumber(row and row.quality) or tonumber(e.quality) or 0
            local maxStack = PendingMaxStack(id, catalog)
            local stacks = math.min(maxStack, math.max(1, tonumber(e.stacks) or 1), remaining)
            local current = pending[family]
            if not current or quality > (tonumber(current.quality) or 0) then
                local oldStacks = current and math.max(1, tonumber(current.stacks) or 1) or 0
                local keepStacks = math.min(maxStack, math.max(stacks, oldStacks))
                pending[family] = { spellId = id, family = family, quality = quality,
                    stacks = keepStacks, maxStack = maxStack }
                remaining = MAX_WISHLIST_ECHOES - PendingTotal()
            elseif id == current.spellId then
                local add = math.min(stacks, remaining)
                current.stacks = math.min(current.maxStack or maxStack,
                    (tonumber(current.stacks) or 1) + add)
                remaining = MAX_WISHLIST_ECHOES - PendingTotal()
            else
                -- A different quality is the same player-facing Echo. Keep one
                -- quality choice and preserve the larger requested stack count.
                current.stacks = math.min(current.maxStack or maxStack,
                    math.max(tonumber(current.stacks) or 1, stacks))
                remaining = MAX_WISHLIST_ECHOES - PendingTotal()
            end
        end
    end
    if lastOverflowSkipped > 0 then
        print(string.format(
            "|cffff6060Nexus:|r this wishlist has more than %d Echo copies -- %d don't fit "
                .. "and aren't locked yet. They're listed below as locked-slot targets and are "
                .. "pursued separately from the 79-copy wishlist.",
            MAX_WISHLIST_ECHOES, lastOverflowSkipped))
    end
    if lastUntrustedOverflowSkipped > 0 then
        print(string.format(
            "|cffff6060Nexus:|r this wishlist has more than %d Echo copies, but Nexus can't "
                .. "safely tell which %d were meant to be your locked picks -- this usually "
                .. "happens after importing through the game's own Import feature instead of "
                .. "Nexus's, which doesn't preserve pick order. They were left out rather than "
                .. "risk locking the wrong ones. Delete this wishlist and use Nexus's own "
                .. "Import button (Wishlist Editor) with the same string instead, or tag your "
                .. "locked picks manually here.",
            MAX_WISHLIST_ECHOES, lastUntrustedOverflowSkipped))
    end
    if swapIdx > 1 then
        print(string.format(
            "|cff4dff80Nexus:|r this build wants %d locked Echo%s different from what you have "
                .. "locked now -- shown gold in the Locked strip. Your current ones stay locked "
                .. "and useful; lock the new ones in as soon as you get each one, replacing "
                .. "whichever old one you're ready to let go.",
            swapIdx - 1, (swapIdx - 1) == 1 and "" or "es"))
    end
    if lastLockDesignCollisions > 0 then
        print(string.format(
            "|cffff9040Nexus:|r %d of this build's locked picks share an Echo with one already "
                .. "queued (different quality copies of the same Echo) -- only the higher-quality "
                .. "copy of each is kept, so fewer than 6 locked-design slots may be filled.",
            lastLockDesignCollisions))
    end
    if lastLockBudgetExceeded > 0 then
        print(string.format(
            "|cffff6060Nexus:|r this build asks for %d more locked-design Echoes than the account's "
                .. "%d permanent slots can ever hold -- they were left out entirely, not just queued.",
            lastLockBudgetExceeded, MAX_LOCK_SLOTS))
    end
    -- Re-apply remembered "eventually lock this" intent -- seeded from this
    -- wishlist's own COMMITTED design set (LockDesignTargets(), written the
    -- last time this exact wishlist was saved) onto whatever landed in
    -- `pending` from the plain server wishlist, which carries no such field
    -- of its own. This is what makes a lockIntent tag (and its replacement
    -- pairing) survive closing and reopening the editor, or a full /reload,
    -- instead of only lasting for the current UI session -- while still
    -- only ever reading the committed set, never writing to it here.
    local targets = LockDesignTargets()
    for spellIdKey, replaces in pairs(targets) do
        local id = tonumber(spellIdKey)
        if id and (tonumber(lockedBySpell[id]) or 0) > 0 then
            M._fulfilledDraftTargets[id] = replaces
        end
    end
    if next(targets) then
        -- Budget check here MUST match LockBudgetUsed's own exemption logic
        -- (a real-locked Echo with an active .replaces pairing counts as
        -- ONE slot being swapped, not two occupied) -- a hand-rolled count
        -- of "every real-locked Echo, unconditionally" previously double-
        -- counted anything already paired for replacement, exhausting the
        -- budget after just one or two promotions and silently leaving
        -- later committed targets un-reseeded on reopen. Confirmed live:
        -- a 6th locked-design pick (already paired against a real lock
        -- being swapped out) never came back after closing and reopening
        -- the wishlist. Re-checking LockBudgetUsed() fresh each iteration
        -- also self-corrects as p.lockIntent gets set, since it reads
        -- `pending`/`pendingLock` live.
        for _, p in pairs(pending) do
            local committed = targets[tonumber(p.spellId)]
            if not p.lockIntent and committed and LockBudgetUsed() < MAX_LOCK_SLOTS then
                p.lockIntent = true
                if type(committed) == "number" then p.replaces = committed end
            end
        end
        -- A committed target whose FAMILY isn't anywhere in `pending` was
        -- queued (pendingLock), not active, at the moment it was last saved
        -- -- the loop above only ever finds ACTIVE (79-list) matches, so
        -- without this a wishlist saved with locked designs entirely in
        -- overflow (no room in the 79 for any of them) would silently show
        -- "Locked (0/N)" on every reopen even though the commit captured
        -- them fine. Reconstruct those directly from the catalog, the same
        -- shape LoadPendingEchoes' own overflow branch above builds.
        for spellIdKey, replaces in pairs(targets) do
            local id = tonumber(spellIdKey)
            if id and (tonumber(lockedBySpell[id]) or 0) <= 0 then
                local row = catalog and catalog.rows and catalog.rows[id]
                local family = PendingFamily(id, catalog)
                if family and not pending[family] and not pendingLock[family] then
                    pendingLock[family] = { spellId = id, family = family,
                        quality = tonumber(row and row.quality) or 0,
                        name = (row and row.name) or ("spell " .. tostring(id)),
                        replaces = type(replaces) == "number" and replaces or nil }
                end
            end
        end
    end
end

local function SeedPendingFromWishlist()
    if pendingSeeded then return end
    pendingSeeded = true
    local wl = Adapter.Wishlist and Adapter.Wishlist()
    if wl then LoadPendingEchoes(wl.entries or {}, false) end
end

-- Builds the browsable list: every catalog row usable by the player's
-- class, matching the search text, sorted by name.
local function BuildAvailableList(catalog, owned)
    local out = {}
    local search = (NexusDB.editorSearch or ""):lower()
    local classOnly = NexusDB.editorClassOnly ~= false
    local playerMask = catalog and catalog.playerMask
    for id, row in pairs((catalog and catalog.rows) or {}) do
        local okClass = (not classOnly) or (Model and Model.MaskMatch
            and Model.MaskMatch(row.classMask, playerMask))
        local nm = (row.name or ""):lower()
        if okClass and (search == "" or nm:find(search, 1, true)) then
            out[#out + 1] = row
        end
    end
    table.sort(out, function(a, b)
        return tostring(a.name or "") < tostring(b.name or "")
    end)
    return out
end

------------------------------------------------------------------------
-- Actions (pending list only -- see file header)
------------------------------------------------------------------------

local function AddPending(row)
    if not row or not tonumber(row.spellId) then return end
    -- Already permanently secured -- adding it back would waste a wishlist
    -- slot on something that never needs to be rolled again.
    if Adapter and Adapter.LockedOwned then
        local locked = Adapter.LockedOwned()
        local n = locked and type(locked.bySpell) == "table" and locked.bySpell[tonumber(row.spellId)]
        if (tonumber(n) or 0) > 0 then
            print("|cffff6060Nexus:|r " .. tostring(row.name or "that Echo")
                .. " is already locked -- it doesn't need a wishlist slot.")
            return
        end
    end
    local catalog = Adapter and Adapter.Catalog and Adapter.Catalog()
    local family = PendingFamily(row.spellId, catalog)
    local maxStack = math.max(1, tonumber(row.maxStack) or 1)
    local old = pending[family]
    -- Same exact Echo: remain selected. Copies are controlled explicitly with +/-.
    if old and tonumber(old.spellId) == tonumber(row.spellId) then return end
    if not old and PendingTotal() >= MAX_WISHLIST_ECHOES then
        -- A normal catalog click always means "add to the 79-copy wishlist."
        -- Locked-slot targets use the dedicated slot picker and have their own
        -- six-slot budget; never silently reinterpret a normal pick as a lock.
        print("|cffff6060Nexus:|r wishlist is full (79 / 79 Echoes). Use an empty Locked slot to design an additional locked Echo.")
        return
    end
    -- Different quality of the same Echo replaces that quality without changing
    -- the total number of Echo copies in the build.
    pending[family] = { spellId = tonumber(row.spellId), family = family,
        quality = tonumber(row.quality) or 0,
        stacks = math.min(maxStack, math.max(1, tonumber(old and old.stacks) or 1)),
        maxStack = maxStack }
end

local function RemovePending(family)
    -- Handles both real wishlist picks and "awaiting lock" entries -- the
    -- caller (Create()'s remove-button handler) doesn't need to know which
    -- table a row came from, keeping that giant widget-builder function's
    -- upvalue count from growing (it's already at WoW 3.3.5's 60 limit
    -- once; see Panel.lua's EnsureFrame crash, Dev Test 17).
    -- lockIntent/.replaces live on the entry itself now (draft-only, see
    -- LockDesignTargets), so removing the entry removes them too -- nothing
    -- else to clear.
    if pendingLock[family] then
        pendingLock[family] = nil
        return
    end
    pending[family] = nil
end

-- Lets a player explicitly design what they want in their locked slots.
-- Called two ways: (1) clicking an already-designed slot in the top strip
-- (queued OR active) -- always UN-assigns it, matching that click's
-- tooltip regardless of which table it currently lives in; (2) clicking a
-- plain, not-yet-designed Selected Echoes row while assign mode is active
-- -- tags it fresh (or as a replacement, if replacingSpellId is set). A
-- tagged pending entry stops consuming the ordinary 79-copy budget and is
-- persisted as separate locked-slot intent. core/Main.lua then pursues and
-- locks it automatically whenever both automation switches allow it.
local function ToggleDesignLock(family)
    if not family then return end
    if pendingLock[family] then
        pendingLock[family] = nil
        return
    end
    local p = pending[family]
    if not p then return end
    if p.lockIntent then
        -- Untagging turns it back into an ordinary server-wishlist entry, so
        -- refuse only when that would push the normal list past 79.
        if PendingTotal() + math.max(1, tonumber(p.stacks) or 1) > MAX_WISHLIST_ECHOES then
            print("|cffff6060Nexus:|r the normal wishlist is already full -- remove another Echo before moving this locked target back into it.")
            return
        end
        p.lockIntent = nil
        p.replaces = nil
        return
    end
    if LockBudgetUsed(replacingSpellId) >= MAX_LOCK_SLOTS then
        print(string.format(
            "|cffff6060Nexus:|r only %d Echoes can be locked in total -- untag one first.",
            MAX_LOCK_SLOTS))
        replacingSpellId = nil
        return
    end
    p.lockIntent = true
    p.replaces = replacingSpellId
    replacingSpellId = nil
end

local function AdjustStacks(family, delta)
    local p = pending[family]
    if not p then return end
    local maxStack = math.max(1, tonumber(p.maxStack) or 1)
    local current = math.max(1, tonumber(p.stacks) or 1)
    if delta > 0 and PendingTotal() >= MAX_WISHLIST_ECHOES then
        print("|cffff6060Nexus:|r wishlist is full (79 / 79 Echoes).")
        return
    end
    local room = math.max(0, MAX_WISHLIST_ECHOES - PendingTotal())
    local nextValue = current + delta
    if delta > 0 then nextValue = math.min(nextValue, current + room) end
    p.stacks = math.max(1, math.min(maxStack, nextValue))
end

local function CanonicalEchoes()
    local echoes = {}
    for _, p in pairs(pending) do
        -- Locked-slot designs are persisted in CommitLockDesignTargets() and
        -- pursued synthetically by WishlistWithLockTargets(). Uploading them
        -- here would put them back inside the server's 79-copy wishlist and
        -- recreate the exact capacity bug this separation is meant to avoid.
        if not p.lockIntent then
            echoes[#echoes + 1] = { spellId = tonumber(p.spellId),
                quality = tonumber(p.quality) or 0,
                stacks = math.max(1, math.min(tonumber(p.maxStack) or 1, tonumber(p.stacks) or 1)) }
        end
    end
    table.sort(echoes, function(a, b) return (a.spellId or 0) < (b.spellId or 0) end)
    return echoes
end

-- Deliberately unimplemented: the write function isn't identified yet
-- (see /nexus sniff). Wiring this up is the ONLY remaining step once we
-- know it -- everything upstream (the pending list, its shape, the UI)
-- is already exactly what a real Save call would need.
-- Confirmed via /nexus sniff (2026-07-24): UploadServerBuildSlot(slot, name,
-- echoes) with slot=0 is the real write function -- two independent live
-- captures (a community-loadout import, and a raw ImportEchoLoadout
-- string import) both used it. This is destructive (it overwrites
-- whatever's currently in that slot), so it goes through a confirmation
-- popup rather than firing on click.
local APPLY_FRIENDLY = {
    spacing = "the server is busy with another build operation -- try again in a moment",
    refused = "the server refused the change (are you in a state that allows editing your build?)",
    ["no echoes"] = "there are no echoes in your pending list",
    ["no valid echoes"] = "none of the pending echoes look valid",
}

-- The only place a Save actually reaches the COMMITTED, automation-visible
-- design-target set (see the draft-vs-committed note above LockDesignTargets).
-- A full replace, not a merge -- matches how the 79-slot list itself is a
-- full replace on save, and correctly drops anything untagged in this
-- session instead of leaving it stranded in the committed store forever.
--
-- Recomputes the storage key fresh from CanonicalEchoes() -- the exact 79
-- about to be uploaded -- rather than reusing currentLockKey as snapshotted
-- at open. They're usually identical, but if the 79-list was edited this
-- session (not just the locked designs), only the FINAL saved content's
-- fingerprint will match what a later reopen recomputes from the server's
-- copy -- so that's the one this has to commit under. currentLockKey is
-- then updated to match, keeping the rest of this session (a same-session
-- re-save, or the fulfilled-design cleanup in M.Refresh() right after)
-- consistent with what was actually just persisted.
local function CommitLockDesignTargets()
    local previousKey = currentLockKey or 0
    local existing = LockDesignTargets()
    local fresh, replaced = {}, {}

    -- A replacement means the old fulfilled target is intentionally leaving
    -- this build's desired lock set. Record those first so preservation below
    -- cannot accidentally carry it forward.
    for _, p in pairs(pending) do
        if p.lockIntent and type(p.replaces) == "number" then replaced[p.replaces] = true end
    end
    for _, p in pairs(pendingLock) do
        if type(p.replaces) == "number" then replaced[p.replaces] = true end
    end
    for _, replacementValue in pairs(M._fulfilledDraftTargets or {}) do
        if type(replacementValue) == "number" then replaced[replacementValue] = true end
    end

    local lockedBySpell = {}
    if Adapter and Adapter.LockedOwned then
        local locked = Adapter.LockedOwned()
        if locked and type(locked.bySpell) == "table" then lockedBySpell = locked.bySpell end
    end

    -- Fulfilled lock targets are desired BUILD STATE, not completed tasks.
    -- M.Refresh removes them from pending so they stop consuming the 79-slot
    -- wishlist, but a later Save must not erase them from the committed lock
    -- design or the automation will eventually treat them as unwanted.
    for spellIdKey, value in pairs(existing or {}) do
        local id = tonumber(spellIdKey)
        if id and (tonumber(lockedBySpell[id]) or 0) > 0 and not replaced[id] then
            fresh[id] = value
        end
    end
    for spellIdKey, value in pairs(M._fulfilledDraftTargets or {}) do
        local id = tonumber(spellIdKey)
        if id and (tonumber(lockedBySpell[id]) or 0) > 0 and not replaced[id] then
            fresh[id] = value
        end
    end

    for _, p in pairs(pending) do
        if p.lockIntent and tonumber(p.spellId) then
            fresh[tonumber(p.spellId)] = p.replaces or true
        end
    end
    for _, p in pairs(pendingLock) do
        if tonumber(p.spellId) then fresh[tonumber(p.spellId)] = p.replaces or true end
    end

    local nextKey = (Adapter and Adapter.WishlistKey and Adapter.WishlistKey(CanonicalEchoes())) or 0
    local state = Nexus.Store.State()
    state.lockDesignTargetsBySlot = state.lockDesignTargetsBySlot or {}
    state.lockDesignTargetsBySlot[nextKey] = fresh
    -- Move, rather than duplicate, the committed design when ordinary
    -- wishlist edits change its content fingerprint.
    if previousKey ~= nextKey and state.lockDesignTargetsBySlot[previousKey] == existing then
        state.lockDesignTargetsBySlot[previousKey] = nil
    end
    currentLockKey = nextKey

    M._fulfilledDraftTargets = {}
    for id, value in pairs(fresh) do
        if (tonumber(lockedBySpell[id]) or 0) > 0 then
            M._fulfilledDraftTargets[id] = value
        end
    end
end

local applyRetry = nil
local function TryApply(slot, name, echoes, isRetry)
    local ok, err = Adapter.UploadWishlist(slot or 0, name, echoes)
    if ok then
        print("|cff4dff80Nexus:|r wishlist saved (" .. EchoListTotal(echoes) .. " / 79 Echoes).")
        CommitLockDesignTargets()
        if editingContext and Adapter.UpdateWishlistAssociationAfterSave then
            Adapter.UpdateWishlistAssociationAfterSave(editingContext.loadoutSlot,
                slot, name, echoes)
        elseif createTargetContext and Adapter.SetLoadoutWishlistIdentity then
            -- A wishlist created while a real Saved Build is active should be
            -- its destination immediately. Store the new wishlist identity now;
            -- its actual server slot is resolved after the server refreshes.
            Adapter.SetLoadoutWishlistIdentity(createTargetContext.loadoutSlot, name, echoes)
            print("|cff4dff80Nexus:|r associated '" .. tostring(name)
                .. "' with " .. tostring(createTargetContext.loadoutName or "the active Saved Build") .. ".")
        elseif Adapter.SetFirstLoadoutWishlistIdentity then
            -- Creating a wishlist must immediately unlock Nexus for a brand-new
            -- player who has no Saved Build yet. They're just starting their
            -- very first loadout -- that's always slot 1 -- so associate this
            -- wishlist with it directly instead of the older, separate
            -- "firstRunWishlist" placeholder mechanism that needed a later
            -- hand-off once a real Saved Build existed. The real server slot
            -- for the wishlist itself is still resolved on the next refresh.
            Adapter.SetFirstLoadoutWishlistIdentity(name, echoes)
        end
        applyRetry = nil
        if applyBtn then applyBtn:SetText("Saved") end
        return true
    end
    if tostring(err) == "spacing" then
        applyRetry = applyRetry or { slot = slot, name = name, echoes = echoes, tries = 0 }
        return false
    end
    print("|cffff6060Nexus:|r couldn't apply: "
        .. (APPLY_FRIENDLY[tostring(err)] or tostring(err)))
    applyRetry = nil
    return false
end

function M._PumpApplyRetry()
    if not applyRetry then return end
    applyRetry.tries = applyRetry.tries + 1
    if applyRetry.tries > 12 then
        print("|cffff6060Nexus:|r couldn't apply: " .. APPLY_FRIENDLY.spacing)
        applyRetry = nil
        return
    end
    TryApply(applyRetry.slot, applyRetry.name, applyRetry.echoes, true)
end

function M.IsApplyPending() return applyRetry ~= nil end

StaticPopupDialogs["WISHLISTREALIZER_UPDATE_WISHLIST"] = {
    text = "Save %d / 79 Echoes to '%s'?\nThis updates the associated server wishlist in place.",
    button1 = "Save Changes",
    button2 = "Cancel",
    OnAccept = function(self, data)
        TryApply(data.slot, data.name, data.echoes)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["WISHLISTREALIZER_CREATE_WISHLIST"] = {
    text = "Create '%s' with %d / 79 Echoes?\nThis saves to a new server wishlist slot and automatically assigns it to the active Saved Build. Existing wishlists will not be overwritten.",
    button1 = "Create Wishlist",
    button2 = "Cancel",
    OnAccept = function(self, data)
        TryApply(0, data.name, data.echoes)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

------------------------------------------------------------------------
-- Nexus-native EBH1 import/export -- players no longer need the server's
-- own ImportEchoLoadout UI. Export always includes currently-locked Echoes
-- alongside the 79-cap selections (up to 85 total), since that's the whole
-- point: a build shared this way should carry both halves of the picture.
-- Import reuses LoadPendingEchoes exactly as-is, so a >79-total pasted
-- string gets the same locked-exclusion/"awaiting lock" handling as any
-- other import path (community build, wishlist switch, server re-read).
------------------------------------------------------------------------

local function ExportEBH1String()
    local Codec = Nexus and Nexus.Codec
    if not (Codec and Codec.EncodeEBH1) then return nil, "export codec unavailable" end
    local entries, seen = {}, {}
    for _, p in pairs(pending) do
        entries[#entries + 1] = { spellId = p.spellId, quality = p.quality,
            stacks = p.lockIntent and 1 or p.stacks, locked = p.lockIntent and true or nil }
        seen[p.spellId] = true
    end
    -- Designed-but-not-yet-locked entries were previously dropped entirely on
    -- export -- a real data-loss bug (importing an 85-Echo build, then
    -- exporting again, silently lost the 6 designed locked picks). Tag them
    -- with the EBH1 4th field so a re-import recognizes the same intent.
    for _, p in pairs(pendingLock) do
        if not seen[p.spellId] then
            entries[#entries + 1] = { spellId = p.spellId, quality = p.quality, stacks = 1, locked = true }
            seen[p.spellId] = true
        end
    end
    if Adapter and Adapter.LockedOwned then
        local locked = Adapter.LockedOwned()
        local catalog = Adapter.Catalog and Adapter.Catalog()
        if locked and type(locked.bySpell) == "table" then
            for id, n in pairs(locked.bySpell) do
                if not seen[id] then
                    local row = catalog and catalog.rows and catalog.rows[id]
                    entries[#entries + 1] = { spellId = id,
                        quality = row and tonumber(row.quality) or 0, stacks = n, locked = true }
                    seen[id] = true
                end
            end
        end
    end
    -- `and`/`or` always collapse to a single value in Lua, even here -- a
    -- direct call is required to keep UnitClass's second return value.
    local classToken = ""
    if UnitClass then
        local _, eng = UnitClass("player")
        classToken = eng or ""
    end
    local name = (editingContext and editingContext.name)
        or (wishlistNameBox and wishlistNameBox:GetText())
        or (Adapter and Adapter.Wishlist and Adapter.Wishlist() and Adapter.Wishlist().name)
        or "Nexus"
    return Codec.EncodeEBH1(entries, classToken, name)
end

local function TrimWishlistName(name)
    name = tostring(name or "")
    return name:gsub("^%s+", ""):gsub("%s+$", "")
end

-- An import is always a new wishlist draft. It must never inherit the current
-- editing slot, because pressing Save after an import would otherwise update
-- (overwrite) the wishlist the player had open before importing.
local function LoadImportedWishlist(parsed, chosenName)
    if not parsed or type(parsed.entries) ~= "table" or #parsed.entries == 0 then return false end
    -- ImportEBH1String already moved the editor onto a completely blank new
    -- draft before the naming prompt. Load only the decoded records here so
    -- no selected rows or overflow state from the previously-open build can
    -- survive into the imported wishlist.
    LoadPendingEchoes(parsed.entries)
    pendingSeeded = true
    scrollOffset, pickOffset = 0, 0
    if wishlistNameBox then wishlistNameBox:SetText(TrimWishlistName(chosenName)) end
    M.Refresh()
    print(string.format("|cff4dff80Nexus:|r imported %d Echo entr%s as new wishlist '%s'. Review and Create Wishlist when ready.",
        #parsed.entries, #parsed.entries == 1 and "y" or "ies", TrimWishlistName(chosenName)))
    return true
end

function M.ImportEBH1String(text, chosenName)
    local Codec = Nexus and Nexus.Codec
    if not (Codec and Codec.DecodeEBH1) then
        print("|cffff6060Nexus:|r import codec unavailable")
        return
    end
    local parsed = Codec.DecodeEBH1(text)
    if not parsed or #parsed.entries == 0 then
        print("|cffff6060Nexus:|r couldn't parse that as an EBH1 string.")
        return
    end

    -- A valid import immediately leaves the old editing context and clears
    -- every visible/local selection before the naming step. This makes the
    -- imported list unambiguous and prevents stale selected rows from the
    -- previously-open wishlist appearing to be part of the import.
    M.NewWishlist()

    local name = TrimWishlistName(chosenName)
    if name ~= "" then
        LoadImportedWishlist(parsed, name)
        return
    end
    StaticPopup_Show("NEXUS_NAME_IMPORTED_WISHLIST",
        TrimWishlistName(parsed.name) ~= "" and TrimWishlistName(parsed.name) or "Imported Wishlist",
        nil, parsed)
end

-- Dedicated slot-picker entry point: click an empty locked slot (enters
-- assign mode), then click any Echo -- either the browsable catalog on the
-- left or an already-selected Echo on the right -- to fill it. `data` is
-- whatever that row's click handler already has on hand (a catalog row or
-- a pending entry), so this never needs to re-resolve a name against the
-- catalog. Reuses AddPending's existing "queue it if the wishlist is full"
-- fallback rather than duplicating that logic -- if AddPending ends up
-- queueing it, it has already printed its own message and already tagged
-- the queued entry's .replaces, so nothing further happens here for that case.
local function AssignLockSlotFromData(data)
    if not data or not tonumber(data.spellId) then return end
    local catalog = Adapter and Adapter.Catalog and Adapter.Catalog()
    local id = tonumber(data.spellId)
    local family = PendingFamily(id, catalog)
    local p = pending[family]

    if p then
        if not p.lockIntent then
            if LockBudgetUsed(replacingSpellId) >= MAX_LOCK_SLOTS then
                print(string.format("|cffff6060Nexus:|r only %d Echoes can be locked in total.", MAX_LOCK_SLOTS))
                replacingSpellId = nil
                return
            end
            p.lockIntent = true
            p.replaces = replacingSpellId
            p.stacks = 1
        end
        print("|cff4dff80Nexus:|r " .. tostring(data.name) .. " is now designed for a locked slot and no longer consumes the 79-copy wishlist budget.")
        replacingSpellId = nil
        return
    end

    if pendingLock[family] then
        print("|cff4dff80Nexus:|r " .. tostring(data.name) .. " is already designed for a locked slot.")
        replacingSpellId = nil
        return
    end
    if LockBudgetUsed(replacingSpellId) >= MAX_LOCK_SLOTS then
        print(string.format("|cffff6060Nexus:|r only %d Echoes can be locked in total.", MAX_LOCK_SLOTS))
        replacingSpellId = nil
        return
    end

    local row = catalog and catalog.rows and catalog.rows[id]
    pendingLock[family] = { spellId = id, family = family,
        quality = tonumber((row and row.quality) or data.quality) or 0,
        name = tostring((row and row.name) or data.name or ("spell " .. tostring(id))),
        replaces = replacingSpellId }
    print("|cff4dff80Nexus:|r added " .. tostring(data.name)
        .. " as a locked-slot target. It is pursued separately from the 79-copy wishlist.")
    replacingSpellId = nil
end

StaticPopupDialogs["NEXUS_EXPORT_WISHLIST"] = {
    text = "Your current wishlist + locked Echoes, as an EBH1 string.\nCtrl+A, Ctrl+C to copy:",
    button1 = "Close",
    hasEditBox = true,
    editBoxWidth = 350,
    OnShow = function(self)
        self.editBox:SetText((ExportEBH1String()) or "")
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["NEXUS_NAME_IMPORTED_WISHLIST"] = {
    text = "Choose a name for this imported wishlist:\n%s",
    button1 = "Load Import",
    button2 = "Cancel",
    hasEditBox = true,
    editBoxWidth = 300,
    OnShow = function(self)
        local suggested = TrimWishlistName(self.data and self.data.name)
        if suggested == "" then suggested = "Imported Wishlist" end
        self.editBox:SetText(suggested)
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    OnAccept = function(self, parsed)
        local name = TrimWishlistName(self.editBox and self.editBox:GetText())
        if name == "" then
            print("|cffff6060Nexus:|r Enter a name for the imported wishlist.")
            return
        end
        LoadImportedWishlist(parsed, name)
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["NEXUS_IMPORT_WISHLIST"] = {
    text = "Paste an EBH1 wishlist string:\nThe import will be loaded as a new wishlist and will not overwrite the one currently open.",
    button1 = "Continue",
    button2 = "Cancel",
    hasEditBox = true,
    editBoxWidth = 350,
    OnAccept = function(self)
        M.ImportEBH1String(self.editBox and self.editBox:GetText())
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function ApplyPending()
    if not (Adapter and Adapter.UploadWishlist) then
        print("|cffff6060Nexus:|r adapter not ready.")
        return
    end
    local echoes = CanonicalEchoes()
    if #echoes == 0 then
        print("|cffff6060Nexus:|r pending list is empty -- add something first.")
        return
    end
    local slot = editingContext and tonumber(editingContext.slot) or 0
    local name
    if editingContext then
        name = tostring(editingContext.name or "Wishlist")
    else
        name = wishlistNameBox and tostring(wishlistNameBox:GetText() or "") or ""
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then
            print("|cffff6060Nexus:|r Enter a wishlist name before saving.")
            if wishlistNameBox then wishlistNameBox:SetFocus() end
            return
        end
    end
    local data = { slot = slot, name = name, echoes = echoes }
    if editingContext then
        StaticPopup_Show("WISHLISTREALIZER_UPDATE_WISHLIST", EchoListTotal(echoes), name, data)
    else
        StaticPopup_Show("WISHLISTREALIZER_CREATE_WISHLIST", name, EchoListTotal(echoes), data)
    end
end


local function ShowEchoTooltip(owner, spellId, anchor)
    if not owner or not GameTooltip then return end

    local id = tonumber(spellId)
    GameTooltip:Hide()
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")

    -- Project Ebonhold runs on the 3.3.5 client. SetSpellByID is not a
    -- reliable tooltip API there; spell hyperlinks provide the complete
    -- server tooltip without breaking the row's mouse scripts.
    if id and GameTooltip.SetHyperlink then
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. tostring(id))
        if ok then
            GameTooltip:Show()
            return
        end
    end

    local name, _, icon = nil, nil, nil
    if id and GetSpellInfo then
        local ok, spellName, _, spellIcon = pcall(GetSpellInfo, id)
        if ok then
            name, icon = spellName, spellIcon
        end
    end

    GameTooltip:AddLine(name or ("Echo " .. tostring(id or "")), 1, 1, 1)
    if icon then
        GameTooltip:AddTexture(icon)
    end
    GameTooltip:Show()
end

local function SpellIcon(spellId)
    if not spellId then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    local ok, _, _, icon = pcall(GetSpellInfo, spellId)
    return (ok and icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function CandidateAssignment(candidate)
    if type(candidate) ~= "table" then return nil, nil end
    local slots = Adapter and Adapter.Slots and Adapter.Slots()
    if not slots then return nil, nil end
    local active = tonumber(slots.activeSlot)
    local maxSlots = tonumber(slots.maxSlots) or 5
    local fallbackSlot, fallbackName
    for slotId, row in pairs(slots.bySlot or {}) do
        slotId = tonumber(slotId)
        if slotId and slotId >= 1 and slotId <= maxSlots and row and type(row.echoes) == "table" and #row.echoes > 0 then
            local linked = Adapter.GetLoadoutWishlist and Adapter.GetLoadoutWishlist(slotId)
            if linked and ((candidate.key and linked.key == candidate.key)
                or (tonumber(linked.slot) == tonumber(candidate.slot))) then
                local nm = tostring(row.name or "")
                if nm == "" then nm = "Saved Build " .. tostring(slotId) end
                if slotId == active then return slotId, nm end
                fallbackSlot, fallbackName = fallbackSlot or slotId, fallbackName or nm
            end
        end
    end
    return fallbackSlot, fallbackName
end

local function StyleWishlistSelector(button)
    button:SetNormalFontObject("GameFontHighlightSmall")
    button:SetHighlightFontObject("GameFontNormalSmall")
    button:SetPushedTextOffset(0, -1)
    pcall(function()
        button:SetBackdrop({
            bgFile="Interface\\Buttons\\WHITE8X8",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=false, edgeSize=10,
            insets={left=2,right=2,top=2,bottom=2},
        })
        button:SetBackdropColor(0.025,0.03,0.04,0.96)
        button:SetBackdropBorderColor(0.38,0.38,0.42,0.95)
    end)
    local fs = button:GetFontString()
    if fs then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", button, "LEFT", 9, 0)
        fs:SetPoint("RIGHT", button, "RIGHT", -22, 0)
        fs:SetJustifyH("LEFT")
    end
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(12,12)
    arrow:SetPoint("RIGHT", button, "RIGHT", -7, 0)
    button._arrow = arrow
end

local function HideWishlistSwitchMenu()
    if wishlistSwitchMenu then wishlistSwitchMenu:Hide() end
end

local function ShowWishlistSwitchMenu(anchor)
    if wishlistSwitchMenu and frame and wishlistSwitchMenu:GetParent() ~= frame then wishlistSwitchMenu:SetParent(frame) end
    local candidates = (Adapter and Adapter.GetWishlistCandidates and Adapter.GetWishlistCandidates()) or {}
    if not wishlistSwitchMenu then
        wishlistSwitchMenu = CreateFrame("Frame", "NexusWishlistEditorSwitchMenu", frame or UIParent)
        wishlistSwitchMenu:SetFrameStrata("TOOLTIP")
        wishlistSwitchMenu:SetFrameLevel((frame and frame:GetFrameLevel() or 50) + 100)
        wishlistSwitchMenu:SetToplevel(true)
        wishlistSwitchMenu:EnableMouse(true)
        wishlistSwitchMenu.rows = {}
        pcall(function()
            wishlistSwitchMenu:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            wishlistSwitchMenu:SetBackdropColor(0.015, 0.02, 0.03, 0.99)
            wishlistSwitchMenu:SetBackdropBorderColor(0.48, 0.42, 0.25, 1)
        end)
    end
    local visible = math.min(#candidates, 10)
    wishlistSwitchMenu:SetSize(286, 18 + math.max(1, visible) * 24)
    wishlistSwitchMenu:ClearAllPoints()
    wishlistSwitchMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)
    for i = 1, math.max(1, visible) do
        local row = wishlistSwitchMenu.rows[i]
        if not row then
            -- Real template buttons stay visibly enabled and reliably clickable
            -- above the editor on 3.3.5 clients.
            row = CreateFrame("Button", nil, wishlistSwitchMenu)
            row:SetSize(270, 22)
            row:SetPoint("TOPLEFT", 8, -8 - ((i - 1) * 24))
            row:EnableMouse(true)
            row:RegisterForClicks("LeftButtonUp")
            row:SetFrameLevel(wishlistSwitchMenu:GetFrameLevel() + 2)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            local check = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            check:SetPoint("LEFT", 7, 0)
            check:SetText("+")
            check:Hide()
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", check, "RIGHT", 7, 0)
            label:SetPoint("RIGHT", row, "RIGHT", -7, 0)
            label:SetJustifyH("LEFT")
            row._check = check
            row._label = label
            wishlistSwitchMenu.rows[i] = row
        end
        local c = candidates[i]
        if c then
            local assignedSlot, assignedName = CandidateAssignment(c)
            local current = editingContext and ((editingContext.key and c.key == editingContext.key)
                or tonumber(editingContext.slot) == tonumber(c.slot))
            local wishlistLabel = tostring(c.name ~= "" and c.name or ("Wishlist " .. tostring(c.slot)))
            local suffix = assignedName and ("  |cff777777Assigned: " .. tostring(assignedName) .. "|r") or "  |cff666666Unassigned|r"
            row._label:SetText(wishlistLabel .. suffix)
            if current then
                row._check:SetText("+")
                row._check:SetTextColor(0.3,1,0.5)
                row._check:Show()
                row._label:SetTextColor(1,0.82,0.2)
            else
                row._check:Hide()
                row._label:SetTextColor(0.92,0.92,0.92)
            end
            row:Enable()
            -- Snapshot this row's values so each click opens the intended wishlist.
            local openCandidate = {
                slot = c.slot, name = c.name, key = c.key, echoes = c.echoes,
                loadoutName = assignedName or "Not assigned",
            }
            local openAssignedSlot = assignedSlot
            row:SetScript("OnClick", function()
                HideWishlistSwitchMenu()
                M.OpenForWishlist(openCandidate, openAssignedSlot)
            end)
            row:Show()
        else
            row._label:SetText("No saved wishlists found")
            row._label:SetTextColor(0.55,0.55,0.55)
            row._check:Hide()
            row:SetScript("OnClick", nil)
            row:SetScript("OnMouseDown", nil)
            row:Disable()
            row:Show()
        end
    end
    for i = math.max(1, visible) + 1, #wishlistSwitchMenu.rows do
        wishlistSwitchMenu.rows[i]:Hide()
    end
    wishlistSwitchMenu:Show()
end


local function HideLoadoutSwitchMenu()
    if loadoutSwitchMenu then loadoutSwitchMenu:Hide() end
end

local function LoadEditorForLoadout(slot)
    slot = tonumber(slot)
    if not slot then return end
    local slots = Adapter and Adapter.Slots and Adapter.Slots()
    local row = slots and slots.bySlot and slots.bySlot[slot]
    local name = row and tostring(row.name or "") or ""
    if name == "" then name = "Saved Build " .. tostring(slot) end

    local linked = Adapter and Adapter.GetLoadoutWishlist and Adapter.GetLoadoutWishlist(slot)
    if linked and tonumber(linked.slot) then
        linked.loadoutName = name
        M.OpenForWishlist(linked, slot)
        return
    end

    editingContext = nil
    createTargetContext = { loadoutSlot = slot, loadoutName = name }
    pending = {}
    currentLockKey = 0
    pendingSeeded = true
    if wishlistNameBox then wishlistNameBox:SetText("") end
    M.Refresh()
end

local function ShowLoadoutSwitchMenu(anchor)
    if loadoutSwitchMenu and frame and loadoutSwitchMenu:GetParent() ~= frame then loadoutSwitchMenu:SetParent(frame) end
    -- Saved Builds are the server's fixed slots 1-5. Build this selector
    -- directly from those slots instead of relying on inferred candidates.
    local slots = Adapter and Adapter.Slots and Adapter.Slots()
    local active = slots and tonumber(slots.activeSlot) or 0
    local candidates = {}
    for slot = 1, 5 do
        local data = slots and slots.bySlot and slots.bySlot[slot]
        local name = data and tostring(data.name or "") or ""
        if name == "" then name = "Loadout " .. tostring(slot) end
        local linked = Adapter and Adapter.GetLoadoutWishlist and Adapter.GetLoadoutWishlist(slot)
        candidates[#candidates + 1] = {
            slot = slot,
            name = name,
            active = active == slot,
            available = data ~= nil,
            wishlist = linked,
        }
    end
    if not loadoutSwitchMenu then
        loadoutSwitchMenu = CreateFrame("Frame", "NexusWishlistEditorLoadoutMenu", frame or UIParent)
        loadoutSwitchMenu:SetFrameStrata("TOOLTIP")
        loadoutSwitchMenu:SetFrameLevel((frame and frame:GetFrameLevel() or 50) + 101)
        loadoutSwitchMenu:SetToplevel(true)
        loadoutSwitchMenu:EnableMouse(true)
        loadoutSwitchMenu.rows = {}
        pcall(function()
            loadoutSwitchMenu:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            loadoutSwitchMenu:SetBackdropColor(0.015, 0.02, 0.03, 0.99)
            loadoutSwitchMenu:SetBackdropBorderColor(0.48, 0.42, 0.25, 1)
        end)
    end
    local visible = 5
    loadoutSwitchMenu:SetSize(230, 18 + math.max(1, visible) * 24)
    loadoutSwitchMenu:ClearAllPoints()
    loadoutSwitchMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)
    for i = 1, math.max(1, visible) do
        local row = loadoutSwitchMenu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, loadoutSwitchMenu)
            row:SetSize(214, 22)
            row:SetPoint("TOPLEFT", 8, -8 - ((i - 1) * 24))
            row:EnableMouse(true)
            row:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
            row:SetFrameLevel(loadoutSwitchMenu:GetFrameLevel() + 2)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", 8, 0)
            label:SetPoint("RIGHT", -8, 0)
            label:SetJustifyH("LEFT")
            row._label = label
            loadoutSwitchMenu.rows[i] = row
        end
        local c = candidates[i]
        if c then
            local label = tostring(c.name or "")
            if label == "" then label = "Saved Build " .. tostring(c.slot) end
            local suffix = c.wishlist and ("  |cff777777" .. tostring(c.wishlist.name or "Wishlist") .. "|r")
                or "  |cff666666No wishlist|r"
            row._label:SetText((c.active and "|cffffd200" or "|cffffffff") .. label .. "|r" .. suffix)
            local targetSlot = tonumber(c.slot)
            local alreadyActive = c.active == true
            if c.available then
                row:Enable()
                local function SelectLoadoutRow()
                    -- This selector chooses which Saved Build's association is
                    -- being edited. It intentionally does not activate the server
                    -- loadout; that action is level-gated and not required here.
                    HideLoadoutSwitchMenu()
                    HideWishlistSwitchMenu()
                    pendingLoadoutOpen = nil
                    LoadEditorForLoadout(targetSlot)
                end
                row:SetScript("OnMouseDown", function(_, button)
                    if button == "LeftButton" then SelectLoadoutRow() end
                end)
                row:SetScript("OnClick", nil)
            else
                row:Disable()
                row:SetScript("OnClick", nil)
                row:SetScript("OnMouseDown", nil)
                row._label:SetText("|cff666666Loadout " .. tostring(targetSlot) .. "  Empty|r")
            end
            row:Show()
        else
            row._label:SetText("No saved loadouts found")
            row._label:SetTextColor(0.55,0.55,0.55)
            row:SetScript("OnClick", nil)
            row:Disable()
            row:Show()
        end
    end
    for i = math.max(1, visible) + 1, #loadoutSwitchMenu.rows do
        loadoutSwitchMenu.rows[i]:Hide()
    end
    loadoutSwitchMenu:Show()
end

------------------------------------------------------------------------
-- Frame construction
------------------------------------------------------------------------

local function EnsureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "NexusEditorFrame", UIParent)
    frame:SetClampedToScreen(true)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "NexusEditorFrame")
    end
    frame:SetSize(1040, 680)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(50)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local refreshTicker = 0
    local applyTicker = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        applyTicker = applyTicker + (elapsed or 0)
        if applyTicker >= 0.5 then
            applyTicker = 0
            if M._PumpApplyRetry then M._PumpApplyRetry() end
        end
        refreshTicker = refreshTicker + (elapsed or 0)
        if refreshTicker >= 0.5 then
            refreshTicker = 0
            -- Go quiet during a PerkService sniff (/nexus sniff): this
            -- ticker's own Adapter.Slots() polling (both the check below and
            -- inside M.Refresh() itself) would otherwise keep calling
            -- GetServerBuildSlots/GetServerActiveSlot/GetServerMaxSlots every
            -- half second regardless of Main.lua's own poll pause, flooding
            -- the 200-call ring buffer with noise unrelated to whatever the
            -- player is actually doing in the native lock UI.
            if not (Nexus and Nexus.sniffPaused) then
                HideServerEchoUI()
                if pendingLoadoutOpen then
                    local slots = Adapter and Adapter.Slots and Adapter.Slots()
                    local active = slots and tonumber(slots.activeSlot)
                    if active == tonumber(pendingLoadoutOpen.slot)
                        or (GetTime() - (pendingLoadoutOpen.at or 0)) >= 1.5 then
                        local target = pendingLoadoutOpen.slot
                        pendingLoadoutOpen = nil
                        LoadEditorForLoadout(target)
                    end
                end
                M.Refresh()
            end
        end
    end)
    frame:SetScript("OnShow", function() HideServerEchoUI() end)
    frame:SetScript("OnHide", function()
        if displayPopup then displayPopup:Hide() end
        HideWishlistSwitchMenu()
        HideLoadoutSwitchMenu()
    end)
    frame:Hide()

    titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", 0, -14)
    titleText:SetText("Nexus Wishlist Editor")

    editContextText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    editContextText:SetPoint("TOP", titleText, "BOTTOM", 0, -4)
    editContextText:SetSize(900, 18)
    editContextText:SetJustifyH("CENTER")
    editContextText:SetText("Creating a new wishlist")

    wishlistNameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wishlistNameLabel:SetPoint("TOPLEFT", 34, -96)
    wishlistNameLabel:SetText("Wishlist name:")

    wishlistNameBox = CreateFrame("EditBox", "NexusWishlistNameInput", frame, "InputBoxTemplate")
    wishlistNameBox:SetSize(260, 22)
    wishlistNameBox:SetPoint("LEFT", wishlistNameLabel, "RIGHT", 10, 0)
    wishlistNameBox:SetAutoFocus(false)
    wishlistNameBox:SetMaxLetters(48)
    wishlistNameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    wishlistNameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local buildsNav = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    buildsNav:SetSize(88, 22)
    buildsNav:SetPoint("TOPLEFT", 18, -12)
    buildsNav:SetText("Builds")
    buildsNav:SetScript("OnClick", function()
        frame:Hide()
        if Nexus.CommunityBuilds then Nexus.CommunityBuilds.Show() end
    end)
    local boardNav = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    boardNav:SetSize(102, 22)
    boardNav:SetPoint("LEFT", buildsNav, "RIGHT", 4, 0)
    boardNav:SetText("Leaderboard")
    boardNav:SetScript("OnClick", function()
        frame:Hide()
        if Nexus.Leaderboard then Nexus.Leaderboard.Show() end
    end)
    local wishNav = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    wishNav:SetSize(92, 22)
    wishNav:SetPoint("LEFT", boardNav, "RIGHT", 4, 0)
    wishNav:SetText("|cffffd200Wishlists|r")
    wishNav:Disable()

    loadoutSwitchBtn = CreateFrame("Button", nil, frame)
    loadoutSwitchBtn:SetSize(230, 22)
    loadoutSwitchBtn:SetPoint("TOPLEFT", 34, -66)
    loadoutSwitchBtn:SetText("Loadout: choose build")
    StyleWishlistSelector(loadoutSwitchBtn)
    loadoutSwitchBtn:Enable()
    local loadoutFont = loadoutSwitchBtn:GetFontString()
    if loadoutFont then loadoutFont:SetTextColor(0.92, 0.92, 0.92) end
    loadoutSwitchBtn:SetScript("OnClick", function(self)
        HideWishlistSwitchMenu()
        if loadoutSwitchMenu and loadoutSwitchMenu:IsShown() then
            HideLoadoutSwitchMenu()
        else
            ShowLoadoutSwitchMenu(self)
        end
    end)
    loadoutSwitchBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Swap Saved Build", 1, 0.8, 0.3)
        GameTooltip:AddLine("Activate another server loadout and immediately edit its associated wishlist.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    loadoutSwitchBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    wishlistSwitchBtn = CreateFrame("Button", nil, frame)
    wishlistSwitchBtn:SetSize(270, 22)
    wishlistSwitchBtn:SetPoint("LEFT", loadoutSwitchBtn, "RIGHT", 8, 0)
    wishlistSwitchBtn:SetText("Choose wishlist to edit")
    StyleWishlistSelector(wishlistSwitchBtn)
    wishlistSwitchBtn:SetScript("OnClick", function(self)
        HideLoadoutSwitchMenu()
        if wishlistSwitchMenu and wishlistSwitchMenu:IsShown() then
            HideWishlistSwitchMenu()
        else
            ShowWishlistSwitchMenu(self)
        end
    end)
    wishlistSwitchBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Switch wishlist", 1, 0.8, 0.3)
        GameTooltip:AddLine("Open a different saved wishlist in this editor.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    wishlistSwitchBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    newWishlistBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    newWishlistBtn:SetSize(112, 22)
    newWishlistBtn:SetPoint("LEFT", wishlistSwitchBtn, "RIGHT", 8, 0)
    newWishlistBtn:SetText("+ New Wishlist")
    newWishlistBtn:SetScript("OnClick", function()
        HideWishlistSwitchMenu()
        M.NewWishlist()
    end)

    -- Locked Echoes strip: the account's up to 6 permanent picks, PLUS an
    -- editable picker for slots that aren't really locked yet. Nexus has no
    -- server API to lock/unlock -- a real slot stays read-only (click jumps
    -- the search to it) -- but an empty or designed slot is fully editable
    -- right here: click empty to assign a target, click a gold (designed)
    -- slot to un-assign it. This is the dedicated slot picker requested in
    -- place of a lock toggle scattered across every row of the pick list.
    lockedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockedLabel:SetPoint("TOPLEFT", 540, -130)
    lockedLabel:SetText("Locked:")
    lockedLabel:Hide()

    lockedIcons = {}
    for i = 1, 6 do
        local btn = CreateFrame("Button", nil, frame)
        btn:SetSize(18, 18)
        if i == 1 then
            btn:SetPoint("LEFT", lockedLabel, "RIGHT", 8, 0)
        else
            btn:SetPoint("LEFT", lockedIcons[i - 1], "RIGHT", 4, 0)
        end
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetAllPoints(btn)
        btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnEnter", function(self)
            if self.slotState == "empty" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Empty locked slot", 1, 1, 1)
                GameTooltip:AddLine("Click to choose an Echo to pursue for it.", 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            elseif self.spellId then
                ShowEchoTooltip(self, self.spellId, "ANCHOR_RIGHT")
                if self.slotState == "designed" then
                    GameTooltip:AddLine("Designed, not locked yet -- click to un-assign.", 1, 0.85, 0.3, true)
                    GameTooltip:Show()
                elseif self.slotState == "locked" then
                    if self.beingReplaced then
                        GameTooltip:AddLine("A replacement is designed for this slot (the gold icon) "
                            .. "-- Nexus will unlock this one and lock the new one in automatically "
                            .. "once it's acquired. Un-assign the gold Echo to cancel.", 1, 0.6, 0.4, true)
                    else
                        GameTooltip:AddLine("Left-click: find in catalog", 0.8, 0.8, 0.8, true)
                        GameTooltip:AddLine("Right-click: design a replacement for this slot", 0.8, 0.8, 0.8, true)
                    end
                    GameTooltip:Show()
                end
            end
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- GameAdapter.LockPerk/UnlockPerk (confirmed live via /nexus sniff,
        -- 2026-08-01) actually perform the lock/unlock -- this only lets
        -- the player START pursuing a replacement now, while the current
        -- one stays locked and useful; Main.lua's TryAutoLock unlocks the
        -- old one and locks the new one in automatically once it's owned.
        btn:SetScript("OnClick", function(self, mouseButton)
            if self.slotState == "locked" and mouseButton == "RightButton" then
                if self.spellId then
                    if replacingSpellId == self.spellId then
                        assigningLockSlot = false
                        replacingSpellId = nil
                        print("|cff7fff7fNexus:|r cancelled.")
                    else
                        assigningLockSlot = true
                        replacingSpellId = self.spellId
                        print("|cff4dff80Nexus:|r click an Echo -- either list -- to design its "
                            .. "replacement. Your current one stays locked until Nexus swaps it "
                            .. "in automatically once you have the replacement.")
                    end
                    M.Refresh()
                end
                return
            end
            if self.slotState == "empty" then
                assigningLockSlot = not assigningLockSlot
                replacingSpellId = nil
                if assigningLockSlot then
                    print("|cff4dff80Nexus:|r click an Echo -- either list -- to assign it to this locked slot.")
                else
                    print("|cff7fff7fNexus:|r cancelled.")
                end
                M.Refresh()
                return
            end
            if self.slotState == "designed" then
                if self.family then ToggleDesignLock(self.family); M.Refresh() end
                return
            end
            if not self.spellId then return end
            local cat = Adapter and Adapter.Catalog and Adapter.Catalog()
            local row = cat and cat.rows and cat.rows[self.spellId]
            if row and row.name and searchBox then
                searchBox:SetText(row.name)
            end
        end)
        btn:Hide()
        lockedIcons[i] = btn
    end

    -- "Needed" row: directly above each locked-slot icon (anchored to its
    -- TOP, not a same-row neighbor) -- only shown for a column whose
    -- current Echo has an active replacement designed, so "what you have
    -- vs. what you're working toward" reads as a simple stacked pair
    -- instead of two unrelated icons sitting side by side.
    lockedNeedIcons = {}
    for i = 1, 6 do
        local btn = CreateFrame("Button", nil, frame)
        btn:SetSize(14, 14)
        btn:SetPoint("BOTTOM", lockedIcons[i], "TOP", 0, 2)
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetAllPoints(btn)
        btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        btn.icon:SetVertexColor(1, 0.85, 0.3)
        btn:SetScript("OnEnter", function(self)
            if not self.spellId then return end
            ShowEchoTooltip(self, self.spellId, "ANCHOR_TOP")
            GameTooltip:AddLine("Designed to replace the Echo below -- click to un-assign.", 1, 0.85, 0.3, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetScript("OnClick", function(self)
            if self.family then ToggleDesignLock(self.family); M.Refresh() end
        end)
        btn:Hide()
        lockedNeedIcons[i] = btn
    end

    -- Auto-lock opt-in: off by default (NexusDB.settings.autoLockEchoes,
    -- see DefaultProfile.lua and Main.lua's TryAutoLock). Deliberately
    -- separate from the main automation switch -- a player may want full
    -- board automation without also handing Nexus this specific, more
    -- consequential write action (LockPerk/UnlockPerk). Sits in the open
    -- space to the right of the locked-slot icon strip.
    autoLockCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    autoLockCheck:SetSize(22, 22)
    autoLockCheck:SetPoint("LEFT", lockedIcons[6], "RIGHT", 26, 0)
    autoLockCheck:SetScript("OnClick", function(self)
        NexusDB.settings = NexusDB.settings or {}
        NexusDB.settings.autoLockEchoes = self:GetChecked() and true or false
    end)
    autoLockCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Automate locked Echo slots", 1, 0.8, 0.3)
        GameTooltip:AddLine("Checked: Nexus locks/unlocks Echoes for your designed locked slots "
            .. "automatically once each is acquired.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Unchecked (default): Nexus only designs and pursues them -- you lock "
            .. "them in yourself in the character progression UI.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    autoLockCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local autoLockLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoLockLabel:SetPoint("LEFT", autoLockCheck, "RIGHT", 2, 0)
    autoLockLabel:SetText("Automate locked Echo slots")

    -- Nexus-native EBH1 import/export. Closures deliberately reference only
    -- the global StaticPopup_Show and a string literal -- no module-level
    -- upvalues added to this function (see the EnsureFrame upvalue-limit
    -- crash, Dev Test 17; Create() gets the same treatment on principle).
    local exportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportBtn:SetSize(70, 22)
    exportBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -100)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function() StaticPopup_Show("NEXUS_EXPORT_WISHLIST") end)

    local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importBtn:SetSize(70, 22)
    importBtn:SetPoint("RIGHT", exportBtn, "LEFT", -4, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function() StaticPopup_Show("NEXUS_IMPORT_WISHLIST") end)

    -- Tracking status: shows EXACTLY what the addon currently believes
    -- the active wishlist is, rather than a bare "no wishlist" that reads
    -- as "you have none" when really it can also mean "you have several
    -- and none is marked active" (2026-07-24 -- this was silently
    -- swallowed before; A.GetWishlistCandidates() surfaces it properly).
    trackingText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trackingText:SetPoint("TOP", 0, -96)
    trackingText:SetSize(900, 16)
    trackingText:SetJustifyH("CENTER")

    -- Shown only when multiple designed wishlists exist and none is
    -- active -- one button per candidate, click to make it the active one.
    candidateButtons = {}
    for i = 1, 4 do
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(115, 20)
        b:SetPoint("TOP", frame, "TOP", -180 + ((i - 1) * 121), -112)
        b:Hide()
        candidateButtons[i] = b
    end

    -- Overlay controls, moved to the top-right where they're actually
    -- visible instead of buried at the bottom of a long window.
    local displayBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    displayBtn:SetSize(150, 22)
    displayBtn:SetPoint("TOPRIGHT", -34, -66)
    displayBtn:SetText("Display Settings")
    displayBtn:SetScript("OnClick", function(self) M.ToggleDisplayPopup(self) end)
    displayBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("On-screen wishlist settings", 1, 1, 1)
        GameTooltip:AddLine("Show/hide the always-on-screen list, and lock/unlock", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("it for moving.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    displayBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    searchBox = CreateFrame("EditBox", "NexusEditorSearch", frame,
        "InputBoxTemplate")
    searchBox:SetSize(330, 22)
    searchBox:SetPoint("TOPLEFT", 34, -126)
    searchBox:SetAutoFocus(false)
    searchBox:SetText(NexusDB.editorSearch or "")
    searchBox:SetScript("OnTextChanged", function(self)
        NexusDB.editorSearch = self:GetText() or ""
        scrollOffset = 0
        M.Refresh()
    end)

    classCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    classCheck:SetPoint("LEFT", searchBox, "RIGHT", 18, 0)
    classCheck:SetChecked(NexusDB.editorClassOnly ~= false)
    classCheck.text = classCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classCheck.text:SetPoint("LEFT", classCheck, "RIGHT", -2, 1)
    classCheck.text:SetText("Current class only")
    classCheck:SetScript("OnClick", function(self)
        NexusDB.editorClassOnly = self:GetChecked() and true or false
        scrollOffset = 0
        M.Refresh()
    end)

    -- Opens Nexus Builds directly -- our own working community-sharing
    -- system (core/Sync.lua), not a best-effort guess at the game's own
    -- UI. That guess-based version is retired now that we have a real one.
    local communityBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    communityBtn:SetSize(140, 22)
    communityBtn:SetPoint("TOPRIGHT", -34, -126)
    communityBtn:SetText("Nexus Builds")
    communityBtn:SetScript("OnClick", function()
        if Nexus.CommunityBuilds then
            Nexus.CommunityBuilds.Show()
        else
            print("|cffff6060Nexus:|r Nexus Builds unavailable")
        end
    end)
    communityBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Browse and post shared wishlists", 1, 1, 1)
        GameTooltip:AddLine("Opens Nexus Builds -- see what other players running", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Nexus have posted, or share your own.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    communityBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    communityBtn:Hide()

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header:SetPoint("TOPLEFT", 34, -158)
    header:SetText("Choose Echoes from the catalog. A wishlist can contain up to 79 total Echoes; + / - adjusts stack copies.")

    -- Left: browsable catalog -----------------------------------------
    local leftArea = CreateFrame("Frame", nil, frame)
    leftArea:SetPoint("TOPLEFT", 34, -180)
    leftArea:SetSize(600, MAX_ROWS * ROW_HEIGHT)
    leftArea:EnableMouseWheel(true)
    leftArea:SetScript("OnMouseWheel", function(_, delta)
        scrollOffset = math.max(0, scrollOffset - delta * 3)
        M.Refresh()
    end)

    rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, leftArea)
        row:SetSize(600, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))
        row:EnableMouse(true)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            scrollOffset = math.max(0, scrollOffset - delta * 3)
            M.Refresh()
        end)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 0, 0)
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetSize(420, ROW_HEIGHT)
        row.text:SetJustifyH("LEFT")

        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.status:SetPoint("RIGHT", row, "RIGHT", -12, 0)
        row.status:SetSize(110, ROW_HEIGHT)
        row.status:SetJustifyH("RIGHT")

        row:SetScript("OnEnter", function(self)
            if not self.data then return end
            ShowEchoTooltip(self, self.data.spellId, "ANCHOR_RIGHT")
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            if not self.data then return end
            if assigningLockSlot then
                AssignLockSlotFromData(self.data)
                assigningLockSlot = false
            else
                AddPending(self.data)
            end
            M.Refresh()
        end)

        rows[i] = row
    end

    footerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerText:SetPoint("BOTTOMLEFT", 34, 26)
    footerText:SetJustifyH("LEFT")

    -- Right: pending picks ----------------------------------------------
    local pickTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pickTitle:SetPoint("TOPLEFT", 674, -158)
    pickTitle:SetText("Selected Echoes")

    local pickArea = CreateFrame("Frame", nil, frame)
    pickArea:SetPoint("TOPLEFT", 674, -180)
    pickArea:SetSize(332, PICK_ROWS * ROW_HEIGHT)
    pickArea:EnableMouseWheel(true)
    pickArea:SetScript("OnMouseWheel", function(_, delta)
        pickOffset = math.max(0, pickOffset - delta * 3)
        M.Refresh()
    end)

    pickRows = {}
    for i = 1, PICK_ROWS do
        local row = CreateFrame("Button", nil, pickArea)
        row:SetSize(332, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))
        row:EnableMouse(true)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            pickOffset = math.max(0, pickOffset - delta * 3)
            M.Refresh()
        end)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 0, 0)
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetSize(224, ROW_HEIGHT)
        row.text:SetJustifyH("LEFT")

        row.minus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.minus:SetSize(22, 20); row.minus:SetPoint("RIGHT", -48, 0); row.minus:SetText("-")
        row.plus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.plus:SetSize(22, 20); row.plus:SetPoint("RIGHT", -24, 0); row.plus:SetText("+")
        row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        row.remove:SetSize(22, 22); row.remove:SetPoint("RIGHT", 0, 0)
        row.minus:SetScript("OnClick", function(self)
            local d = self:GetParent().data
            if d and not d.ghost then AdjustStacks(d.family, -1); M.Refresh() end
        end)
        row.plus:SetScript("OnClick", function(self)
            local d = self:GetParent().data
            if d and not d.ghost then AdjustStacks(d.family, 1); M.Refresh() end
        end)
        row.remove:SetScript("OnClick", function(self)
            local d = self:GetParent().data
            if d and not d.ghost then RemovePending(d.family); M.Refresh() end
        end)

        row:SetScript("OnEnter", function(self)
            if not self.data then return end
            ShowEchoTooltip(self, self.data.spellId, "ANCHOR_LEFT")
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Only meaningful while assign mode is active (see the locked-slot
        -- strip): assigns an already-selected, not-yet-designed Echo to the
        -- open slot. A no-op otherwise, so clicking here normally still
        -- does nothing -- adjustment stays on the +/-/X buttons.
        row:SetScript("OnClick", function(self)
            if not assigningLockSlot then return end
            local d = self.data
            if not d or d.ghost or d.toLock or d.lockIntent then return end
            ToggleDesignLock(d.family)
            assigningLockSlot = false
            M.Refresh()
        end)

        pickRows[i] = row
    end

    pickFooterText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pickFooterText:SetPoint("BOTTOMLEFT", 674, 56)
    pickFooterText:SetJustifyH("LEFT")

    -- Apply button: deliberately disabled until the real write function
    -- is known (see file header). Wire ApplyPending() and re-enable this
    -- once /nexus sniff has an answer.
    applyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    applyBtn:SetSize(332, 26)
    applyBtn:SetPoint("BOTTOMLEFT", 674, 24)
    applyBtn:SetText("Create Wishlist")
    applyBtn:SetScript("OnClick", ApplyPending)
    applyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(editingContext and "Save this associated wishlist" or "Create a server wishlist", 1, 0.8, 0.3)
        GameTooltip:AddLine(editingContext and
            ("Edits only: " .. tostring(editingContext.name or "Wishlist")) or
            "Uploads the pending Echo list as a new server wishlist.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("A confirmation is shown before anything is replaced.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    applyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Cosmetic only, deliberately last: every functional widget above
    -- already exists regardless of whether this succeeds (this exact
    -- ordering mistake -- a cosmetic call sitting BEFORE pickRows/
    -- applyBtn -- was why they never got created when SetColorTexture
    -- threw, live 2026-07-24).
    pcall(function()
        local divider = frame:CreateTexture(nil, "ARTWORK")
        divider:SetTexture(0.35, 0.35, 0.35, 0.65)
        divider:SetSize(1, 456)
        divider:SetPoint("TOPLEFT", 652, -180)
    end)

    -- Background -- this was simply never added (not a crash, just an
    -- oversight, 2026-07-24). Separate pcall from the divider above so
    -- either one failing can't take out the other.
    pcall(function()
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end)

    return frame
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------

function M.Refresh()
    if not frame then return end
    SeedPendingFromWishlist()

    local catalog = Adapter and Adapter.Catalog and Adapter.Catalog()
    local owned = Adapter and Adapter.Owned and Adapter.Owned()
    local ownedBySpell = (owned and owned.bySpell) or {}

    -- Read once per refresh, reused by the strip below, the catalog row
    -- loop further down (so an already-locked Echo shows "Locked" instead
    -- of an addable status there too), and the footer count -- one live
    -- source of truth instead of the load-time-only lastLockedSkipped.
    local lockedBySpell = {}
    if Adapter and Adapter.LockedOwned then
        local locked = Adapter.LockedOwned()
        if locked and type(locked.bySpell) == "table" then lockedBySpell = locked.bySpell end
    end
    local lockedCount = 0
    for _ in pairs(lockedBySpell) do lockedCount = lockedCount + 1 end

    -- Reconcile "awaiting lock" against reality: the moment LockedOwned()
    -- confirms one of these is actually locked, it belongs in the strip
    -- above instead, not here anymore -- drop it from the DRAFT (pendingLock/
    -- pending) so the UI stops showing it as still needing a lock.
    --
    -- Deliberately NOT clearing it from the COMMITTED store anymore (this
    -- used to also do `designTargets[id] = nil` here). Confirmed live: once
    -- TryAutoLock's own per-tick "wanted" check (core/Main.lua) is computed
    -- FROM the committed store, deleting a fulfilled entry from that store
    -- makes it invisible to that check on the very next tick -- so a design
    -- that had just been successfully locked in immediately looked like an
    -- Echo the wishlist doesn't want at all, and the eager shed pass
    -- unlocked it right back out again 10-20s later. Repeated for every
    -- design in turn: lock, vanish from the committed set, get shed, lock
    -- something else, repeat -- never converging on a stable 6 locked
    -- Echoes. Leaving fulfilled entries in the committed store is harmless
    -- (isLocked already skips re-processing them everywhere that reads it)
    -- and the table gets a full, clean replace on every real Save anyway
    -- (CommitLockDesignTargets), so there was never a real need to prune it
    -- here at all.
    for family, p in pairs(pendingLock) do
        if (tonumber(lockedBySpell[p.spellId]) or 0) > 0 then
            M._fulfilledDraftTargets[tonumber(p.spellId)] = p.replaces or true
            pendingLock[family] = nil
        end
    end

    -- Same reconciliation for the ACTIVE wishlist: an entry the player just
    -- locked in-game (native character progression UI, outside Nexus) no
    -- longer needs a wishlist slot -- drop it here too, immediately, rather
    -- than waiting for a full editor close/reopen to notice. This is what
    -- actually frees room for the promotion step below.
    for family, p in pairs(pending) do
        if (tonumber(lockedBySpell[p.spellId]) or 0) > 0 then
            if p.lockIntent then
                M._fulfilledDraftTargets[tonumber(p.spellId)] = p.replaces or true
            end
            pending[family] = nil
        end
    end

    -- Locked-slot targets remain separate from the ordinary 79-copy list.
    -- core/Main.lua injects every committed target into the live plan, so no
    -- promotion into `pending` is required when wishlist room opens.

    -- Locked Echoes strip: the dedicated slot picker. Real locked slots
    -- come from Adapter.LockedOwned/GetLockedPerks; when both automation
    -- switches are enabled, core/Main.lua reconciles them with LockPerk and
    -- UnlockPerk. Each real-locked column gets its
    -- own STABLE position; a designed replacement for it (right-click, or
    -- auto-paired on import -- see LoadPendingEchoes) renders directly
    -- ABOVE that exact column in lockedNeedIcons, not beside it, so
    -- current-vs-needed reads as one stacked pair instead of two icons
    -- that happen to sit in the same row. A designed target that ISN'T
    -- replacing anything (bound for a genuinely open slot) fills the next
    -- open column in the bottom row instead.
    if lockedLabel and lockedIcons then
        local realIds = {}
        for id in pairs(lockedBySpell) do realIds[#realIds + 1] = id end
        table.sort(realIds)

        -- Replacement pairing reads straight off each draft entry's own
        -- .replaces field now (set by LoadPendingEchoes/ToggleDesignLock/
        -- AssignLockSlotFromData) -- no separate committed-store lookup
        -- needed for what's still just being designed in this session.
        local designed = {}
        for fam, p in pairs(pending) do
            if p.lockIntent then
                local row = catalog and catalog.rows and catalog.rows[p.spellId]
                designed[#designed + 1] = { spellId = p.spellId, family = fam,
                    name = (row and row.name) or ("spell " .. tostring(p.spellId)), replaces = p.replaces }
            end
        end
        for fam, p in pairs(pendingLock) do
            designed[#designed + 1] = { spellId = p.spellId, family = fam, name = p.name, replaces = p.replaces }
        end
        table.sort(designed, function(a, b) return tostring(a.name) < tostring(b.name) end)

        local replacementFor, freshDesigned = {}, {}
        for _, d in ipairs(designed) do
            if type(d.replaces) == "number" then
                replacementFor[d.replaces] = d
            else
                freshDesigned[#freshDesigned + 1] = d
            end
        end

        -- Always show all MAX_LOCK_SLOTS slots, not just however many are
        -- currently locked -- an account with 5/6 locked was rendering as
        -- "Locked (5):" with no visible hint a 6th slot even existed.
        lockedLabel:SetText(string.format("Locked (%d/%d):", #realIds, MAX_LOCK_SLOTS))
        lockedLabel:Show()
        local fi = 1
        for i = 1, MAX_LOCK_SLOTS do
            local btn, needBtn = lockedIcons[i], lockedNeedIcons[i]
            local id = realIds[i]
            if id then
                local row = catalog and catalog.rows and catalog.rows[id]
                local replacement = replacementFor[id]
                btn.spellId = id
                btn.family = nil
                btn.slotState = "locked"
                btn.beingReplaced = replacement and true or nil
                btn.icon:SetTexture(SpellIcon(id))
                if replacement then
                    -- Dimmed: a replacement is already designed, directly above.
                    btn.icon:SetVertexColor(0.42, 0.42, 0.42)
                    needBtn.spellId = replacement.spellId
                    needBtn.family = replacement.family
                    needBtn.icon:SetTexture(SpellIcon(replacement.spellId))
                    needBtn:Show()
                else
                    if row then
                        local c = QUALITY_COLORS[tonumber(row.quality) or 0] or { 1, 1, 1 }
                        btn.icon:SetVertexColor(c[1], c[2], c[3])
                    else
                        btn.icon:SetVertexColor(1, 1, 1)
                    end
                    needBtn.spellId = nil
                    needBtn:Hide()
                end
                btn:Show()
            elseif freshDesigned[fi] then
                local d = freshDesigned[fi]
                fi = fi + 1
                btn.spellId = d.spellId
                btn.family = d.family
                btn.slotState = "designed"
                btn.beingReplaced = nil
                btn.icon:SetTexture(SpellIcon(d.spellId))
                btn.icon:SetVertexColor(1, 0.85, 0.3)
                btn:Show()
                needBtn.spellId = nil
                needBtn:Hide()
            else
                -- An open, unused locked slot -- shown as an empty outline
                -- and directly clickable to assign a pursuit target.
                btn.spellId = nil
                btn.family = nil
                btn.slotState = "empty"
                btn.beingReplaced = nil
                btn.icon:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent")
                btn.icon:SetVertexColor(1, 1, 1)
                btn:Show()
                needBtn.spellId = nil
                needBtn:Hide()
            end
        end
    end

    if autoLockCheck then
        autoLockCheck:SetChecked(NexusDB.settings and NexusDB.settings.autoLockEchoes and true or false)
    end

    -- Tracking status: show EXACTLY what's active, or why nothing is,
    -- rather than a bare "no wishlist" that reads as "you have none"
    -- when it might really mean "you have several, pick one".
    local wl = Adapter and Adapter.Wishlist and Adapter.Wishlist()
    if wl then
        trackingText:SetText(string.format("|cff4dff80Tracking:|r '%s' (%s, %d echoes)",
            (wl.name ~= "" and wl.name) or "(unnamed)", tostring(wl.source), EchoListTotal(wl.entries)))
        for _, b in ipairs(candidateButtons) do b:Hide() end
    else
        local candidates = (Adapter and Adapter.GetWishlistCandidates
            and Adapter.GetWishlistCandidates()) or {}
        if #candidates > 1 then
            trackingText:SetText(string.format(
                "|cffff9040%d wishlists found|r -- click one to assign it to the active loadout:",
                #candidates))
            for i, b in ipairs(candidateButtons) do
                local c = candidates[i]
                if c then
                    b:SetText(string.format("%s (%d)",
                        (c.name ~= "" and c.name) or ("Slot " .. tostring(c.slot)), c.count))
                    b:SetScript("OnClick", function()
                        local slots = Adapter.Slots and Adapter.Slots()
                        local active = slots and tonumber(slots.activeSlot)
                        local ok, err = active and Adapter.SetLoadoutWishlist
                            and Adapter.SetLoadoutWishlist(active, c.slot)
                        if ok then
                            print("|cff4dff80Nexus:|r associated '" .. tostring(c.name)
                                .. "' with Loadout " .. tostring(active) .. ".")
                            M.Refresh()
                        else
                            print("|cffff6060Nexus:|r " .. tostring(err or
                                "activate a real saved loadout first"))
                        end
                    end)
                    b:Show()
                else
                    b:Hide()
                end
            end
        elseif #candidates == 1 then
            -- Exactly one candidate but not yet flagged active by the
            -- server -- offer to activate it directly.
            trackingText:SetText("|cffff9040Found a wishlist|r -- click to assign it to the active loadout:")
            candidateButtons[1]:SetText(candidates[1].name ~= "" and candidates[1].name
                or ("Slot " .. tostring(candidates[1].slot)))
            candidateButtons[1]:SetScript("OnClick", function()
                local slots = Adapter.Slots and Adapter.Slots()
                local active = slots and tonumber(slots.activeSlot)
                local ok, err = active and Adapter.SetLoadoutWishlist
                    and Adapter.SetLoadoutWishlist(active, candidates[1].slot)
                if ok then
                    print("|cff4dff80Nexus:|r associated '" .. tostring(candidates[1].name)
                        .. "' with Loadout " .. tostring(active) .. ".")
                    M.Refresh()
                else
                    print("|cffff6060Nexus:|r " .. tostring(err or
                        "activate a real saved loadout first"))
                end
            end)
            candidateButtons[1]:Show()
            for i = 2, #candidateButtons do candidateButtons[i]:Hide() end
        else
            trackingText:SetText("|cff888888No wishlist yet|r -- build one below, or check Nexus Builds.")
            for _, b in ipairs(candidateButtons) do b:Hide() end
        end
    end

    if titleText and editContextText then
        if editingContext then
            titleText:SetText("Edit Wishlist")
            local buildLabel = editingContext.loadoutName
                or (editingContext.loadoutSlot and ("Saved Build " .. tostring(editingContext.loadoutSlot)))
                or "Not assigned"
            editContextText:SetText("Wishlist: |cff7fd5ff" .. tostring(editingContext.name or "Wishlist") .. "|r   •   Assigned to: |cffffffff" .. tostring(buildLabel) .. "|r")
        else
            titleText:SetText("Create New Wishlist")
            if createTargetContext then
                editContextText:SetText("New destination for |cffffffff"
                    .. tostring(createTargetContext.loadoutName or "Active Saved Build")
                    .. "|r — it will be associated automatically after saving")
            else
                editContextText:SetText("Create a new destination wishlist for your first run")
            end
        end
    end

    if loadoutSwitchBtn and not pendingLoadoutOpen then
        local slots = Adapter and Adapter.Slots and Adapter.Slots()
        local selected = editingContext and tonumber(editingContext.loadoutSlot)
            or (createTargetContext and tonumber(createTargetContext.loadoutSlot))
            or (slots and tonumber(slots.activeSlot))
        local selectedRow = selected and slots and slots.bySlot and slots.bySlot[selected]
        local selectedName = selectedRow and tostring(selectedRow.name or "") or ""
        if selected and selected > 0 then
            if selectedName == "" then selectedName = "Saved Build " .. tostring(selected) end
            loadoutSwitchBtn:SetText("Loadout: " .. selectedName)
        else
            loadoutSwitchBtn:SetText("Loadout: choose build")
        end
    end

    if wishlistSwitchBtn then
        if editingContext then
            wishlistSwitchBtn:SetText("Editing: " .. tostring(editingContext.name or "Wishlist"))
        else
            wishlistSwitchBtn:SetText("New Wishlist  -  choose another")
        end
    end

    if wishlistNameLabel and wishlistNameBox then
        if editingContext then
            wishlistNameLabel:Hide()
            wishlistNameBox:Hide()
            trackingText:Hide()
            for _, b in ipairs(candidateButtons or {}) do b:Hide() end
        else
            wishlistNameLabel:Show()
            wishlistNameBox:Show()
            trackingText:Hide()
            for _, b in ipairs(candidateButtons or {}) do b:Hide() end
        end
    end

    if applyBtn then
        local saving = M.IsApplyPending()
        applyBtn:SetText(saving and "Saving..." or
            (editingContext and "Save Wishlist" or "Create Wishlist"))
        if saving then applyBtn:Disable() else applyBtn:Enable() end
    end
    if displayCheck and Nexus.WishlistOverlay then
        displayCheck:SetChecked(Nexus.WishlistOverlay.IsShown() == true)
        if displayLockBtn then
            displayLockBtn:SetText(Nexus.WishlistOverlay.IsLocked() and "Unlock to Move" or "Lock Position")
        end
    end

    local available = BuildAvailableList(catalog, owned)
    if scrollOffset >= #available then
        scrollOffset = math.max(0, #available - MAX_ROWS)
    end
    for i, row in ipairs(rows) do
        local data = available[scrollOffset + i]
        row.data = data
        if data then
            row:Show()
            row.icon:SetTexture(SpellIcon(data.spellId))
            local c = QUALITY_COLORS[data.quality] or QUALITY_COLORS[0]
            row.text:SetTextColor(c[1], c[2], c[3])
            local fam = PendingFamily(data.spellId, catalog)
            local chosen = pending[fam]
            local suffix = ""
            if chosen and tonumber(chosen.spellId) == tonumber(data.spellId) then
                suffix = "  |cff4dff80(selected)|r"
            elseif chosen then
                suffix = "  |cffffd200(replaces selected quality)|r"
            end
            row.text:SetText(data.name .. suffix)
            local ownedCount = ownedBySpell[data.spellId] or 0
            local isLocked = (tonumber(lockedBySpell[data.spellId]) or 0) > 0
            local qualityName = ({ [0] = "Common", [1] = "Uncommon", [2] = "Rare", [3] = "Epic", [4] = "Legendary" })[tonumber(data.quality) or 0] or "Echo"
            if isLocked then
                -- Permanently secured -- never needs a wishlist slot again.
                -- Distinct from RollStatus's unrelated "locked" (tome-gated).
                row.status:SetText("|cffb266ffLocked|r")
            elseif chosen and tonumber(chosen.spellId) == tonumber(data.spellId) then
                row.status:SetText("|cff4dff80Selected|r")
            elseif ownedCount > 0 then
                row.status:SetText("|cffffd200" .. qualityName .. " · Owned|r")
            else
                row.status:SetText("|cffb8b8b8" .. qualityName .. "|r")
            end
        else
            row:Hide()
        end
    end
    local availableFamilies = {}
    for _, r in ipairs(available) do
        availableFamilies[PendingFamily(r.spellId, catalog)] = true
    end
    local uniqueAvailable = 0
    for _ in pairs(availableFamilies) do uniqueAvailable = uniqueAvailable + 1 end
    footerText:SetText(string.format("Showing %d-%d of %d variants  •  %d Echo names",
        math.min(scrollOffset + 1, #available), math.min(#available, scrollOffset + MAX_ROWS),
        #available, uniqueAvailable))

    local list = {}
    local designedCount = 0
    for _, p in pairs(pending) do
        local row = catalog and catalog.rows and catalog.rows[p.spellId]
        list[#list + 1] = { spellId = p.spellId, family = p.family, stacks = p.stacks,
            maxStack = p.maxStack, quality = p.quality, lockIntent = p.lockIntent,
            name = (row and row.name) or ("spell " .. p.spellId), replaces = p.replaces }
        if p.lockIntent then designedCount = designedCount + 1 end
    end
    table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
    -- Locked-slot designs are listed separately after the ordinary 79-copy
    -- wishlist. They are committed locally and injected into automation, not
    -- uploaded as ordinary server-wishlist entries.
    local toLockList = {}
    for _, p in pairs(pendingLock) do
        toLockList[#toLockList + 1] = { spellId = p.spellId, family = p.family,
            stacks = 1, maxStack = 1, quality = p.quality, name = p.name, toLock = true,
            replaces = p.replaces }
    end
    table.sort(toLockList, function(a, b) return tostring(a.name) < tostring(b.name) end)
    local toLockCount = #toLockList
    for _, e in ipairs(toLockList) do list[#list + 1] = e end
    local realEntryCount = #list
    -- An entry designed to REPLACE a specific currently-real-locked Echo
    -- (.replaces -- see LoadPendingEchoes/ToggleDesignLock/
    -- AssignLockSlotFromData) got no visual pairing here at all before --
    -- just an easy-to-miss "(locked slot)"/"(awaiting lock)" tag, with
    -- nothing showing WHICH real slot it targets. Splice a read-only row for
    -- the Echo being replaced directly after it, mirroring the Locked strip
    -- above (which already stacks the replacement directly above the real
    -- slot it targets) so the pairing reads as one adjacent pair here too.
    do
        local withGhosts = {}
        for _, e in ipairs(list) do
            withGhosts[#withGhosts + 1] = e
            if type(e.replaces) == "number" then
                local oldRow = catalog and catalog.rows and catalog.rows[e.replaces]
                withGhosts[#withGhosts + 1] = {
                    spellId = e.replaces,
                    quality = oldRow and tonumber(oldRow.quality) or 0,
                    name = (oldRow and oldRow.name) or ("spell " .. tostring(e.replaces)),
                    ghost = true,
                }
            end
        end
        list = withGhosts
    end
    -- The same search box that filters the catalog on the left also filters
    -- this list -- typing an Echo's name shows immediately whether it's
    -- already selected instead of needing to scroll the whole wishlist.
    -- designedCount/toLockCount above are already fixed (computed from the
    -- full, unfiltered pending/pendingLock) so the lock-budget checks and
    -- footer counts stay correct while a search is active.
    local searchTerm = (NexusDB.editorSearch or ""):lower()
    if searchTerm ~= "" then
        local filtered = {}
        for _, e in ipairs(list) do
            if tostring(e.name or ""):lower():find(searchTerm, 1, true) then
                filtered[#filtered + 1] = e
            end
        end
        list = filtered
    end
    if pickOffset >= #list then pickOffset = math.max(0, #list - PICK_ROWS) end
    for i, row in ipairs(pickRows) do
        local data = list[pickOffset + i]
        row.data = data
        if data and data.ghost then
            -- Read-only pairing row for the real-locked Echo a design above
            -- it replaces -- not a wishlist entry, so no stack controls, no
            -- remove button, and clicks on it (minus/plus/remove/OnClick,
            -- guarded by d.ghost below) do nothing.
            row:Show()
            row.icon:SetTexture(SpellIcon(data.spellId))
            row.icon:SetVertexColor(0.5, 0.5, 0.5)
            row.text:SetTextColor(0.6, 0.6, 0.6)
            row.text:SetText("    |cff8a8a8a-> replaces|r " .. data.name
                .. "  |cff8a8a8a(currently locked)|r")
            if row.minus then row.minus:Hide() end
            if row.plus then row.plus:Hide() end
            if row.remove then row.remove:Hide() end
        elseif data then
            row:Show()
            row.icon:SetTexture(SpellIcon(data.spellId))
            row.icon:SetVertexColor(1, 1, 1)
            if row.remove then row.remove:Show() end
            -- Same quality color scheme as the left catalog list, so an
            -- Epic pick still reads as Epic once it's selected instead of
            -- going flat white. Queued (toLock) entries fully override this
            -- with their own orange wrap below -- that's intentional, the
            -- "still needs acquiring" state is the more useful signal there.
            local pc = QUALITY_COLORS[data.quality] or QUALITY_COLORS[0]
            row.text:SetTextColor(pc[1], pc[2], pc[3])
            if data.toLock then
                -- Separate locked-slot target: core/Main.lua injects it into
                -- automation without consuming or uploading a normal slot.
                row.text:SetText("|cffff9040" .. data.name .. "  (locked slot)|r")
            elseif data.lockIntent then
                -- Same separate locked-slot intent, represented on a pending
                -- row for compatibility with an in-progress editor session.
                -- It is excluded from the 79-copy upload and automated by its
                -- committed exact spellId.
                row.text:SetText(data.name .. "  |cffffd200x" .. tostring(data.stacks or 1)
                    .. "|r  |cff40c0ff(locked slot)|r")
            else
                row.text:SetText(data.name .. "  |cffffd200x" .. tostring(data.stacks or 1) .. "|r")
            end
            -- An Echo that can only ever hold 1 stack has nothing to adjust --
            -- hiding +/- entirely for it instead of leaving inert-looking
            -- buttons that appear clickable but never do anything.
            local canStack = not data.toLock and not data.lockIntent
                and (tonumber(data.maxStack) or 1) > 1
            if row.minus then
                if canStack then
                    row.minus:Show()
                    if (data.stacks or 1) > 1 then row.minus:Enable() else row.minus:Disable() end
                else
                    row.minus:Hide()
                end
            end
            if row.plus then
                if canStack then
                    row.plus:Show()
                    if (data.stacks or 1) < (data.maxStack or 1)
                        and PendingTotal() < MAX_WISHLIST_ECHOES then
                        row.plus:Enable()
                    else
                        row.plus:Disable()
                    end
                else
                    row.plus:Hide()
                end
            end
        else
            row:Hide()
        end
    end
    local footerParts = {}
    if lockedCount > 0 then footerParts[#footerParts + 1] = lockedCount .. " locked" end
    footerParts[#footerParts + 1] = PendingTotal() .. " / 79 wishlist"
    local totalDesigned = designedCount + toLockCount
    if totalDesigned > 0 then footerParts[#footerParts + 1] = totalDesigned .. " designed locks" end
    -- realEntryCount, not #list -- the spliced-in "replaces" ghost rows are
    -- a display aid, not separate wishlist entries, and shouldn't inflate
    -- this count.
    footerParts[#footerParts + 1] = realEntryCount .. " entries"
    pickFooterText:SetText(table.concat(footerParts, "  •  "))
end

------------------------------------------------------------------------
-- Server UI suppression while the standalone Nexus editor is open
------------------------------------------------------------------------

local serverHideHooks = {}
HideServerEchoUI = function()
    local journal = _G["ProjectEbonholdEchoJournal"]
    local targets = {}
    local f = journal
    for _ = 1, 4 do
        if not f or f == UIParent or f == frame then break end
        targets[#targets + 1] = f
        f = f.GetParent and f:GetParent() or nil
    end
    for _, target in ipairs(targets) do
        if HideUIPanel then pcall(HideUIPanel, target) end
        if target.Hide then pcall(target.Hide, target) end
        if target.HookScript and not serverHideHooks[target] then
            serverHideHooks[target] = true
            pcall(target.HookScript, target, "OnShow", function(self)
                if frame and frame:IsShown() then
                    if HideUIPanel then pcall(HideUIPanel, self) end
                    pcall(self.Hide, self)
                end
            end)
        end
    end
end

------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Display popup (on-screen wishlist settings) -- small, self-contained,
-- opened from the "Display..." button so the main editor stays uncluttered
------------------------------------------------------------------------

local function EnsureDisplayPopup()
    if displayPopup then return displayPopup end

    -- Always parent this dialog directly to UIParent. Parenting it to the
    -- editor made its visibility and mouse state depend on a much larger
    -- window, which could leave the popup visible but unable to receive
    -- clicks after the editor was hidden.
    local p = CreateFrame("Frame", "NexusDisplayPopup", UIParent)
    p:SetSize(300, 218)
    p:SetFrameStrata("TOOLTIP")
    p:SetFrameLevel(100)
    p:EnableMouse(true)
    if p.SetClampedToScreen then p:SetClampedToScreen(true) end
    p:Hide()

    pcall(function()
        p:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 24,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        p:SetBackdropColor(0.04, 0.04, 0.04, 0.98)
    end)

    -- Only the title bar drags the dialog. Making the entire popup a drag
    -- target can steal mouse-down events from checkboxes, sliders and
    -- buttons on older clients.
    local dragBar = CreateFrame("Frame", nil, p)
    dragBar:SetPoint("TOPLEFT", 10, -8)
    dragBar:SetPoint("TOPRIGHT", -34, -8)
    dragBar:SetHeight(30)
    dragBar:SetFrameLevel(p:GetFrameLevel() + 1)
    dragBar:EnableMouse(true)
    dragBar:RegisterForDrag("LeftButton")
    p:SetMovable(true)
    dragBar:SetScript("OnDragStart", function() p:StartMoving() end)
    dragBar:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText("On-Screen Wishlist")

    local subtitle = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetSize(245, 28)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Show, position, and resize the wishlist list used while playing.")

    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetFrameLevel(p:GetFrameLevel() + 5)
    close:SetScript("OnClick", function() p:Hide() end)

    displayCheck = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    displayCheck:SetPoint("TOPLEFT", 16, -68)
    displayCheck:SetFrameLevel(p:GetFrameLevel() + 5)
    displayCheck:EnableMouse(true)
    displayCheck:SetChecked(NexusDB.overlayShown == true)
    displayCheck.text = displayCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    displayCheck.text:SetPoint("LEFT", displayCheck, "RIGHT", -2, 1)
    displayCheck.text:SetText("Show on-screen wishlist")
    displayCheck:SetScript("OnClick", function(self)
        if Nexus.WishlistOverlay then
            if self:GetChecked() then
                Nexus.WishlistOverlay.Show()
            else
                Nexus.WishlistOverlay.Hide()
            end
        end
    end)

    local moveLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    moveLabel:SetPoint("TOPLEFT", 18, -102)
    moveLabel:SetText("Position")

    displayLockBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    displayLockBtn:SetSize(92, 22)
    displayLockBtn:SetPoint("LEFT", moveLabel, "RIGHT", 16, 0)
    displayLockBtn:SetFrameLevel(p:GetFrameLevel() + 5)
    displayLockBtn:EnableMouse(true)
    displayLockBtn:SetScript("OnClick", function()
        if Nexus.WishlistOverlay then
            Nexus.WishlistOverlay.ToggleLock()
            displayLockBtn:SetText(Nexus.WishlistOverlay.IsLocked()
                and "Unlock to Move" or "Lock Position")
        end
    end)

    local resetBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    resetBtn:SetSize(100, 22)
    resetBtn:SetPoint("LEFT", displayLockBtn, "RIGHT", 10, 0)
    resetBtn:SetFrameLevel(p:GetFrameLevel() + 5)
    resetBtn:EnableMouse(true)
    resetBtn:SetText("Reset Position")
    resetBtn:SetScript("OnClick", function()
        if Nexus.WishlistOverlay and Nexus.WishlistOverlay.ResetPosition then
            Nexus.WishlistOverlay.ResetPosition()
            displayCheck:SetChecked(true)
        end
    end)

    local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 18, -128)
    hint:SetSize(260, 24)
    hint:SetJustifyH("LEFT")
    hint:SetText("Unlock to drag the list. Lock it when placed so the list does not block gameplay clicks.")

    local sizeLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeLabel:SetPoint("TOPLEFT", 18, -164)
    sizeLabel:SetText("Size")

    local scaleMinus = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    scaleMinus:SetSize(22, 22)
    scaleMinus:SetPoint("LEFT", sizeLabel, "RIGHT", 22, 0)
    scaleMinus:SetFrameLevel(p:GetFrameLevel() + 5)
    scaleMinus:EnableMouse(true)
    scaleMinus:SetText("-")

    local scaleValueText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleValueText:SetPoint("LEFT", scaleMinus, "RIGHT", 7, 0)
    scaleValueText:SetSize(48, 22)
    scaleValueText:SetJustifyH("CENTER")

    local scalePlus = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    scalePlus:SetSize(22, 22)
    scalePlus:SetPoint("LEFT", scaleValueText, "RIGHT", 7, 0)
    scalePlus:SetFrameLevel(p:GetFrameLevel() + 5)
    scalePlus:EnableMouse(true)
    scalePlus:SetText("+")

    local scaleSlider = CreateFrame("Slider", "NexusScaleSlider", p,
        "OptionsSliderTemplate")
    scaleSlider:SetSize(250, 16)
    scaleSlider:SetPoint("TOPLEFT", 20, -195)
    scaleSlider:SetFrameLevel(p:GetFrameLevel() + 5)
    scaleSlider:EnableMouse(true)
    pcall(function()
        scaleSlider:SetMinMaxValues(0.5, 1.6)
        scaleSlider:SetValueStep(0.02)
    end)

    local updatingDisplay = false
    local function RefreshScaleDisplay()
        if not Nexus.WishlistOverlay then return end
        local v = Nexus.WishlistOverlay.GetScale()
        updatingDisplay = true
        pcall(function() scaleSlider:SetValue(v) end)
        scaleValueText:SetText(string.format("%d%%", math.floor(v * 100 + 0.5)))
        updatingDisplay = false
    end

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        if updatingDisplay then return end
        if Nexus.WishlistOverlay then Nexus.WishlistOverlay.SetScale(value) end
        RefreshScaleDisplay()
    end)
    scaleMinus:SetScript("OnClick", function()
        if Nexus.WishlistOverlay then
            Nexus.WishlistOverlay.SetScale(Nexus.WishlistOverlay.GetScale() - 0.02)
        end
        RefreshScaleDisplay()
    end)
    scalePlus:SetScript("OnClick", function()
        if Nexus.WishlistOverlay then
            Nexus.WishlistOverlay.SetScale(Nexus.WishlistOverlay.GetScale() + 0.02)
        end
        RefreshScaleDisplay()
    end)

    p:SetScript("OnShow", function(self)
        self:SetFrameStrata("TOOLTIP")
        self:SetFrameLevel(100)
        self:EnableMouse(true)
        if displayCheck and Nexus.WishlistOverlay then
            displayCheck:SetChecked(Nexus.WishlistOverlay.IsShown() == true)
            displayLockBtn:SetText(Nexus.WishlistOverlay.IsLocked()
                and "Unlock to Move" or "Lock Position")
        end
        RefreshScaleDisplay()
    end)

    p.RefreshScaleDisplay = RefreshScaleDisplay
    displayPopup = p
    return p
end

function M.ToggleDisplayPopup(anchorTo)
    local p = EnsureDisplayPopup()
    if p:IsShown() then
        p:Hide()
        return
    end
    p:ClearAllPoints()
    if anchorTo and anchorTo.IsVisible and anchorTo:IsVisible() then
        p:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, -6)
    else
        p:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    p:Show()
end

function M.Init(adapter, model)
    Adapter, Model = adapter, model
end

-- Debug/test accessor only.
function M.DebugPendingCount()
    local n = 0
    for _ in pairs(pending) do n = n + 1 end
    return n
end


function M.OpenForCandidate(candidate)
    editingContext = nil
    createTargetContext = nil
    pendingSeeded = true
    -- LoadPendingEchoes sets currentLockKey fresh from this candidate's own
    -- content, so there's no shared "bucket 0" to clear here anymore --
    -- unlike the old slot-number keying, a different candidate's content
    -- naturally gets a different fingerprint, not a colliding placeholder.
    LoadPendingEchoes(type(candidate) == "table" and candidate.echoes or {})
    EnsureFrame()
    -- Pre-fill the name from the source build's title -- this is a fresh
    -- "Create New Wishlist" draft (editingContext is nil), so the name box
    -- is visible and would otherwise sit empty, forcing a manual retype of
    -- something Nexus already knows. M.Refresh() never overwrites this
    -- box's text on its own, so setting it once here is safe.
    if wishlistNameBox and type(candidate) == "table" and candidate.title then
        wishlistNameBox:SetText(TrimWishlistName(candidate.title))
    end
    frame:Show()
    M.Refresh()
end

function M.OpenForWishlist(wishlist, loadoutSlot)
    createTargetContext = nil
    if type(wishlist) ~= "table" or not tonumber(wishlist.slot) then
        print("|cffff6060Nexus:|r Associated wishlist data is unavailable.")
        return false
    end
    pendingSeeded = true
    editingContext = {
        slot = tonumber(wishlist.slot),
        name = tostring(wishlist.name or "Wishlist"),
        key = wishlist.key,
        loadoutSlot = tonumber(loadoutSlot),
        loadoutName = tostring(wishlist.loadoutName or ""),
    }
    LoadPendingEchoes(wishlist.echoes or {}, false)
    EnsureFrame()
    HideServerEchoUI()
    if Nexus.Panel and Nexus.Panel.CloseOtherWindows then
        Nexus.Panel.CloseOtherWindows("NexusEditorFrame")
    end
    frame:Show()
    M.Refresh()
    return true
end

function M.NewWishlist()
    HideServerEchoUI()
    editingContext = nil
    createTargetContext = nil
    local slots = Adapter and Adapter.Slots and Adapter.Slots()
    local active = slots and tonumber(slots.activeSlot) or 0
    local maxSlots = slots and (tonumber(slots.maxSlots) or 5) or 5
    local activeRow = slots and slots.bySlot and slots.bySlot[active]
    if active >= 1 and active <= maxSlots and activeRow
        and type(activeRow.echoes) == "table" and #activeRow.echoes > 0 then
        local loadoutName = tostring(activeRow.name or "")
        if loadoutName == "" then loadoutName = "Saved Build " .. tostring(active) end
        createTargetContext = { loadoutSlot = active, loadoutName = loadoutName }
    end
    pending = {}
    pendingLock = {}
    M._fulfilledDraftTargets = {}
    scrollOffset, pickOffset = 0, 0
    pendingLoadoutOpen = nil
    pendingSeeded = true
    -- Doesn't call LoadPendingEchoes (nothing to load yet), so reset the
    -- lock-design key directly -- a brand new, still-empty wishlist has no
    -- content yet, so no fingerprint (bucket 0), matching WishlistKey(nil).
    currentLockKey = 0
    EnsureFrame()
    if Nexus.Panel and Nexus.Panel.AttachMenuFrame then Nexus.Panel.AttachMenuFrame(frame) end
    if Nexus.Theme and Nexus.Theme.StyleWindow then Nexus.Theme.StyleWindow(frame, 0.96) end
    if wishlistNameBox then wishlistNameBox:SetText("") end
    if Nexus.Panel and Nexus.Panel.CloseOtherWindows then Nexus.Panel.CloseOtherWindows("NexusEditorFrame") end
    frame:Show()
    M.Refresh()
end

function M.Show()
    HideServerEchoUI()
    EnsureFrame()
    if Nexus.Panel and Nexus.Panel.AttachMenuFrame then Nexus.Panel.AttachMenuFrame(frame) end
    if Nexus.Theme and Nexus.Theme.StyleWindow then Nexus.Theme.StyleWindow(frame, 0.96) end
    if Nexus.Panel and Nexus.Panel.CloseOtherWindows then Nexus.Panel.CloseOtherWindows("NexusEditorFrame") end

    -- Opening the editor should always reflect the active server loadout.
    -- Load its associated wishlist immediately instead of leaving stale
    -- "Create New Wishlist" context over already-populated Echoes.
    local slots = Adapter and Adapter.Slots and Adapter.Slots()
    local active = slots and tonumber(slots.activeSlot) or 0
    if active >= 1 and active <= 5 then
        LoadEditorForLoadout(active)
        return
    end
    -- No active Saved Build yet (pre-80 first run) -- this used to always
    -- fall through to a blank "Create New Wishlist" draft even when a
    -- first-run wishlist was already being tracked and shown correctly on
    -- the Panel HUD (Adapter.Wishlist()/GetFirstRunWishlist), which made
    -- clicking STILL NEEDED there look broken: the panel clearly knew what
    -- wishlist it was progressing, but the editor it opened had no idea.
    -- Open that same one directly when it exists.
    local firstRun = Adapter and Adapter.GetFirstRunWishlist and Adapter.GetFirstRunWishlist()
    if firstRun and tonumber(firstRun.slot) then
        M.OpenForWishlist(firstRun, nil)
        return
    end
    editingContext = nil
    createTargetContext = nil
    pending = {}
    pendingLock = {}
    M._fulfilledDraftTargets = {}
    currentLockKey = 0
    pendingSeeded = true
    frame:Show()
    M.Refresh()
end

function M.Toggle()
    EnsureFrame()
    if frame:IsShown() then frame:Hide() else M.Show() end
end

-- Keep editor navigation and actions consistent with the dark Nexus theme.
do
    local originalRefresh = M.Refresh
    M.Refresh = function(...)
        local result = originalRefresh(...)
        if frame and Nexus.Theme then Nexus.Theme.StyleTree(frame) end
        return result
    end
end
