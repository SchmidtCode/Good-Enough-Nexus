-- Nexus: logic/Ratchet.lua
-- Outer convergence: domination-guarded overwrite, slot scoring, and runs
-- estimate. PURE -- no WoW API, no
-- ProjectEbonhold, no SavedVariables; loads under bare LuaJIT.
--
-- Convergence and save safety are exact-spell/quality aware. Saved Builds are
-- comparison targets only; current Ebonhold offerings are random. A
-- lower-quality sibling is persistence filler, not wishlist coverage.

Nexus = Nexus or {}
local M = {}
Nexus.Ratchet = M

local function Pos(n)
    return type(n) == "number" and n > 0
end

-- Family key for an entry: the adapter-stamped field first, then the
-- catalog, then a synthetic per-spellId key (unknown rows stay visible
-- in planning output rather than silently vanishing).
local function FamOf(entry, catalog)
    if type(entry) ~= "table" then return nil end
    if entry.family ~= nil then return entry.family end
    local spellId = entry.spellId
    if spellId == nil then return nil end
    local byId = catalog and catalog.familyOf
    return (byId and byId[spellId]) or ("s" .. tostring(spellId))
end

local function FamName(catalog, fam)
    local names = catalog and catalog.familyName
    return (names and names[fam]) or tostring(fam)
end

local function OwnedFromEchoes(echoes, catalog)
    local owned = { byFamily = {}, bySpell = {} }
    for i = 1, #(echoes or {}) do
        local entry = echoes[i]
        local family = FamOf(entry, catalog)
        local spellId = type(entry) == "table" and tonumber(entry.spellId) or nil
        local count = type(entry) == "table"
            and (tonumber(entry.stacks or entry.count) or 1) or 0
        if family ~= nil and count > 0 then
            owned.byFamily[family] =
                (tonumber(owned.byFamily[family]) or 0) + count
        end
        if spellId and count > 0 then
            owned.bySpell[spellId] =
                (tonumber(owned.bySpell[spellId]) or 0) + count
        end
    end
    return owned
end

local function TargetProgress(plan, catalog, family, owned)
    local Model = Nexus.Model
    if type(Model) == "table" and type(Model.TargetProgress) == "function" then
        return Model.TargetProgress(plan, catalog, family, owned)
    end
    local target = type(plan) == "table"
        and type(plan.targets) == "table" and plan.targets[family] or nil
    local want = type(target) == "table"
        and tonumber(target.targetStacks) or 1
    if want < 1 then want = 1 end
    local byFamily = type(owned) == "table" and owned.byFamily or nil
    local have = tonumber(byFamily and byFamily[family]) or 0
    return math.min(have, want), want
end

-- Distinct coverage/filler family sets of a slot-echoes array.
local function EchoFamilySets(echoes, wished, catalog)
    local cov, fill = {}, {}
    if type(echoes) == "table" then
        for i = 1, #echoes do
            local fam = FamOf(echoes[i], catalog)
            if fam ~= nil then
                if wished[fam] then cov[fam] = true else fill[fam] = true end
            end
        end
    end
    return cov, fill
end

local function SortedNames(set, catalog)
    local list = {}
    for fam in pairs(set) do
        list[#list + 1] = FamName(catalog, fam)
    end
    table.sort(list)
    return list
end

------------------------------------------------------------------------
-- Compatibility seam retained for callers and old diagnostics. Current
-- Ebonhold Saved Builds do not produce guaranteed future Echoes, so the queue
-- is always empty.
------------------------------------------------------------------------

function M.PredictQueue(activeEchoes, owned, plan, flags, disabledLevers, catalog)
    return { entries = {}, random = true }
end

------------------------------------------------------------------------
-- Exact wishlist targets: the ONE coverage identity every consumer shares.
--
-- Coverage is counted per exact spellId, never per family. An Uncommon Quick
-- Hands is persistence filler, not one of the five Rare copies the wishlist
-- asked for. A player who genuinely wants
-- lower tiers says so with a multi-tier wishlist entry, which arrives here as
-- separate qualityTiers rows and is counted tier by tier.
--
-- Main.lua's WishlistProgress/LoadoutCoverage/SaveChangeSummary used to count
-- by FAMILY while the save gate below counted exactly, so the two contradicted
-- each other in the player's face. Live 2026-08-02: a run that shed three
-- forced Uncommon siblings (Quick Hands, Vital Bond, Ferocious Bond) while
-- gaining a real Rare Ferocious Bond was correctly saved by the gate as "+1
-- exact progress" and simultaneously reported to the player as "loadout
-- cleaned up -- shed Quick Hands", with STILL NEEDED going from 2 to 3 Quick
-- Hands. Every consumer reads these helpers now.
------------------------------------------------------------------------

-- Exact { [spellId] = wanted stacks } for one compiled family target,
-- accumulated into `out` when merging several.
function M.TargetExact(target, out)
    out = out or {}
    if type(target) ~= "table" then return out end
    local tiers = target.qualityTiers
    if type(tiers) == "table" and #tiers > 0 then
        for i = 1, #tiers do
            local tier = tiers[i]
            local id = type(tier) == "table" and tonumber(tier.spellId) or nil
            if id then
                out[id] = (out[id] or 0) + math.max(1, tonumber(tier.n) or 1)
            end
        end
    else
        local id = tonumber(target.spellId)
        if id then
            out[id] = (out[id] or 0)
                + math.max(1, tonumber(target.targetStacks) or 1)
        end
    end
    return out
end

function M.WantedExact(plan)
    local out = {}
    local targets = (type(plan) == "table" and plan.targets) or {}
    for _, target in pairs(targets) do M.TargetExact(target, out) end
    return out
end

-- Covered/total stacks of an exact want map against an owned bySpell map.
-- Capped per spellId, so extra copies past a target never inflate coverage.
function M.ExactCoverage(wantedExact, bySpell)
    local covered, total = 0, 0
    bySpell = type(bySpell) == "table" and bySpell or {}
    for id, cap in pairs(type(wantedExact) == "table" and wantedExact or {}) do
        cap = math.max(0, tonumber(cap) or 0)
        total = total + cap
        covered = covered + math.min(cap, math.max(0, tonumber(bySpell[id]) or 0))
    end
    return covered, total
end

------------------------------------------------------------------------
-- Domination guard: the candidate build may overwrite the incumbent when
-- its TOTAL useful exact-target stack count advances, or when exact progress
-- is unchanged and the run is a genuine cleanup. A net regression remains
-- blocked. An unreadable input never dominates (brick guard).
--
-- Exact wishlist progress is monotonic in TOTAL useful target stacks, not
-- per-spell permanence. A later run may lose one exact target to bad RNG while
-- gaining several others; refusing that trade strands the baseline even though
-- the build is objectively closer to the wishlist. Losses are therefore
-- subtracted from gains through progressGain, rather than acting as an
-- unconditional per-id veto. Pollution remains diagnostic/cleanup guidance.
------------------------------------------------------------------------

-- Comparative pollution weights. Not derived from a formal model --
-- tune these against observed runs, the same way reroll pacing is tuned.
local FORCED_EXCESS_WEIGHT    = 1     -- unavoidable extra copy of an exact target
local AVOIDABLE_EXCESS_WEIGHT = 3     -- a better option existed and wasn't taken
local FORCED_WRONGQ_WEIGHT    = 3     -- unavoidable wrong-quality sibling
local AVOIDABLE_WRONGQ_WEIGHT = 6     -- voluntary wrong-quality sibling: worst case
local EXCESS_SHED_CREDIT      = 2     -- reward for an excess copy actually clearing
local WRONGQ_SHED_CREDIT      = 3     -- reward for clearing a wrong-quality sibling:
                                       -- mirrors FORCED_WRONGQ_WEIGHT so acquiring
                                       -- and later shedding one nets out to zero
local UNRELATED_FILLER_WEIGHT = 0.25  -- ordinary off-wishlist junk, same discount
                                       -- factor used elsewhere in this file (ScoreSlot)

-- forcedBySpell (optional): { [spellId] = forced units taken this run }, from
-- Main.lua accumulating Policy.Decide's `forced = true` take results. It only
-- labels unavoidable pollution for diagnostics and cleanup decisions.
function M.Dominates(candidateOwned, incumbentEchoes, plan, catalog, forcedBySpell)
    if type(candidateOwned) ~= "table"
        or type(candidateOwned.bySpell) ~= "table" then
        return false, "candidate owned state unreadable"
    end
    if type(incumbentEchoes) ~= "table" then
        return false, "incumbent echoes unreadable"
    end
    local forced = type(forcedBySpell) == "table" and forcedBySpell or {}

    local wantedExact = M.WantedExact(plan)

    local incumbentExact = {}
    local incumbentLockedExact = {}
    local incumbentTotal = 0
    for _, e in ipairs(incumbentEchoes) do
        if type(e) == "table" and tonumber(e.spellId) then
            local id = tonumber(e.spellId)
            local n = math.max(1, tonumber(e.stacks or e.count or e.stack) or 1)
            incumbentExact[id] = (incumbentExact[id] or 0) + n
            incumbentTotal = incumbentTotal + n
            -- Locked slot echoes are preserved by Save() regardless of what
            -- this run collected -- Main.lua's own shed/coverage logic
            -- (BuildProgress's `keepCount = max(wantedExact, lockedExact)`)
            -- already treats them as protected. Without this, a wished
            -- family that's locked-but-unpicked-this-run (own=0 in a fresh
            -- run) reads as a coverage loss on every single save check --
            -- confirmed against the Driagon hunter diagnostic, which carries
            -- 4 locked+wished singles (Unstable Infusion, Sanctum Sentries,
            -- Adaptive Power, Contagion) that this run's `owned` never
            -- touched.
            if e.locked then
                incumbentLockedExact[id] = (incumbentLockedExact[id] or 0) + n
            end
        end
    end

    -- Saved Build rows contain the rolled loadout UNION the permanent locked
    -- Echoes. If the same spell is both rolled and locked the server keeps one
    -- entry, so use max(), never addition. This also keeps filler/excess math
    -- on the same representation as the incumbent snapshot.
    local candidatePostExact = {}
    for id, n in pairs(candidateOwned.bySpell) do
        candidatePostExact[id] = math.max(0, tonumber(n) or 0)
    end
    for id, n in pairs(incumbentLockedExact) do
        local have = tonumber(candidatePostExact[id]) or 0
        local permanent = tonumber(n) or 0
        if permanent > have then candidatePostExact[id] = permanent end
    end

    local candidateTotal = 0
    for _, n in pairs(candidatePostExact) do
        candidateTotal = candidateTotal + math.max(0, tonumber(n) or 0)
    end

    local incumbentProgress, candidateProgress = 0, 0
    local gainedStacks, lostStacks = 0, 0
    local hadExactExcess = false
    local excessIncreaseForced, excessIncreaseAvoidable, excessDecrease = 0, 0, 0
    local firstLostId = nil
    for id, cap in pairs(wantedExact) do
        local beforeRaw = tonumber(incumbentExact[id]) or 0
        local afterRaw = tonumber(candidatePostExact[id]) or 0
        local before = math.min(beforeRaw, cap)
        local after = math.min(afterRaw, cap)

        if after < before and firstLostId == nil then firstLostId = id end

        local beforeExcess = math.max(0, beforeRaw - cap)
        local afterExcess = math.max(0, afterRaw - cap)
        if beforeExcess > 0 then hadExactExcess = true end
        local excessDelta = afterExcess - beforeExcess
        if excessDelta > 0 then
            local forcedUnits = math.min(excessDelta, tonumber(forced[id]) or 0)
            excessIncreaseForced = excessIncreaseForced + forcedUnits
            excessIncreaseAvoidable = excessIncreaseAvoidable + (excessDelta - forcedUnits)
        elseif excessDelta < 0 then
            excessDecrease = excessDecrease - excessDelta
        end

        incumbentProgress = incumbentProgress + before
        candidateProgress = candidateProgress + after
        local d = after - before
        if d > 0 then gainedStacks = gainedStacks + d
        elseif d < 0 then lostStacks = lostStacks + (-d) end
    end

    -- A newly-added lower-quality sibling of a wished family is persistent
    -- pollution in the saved baseline. Tracked per-spell (forced vs avoidable) rather than an
    -- automatic veto, same reasoning as exact-target excess above.
    -- Removing one of these is real cleanup, not a coverage loss: it frees a
    -- saved-baseline entry that would otherwise keep the wrong tier. Tracked
    -- symmetrically with the added case (wrongQShed) so the gate
    -- can credit a run for clearing them instead of only ever punishing their
    -- arrival -- otherwise a pure wrong-quality cleanup pass scores zero and
    -- gets blocked by the cleanup branch below.
    local wishedFamilies = (type(plan) == "table" and plan.wishedFamilies) or {}
    local Model = Nexus and Nexus.Model
    local wrongQForced, wrongQAvoidable, wrongQShed, wrongQDetail = 0, 0, 0, nil
    local siblingIds = {}
    for id in pairs(candidatePostExact) do siblingIds[id] = true end
    for id in pairs(incumbentExact) do siblingIds[id] = true end
    for id in pairs(siblingIds) do
        if not wantedExact[id] then
            local afterRaw = math.max(0, tonumber(candidatePostExact[id]) or 0)
            local beforeRaw = math.max(0, tonumber(incumbentExact[id]) or 0)
            if afterRaw ~= beforeRaw then
                local row = catalog and catalog.rows and catalog.rows[id]
                local fam = (row and row.family)
                    or (catalog and catalog.familyOf and catalog.familyOf[id])
                if fam ~= nil and wishedFamilies[fam] then
                    local wishedQuality = type(Model) == "table"
                        and type(Model.EffectiveWishedQuality) == "function"
                        and Model.EffectiveWishedQuality(plan, catalog, fam, 0,
                            candidatePostExact) or nil
                    local actualQuality = row and tonumber(row.quality) or nil
                    if actualQuality ~= nil and wishedQuality ~= nil
                        and actualQuality < wishedQuality then
                        if afterRaw > beforeRaw then
                            local added = afterRaw - beforeRaw
                            local forcedUnits = math.min(added, tonumber(forced[id]) or 0)
                            wrongQForced = wrongQForced + forcedUnits
                            wrongQAvoidable = wrongQAvoidable + (added - forcedUnits)
                            wrongQDetail = wrongQDetail or string.format(
                                "%d q%d<q%d", id, actualQuality, wishedQuality)
                        else
                            wrongQShed = wrongQShed + (beforeRaw - afterRaw)
                        end
                    end
                end
            end
        end
    end

    -- Every stack that is not useful exact wishlist coverage is persistence
    -- pollution, including wrong-quality siblings inside a wished family and
    -- excess copies above an exact target. Count stacks rather than distinct
    -- families so one accidental Common stat copy is visible to the save gate.
    local incumbentFiller = math.max(0, incumbentTotal - incumbentProgress)
    local candidateFiller = math.max(0, candidateTotal - candidateProgress)
    local fillerDelta = candidateFiller - incumbentFiller
    local progressGain = candidateProgress - incumbentProgress

    -- "Unrelated" filler excludes the exact-target-excess and wrong-quality
    -- stacks already tallied above, so pollution is never counted twice.
    local trackedPollutionDelta = (excessIncreaseForced + excessIncreaseAvoidable
        - excessDecrease) + (wrongQForced + wrongQAvoidable - wrongQShed)
    local unrelatedFillerDelta = fillerDelta - trackedPollutionDelta

    local diag = {
        progressGain = progressGain, gainedStacks = gainedStacks, lostStacks = lostStacks,
        excessIncreaseForced = excessIncreaseForced,
        excessIncreaseAvoidable = excessIncreaseAvoidable,
        excessDecrease = excessDecrease,
        wrongQForced = wrongQForced, wrongQAvoidable = wrongQAvoidable,
        wrongQShed = wrongQShed,
        wrongQDetail = wrongQDetail, fillerDelta = fillerDelta,
        unrelatedFillerDelta = unrelatedFillerDelta,
        firstLostId = firstLostId,
    }

    if progressGain > 0 then
        local pollutionScore = excessIncreaseForced * FORCED_EXCESS_WEIGHT
            + excessIncreaseAvoidable * AVOIDABLE_EXCESS_WEIGHT
            + wrongQForced * FORCED_WRONGQ_WEIGHT
            + wrongQAvoidable * AVOIDABLE_WRONGQ_WEIGHT
            - excessDecrease * EXCESS_SHED_CREDIT
            - wrongQShed * WRONGQ_SHED_CREDIT
            + math.max(0, unrelatedFillerDelta) * UNRELATED_FILLER_WEIGHT
        diag.pollutionScore = pollutionScore
        -- Any NET exact wishlist gain advances the bounded convergence target.
        -- Forced filler, quality siblings, or trading one target for several
        -- others may make a run imperfect, but they must not discard genuine
        -- progress; later runs can clean that pollution while building from the
        -- stronger baseline.
        return true, string.format(
            "net exact wishlist progress +%d (gained %d, lost %d; forced excess %d, "
                .. "avoidable excess %d, wrong-quality forced %d/avoidable %d/shed %d, "
                .. "filler %+d)",
            progressGain, gainedStacks, lostStacks, excessIncreaseForced,
            excessIncreaseAvoidable, wrongQForced, wrongQAvoidable, wrongQShed,
            fillerDelta), diag
    end

    if progressGain == 0 then
        -- Cleanup-only pass: there is no exact progress to weigh pollution
        -- against, so stay strict -- ANY new excess or wrong-quality
        -- sibling fails it outright, forced or not, and an existing excess
        -- must actually shrink rather than being masked by unrelated
        -- filler cleanup elsewhere.
        if excessIncreaseForced > 0 or excessIncreaseAvoidable > 0
            or wrongQForced > 0 or wrongQAvoidable > 0 then
            return false, "cleanup-only save added new excess/wrong-quality pollution", diag
        end
        -- A clean one-for-one wishlist rotation advances convergence even
        -- though aggregate exact progress is unchanged: the new baseline keeps
        -- the acquired target while later random boards search for the
        -- rotated-out target. New filler or persistence pollution still blocks
        -- the save.
        if gainedStacks > 0 and lostStacks > 0
            and fillerDelta <= 0 and unrelatedFillerDelta <= 0 then
            return true, string.format(
                "wishlist rotation (gained %d, shed %d wished stacks, filler %+d)",
                gainedStacks, lostStacks, fillerDelta), diag
        end
        if hadExactExcess and excessDecrease <= 0 and wrongQShed <= 0 then
            return false, "filler improved but existing exact excess was not reduced", diag
        end
        if fillerDelta < 0 or excessDecrease > 0 or wrongQShed > 0 then
            return true, string.format(
                "exact wishlist progress unchanged; filler %+d, excess -%d, wrong-quality -%d",
                fillerDelta, excessDecrease, wrongQShed), diag
        end
        return false, "no exact gain (wishlist +0, filler +0)", diag
    end

    return false, string.format(
        "exact wishlist progress regressed %d (gained %d, shed %d exact stacks)",
        -progressGain, gainedStacks, lostStacks), diag
end

------------------------------------------------------------------------
-- Slot scoring / selection over GENUINELY-verified rows only.
------------------------------------------------------------------------

function M.ScoreSlot(slotEchoes, plan, catalog)
    local wished  = (type(plan) == "table" and plan.wishedFamilies) or {}
    local targets = (type(plan) == "table" and plan.targets) or {}
    local _, fill = EchoFamilySets(slotEchoes, wished, catalog)
    local owned = OwnedFromEchoes(slotEchoes, catalog)
    local nc, nf = 0, 0
    for _ in pairs(fill) do nf = nf + 1 end

    -- Stack bonus: for each wished stacking family, add fractional credit
    -- proportional to stacks present vs the target.  This ensures BestSlot
    -- prefers a slot with 14×Rend over one with 1×Rend when the wishlist
    -- calls for 67×Rend.  Weight < 1 so a stack bonus never outweighs a
    -- genuinely new echo family.
    local stackBonus = 0
    for family in pairs(wished) do
        local have, want = TargetProgress(plan, catalog, family, owned)
        if have > 0 then nc = nc + 1 end
        if have <= 0
            and (tonumber(owned.byFamily[family]) or 0) > 0 then
            nf = nf + 1
        end
        if want > 1 then
            stackBonus = stackBonus + 0.9 * math.min(have, want) / want
        end
    end

    return nc + stackBonus - 0.25 * nf
end

-- bySlot is SPARSE (designed builds live above maxSlots): pairs only,
-- never ipairs/#. Ties break toward the lowest slot id.
function M.BestSlot(slots, plan, catalog)
    if type(slots) ~= "table" or type(slots.bySlot) ~= "table" then
        return nil
    end
    local ids = {}
    for id, row in pairs(slots.bySlot) do
        if type(id) == "number" and type(row) == "table"
            and row.verified and row.verifiedFieldPresent
            and not row.suspectParse then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    local best, bestScore
    for i = 1, #ids do
        local score = M.ScoreSlot(slots.bySlot[ids[i]].echoes, plan, catalog)
        if bestScore == nil or score > bestScore then
            best, bestScore = ids[i], score
        end
    end
    return best
end

------------------------------------------------------------------------
-- Runs estimate. The free-slot draw rate (theta) is unmeasured in v1
-- (measurement M4 open), so `support` cannot honestly yield a run
-- count: unknown stays true and the text reports only what is known.
------------------------------------------------------------------------

function M.RunsEstimate(plan, owned, queue, support, catalog)
    local wished = type(plan) == "table" and plan.wishedFamilies or nil
    if not wished or not next(wished) then
        return { text = "no wishlist target - advisor mode", unknown = true }
    end
    local pending = 0
    for fam in pairs(wished) do
        local have, want = TargetProgress(plan, catalog, fam, owned)
        if have < want then pending = pending + 1 end
    end
    local text
    if pending == 0 then
        text = "wishlist complete - 0 wanted echoes pending"
    else
        text = string.format(
            "~%d wishlist echo%s pending from random offerings (rate unmeasured)",
            pending, pending == 1 and "" or "es")
    end
    return { text = text, unknown = true }
end

return M
