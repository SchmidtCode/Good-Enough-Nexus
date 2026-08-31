-- Nexus: logic/Policy.lua
-- Pure per-board decision engine for current Ebonhold random offerings.
-- Saved Builds are comparison targets only. No board position or legacy
-- isGuaranteed flag predicts a future Echo. Select is mandatory; Freeze does
-- not consume the board, so two visible wishlist Echoes can both be kept by
-- freezing one before taking the other. Policy proposes; the adapter re-checks
-- and may drop. Never banishes a wished/frozen/carried/justFrozen card.
-- No WoW API calls; plain Lua 5.1.
--
-- Current live-play rules:
--  A. Every visible card is a random offering. Saved Builds and legacy
--     isGuaranteed fields never reserve a card or predict a later return.
--  B. If two usable wishlist Echoes share a board and Freeze is available,
--     freeze the better target and then take the other. This preserves both
--     random opportunities instead of discarding one.
--  C. If a wanted Echo is already frozen, take another visible target while
--     the held one remains protected; otherwise recover the held target.
--  D. Below-target-quality copies of multi-quality families are not wanted.
--     Wished families remain protected from Banish even when that offered
--     quality cannot satisfy the target.

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

-- Base annotation: wanted > duplicate > filler > junk. Decide may overlay
-- "banked" or "low quality" after the effective-value pass.
local function TargetCap(plan, family, wished)
    if not wished or type(plan.targets) ~= "table" then return 1 end
    local target = plan.targets[family]
    return type(target) == "table" and target.targetStacks or 1
end

local function Annotation(card, delta, plan, owned)
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

local function SafeBanishCard(card, plan)
    return not card.isFrozen
        and not card.isCarried
        and not card.justFrozen
        and not Wished(plan, card.family)
end

local function SafeBanishCandidate(cards, deltas, plan)
    local worst, worstDelta = nil, nil
    for i = 1, #cards do
        if SafeBanishCard(cards[i], plan)
            and (worst == nil or deltas[i] < worstDelta
                or (deltas[i] == worstDelta and i < worst)) then
            worst, worstDelta = i, deltas[i]
        end
    end
    return worst
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
        local source = type(rawCards[i]) == "table" and rawCards[i] or {}
        local card = {}
        for key, value in pairs(source) do card[key] = value end
        -- Current Ebonhold no longer guarantees the right slot or any other
        -- card. Ignore stale flags from older clients and captured logs.
        card.isGuaranteed = false
        cards[i] = card
    end
    return cards
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

local function CardPresentation(ctx, card, delta, wanted)
    local annotation = Annotation(card, delta, ctx.plan, ctx.owned)
    local effective = delta
    if IsFrozen(card) and wanted then
        ctx.bankedWantedOnBoard = true
        return "banked", effective
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
    local annotation, effective = CardPresentation(
        ctx, card, delta, wanted)
    ctx.deltas[index] = delta
    ctx.wanted[index] = wanted
    ctx.annotations[index] = annotation
    ctx.effective[index] = effective
end


local function IsFinalSelection(ctx)
    return (ctx.level or 0) >= 80
        and type(ctx.state.horizon) == "number"
        and ctx.state.horizon == 1
end

local function FinishContext(ctx)
    ctx.finalSelection = IsFinalSelection(ctx)
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
        bankedWantedOnBoard = false,
    }
    ctx.owned = EffectiveOwned(state.owned, state.locked)
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

local function WantedSideBlocksBanish(ctx)
    local anyWanted = false
    for i = 1, ctx.count do
        if ctx.wanted[i] then
            anyWanted = true
            break
        end
    end
    return anyWanted
end

local function EarlyBanish(ctx)
    if not ctx.level or ctx.level >= 80 then return nil end
    if WantedSideBlocksBanish(ctx) or not CanBanish(ctx) then return nil end
    local worst = SafeBanishCandidate(ctx.cards, ctx.deltas, ctx.plan)
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
            elseif BetterWanted(
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

local function FinalRerollReason(ctx, frozen)
    if frozen then
        return "Final selection: Reroll searches while the frozen wanted "
            .. "Echo remains protected"
    end
    return "Final selection: Reroll searches for a missing wishlist Echo"
end

local function FinalSearchPending(ctx, frozen)
    local fallback = frozen and ctx.cards[frozen] or nil
    return MissingAfterFallback(ctx.plan, ctx.owned, fallback, ctx.catalog)
end

local function FinalBanishAction(ctx)
    if not CanBanish(ctx) then return nil end
    local worst = SafeBanishCandidate(ctx.cards, ctx.deltas, ctx.plan)
    if not worst then return nil end
    return Endgame(BanishAction(ctx, worst,
        "Final selection: safe Banish searches for another missing wanted Echo"))
end

local function FinalSearchAction(ctx, frozen)
    if not FinalSearchPending(ctx, frozen) then return nil end
    local action = FinalBanishAction(ctx)
    if action then return action end
    if CanReroll(ctx) then
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

local function FreezeAvailable(ctx, index)
    return (tonumber(ctx.charges.freeze) or 0) > 0
        and ctx.charges.trustworthy == true
        and ctx.state.canFreeze ~= false
end

local function FindNormalWanted(ctx)
    local frozen, visible, alternate, protected = nil, nil, nil, false
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
                alternate, visible = visible, i
            elseif BetterWanted(
                ctx.model, ctx.cards, ctx.deltas, ctx.plan, ctx.owned,
                ctx.catalog, i, alternate) then
                alternate = i
            end
        end
    end
    return frozen, visible, alternate, protected
end

local function FreezeRandomPair(ctx, freezeIndex, takeIndex)
    return {
        type = "freeze",
        index = freezeIndex,
        spellId = ctx.cards[freezeIndex].spellId,
        reason = "Freeze one wishlist Echo; take the other after it resolves",
        steps = {
            { type = "freeze", index = freezeIndex,
              spellId = ctx.cards[freezeIndex].spellId },
            { type = "take", index = takeIndex,
              spellId = ctx.cards[takeIndex].spellId },
        },
        annotations = ctx.annotations,
        deltas = ctx.deltas,
    }
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
        local worst = SafeBanishCandidate(ctx.cards, ctx.deltas, ctx.plan)
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
    local frozen, visible, alternate, protected = FindNormalWanted(ctx)
    -- A held wishlist Echo is already protected. Take another visible target
    -- first, then recover the held one on a later board.
    if frozen and visible then
        return TakeAction(ctx.cards, ctx.annotations, ctx.deltas, visible,
            "Take visible wishlist Echo while another remains frozen")
    end
    if frozen then
        return TakeAction(ctx.cards, ctx.annotations, ctx.deltas, frozen,
            "Take frozen wanted Echo before searching")
    end
    if visible and alternate and FreezeAvailable(ctx, visible) then
        return FreezeRandomPair(ctx, visible, alternate)
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
--           support, params, canFreeze [, catalog] }
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
    local action = EarlyBanish(ctx)
    if action then return action end
    if ctx.finalSelection then
        action = FinalSelectionAction(ctx)
        if action then return action end
    end
    return NormalPhase(ctx)
end

function Policy.Decide(state)
    local ctx, result = InitializeDecision(state)
    if result then return result end
    result = AutomationWait(ctx)
    if result then return result end
    return ChooseAction(ctx)
end
