-- Deterministic current-Ebonhold random-board policy scenarios.
dofile("logic/Model.lua")
dofile("logic/Policy.lua")

local Policy = Nexus.Policy
local checks = 0

local function expect(condition, message)
    checks = checks + 1
    assert(condition, message)
end

local rows = {
    [100] = { spellId=100, name="Stack Target", quality=1, maxStack=3 },
    [200] = { spellId=200, name="Ordinary Target", quality=1, maxStack=1 },
    [210] = { spellId=210, name="Quality Target", quality=0, maxStack=1 },
    [211] = { spellId=211, name="Quality Target", quality=2, maxStack=1 },
    [220] = { spellId=220, name="Held Target", quality=1, maxStack=1 },
    [221] = { spellId=221, name="Side Target", quality=1, maxStack=1 },
    [222] = { spellId=222, name="Another Target", quality=1, maxStack=1 },
    [300] = { spellId=300, name="Legacy Flag Target", quality=1, maxStack=1 },
    [400] = { spellId=400, name="Filler A", quality=1, maxStack=1 },
    [401] = { spellId=401, name="Filler B", quality=1, maxStack=1 },
}
local catalog = {
    rows = rows,
    familyOf = {
        [100]="stack", [200]="ordinary", [210]="quality", [211]="quality",
        [220]="held", [221]="side", [222]="another",
        [300]="legacy", [400]="fillerA", [401]="fillerB",
    },
    familyMembers = {
        stack={100}, ordinary={200}, quality={210,211}, legacy={300},
        held={220}, side={221}, another={222},
        fillerA={400}, fillerB={401},
    },
}
local plan = {
    advisorOnly = false,
    wishedFamilies = {
        stack=true, ordinary=true, quality=true, held=true,
        side=true, another=true, legacy=true,
    },
    targets = {
        stack={ targetStacks=3, wishedQuality=1 },
        ordinary={ targetStacks=1, wishedQuality=1 },
        quality={ targetStacks=1, wishedQuality=2 },
        held={ targetStacks=1, wishedQuality=1 },
        side={ targetStacks=1, wishedQuality=1 },
        another={ targetStacks=1, wishedQuality=1 },
        legacy={ targetStacks=1, wishedQuality=1 },
    },
}

local function card(spellId, extra)
    local out = {
        spellId=spellId,
        family=catalog.familyOf[spellId],
        quality=rows[spellId].quality,
    }
    for key, value in pairs(extra or {}) do out[key] = value end
    return out
end

local function decide(cards, options)
    options = options or {}
    return Policy.Decide({
        board={cards=cards, guaranteedIndex=options.guaranteedIndex},
        owned={
            synced=options.synced ~= false,
            bySpell=options.bySpell or {},
            byFamily=options.byFamily or {},
        },
        locked=options.locked,
        charges=options.charges or {
            freeze=1, banish=1, reroll=1, trustworthy=true,
            banishSpentThisPush=options.banishSpentThisPush,
        },
        plan=options.plan or plan,
        queue=options.queue,
        catalog=catalog,
        canFreeze=options.canFreeze,
        level=options.level ~= nil and options.level or 20,
        horizon=options.horizon,
        searchRefused=options.searchRefused,
        allowBanish=options.allowBanish,
    })
end

do
    local result = decide({card(400), card(401)}, {
        synced=false,
        charges={freeze=0,banish=0,reroll=0,trustworthy=true},
    })
    expect(result.type == "wait", "unsynchronized ownership must pause automation")
end

do
    local result = decide({card(200), card(221), card(400)})
    expect(result.type == "freeze" and result.index == 1,
        "two random wishlist Echoes must Freeze one before either is taken")
    expect(result.steps and result.steps[2] and result.steps[2].spellId == 221,
        "the Freeze recommendation must preserve and then take both wishlist Echoes")
end

do
    local result = decide({
        card(200, {isGuaranteed=true}), card(221), card(400),
    }, {guaranteedIndex=1})
    expect(result.type == "freeze" and result.index == 1,
        "legacy guaranteed flags must not change a random-board decision")
end

do
    local result = decide({card(200), card(221), card(400)}, {
        queue={entries={{spellId=200,family="ordinary",wanted=true}}},
    })
    expect(result.type == "freeze",
        "obsolete Saved Build queue data must not defer a random wishlist Echo")
    expect(result.annotations[1] ~= "returns later",
        "random wishlist Echoes must never be labeled returns later")
end

do
    local result = decide({
        card(200, {justFrozen=true}), card(221), card(400),
    })
    expect(result.type == "take" and result.index == 2,
        "after Freeze resolves, Nexus must take the other visible wishlist Echo")
end

do
    local result = decide({
        card(220, {isFrozen=true}), card(221), card(400),
    })
    expect(result.type == "take" and result.index == 2,
        "a visible wishlist Echo must be taken while another remains protected")
end

do
    local result = decide({card(200), card(400), card(401)})
    expect(result.type == "take" and result.index == 1,
        "one visible wishlist Echo must be taken without spending Freeze")
end

do
    local result = decide({card(200), card(221), card(400)}, {
        charges={freeze=0,banish=1,reroll=1,trustworthy=true},
    })
    expect(result.type == "take" and result.index == 1,
        "without a usable Freeze Nexus must take the best wishlist Echo")
end

do
    local result = decide({card(200), card(211), card(100)})
    expect(result.type == "freeze" and result.index == 3,
        "a still-short stacking target must receive first Freeze priority")
    expect(result.steps and result.steps[2] and result.steps[2].spellId == 211,
        "after protecting the stack target Nexus must take the quality catch")
end

do
    local result = decide({card(400), card(401)})
    expect(result.type == "banish" and result.index == 1,
        "a random all-filler board must Banish a safe filler first")
end

do
    local result = decide({card(400), card(401)}, {banishSpentThisPush=true})
    expect(result.type == "reroll",
        "after the available Banish is spent an all-filler board must Reroll")
end

do
    local result = decide({card(400), card(401)}, {
        charges={freeze=0,banish=0,reroll=0,trustworthy=true},
    })
    expect(result.type == "take" and result.forced == true,
        "an exhausted all-filler board must record a forced least-harmful take")
end

do
    local result = decide({card(210), card(400), card(401)})
    expect(result.type == "banish" and result.index ~= 1,
        "a wrong-quality wished family must remain protected from Banish")
end

do
    local result = decide({card(200), card(221), card(400)}, {
        level=80, horizon=1, canFreeze=false,
        charges={freeze=1,banish=0,reroll=0,trustworthy=true},
    })
    expect(result.type == "take" and result.index == 1 and result.endgame,
        "the final selection must take the best wishlist Echo without Freeze")
end

do
    local result = decide({
        card(220, {isFrozen=true}), card(400), card(401),
    }, {
        level=80, horizon=1, canFreeze=false,
        charges={freeze=0,banish=1,reroll=1,trustworthy=true},
    })
    expect(result.type == "banish" and result.index == 2 and result.endgame,
        "the final selection may search safe filler while a wishlist Echo is frozen")
end

do
    local result = decide({
        card(220, {isFrozen=true}), card(400), card(401),
    }, {
        level=80, horizon=1, canFreeze=false,
        charges={freeze=0,banish=1,reroll=1,trustworthy=true},
        searchRefused={banish=true,reroll=true},
    })
    expect(result.type == "take" and result.index == 1 and result.endgame,
        "after final-search refusals Nexus must cash the frozen wishlist Echo")
end

do
    local result = decide({card(400), card(401)}, {
        allowBanish=false,
        charges={freeze=0,banish=2,reroll=0,trustworthy=true},
    })
    expect(result.type == "take" and result.forced,
        "disabled automatic Banish must advance to an executable action")
end

do
    local result = decide({card(200), card(221)}, {
        plan={advisorOnly=true,wishedFamilies={},targets={}},
    })
    expect(result.type == "wait" and result.reason == "advisor",
        "advisor mode must never spend gameplay charges")
end

expect(Policy.Decide(nil).type == "wait", "malformed policy state must fail closed")

print("random-board policy scenarios OK (checks=" .. checks .. ")")
