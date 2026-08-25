-- Nexus: core/AccountBuildWorkspace.lua
-- Durable account-build lifecycle. UI modules collect input and render results;
-- this module owns identity, validation, saved-loadout mirrors, and mutations.

Nexus = Nexus or {}
local Workspace = {}
Nexus.AccountBuildWorkspace = Workspace

local Adapter
local lastSavedLoadoutImport = 0
local stats = { relatedScans=0, relatedHydrations=0, imports=0, mutations=0 }

local CLASS_MASK = {
    WARRIOR=1, PALADIN=2, HUNTER=4, ROGUE=8, PRIEST=16,
    DEATHKNIGHT=32, SHAMAN=64, MAGE=128, WARLOCK=256, DRUID=1024,
}
local CLASS_LABEL = {
    DEATHKNIGHT="Death Knight", DRUID="Druid", HUNTER="Hunter",
    MAGE="Mage", PALADIN="Paladin", PRIEST="Priest", ROGUE="Rogue",
    SHAMAN="Shaman", WARLOCK="Warlock", WARRIOR="Warrior",
}
local VALID_CLASS = {}
for class in pairs(CLASS_MASK) do VALID_CLASS[class] = true end

local function Catalog()
    return Nexus and Nexus.BuildCatalog
end

local function LoadBuild(id)
    local catalog = Catalog()
    return catalog and catalog.Get and catalog.Get(id) or nil
end

local function SaveBuild(build)
    local catalog = Catalog()
    if not (catalog and catalog.Put) then return false, "build catalog unavailable" end
    return catalog.Put(build)
end

local function RemoveOverlay(id)
    local catalog = Catalog()
    return catalog and catalog.RemoveOverlay and catalog.RemoveOverlay(id) or false
end

local function SetTombstone(id, tombstone)
    local catalog = Catalog()
    return catalog and catalog.SetTombstone
        and catalog.SetTombstone(id, tombstone) or false
end

local function Store()
    local catalog = Catalog()
    return catalog and catalog.All and catalog.All() or {}
end

local function SummaryStore()
    local catalog = Catalog()
    if catalog and type(catalog.Summaries) == "function" then
        return catalog.Summaries()
    end
    return Store()
end

local function NormalizeClass(class)
    class = type(class) == "string" and class:upper() or nil
    return class and VALID_CLASS[class] and class or nil
end

local function InferBuildClass(echoes)
    local scores = {}
    local cat = Adapter and Adapter.Catalog and Adapter.Catalog()
    local rows = cat and cat.rows
    if type(echoes) == "table" and type(rows) == "table" and bit and bit.band then
        for _, echo in ipairs(echoes) do
            local row = rows[tonumber(echo.spellId)]
            local mask = row and tonumber(row.classMask) or 0
            if mask > 0 then
                local matched, onlyClass = 0, nil
                for class, classMask in pairs(CLASS_MASK) do
                    if bit.band(mask, classMask) ~= 0 then
                        matched, onlyClass = matched + 1, class
                    end
                end
                if matched == 1 and onlyClass then
                    scores[onlyClass] = (scores[onlyClass] or 0) + 1
                end
            end
        end
    end
    local best, bestScore, tied = nil, 0, false
    for class, score in pairs(scores) do
        if score > bestScore then
            best, bestScore, tied = class, score, false
        elseif score == bestScore and score > 0 then
            tied = true
        end
    end
    return bestScore > 0 and not tied and best or nil
end

local function CurrentRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() end
    return tostring(realm or "unknown"):lower():gsub("%s+", "")
end

local function OwnerKey(name, realm)
    name = tostring(name or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    realm = tostring(realm or CurrentRealm()):lower():gsub("%s+", "")
    return name .. "@" .. realm
end

local function CurrentOwnerKey()
    local store = Nexus and Nexus.Store
    if store and type(store.CurrentOwnerKey) == "function" then
        local ok, value = pcall(store.CurrentOwnerKey)
        if ok and value then return value end
    end
    return OwnerKey(UnitName and UnitName("player"), CurrentRealm())
end

local function IsOwnBuild(build)
    if not build then return false end
    local mine = CurrentOwnerKey()
    if not mine then return false end
    if build.ownerKey then return tostring(build.ownerKey):lower() == mine end
    if not build.isMine then return false end
    local me = tostring((UnitName and UnitName("player")) or ""):lower()
    return me ~= "" and tostring(build.author or ""):lower() == me
end

local function IsAccountBuild(build)
    if not build then return false end
    local store = Nexus and Nexus.Store
    if store and type(store.IsAccountBuild) == "function" then
        local ok, value = pcall(store.IsAccountBuild, build)
        if ok then return value == true end
    end
    return build.isMine == true or build.importedSavedBuild == true
        or IsOwnBuild(build)
end

local function NextStamp(previous)
    local now = (time and time()) or 0
    local previousStamp = tonumber(previous) or 0
    return now > previousStamp and now or previousStamp + 1
end

local function Broadcast(record)
    if Nexus.Sync then
        pcall(Nexus.Sync.BroadcastBuildSummary or Nexus.Sync.BroadcastBuild, record)
    end
end

local function WishlistEchoes(wishlist)
    if not wishlist then return nil end
    if type(wishlist.echoes) == "table" and #wishlist.echoes > 0 then
        return wishlist.echoes
    end
    if type(wishlist.entries) == "table" and #wishlist.entries > 0 then
        return wishlist.entries
    end
    return nil
end

local function FingerprintHash(text)
    local h1, h2 = 5381, 2166136261
    for i = 1, #text do
        local byte = text:byte(i)
        h1 = (h1 * 33 + byte) % 2147483647
        h2 = (h2 * 131 + byte) % 2147483629
    end
    return string.format("%08x%08x", h1, h2)
end

local function CanonicalFingerprintHash(text)
    if type(text) ~= "string" or text == "" then return nil end
    local hash = 5381
    for i = 1, #text do
        hash = ((hash * 33) + text:byte(i)) % 2147483648
    end
    return string.format("%x", hash)
end

local function NormalizeDiscordBuildLink(value)
    local link = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if link == "" then return nil end
    link = link:gsub("^<", ""):gsub(">$", "")
        :gsub("^http://", "https://")
        :gsub("^https://www%.discord%.com/", "https://discord.com/")
        :gsub("^https://discordapp%.com/", "https://discord.com/")
    local guildId, channelId, messageId =
        link:match("^https://discord%.com/channels/(%d+)/(%d+)/(%d+)/?$")
    if guildId then
        return string.format("https://discord.com/channels/%s/%s/%s",
            guildId, channelId, messageId)
    end
    guildId, channelId =
        link:match("^https://discord%.com/channels/(%d+)/(%d+)/?$")
    if guildId then
        return string.format("https://discord.com/channels/%s/%s", guildId, channelId)
    end
    return nil, "Paste a Discord channel or message link from discord.com/channels/."
end

local function RefreshIdentity(build)
    if type(build) ~= "table" or type(build.echoes) ~= "table"
        or #build.echoes == 0 then return false, "invalid Echo list" end
    local capture = Nexus.DpsCapture
    local count = 0
    for i = 1, #build.echoes do
        local echo = build.echoes[i]
        local id = type(echo) == "table" and tonumber(echo.spellId or echo.id) or nil
        local stacks = type(echo) == "table"
            and tonumber(echo.stacks or echo.count) or nil
        if not id or not stacks or stacks < 1 or stacks ~= math.floor(stacks) then
            return false, "invalid Echo list"
        end
        count = count + stacks
        if count > 120 then return false, "too many Echoes" end
    end
    local fingerprint = capture and capture.GetEchoKey
        and capture.GetEchoKey(build.echoes) or nil
    if type(fingerprint) ~= "string" or fingerprint == "" then
        local counts, ids = {}, {}
        for i = 1, #build.echoes do
            local echo = build.echoes[i]
            local id = tonumber(echo.spellId or echo.id)
            counts[id] = (counts[id] or 0) + tonumber(echo.stacks or echo.count)
        end
        for id in pairs(counts) do ids[#ids + 1] = id end
        table.sort(ids)
        local parts = {}
        for i = 1, #ids do
            parts[#parts + 1] = tostring(ids[i]) .. "x" .. tostring(counts[ids[i]])
        end
        fingerprint = table.concat(parts, ",")
    end
    build.fingerprint = fingerprint
    build.fingerprintHash = capture and capture.GetEchoHash
        and capture.GetEchoHash(build.echoes) or CanonicalFingerprintHash(fingerprint)
    build.echoCount = count
    build.loadoutAvailable = true
    build.needsFullBuild = false
    return true
end

local function NormalizeTitle(text)
    return tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function EchoPresence(echoes)
    local out = {}
    for _, echo in ipairs(type(echoes) == "table" and echoes or {}) do
        local id = tonumber(echo.spellId or echo.id)
        if id then out[id] = (out[id] or 0) + (tonumber(echo.stacks or echo.count) or 1) end
    end
    return out
end

local function EchoProgress(current, target)
    local have = EchoPresence(current)
    local matched, total = 0, 0
    for _, echo in ipairs(type(target) == "table" and target or {}) do
        local id = tonumber(echo.spellId or echo.id) or 0
        local needed = tonumber(echo.stacks or echo.count) or 1
        total = total + needed
        local found = math.min(needed, have[id] or 0)
        matched = matched + found
        have[id] = math.max(0, (have[id] or 0) - found)
    end
    return matched, total
end

local function FindRelatedBuild(serverTitle, echoes, old, author, store)
    store = type(store) == "table" and store or SummaryStore()
    local capture = Nexus.DpsCapture
    local exactKey = capture and capture.GetEchoKey and capture.GetEchoKey(echoes) or nil
    local titleKey, authorKey = NormalizeTitle(serverTitle), NormalizeTitle(author)
    local wanted, wantedTotal = EchoPresence(echoes), 0
    for _, count in pairs(wanted) do wantedTotal = wantedTotal + count end

    local function CandidateScore(candidate, candidateId, preferred)
        stats.relatedScans = stats.relatedScans + 1
        if not candidate or candidate.importedSavedBuild then return nil end
        if authorKey ~= "" and NormalizeTitle(candidate.author) ~= authorKey then return nil end
        local currentOwner = CurrentOwnerKey()
        if candidate.ownerKey and currentOwner
            and tostring(candidate.ownerKey):lower() ~= currentOwner then return nil end
        local candidateKey = candidate.fingerprint
        if not candidateKey and capture and capture.GetEchoKey then
            candidateKey = capture.GetEchoKey(candidate.echoes)
        end
        if exactKey and candidateKey == exactKey then return 100000, candidate end
        local sameTitle = titleKey ~= ""
            and NormalizeTitle(candidate.title or candidate.serverTitle) == titleKey
        if not preferred and not sameTitle then return nil end
        if type(candidate.echoes) ~= "table" and candidateId ~= nil then
            candidate = LoadBuild(candidateId)
            if not candidate then return nil end
            stats.relatedHydrations = stats.relatedHydrations + 1
        end
        local have, overlap = EchoPresence(candidate.echoes), 0
        for id, count in pairs(wanted) do
            overlap = overlap + math.min(count, have[id] or 0)
        end
        local required = math.min(8, math.max(1, math.floor(wantedTotal / 2)))
        if overlap < required then return nil end
        if sameTitle then return 10000 + overlap, candidate end
        if overlap == wantedTotal and wantedTotal >= 6 then return 1000 + overlap, candidate end
        return nil
    end

    local preferred = {}
    if old and old.recordBuildId then preferred[#preferred + 1] = old.recordBuildId end
    if old and old.publishedBuildId then preferred[#preferred + 1] = old.publishedBuildId end
    local best, bestScore, preferredIds = nil, -1, {}
    for _, candidateId in ipairs(preferred) do
        preferredIds[candidateId] = true
        local candidate = store[candidateId] or LoadBuild(candidateId)
        local score, resolved = CandidateScore(candidate, candidateId, true)
        if score and score > bestScore then best, bestScore = resolved or candidate, score end
    end
    for candidateId, candidate in pairs(store) do
        if not preferredIds[candidateId] then
            local score, resolved = CandidateScore(candidate, candidateId, false)
            if score and score > bestScore then best, bestScore = resolved or candidate, score end
        end
    end
    return best
end

local function ImportSavedLoadouts(force)
    local now = GetTime and GetTime() or 0
    if not force and now > 0 and now - lastSavedLoadoutImport < 1 then return 0 end
    lastSavedLoadoutImport = now
    local slots = Adapter and Adapter.Slots and Adapter.Slots()
    if not (slots and type(slots.bySlot) == "table") then return 0 end
    local me = tostring((UnitName and UnitName("player")) or "You")
    local meKey = me:lower():gsub("[^%w]", "_")
    local currentOwner = CurrentOwnerKey()
    if not currentOwner then return 0 end
    local ownerSlug = currentOwner:gsub("[^%w]", "_")
    local seen, changed, summaries = {}, 0, SummaryStore()
    for rawSlot, live in pairs(slots.bySlot) do
        local slot = tonumber(rawSlot)
        if slot and slot >= 1 and slot < 100 and live
            and type(live.echoes) == "table" and #live.echoes > 0 then
            local id = string.format("saved-%s-%d", ownerSlug, slot)
            local legacyId = string.format("saved-%s-%d", meKey, slot)
            seen[id] = true
            local echoes, total = {}, 0
            for _, echo in ipairs(live.echoes) do
                local stacks = tonumber(echo.stacks or echo.count) or 1
                echoes[#echoes + 1] = {
                    spellId=echo.spellId or echo.id, quality=echo.quality,
                    stacks=stacks, locked=echo.locked and true or false,
                }
                total = total + stacks
            end
            local serverTitle = live.name and live.name ~= "" and live.name
                or "Saved Build " .. slot
            local old = LoadBuild(id) or legacyId ~= id and LoadBuild(legacyId)
            local title = old and old.userTitle and old.userTitle ~= ""
                and old.userTitle or serverTitle
            local linked = Adapter.GetLoadoutWishlist
                and Adapter.GetLoadoutWishlist(slot) or nil
            local destinationName = linked and linked.name or nil
            local destinationEchoes = linked and linked.echoes or nil
            local progress, destinationTotal = EchoProgress(echoes, destinationEchoes)
            local related = FindRelatedBuild(serverTitle, echoes, old, me, summaries)
            local currentClass = select(2, UnitClass and UnitClass("player"))
            local class = related and related.class or live.class or currentClass
                or InferBuildClass(echoes) or "UNKNOWN"
            local recordBuildId = related and related.id or nil
            local signatureParts = { serverTitle, tostring(class),
                tostring(recordBuildId or ""), tostring(total),
                tostring(destinationName or ""), tostring(progress),
                tostring(destinationTotal) }
            for _, echo in ipairs(echoes) do
                signatureParts[#signatureParts + 1] = table.concat({
                    tostring(echo.spellId or 0), tostring(echo.quality or ""),
                    tostring(echo.stacks or 1),
                }, ":")
            end
            local signature = table.concat(signatureParts, "|")
            if not old or old._savedSignature ~= signature then
                local stamp = NextStamp(old and old.lastModified or 0)
                local record = {
                    id=id, title=title, serverTitle=serverTitle,
                    userTitle=old and old.userTitle or nil,
                    description=old and old.userDescription
                        or destinationName and string.format(
                            "Destination wishlist: %s — in progress (%d/%d).",
                            destinationName, progress, destinationTotal)
                        or "No destination wishlist associated yet.",
                    userDescription=old and old.userDescription or nil,
                    publishedBuildId=old and old.publishedBuildId or nil,
                    lastPublishedAt=old and old.lastPublishedAt or nil,
                    author=me, ownerKey=currentOwner, class=class, echoes=echoes,
                    postedAt=old and old.postedAt or stamp, lastModified=stamp,
                    isMine=true, importedSavedBuild=true, serverSlot=slot,
                    recordBuildId=recordBuildId,
                    destinationWishlistName=destinationName,
                    destinationWishlistSlot=linked and linked.slot or nil,
                    destinationProgress=progress, destinationTotal=destinationTotal,
                    activeServerBuild=slots.activeSlot == slot,
                    _savedSignature=signature,
                }
                if RefreshIdentity(record) then
                    SaveBuild(record)
                    if legacyId ~= id and LoadBuild(legacyId) then RemoveOverlay(legacyId) end
                    changed = changed + 1
                end
            elseif old then
                old.activeServerBuild = slots.activeSlot == slot
                old.serverSlot, old.serverTitle, old.class = slot, serverTitle, class
                old.ownerKey = old.ownerKey or currentOwner
                old.recordBuildId = recordBuildId
                if not old.userTitle or old.userTitle == "" then old.title = serverTitle end
                old.importedSavedBuild, old.isMine, old.id = true, true, id
                old.destinationWishlistName = destinationName
                old.destinationWishlistSlot = linked and linked.slot or nil
                old.destinationProgress, old.destinationTotal = progress, destinationTotal
                SaveBuild(old)
                if legacyId ~= id and LoadBuild(legacyId) then RemoveOverlay(legacyId) end
            end
        end
    end
    for id, build in pairs(summaries) do
        if build and build.importedSavedBuild and IsOwnBuild(build) and not seen[id] then
            RemoveOverlay(id)
            changed = changed + 1
        end
    end
    stats.imports = stats.imports + 1
    return changed
end

local function EnsureDpsBuild(echoes, category, record)
    local capture = Nexus.DpsCapture
    if not (capture and capture.GetEchoKey) then return nil end
    local key = capture.GetEchoKey(echoes)
    if not key then return nil end
    local explicitClass = NormalizeClass(record and (record.class or record.k))
    local player = tostring(record and record.player
        or UnitName and UnitName("player") or "Unknown")
    local recordOwner = record and record.ownerKey
    local explicitId = record and (record.buildId or record.b)
    if type(explicitId) ~= "string" or explicitId == "" then explicitId = nil end
    local explicitExisting = explicitId and LoadBuild(explicitId) or nil
    if explicitExisting then
        local existingKey = explicitExisting.fingerprint
            or capture.GetEchoKey(explicitExisting.echoes)
        if existingKey and existingKey ~= key then return nil end
        if recordOwner and explicitExisting.ownerKey
            and tostring(recordOwner):lower()
                ~= tostring(explicitExisting.ownerKey):lower() then return nil end
        if type(explicitExisting.echoes) ~= "table" or #explicitExisting.echoes == 0 then
            local copied = {}
            for _, echo in ipairs(echoes or {}) do
                copied[#copied + 1] = {
                    spellId=echo.spellId or echo.id,
                    stacks=echo.count or echo.stacks or 1,
                }
            end
            local refreshed = { echoes=copied }
            if not RefreshIdentity(refreshed) then return nil end
            explicitExisting.echoes = copied
            explicitExisting.fingerprint = refreshed.fingerprint
            explicitExisting.fingerprintHash = refreshed.fingerprintHash
            explicitExisting.echoCount = refreshed.echoCount
            explicitExisting.loadoutAvailable = #copied > 0
            explicitExisting.needsFullBuild, explicitExisting.tombstoned = false, nil
            explicitExisting.autoDps = true
            explicitExisting.author = explicitExisting.author or player
            explicitExisting.ownerKey = explicitExisting.ownerKey or recordOwner
            explicitExisting.class = explicitClass or explicitExisting.class
                or InferBuildClass(copied) or "UNKNOWN"
            if explicitExisting.title == "Loadout pending" then
                explicitExisting.title = (CLASS_LABEL[explicitExisting.class]
                    or explicitExisting.class) .. " Record Loadout"
            end
            explicitExisting.description = "Automatically completed from a compatible DPS record. Exact Echo IDs and stack quantities are preserved for copying and comparison."
            explicitExisting.lastModified = NextStamp(
                explicitExisting.lastModified or explicitExisting.postedAt or 0)
            SaveBuild(explicitExisting)
            Broadcast(explicitExisting)
        end
        return explicitId, explicitExisting
    end
    local ownAutoId, ownAutoBuild, manualId, manualBuild
    if not explicitId then
        for id, build in pairs(Store()) do
            if capture.GetEchoKey(build.echoes) == key then
                if not build.autoDps then
                    if IsOwnBuild(build) then return id, build end
                    manualId, manualBuild = manualId or id, manualBuild or build
                else
                    local sameOwner = recordOwner and build.ownerKey
                        and tostring(recordOwner):lower() == tostring(build.ownerKey):lower()
                    local sameLegacyAuthor = not recordOwner
                        and tostring(build.author or ""):lower() == player:lower()
                    if sameOwner or sameLegacyAuthor then
                        ownAutoId, ownAutoBuild = id, build
                    end
                end
            end
        end
    end
    if manualId then return manualId, manualBuild end
    local copied, seen = {}, {}
    for _, echo in ipairs(echoes or {}) do
        local id = tonumber(echo and (echo.spellId or echo.id))
        copied[#copied + 1] = {
            spellId=id, quality=echo.quality, stacks=echo.count or echo.stacks or 1,
        }
        if id then seen[id] = true end
    end
    if record and type(record.lockedEchoes) == "table" then
        for _, echo in ipairs(record.lockedEchoes) do
            local id = tonumber(echo and echo.spellId)
            if id and not seen[id] then
                copied[#copied + 1] = {
                    spellId=id, stacks=echo.count or echo.stacks or 1, locked=true,
                }
                seen[id] = true
            end
        end
    end
    local me = tostring((UnitName and UnitName("player")) or "")
    local playerIsLocal = player:lower() == me:lower()
    local localClass
    if playerIsLocal and UnitClass then localClass = NormalizeClass(select(2, UnitClass("player"))) end
    local class = explicitClass or InferBuildClass(copied) or localClass or "UNKNOWN"
    if ownAutoId then
        if explicitClass and ownAutoBuild.class ~= explicitClass then
            ownAutoBuild.class = explicitClass
            ownAutoBuild.title = (CLASS_LABEL[explicitClass] or explicitClass) .. " Record Loadout"
            ownAutoBuild.lastModified = NextStamp(
                ownAutoBuild.lastModified or ownAutoBuild.postedAt)
            SaveBuild(ownAutoBuild)
            Broadcast(ownAutoBuild)
        end
        return ownAutoId, ownAutoBuild
    end
    local stamp = NextStamp(0)
    local ownerKey = recordOwner or playerIsLocal and CurrentOwnerKey() or nil
    local identity = ownerKey or player:lower()
    local id = explicitId or "dps-" .. FingerprintHash(key) .. "-"
        .. FingerprintHash(identity):sub(1, 8)
    local build = {
        id=id, title=(CLASS_LABEL[class] or class) .. " Record Loadout",
        description="Automatically created from a verified DPS record. Exact Echo IDs and stack quantities are preserved for copying and comparison.",
        author=player, ownerKey=ownerKey, class=class, echoes=copied,
        postedAt=stamp, lastModified=stamp,
        isMine=ownerKey and ownerKey == CurrentOwnerKey() or false,
        autoDps=true, fingerprint=key, loadoutAvailable=true, needsFullBuild=false,
    }
    if not RefreshIdentity(build) then return nil end
    SaveBuild(build)
    Broadcast(build)
    return id, build
end

local function PostCurrentWishlist(title, description, selectedWishlist, selectedClass)
    if not (Adapter and Adapter.Wishlist) then return false, "adapter not ready" end
    local wishlist = selectedWishlist
    local sourceEchoes = WishlistEchoes(wishlist)
    if (not sourceEchoes or #sourceEchoes == 0) and wishlist and wishlist.slot
        and Adapter.Slots then
        local slots = Adapter.Slots()
        local live = slots and slots.bySlot and slots.bySlot[wishlist.slot]
        if live and type(live.echoes) == "table" and #live.echoes > 0 then
            wishlist = {
                slot=wishlist.slot, name=live.name or wishlist.name,
                count=#live.echoes, echoes=live.echoes,
                active=slots.activeSlot == wishlist.slot,
            }
            sourceEchoes = wishlist.echoes
        end
    end
    if not wishlist then wishlist = Adapter.Wishlist() end
    sourceEchoes = sourceEchoes or WishlistEchoes(wishlist)
    if not wishlist or not sourceEchoes or #sourceEchoes == 0 then
        return false, "no wishlist selected to post"
    end
    title = tostring(title or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if title == "" then title = wishlist.name ~= "" and wishlist.name or "Untitled" end
    description = tostring(description or "")
    if #title > 80 then return false, "title is too long" end
    if #description > 2000 then return false, "description is too long" end
    local echoes = {}
    for _, echo in ipairs(sourceEchoes) do
        echoes[#echoes + 1] = {
            spellId=echo.spellId, quality=echo.quality, stacks=echo.stacks or 1,
        }
    end
    local stamp = NextStamp(0)
    local id = string.format("mine-%d-%d", stamp, math.random(100000, 999999))
    local record = {
        id=id, title=title, description=description,
        author=UnitName and UnitName("player") or "You",
        ownerKey=CurrentOwnerKey(),
        class=NormalizeClass(selectedClass) or InferBuildClass(echoes)
            or NormalizeClass(wishlist.class),
        echoes=echoes, postedAt=stamp, lastModified=stamp, isMine=true,
    }
    local ok, err = RefreshIdentity(record)
    if not ok then return false, err end
    SaveBuild(record)
    Broadcast(record)
    local capture = Nexus.DpsCapture
    if capture and capture.BroadcastBestForBuild then
        pcall(capture.BroadcastBestForBuild, id)
    end
    return true, id
end

local function HasLeaderboardRecord(build)
    if not build then return false end
    if build.autoDps then return true end
    local capture = Nexus.DpsCapture
    if not (capture and capture.GetLeaderboard) then return false end
    return #(capture.GetLeaderboard(build.id, "dummy") or {}) > 0
        or #(capture.GetLeaderboard(build.id, "lk") or {}) > 0
end

local function PublishImportedBuild(id)
    local source = LoadBuild(id)
    if not source or not source.importedSavedBuild then return false, "not a saved loadout" end
    if not IsOwnBuild(source) then return false, "not your build" end
    if type(source.echoes) ~= "table" or #source.echoes == 0 then
        return false, "that build has no echoes"
    end
    local publishedId = source.publishedBuildId or "published-" .. tostring(id)
    local old = LoadBuild(publishedId)
    local stamp = NextStamp(old and old.lastModified or 0)
    local echoes = {}
    for _, echo in ipairs(source.echoes) do
        echoes[#echoes + 1] = {
            spellId=echo.spellId, quality=echo.quality,
            stacks=echo.stacks or echo.count or 1,
            locked=echo.locked and true or false,
        }
    end
    local record = {
        id=publishedId, title=source.title or "Saved Build",
        description=source.userDescription or source.description or "",
        author=UnitName and UnitName("player") or "You",
        ownerKey=CurrentOwnerKey(),
        class=NormalizeClass(source.class) or InferBuildClass(echoes), echoes=echoes,
        postedAt=old and old.postedAt or stamp, lastModified=stamp, isMine=true,
        sourceSavedBuildId=id, link=old and old.link or nil,
    }
    local ok, err = RefreshIdentity(record)
    if not ok then return false, err end
    SaveBuild(record)
    source.publishedBuildId, source.lastPublishedAt = publishedId, stamp
    SaveBuild(source)
    Broadcast(record)
    local capture = Nexus.DpsCapture
    if capture and capture.BroadcastBestForBuild then
        pcall(capture.BroadcastBestForBuild, publishedId)
    end
    return true, publishedId
end

local function EditBuild(id, title, description, discordLink)
    local build = LoadBuild(id)
    if not build then return false, "not found" end
    if not IsOwnBuild(build) then return false, "not your build" end
    local nextTitle = tostring(title or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local nextDescription = description ~= nil and tostring(description)
        or tostring(build.description or "")
    if nextTitle == "" then nextTitle = tostring(build.title or "Untitled") end
    if #nextTitle > 80 then return false, "title is too long" end
    if #nextDescription > 2000 then return false, "description is too long" end
    local nextLink = build.link
    if discordLink ~= nil then
        local raw = tostring(discordLink or "")
        local normalized, err = NormalizeDiscordBuildLink(raw)
        if raw:match("^%s*$") then nextLink = nil
        elseif not normalized then return false, err or "invalid Discord build link"
        else nextLink = normalized end
    end
    build.title, build.description, build.link = nextTitle, nextDescription, nextLink
    if build.importedSavedBuild then
        build.userTitle, build.userDescription = nextTitle, nextDescription
    end
    build.lastModified = NextStamp(build.lastModified or build.postedAt)
    SaveBuild(build)
    if not build.importedSavedBuild then Broadcast(build) end
    return true
end

local function UpdateFromWishlist(id)
    local build = LoadBuild(id)
    if not build then return false, "not found" end
    if not IsOwnBuild(build) then return false, "not your build" end
    if build.importedSavedBuild then
        return false, "saved loadouts update from the server; edit the server loadout itself to change its Echoes"
    end
    if HasLeaderboardRecord(build) then
        return false, "this exact loadout has a leaderboard record and is locked; post a new build to change its Echoes"
    end
    if not (Adapter and Adapter.Wishlist) then return false, "adapter not ready" end
    local wishlist = Adapter.Wishlist()
    if not wishlist or not wishlist.entries or #wishlist.entries == 0 then
        return false, "no active wishlist"
    end
    local echoes = {}
    for _, echo in ipairs(wishlist.entries) do
        echoes[#echoes + 1] = {
            spellId=echo.spellId, quality=echo.quality, stacks=echo.stacks or 1,
        }
    end
    local candidate = { echoes=echoes }
    local ok, err = RefreshIdentity(candidate)
    if not ok then return false, err end
    build.echoes = echoes
    build.fingerprint, build.fingerprintHash = candidate.fingerprint, candidate.fingerprintHash
    build.echoCount, build.loadoutAvailable = candidate.echoCount, candidate.loadoutAvailable
    build.needsFullBuild = candidate.needsFullBuild
    build.lastModified = NextStamp(build.lastModified or build.postedAt)
    SaveBuild(build)
    Broadcast(build)
    local capture = Nexus.DpsCapture
    if capture and capture.BroadcastBestForBuild then
        pcall(capture.BroadcastBestForBuild, id)
    end
    return true, #echoes
end

local function DeleteBuild(id)
    local build = LoadBuild(id)
    if not build then return false, "not found" end
    local admin = tostring(UnitName and UnitName("player") or ""):lower() == "explore"
    if not IsOwnBuild(build) and not admin then return false, "not your build" end
    if build.importedSavedBuild then
        return false, "server Saved Builds cannot be deleted here"
    end
    if IsOwnBuild(build) and Nexus.Sync then pcall(Nexus.Sync.BroadcastDelete, build) end
    if LoadBuild(id) then
        SetTombstone(id, {
            stamp=time and time() or 0, author=tostring(build.author or ""),
            localOnly=not IsOwnBuild(build) or nil,
        })
    end
    RemoveOverlay(id)
    return true
end

local commands = {
    ["ensure-dps"]=EnsureDpsBuild,
    post=PostCurrentWishlist,
    publish=PublishImportedBuild,
    edit=EditBuild,
    update=UpdateFromWishlist,
    delete=DeleteBuild,
}

function Workspace.Init(adapter)
    Adapter = adapter or Adapter
    return Workspace
end

function Workspace.Owns(idOrBuild)
    return IsOwnBuild(type(idOrBuild) == "table" and idOrBuild or LoadBuild(idOrBuild))
end

function Workspace.AccountOwns(idOrBuild)
    return IsAccountBuild(type(idOrBuild) == "table" and idOrBuild or LoadBuild(idOrBuild))
end

function Workspace.Import(force)
    return ImportSavedLoadouts(force)
end

function Workspace.Execute(command, ...)
    local handler = commands[command]
    if not handler then return false, "unknown account-build command" end
    stats.mutations = stats.mutations + 1
    return handler(...)
end

function Workspace.RefreshIdentity(build)
    return RefreshIdentity(build)
end

function Workspace.InferClass(echoes)
    return InferBuildClass(echoes)
end

function Workspace.Stats()
    return {
        relatedScans=stats.relatedScans,
        relatedHydrations=stats.relatedHydrations,
        imports=stats.imports,
        mutations=stats.mutations,
    }
end
