-- Nexus: logic/Policy.lua
-- Pure per-board decision engine, v2 quality- and guarantee-aware greedy.
-- Board model: 2 free slots + at most 1 guaranteed (flag-3) card; select
-- is mandatory; freeze does NOT consume the board (freeze fires, then the
-- take happens on the next tick of the same board), which makes banking a
-- stacking-wishlist card nearly free. Policy PROPOSES; the adapter
-- re-checks and may drop. Never targets a guaranteed/frozen/carried/
-- justFrozen card with banish/reroll. No WoW API calls; plain Lua 5.1.
--
-- The live-play rules this version encodes (2026-07-24 session, freeze
-- self-block confirmed 2026-08-01 via structured log analysis across
-- 3,221 distinct boards -- Dev Test 63/Dev Test 2):
--  A. QUALITY GATE -- a below-wished-quality copy of a single-stack,
--     multi-quality family (the stat echoes) scores qualityMiss (< filler):
--     taking it locks the family at the wrong quality AND poisons the
--     saved loadout. The wished quality per family comes from the
--     wishlist itself (plan.targets[fam].wishedQuality) -- no hardcoded
--     stat list.
--  B. DEFER -- a free-slot wished card whose guarantee is still pending
--     (family present in the predicted queue) will come back on its own;
--     its take-value is discounted by deferFactor so a one-shot pick
--     (guaranteed head, banked stack copy, at-quality stat catch) never
--     loses to it. An at-or-above-wished-quality catch of a multi-quality
--     family is NEVER deferred: the guarantee is level-gated and may only
--     serve the low-quality variant, so the free-slot catch is the real
--     opportunity.
--  C. BANK -- freeze only a wanted side copy that is not already fully
--     covered by owned copies plus the remaining exact Saved Build floor,
--     AND only when that family's own guarantee is already exhausted
--     (not pendingFam -- see below). Confirmed live: while a copy of a
--     family sits frozen anywhere on the board, the server will not
--     guarantee another copy of that SAME family in slot 3 -- other
--     families are unaffected (0 of 76 Quick-Hands-guaranteed boards had
--     Quick Hands frozen, across 3,221 distinct boards; a Double-Strike-
--     frozen control board still guaranteed Quick Hands normally). So
--     freezing a family whose guarantee is still open (pendingFam true)
--     would silence the exact channel meant to deliver its remaining
--     copies -- Dev Test 63: Rare Quick Hands frozen at owned=0
--     self-blocked its own guarantee for 4 straight boards while other
--     wanted guarantees kept arriving normally. Once a family's guarantee
--     is exhausted (pendingFam false -- baseline restored, or it was
--     never in the Saved Build to begin with), freezing it costs nothing
--     on that front and this rule applies as before: bank it while a
--     DIFFERENT wanted guarantee is taken. The precious-catch pass (a
--     one-shot multi-quality catch) is exempt from the pendingFam check --
--     its guarantee is already known to serve the wrong quality tier, so
--     nothing of value is lost by freezing it either way.
--  D. RETRIEVE -- once ANY copy is held/frozen, take it back the moment
--     doing so is FREE -- i.e. slot 3 is not a different wanted
--     guarantee. Never sacrifices a different wanted guarantee to
--     retrieve early: rule C only ever freezes a family whose own
--     guarantee was already exhausted, so once something is actually
--     held there is no self-block risk left to race against -- holding
--     it one more board costs that family nothing. Live 2026-08-01 (run
--     2) proved the earlier "always retrieve, even over a different
--     wanted guarantee" version wrong: it cost a guaranteed, single-copy
--     Ember Spark (its only guaranteed appearance all run, permanently
--     forfeited -- see "Absolute one-shot rule" below) to retrieve a
--     Ferocious Bond extra one board sooner, for zero actual benefit.
--     This replaces the older HeldBaselineReady threshold wait too: no
--     artificial delay needed either, since the very first board where
--     slot 3 isn't a competing wanted guarantee is free to take.

Nexus = Nexus or {}
local Policy = {}
Nexus.Policy = Policy

local NEG_INF = -math.huge

-- Resolved at call time, never at file load (load order is not ours).
local Model

local function GetModel()
    Model = Model or Nexus.Model
    return Model
end

local function OwnedFam(owned, fam)
    if fam == nil or type(owned) ~= "table" then return 0 end
    local byFamily = owned.byFamily
    return (type(byFamily) == "table" and tonumber(byFamily[fam])) or 0
end

local function Wished(plan, fam)
    return fam ~= nil and type(plan.wishedFamilies) == "table"
        and plan.wishedFamilies[fam] and true or false
end

local function WishedQuality(plan, fam)
    local t = type(plan.targets) == "table" and plan.targets[fam] or nil
    return (type(t) == "table" and tonumber(t.wishedQuality)) or 0
end

-- Base annotation: guaranteed > wanted > duplicate > filler > junk.
-- Decide overlays "banked" / "returns later" / "low quality" after the
-- effective-value pass.
local function TargetCap(plan, family, wished)
    if not wished or type(plan.targets) ~= "table" then return 1 end
    local target = plan.targets[family]
    return type(target) == "table" and target.targetStacks or 1
end

local function Annotation(card, delta, plan, owned)
    if card.isGuaranteed then return "guaranteed" end
    local fam = card.family
    local wished = Wished(plan, fam)
    if wished and delta > 0 then return "wanted" end
    local have = OwnedFam(owned, fam)
    local cap = TargetCap(plan, fam, wished)
    if have > 0 and have >= cap then return "duplicate" end
    if not wished then return "filler" end
    return "junk"
end

local function IsFrozen(card)
    return card.isFrozen or card.isCarried or card.justFrozen
end

local function MultiQualityWanted(model, card, plan, owned, catalog)
    if type(model.QualityOfferNeeded) == "function" then
        return model.QualityOfferNeeded(
            plan, catalog, card.family, tonumber(card.quality) or 0, owned)
    end
    local bySpell = type(owned) == "table" and owned.bySpell or nil
    local required = type(model.EffectiveWishedQuality) == "function"
        and model.EffectiveWishedQuality(
            plan, catalog, card.family, OwnedFam(owned, card.family), bySpell)
        or WishedQuality(plan, card.family)
    return (tonumber(card.quality) or 0) >= (tonumber(required) or 0)
end

local function IsWanted(model, card, delta, plan, owned, catalog)
    if not delta or delta <= 0 or not Wished(plan, card.family) then return false end
    local multiQuality = type(model.FamilyMultiQuality) == "function"
        and model.FamilyMultiQuality(catalog, card.family)
    if multiQuality then
        return MultiQualityWanted(model, card, plan, owned, catalog)
    end
    return true
end

local function IsOneShot(model, card, plan, owned, catalog)
    local have = OwnedFam(owned, card.family)
    if type(model.TargetProgress) == "function" then
        have = model.TargetProgress(plan, catalog, card.family, owned)
    end
    return have <= 0 and type(model.FamilyMultiQuality) == "function"
        and model.FamilyMultiQuality(catalog, card.family)
        and (type(model.QualityOfferNeeded) ~= "function"
            or model.QualityOfferNeeded(
                plan, catalog, card.family,
                tonumber(card.quality) or 0, owned))
end

local function WantedTier(model, card, plan, owned, catalog)
    if type(model.StackWishBelowTarget) == "function"
        and model.StackWishBelowTarget(
            plan, owned, card.family, catalog) then
        return 1
    end
    if IsOneShot(model, card, plan, owned, catalog) then return 2 end
    return 3
end

local function BetterWanted(model, cards, deltas, plan, owned, catalog,
    candidate, incumbent)
    if incumbent == nil then return true end
    local ct = WantedTier(model, cards[candidate], plan, owned, catalog)
    local it = WantedTier(model, cards[incumbent], plan, owned, catalog)
    if ct ~= it then return ct < it end
    if deltas[candidate] ~= deltas[incumbent] then
        return deltas[candidate] > deltas[incumbent]
    end
    return candidate < incumbent
end

local function EntryQuality(entry, catalog)
    local rows = type(catalog) == "table" and catalog.rows or nil
    local row = type(rows) == "table" and rows[tonumber(entry.spellId)] or nil
    return type(row) == "table"
        and tonumber(row.quality) or tonumber(entry.quality)
end

local function EntryDeliversWanted(model, entry, card, plan, owned, catalog)
    if type(entry) ~= "table" or entry.wanted ~= true
        or entry.family ~= card.family then
        return false
    end
    local multiQuality = type(model.FamilyMultiQuality) == "function"
        and model.FamilyMultiQuality(catalog, card.family)
    if not multiQuality then return true end
    local quality = EntryQuality(entry, catalog)
    return quality ~= nil
        and type(model.QualityOfferNeeded) == "function"
        and model.QualityOfferNeeded(
            plan, catalog, card.family, quality, owned)
end

local function QueueCanDeliverWanted(model, state, card, plan, owned, catalog)
    local queue = type(state.queue) == "table" and state.queue.entries or nil
    if type(queue) ~= "table" or card.family == nil then return false end
    for i = 1, #queue do
        if EntryDeliversWanted(
            model, queue[i], card, plan, owned, catalog) then
            return true
        end
    end
    return false
end

local function FreezeWorthy(model, state, card, plan, owned, catalog)
    if type(model.StackWishBelowTarget) == "function"
        and model.StackWishBelowTarget(
            plan, owned, card.family, catalog) then
        return true
    end
    return not QueueCanDeliverWanted(
        model, state, card, plan, owned, catalog)
end

local function TakeAction(cards, annotations, deltas, index, reason)
    return {
        type = "take", index = index, spellId = cards[index].spellId,
        reason = reason, annotations = annotations, deltas = deltas,
    }
end

local function Endgame(action)
    action.endgame = true
    return action
end

local function SafeBanishCard(card, index, plan, gIndex)
    return index ~= gIndex
        and not card.isGuaranteed
        and not card.isFrozen
        and not card.isCarried
        and not card.justFrozen
        and not Wished(plan, card.family)
end

local function SafeBanishCandidate(cards, deltas, plan, gIndex)
    local worst, worstDelta = nil, nil
    for i = 1, #cards do
        if SafeBanishCard(cards[i], i, plan, gIndex)
            and (worst == nil or deltas[i] < worstDelta
                or (deltas[i] == worstDelta and i < worst)) then
            worst, worstDelta = i, deltas[i]
        end
    end
    return worst
end

local function SelectableSide(card, index, gIndex)
    return index ~= gIndex
        and not card.isGuaranteed
        and not card.justFrozen
end

local function BetterLeastHarmful(cards, annotations, deltas, candidate, pick)
    if pick == nil then return true end
    if deltas[candidate] ~= deltas[pick] then
        return deltas[candidate] > deltas[pick]
    end
    local filler = annotations[candidate] == "filler"
    local pickedFiller = annotations[pick] == "filler"
    if filler ~= pickedFiller then return not filler end
    local quality = tonumber(cards[candidate].quality) or 0
    local pickedQuality = tonumber(cards[pick].quality) or 0
    if quality ~= pickedQuality then return quality < pickedQuality end
    return candidate < pick
end

local function LeastHarmfulSide(cards, annotations, deltas, gIndex)
    local anyNonDuplicate = false
    for i = 1, #cards do
        if SelectableSide(cards[i], i, gIndex)
            and annotations[i] ~= "duplicate" then
            anyNonDuplicate = true
            break
        end
    end
    local pick = nil
    for i = 1, #cards do
        local eligible = SelectableSide(cards[i], i, gIndex)
            and ((not anyNonDuplicate) or annotations[i] ~= "duplicate")
        if eligible
            and BetterLeastHarmful(cards, annotations, deltas, i, pick) then
            pick = i
        end
    end
    return pick
end

local function SimulationFromOwned(owned)
    local simulated = { byFamily = {}, bySpell = {} }
    for family, count in pairs(type(owned) == "table" and owned.byFamily or {}) do
        simulated.byFamily[family] = tonumber(count) or 0
    end
    for spellId, count in pairs(type(owned) == "table" and owned.bySpell or {}) do
        simulated.bySpell[spellId] = tonumber(count) or 0
    end
    return simulated
end

local function FallbackFamily(card, catalog)
    if card.family ~= nil then return card.family end
    local families = type(catalog) == "table" and catalog.familyOf or nil
    return type(families) == "table"
        and families[tonumber(card.spellId)] or nil
end

local function AddFallback(simulated, card, catalog)
    if type(card) ~= "table" then return end
    local family = FallbackFamily(card, catalog)
    local count = tonumber(card.stacks or card.count) or 1
    if family ~= nil then
        simulated.byFamily[family] =
            (tonumber(simulated.byFamily[family]) or 0) + count
    end
    local spellId = tonumber(card.spellId)
    if spellId then
        simulated.bySpell[spellId] =
            (tonumber(simulated.bySpell[spellId]) or 0) + count
    end
end

local function FamilyStillMissing(model, plan, catalog, family, simulated)
    local have, want
    if type(model.TargetProgress) == "function" then
        have, want = model.TargetProgress(plan, catalog, family, simulated)
    else
        local target = type(plan.targets) == "table" and plan.targets[family]
        want = type(target) == "table" and tonumber(target.targetStacks) or 1
        have = tonumber(simulated.byFamily[family]) or 0
    end
    return have < math.max(1, tonumber(want) or 1)
end

local function MissingAfterFallback(plan, owned, fallbackCard, catalog)
    local simulated = SimulationFromOwned(owned)
    AddFallback(simulated, fallbackCard, catalog)
    local model = GetModel()
    for family in pairs(type(plan) == "table" and plan.wishedFamilies or {}) do
        if FamilyStillMissing(model, plan, catalog, family, simulated) then
            return true
        end
    end
    return false
end

local function WaitAction(reason, annotations, deltas)
    return {
        type = "wait",
        reason = reason,
        annotations = annotations or {},
        deltas = deltas,
    }
end

local function NormalizeCards(board)
    local rawCards = type(board) == "table" and board.cards or nil
    if type(rawCards) ~= "table" or #rawCards == 0 then return nil end
    local cards = {}
    for i = 1, #rawCards do
        cards[i] = type(rawCards[i]) == "table" and rawCards[i] or {}
    end
    return cards
end

local function GuaranteedIndex(board, cards)
    local index = board.guaranteedIndex
    if index and not cards[index] then index = nil end
    if index then return index end
    for i = 1, #cards do
        if cards[i].isGuaranteed then return i end
    end
    return nil
end

local function PendingFamilies(state)
    local pending = {}
    local entries = type(state.queue) == "table" and state.queue.entries or nil
    if type(entries) ~= "table" then return pending end
    for i = 1, #entries do
        local entry = entries[i]
        if type(entry) == "table" and entry.family ~= nil then
            pending[entry.family] = true
        end
    end
    return pending
end

local function CopyCounts(source)
    local result = {}
    for key, count in pairs(type(source) == "table" and source or {}) do
        result[key] = count
    end
    return result
end

local function AddCounts(target, source)
    for key, count in pairs(type(source) == "table" and source or {}) do
        target[key] = (target[key] or 0) + (tonumber(count) or 0)
    end
end

local function EffectiveOwned(owned, locked)
    local base = owned or {}
    if type(locked) ~= "table" then return base end
    if type(locked.bySpell) ~= "table"
        and type(locked.byFamily) ~= "table" then
        return base
    end
    local merged = {
        synced = base.synced,
        bySpell = CopyCounts(base.bySpell),
        byFamily = CopyCounts(base.byFamily),
    }
    AddCounts(merged.bySpell, locked.bySpell)
    AddCounts(merged.byFamily, locked.byFamily)
    return merged
end

local function IsPrecious(ctx, card, delta)
    local model = ctx.model
    return not IsFrozen(card)
        and delta > 0
        and Wished(ctx.plan, card.family)
        and OwnedFam(ctx.owned, card.family) <= 0
        and type(model.FamilyMultiQuality) == "function"
        and model.FamilyMultiQuality(ctx.catalog, card.family)
        and (tonumber(card.quality) or 0)
            >= model.EffectiveWishedQuality(
                ctx.plan, ctx.catalog, card.family)
end

local function PendingWanted(ctx, index, card, wanted, precious)
    return index ~= ctx.guaranteedIndex
        and not IsFrozen(card)
        and wanted
        and Wished(ctx.plan, card.family)
        and OwnedFam(ctx.owned, card.family) <= 0
        and ctx.pendingFamilies[card.family]
        and not precious
end

local function CardPresentation(ctx, index, card, delta, wanted, precious)
    local annotation = Annotation(card, delta, ctx.plan, ctx.owned)
    local effective = delta
    if IsFrozen(card) and wanted then
        ctx.bankedWantedOnBoard = true
        return "banked", effective
    end
    if PendingWanted(ctx, index, card, wanted, precious) then
        return "returns later", delta * ctx.deferFactor
    end
    if Wished(ctx.plan, card.family) and delta < 0
        and annotation ~= "duplicate" then
        annotation = "low quality"
    end
    return annotation, effective
end

local function ClassifyCard(ctx, index)
    local card = ctx.cards[index]
    local delta = tonumber(ctx.model.Delta(
        ctx.plan, ctx.owned, card.spellId, ctx.catalog, ctx.params)) or 0
    local wanted = IsWanted(
        ctx.model, card, delta, ctx.plan, ctx.owned, ctx.catalog)
    local precious = IsPrecious(ctx, card, delta)
    local annotation, effective = CardPresentation(
        ctx, index, card, delta, wanted, precious)
    ctx.deltas[index] = delta
    ctx.wanted[index] = wanted
    ctx.annotations[index] = annotation
    ctx.effective[index] = effective
    ctx.precious[index] = precious
end


local function IsFinalSelection(ctx)
    return (ctx.level or 0) >= 80
        and type(ctx.state.horizon) == "number"
        and ctx.state.horizon == 1
end

local function FinishContext(ctx)
    ctx.guaranteedWanted = ctx.guaranteedIndex ~= nil
        and ctx.wanted[ctx.guaranteedIndex] == true
    ctx.finalSelection = IsFinalSelection(ctx)
    ctx.unusableGuarantee = ctx.guaranteedIndex ~= nil
        and not ctx.guaranteedWanted
    return ctx
end

local function BuildContext(state, model, cards)
    local board = state.board
    local ctx = {
        state = state,
        model = model,
        board = board,
        cards = cards,
        count = #cards,
        originalOwned = state.owned,
        plan = state.plan or { advisorOnly = true },
        params = state.params or {},
        charges = state.charges or {},
        flags = state.flags or {},
        level = tonumber(state.level),
        catalog = state.catalog,
        annotations = {},
        deltas = {},
        effective = {},
        wanted = {},
        precious = {},
        bankedWantedOnBoard = false,
    }
    ctx.guaranteedIndex = GuaranteedIndex(board, cards)
    ctx.pendingFamilies = PendingFamilies(state)
    ctx.owned = EffectiveOwned(state.owned, state.locked)
    ctx.deferFactor = tonumber(ctx.params.deferFactor) or 0.35
    for i = 1, ctx.count do ClassifyCard(ctx, i) end
    return FinishContext(ctx)
end

local function SearchRefused(ctx)
    return type(ctx.state.searchRefused) == "table"
        and ctx.state.searchRefused or {}
end

local function CanBanish(ctx)
    local refused = SearchRefused(ctx)
    return ctx.state.allowBanish ~= false
        and not refused.banish
        and (tonumber(ctx.charges.banish) or 0) > 0
        and ctx.charges.trustworthy == true
        and not ctx.charges.banishSpentThisPush
end

local function CanReroll(ctx)
    return not SearchRefused(ctx).reroll
        and (tonumber(ctx.charges.reroll) or 0) > 0
        and ctx.charges.trustworthy == true
end

local function BanishAction(ctx, index, reason)
    return {
        type = "banish",
        index = index,
        spellId = ctx.cards[index].spellId,
        reason = reason,
        annotations = ctx.annotations,
        deltas = ctx.deltas,
    }
end

local function RerollAction(ctx, reason)
    return {
        type = "reroll",
        reason = reason,
        annotations = ctx.annotations,
        deltas = ctx.deltas,
    }
end

local function FindWantedSide(ctx)
    local best, resolving = nil, false
    for i = 1, ctx.count do
        if i ~= ctx.guaranteedIndex and ctx.wanted[i] then
            if not FreezeWorthy(
                ctx.model, ctx.state, ctx.cards[i], ctx.plan,
                ctx.owned, ctx.catalog) then
                ctx.annotations[i] = "returns later"
            elseif ctx.cards[i].justFrozen then
                resolving = true
            elseif BetterWanted(
                ctx.model, ctx.cards, ctx.deltas, ctx.plan, ctx.owned,
                ctx.catalog, i, best) then
                best = i
            end
        end
    end
    return best, resolving
end

local function RejectOffWishlistGuarantee(ctx)
    local bestSide, freezeResolving = FindWantedSide(ctx)
    if bestSide then
        return TakeAction(
            ctx.cards, ctx.annotations, ctx.deltas, bestSide,
            "Reject off-wishlist guarantee; take missing wishlist side Echo")
    end
    if freezeResolving then
        return WaitAction(
            "Wanted side Freeze is resolving before rejecting "
                .. "off-wishlist guarantee",
            ctx.annotations, ctx.deltas)
    end
    if CanBanish(ctx) then
        local worst = SafeBanishCandidate(
            ctx.cards, ctx.deltas, ctx.plan, ctx.guaranteedIndex)
        if worst then
            return BanishAction(ctx, worst,
                "Replace off-wishlist guarantee: Banish safe side to search "
                    .. "for a missing wishlist Echo")
        end
    end
    if CanReroll(ctx) then
        return RerollAction(ctx,
            "Replace off-wishlist guarantee: Reroll side choices for a "
                .. "missing wishlist Echo")
    end
    local side = LeastHarmfulSide(
        ctx.cards, ctx.annotations, ctx.deltas, ctx.guaranteedIndex)
    if side then
        return TakeAction(ctx.cards, ctx.annotations, ctx.deltas, side,
            "Reject off-wishlist guarantee; take least-harmful side")
    end
    return WaitAction("Off-wishlist guarantee has no selectable side",
        ctx.annotations, ctx.deltas)
end

local function WantedSideBlocksBanish(ctx)
    local anyWanted, anyUnbanked = false, false
    for i = 1, ctx.count do
        if i ~= ctx.guaranteedIndex and ctx.wanted[i] then
            anyWanted = true
            if not IsFrozen(ctx.cards[i]) then
                anyUnbanked = true
                break
            end
        end
    end
    if ctx.guaranteedIndex then return anyUnbanked end
    return anyWanted
end

local function EarlyBanish(ctx)
    if not ctx.level or ctx.level >= 80 then return nil end
    if WantedSideBlocksBanish(ctx) or not CanBanish(ctx) then return nil end
    local worst = SafeBanishCandidate(
        ctx.cards, ctx.deltas, ctx.plan, ctx.guaranteedIndex)
    if not worst then return nil end
    return BanishAction(ctx, worst,
        "Early search: Banish safe off-wishlist side before normal roll "
            .. "sequencing")
end

local function FinalCandidate(ctx, index)
    return ctx.wanted[index] and not ctx.cards[index].justFrozen
end

local function FindFinalOptions(ctx)
    local frozen, visible = nil, nil
    for i = 1, ctx.count do
        local card = ctx.cards[i]
        if FinalCandidate(ctx, i) then
            if card.isFrozen or card.isCarried then
                if BetterWanted(
                    ctx.model, ctx.cards, ctx.deltas, ctx.plan, ctx.owned,
                    ctx.catalog, i, frozen) then
                    frozen = i
                end
            elseif i ~= ctx.guaranteedIndex and not card.isGuaranteed
                and BetterWanted(
                    ctx.model, ctx.cards, ctx.deltas, ctx.plan, ctx.owned,
                    ctx.catalog, i, visible) then
                visible = i
            end
        end
    end
    return frozen, visible
end

local function BetterFinalVisible(ctx, visible, frozen)
    return visible and (not frozen or BetterWanted(
        ctx.model, ctx.cards, ctx.deltas, ctx.plan, ctx.owned,
        ctx.catalog, visible, frozen))
end

local function FinalRerollSafe(ctx, frozen)
    return frozen ~= nil
        or ctx.guaranteedIndex == nil
        or ctx.wanted[ctx.guaranteedIndex] ~= true
        or ctx.flags.REROLL_HOLDS_GUARANTEED == true
end

local function FinalRerollReason(ctx, frozen)
    if frozen then
        return "Final selection: Reroll searches while the frozen wanted "
            .. "Echo remains protected"
    end
    if ctx.guaranteedIndex and ctx.wanted[ctx.guaranteedIndex] then
        return "Final selection: Reroll searches while the guaranteed "
            .. "wanted Echo is held"
    end
    return "Final selection: Reroll searches past a non-wanted guaranteed Echo"
end

local function FinalSearchPending(ctx, frozen)
    local protectedIndex = frozen or ctx.guaranteedIndex
    if protectedIndex == nil then return false end
    local protectedWanted = frozen ~= nil
        or (ctx.guaranteedIndex ~= nil
            and ctx.wanted[ctx.guaranteedIndex] == true)
    local fallback = protectedWanted and ctx.cards[protectedIndex] or nil
    return MissingAfterFallback(ctx.plan, ctx.owned, fallback, ctx.catalog)
end

local function FinalBanishAction(ctx)
    if not CanBanish(ctx) then return nil end
    local worst = SafeBanishCandidate(
        ctx.cards, ctx.deltas, ctx.plan, ctx.guaranteedIndex)
    if not worst then return nil end
    return Endgame(BanishAction(ctx, worst,
        "Final selection: safe Banish searches for another missing wanted Echo"))
end

local function FinalSearchAction(ctx, frozen)
    if not FinalSearchPending(ctx, frozen) then return nil end
    local action = FinalBanishAction(ctx)
    if action then return action end
    if CanReroll(ctx) and FinalRerollSafe(ctx, frozen) then
        return Endgame(RerollAction(ctx, FinalRerollReason(ctx, frozen)))
    end
    return nil
end

local function FinalFrozenFallback(ctx, frozen)
    if not frozen then return nil end
    local reason = "Final selection: search exhausted or unavailable; "
        .. "take frozen wanted Echo"
    local refused = SearchRefused(ctx)
    if refused.banish or refused.reroll then
        reason = "Final selection: search action refused; take frozen wanted Echo"
    end
    return Endgame(TakeAction(
        ctx.cards, ctx.annotations, ctx.deltas, frozen, reason))
end

local function FinalSelectionAction(ctx)
    local frozen, visible = FindFinalOptions(ctx)
    if BetterFinalVisible(ctx, visible, frozen) then
        local reason = frozen
            and "Final selection: better remaining wishlist Echo replaces "
                .. "frozen target"
            or "Final selection: take wanted side Echo before search"
        return Endgame(TakeAction(
            ctx.cards, ctx.annotations, ctx.deltas, visible, reason))
    end
    return FinalSearchAction(ctx, frozen)
        or FinalFrozenFallback(ctx, frozen)
end

local function RejectFinalGuarantee(ctx)
    if not ctx.finalSelection or not ctx.unusableGuarantee then return nil end
    local side = LeastHarmfulSide(
        ctx.cards, ctx.annotations, ctx.deltas, ctx.guaranteedIndex)
    if side then
        return Endgame(TakeAction(ctx.cards, ctx.annotations, ctx.deltas, side,
            "Final selection: reject off-wishlist guarantee"))
    end
    return Endgame(WaitAction(
        "Final off-wishlist guarantee has no selectable side",
        ctx.annotations, ctx.deltas))
end

local function FindGuaranteedSide(ctx)
    local unbanked, banked = nil, false
    for i = 1, ctx.count do
        if i ~= ctx.guaranteedIndex and ctx.wanted[i] then
            if IsFrozen(ctx.cards[i]) then
                banked = true
            elseif FreezeWorthy(
                ctx.model, ctx.state, ctx.cards[i], ctx.plan,
                ctx.owned, ctx.catalog) then
                if BetterWanted(
                    ctx.model, ctx.cards, ctx.deltas, ctx.plan, ctx.owned,
                    ctx.catalog, i, unbanked) then
                    unbanked = i
                end
            else
                ctx.annotations[i] = "returns later"
            end
        end
    end
    return unbanked, banked
end

local function FreezeAvailable(ctx, index)
    return (tonumber(ctx.charges.freeze) or 0) > 0
        and ctx.charges.trustworthy == true
        and ctx.state.canFreeze ~= false
        and not ctx.cards[index].isGuaranteed
end

local function FreezeAction(ctx, index)
    return {
        type = "freeze",
        index = index,
        spellId = ctx.cards[index].spellId,
        reason = "Freeze wanted side Echo; take guaranteed after it resolves",
        steps = {
            { type = "freeze", index = index,
              spellId = ctx.cards[index].spellId },
            { type = "take", index = ctx.guaranteedIndex,
              spellId = ctx.cards[ctx.guaranteedIndex].spellId },
        },
        annotations = ctx.annotations,
        deltas = ctx.deltas,
    }
end

local function FreezeUnavailableReason(ctx)
    if (tonumber(ctx.charges.freeze) or 0) <= 0 then
        return "Freeze unavailable"
    end
    if ctx.charges.trustworthy ~= true then return "Freeze count untrusted" end
    return "Freeze unavailable or refused on this board"
end

local function GuaranteedPhase(ctx)
    if not ctx.guaranteedIndex then return nil end
    local unbanked, banked = FindGuaranteedSide(ctx)
    if banked then
        return TakeAction(
            ctx.cards, ctx.annotations, ctx.deltas, ctx.guaranteedIndex,
            "Take guaranteed; wanted side Echo is safely frozen")
    end
    if unbanked and FreezeAvailable(ctx, unbanked) then
        return FreezeAction(ctx, unbanked)
    end
    if unbanked then
        return TakeAction(ctx.cards, ctx.annotations, ctx.deltas, unbanked,
            FreezeUnavailableReason(ctx)
                .. ": taking wanted side Echo to prevent its loss")
    end
    return TakeAction(
        ctx.cards, ctx.annotations, ctx.deltas, ctx.guaranteedIndex,
        "Drain guaranteed queue")
end

local function FindNormalWanted(ctx)
    local frozen, visible, protected = nil, nil, false
    for i = 1, ctx.count do
        if ctx.wanted[i] then
            local card = ctx.cards[i]
            if card.justFrozen then
                protected = true
            elseif card.isFrozen or card.isCarried then
                if BetterWanted(
                    ctx.model, ctx.cards, ctx.deltas, ctx.plan, ctx.owned,
                    ctx.catalog, i, frozen) then
                    frozen = i
                end
            elseif BetterWanted(
                ctx.model, ctx.cards, ctx.deltas, ctx.plan, ctx.owned,
                ctx.catalog, i, visible) then
                visible = i
            end
        end
    end
    return frozen, visible, protected
end

local function BetterConvergenceCandidate(ctx, candidate, incumbent)
    if incumbent == nil then return true end
    local delta, previous = ctx.deltas[candidate], ctx.deltas[incumbent]
    if delta ~= previous then return delta > previous end
    local filler = ctx.annotations[candidate] == "filler"
    local previousFiller = ctx.annotations[incumbent] == "filler"
    if filler ~= previousFiller then return not filler end
    local quality = tonumber(ctx.cards[candidate].quality) or 0
    local previousQuality = tonumber(ctx.cards[incumbent].quality) or 0
    if quality ~= previousQuality then return quality < previousQuality end
    return candidate < incumbent
end

local function ConvergenceOptions(ctx)
    local selectable, nonDuplicate = false, false
    for i = 1, ctx.count do
        if ctx.annotations[i] ~= "duplicate" then nonDuplicate = true end
        if not ctx.cards[i].justFrozen then selectable = true end
    end
    return selectable, nonDuplicate
end

local function ConvergencePick(ctx)
    local selectable, nonDuplicate = ConvergenceOptions(ctx)
    local pick = nil
    for i = 1, ctx.count do
        local eligible = (not nonDuplicate or ctx.annotations[i] ~= "duplicate")
            and (not selectable or not ctx.cards[i].justFrozen)
        if eligible and BetterConvergenceCandidate(ctx, i, pick) then
            pick = i
        end
    end
    return pick or 1
end

local function ConvergenceAction(ctx)
    local pick = ConvergencePick(ctx)
    local action = TakeAction(
        ctx.cards, ctx.annotations, ctx.deltas, pick,
        ctx.annotations[pick] == "duplicate"
            and "Forced take: every selectable Echo is already owned"
            or "Forced least-harmful selection")
    action.forced = true
    return ctx.finalSelection and Endgame(action) or action
end

local function FinishSearchAction(ctx, action)
    return ctx.finalSelection and Endgame(action) or action
end

local function NormalSearchAction(ctx, protected)
    if protected then return nil end
    if CanBanish(ctx) then
        local worst = SafeBanishCandidate(
            ctx.cards, ctx.deltas, ctx.plan, ctx.guaranteedIndex)
        if worst then
            return FinishSearchAction(ctx, BanishAction(ctx, worst,
                "No wanted Echo: banish worst safe off-wishlist card"))
        end
    end
    if CanReroll(ctx) then
        return FinishSearchAction(ctx, RerollAction(ctx,
            "No wanted Echo or useful safe Banish: reroll"))
    end
    return nil
end

local function NormalPhase(ctx)
    local frozen, visible, protected = FindNormalWanted(ctx)
    if frozen then
        return TakeAction(ctx.cards, ctx.annotations, ctx.deltas, frozen,
            "Take frozen wanted Echo before searching")
    end
    if visible then
        return TakeAction(ctx.cards, ctx.annotations, ctx.deltas, visible,
            "Take wanted Echo")
    end
    local action = NormalSearchAction(ctx, protected)
    if action then return action end
    return ConvergenceAction(ctx)
end

-- state = { board, owned, charges, plan, queue, flags, level, horizon,
--           support, params, canFreeze, rerollBudget [, catalog] }
-- Returns { type = "take"|"freeze"|"reroll"|"banish"|"wait", spellId=?,
--   index=?, reason = s, annotations = { [cardIndex] = s },
--   deltas = { [cardIndex] = n } }
-- Pure: same input, same output; malformed input degrades to "wait".

local function InitializeDecision(state)
    local annotations = {}
    if type(state) ~= "table" then
        return nil, WaitAction("no board", annotations)
    end
    local model = GetModel()
    if not model or type(model.Delta) ~= "function" then
        return nil, WaitAction("model unavailable", annotations)
    end
    local cards = NormalizeCards(state.board)
    if not cards then return nil, WaitAction("no board", annotations) end
    return BuildContext(state, model, cards), nil
end

local function AutomationWait(ctx)
    if (ctx.originalOwned == nil or ctx.originalOwned.synced == false)
        and ctx.level and ctx.level > 1 then
        return WaitAction("unsynced", ctx.annotations, ctx.deltas)
    end
    if ctx.plan.advisorOnly then
        return WaitAction("advisor", ctx.annotations, ctx.deltas)
    end
    return nil
end

local function ChooseAction(ctx)
    if ctx.unusableGuarantee and not ctx.finalSelection then
        return RejectOffWishlistGuarantee(ctx)
    end

    local action = EarlyBanish(ctx)
    if action then return action end
    if ctx.finalSelection then
        action = FinalSelectionAction(ctx)
        if action then return action end
    end
    action = RejectFinalGuarantee(ctx)
    if action then return action end
    action = GuaranteedPhase(ctx)
    if action then return action end
    return NormalPhase(ctx)
end

function Policy.Decide(state)
    local ctx, result = InitializeDecision(state)
    if result then return result end
    result = AutomationWait(ctx)
    if result then return result end
    return ChooseAction(ctx)
end
