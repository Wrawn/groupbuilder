-- GroupBuilder :: GroupSort.lua
-- /gb sort (and the status "Sort Groups" button) — arrange raid subgroups so each
-- group of 5 has a healer and an aura, with tanks in group 1, using the roles/auras
-- we already track. Approach adapted from Bokuden's MS-Leveling.

local addonName, GB = ...

local sortRunning = false
local pendingSort = false
local tickFrame

local function short(n) return n and n:gsub("%-.*", "") or n end

-- role/aura for a name from our tracked claims (+ your own slot).
local function infoFor(name)
    if name == GB:MyName() then
        local s = GB:GetSelfClaim()
        if s then return { role = s.role, aura = s.aura } end
    end
    local c = GB.claims[name] or (GB.cdb and GB.cdb.claims and GB.cdb.claims[name])
    if c then return { role = c.role, aura = c.aura } end
    return {}
end

-- Decide each member's target subgroup (pure — performs no moves). Returns
-- groupOf[name]=subgroup, plus roster / info / groups / currentGroup for the caller.
function GB:PlanGroups()
    local roster, currentGroup, info = {}, {}, {}
    local n = GetNumRaidMembers()
    for i = 1, n do
        local nm, _, sg = GetRaidRosterInfo(i)
        if nm then nm = short(nm); roster[#roster + 1] = nm; currentGroup[nm] = sg or 1; info[nm] = infoFor(nm) end
    end
    local groups = math.max(1, math.ceil(n / 5))
    local groupOf, countOf = {}, {}
    for g = 1, groups do countOf[g] = 0 end
    local function addToGroup(name, g)
        if not groupOf[name] and countOf[g] < 5 then groupOf[name] = g; countOf[g] = countOf[g] + 1 end
    end
    local function hasIn(g, pred)
        for _, nm in ipairs(roster) do if groupOf[nm] == g and pred(info[nm]) then return true end end
        return false
    end
    local function healIn(g) return hasIn(g, function(i) return i and i.role == "healer" end) end
    local function auraIn(g) return hasIn(g, function(i) return i and i.aura end) end

    -- tanks -> group 1
    for _, nm in ipairs(roster) do if info[nm].role == "tank" then addToGroup(nm, 1) end end
    -- healers: spread one per group, then fill
    for _, nm in ipairs(roster) do
        if not groupOf[nm] and info[nm].role == "healer" then
            local placed = false
            for g = 1, groups do if not placed and not healIn(g) and countOf[g] < 5 then addToGroup(nm, g); placed = true end end
            if not placed then for g = 1, groups do if not placed and countOf[g] < 5 then addToGroup(nm, g); placed = true end end end
        end
    end
    -- auras: spread one per group, then fill
    for _, nm in ipairs(roster) do
        if not groupOf[nm] and info[nm].aura then
            local placed = false
            for g = 1, groups do if not placed and not auraIn(g) and countOf[g] < 5 then addToGroup(nm, g); placed = true end end
            if not placed then for g = 1, groups do if not placed and countOf[g] < 5 then addToGroup(nm, g); placed = true end end end
        end
    end
    -- everyone else fills the gaps
    for _, nm in ipairs(roster) do
        if not groupOf[nm] then for g = 1, groups do addToGroup(nm, g); if groupOf[nm] then break end end end
    end
    return groupOf, roster, info, groups, currentGroup
end

function GB:SortGroups()
    if GetNumRaidMembers() == 0 then self:Print("you must be in a raid to sort groups."); return end
    if not (IsRaidLeader() or (IsRaidOfficer and IsRaidOfficer())) then
        self:Print("you must be raid leader or assist to sort groups."); return
    end
    if InCombatLockdown and InCombatLockdown() then
        if not pendingSort then pendingSort = true; self:Print("in combat — I'll sort the groups the moment combat ends.") end
        return
    end
    if sortRunning then self:Print("a sort is already running."); return end
    pendingSort = false
    sortRunning = true

    local groupOf, roster, info, groups, currentGroup = self:PlanGroups()

    -- live-roster helpers (subgroup changes need a server round-trip, so re-read).
    local function liveGroup(name)
        for i = 1, GetNumRaidMembers() do local nm, _, sg = GetRaidRosterInfo(i); if nm and short(nm) == name then return sg or 1 end end
        return 1
    end
    local function getIndex(name)
        for i = 1, GetNumRaidMembers() do local nm = GetRaidRosterInfo(i); if nm and short(nm) == name then return i end end
    end
    local function countIn(g) local c = 0 for _, nm in ipairs(roster) do if liveGroup(nm) == g then c = c + 1 end end return c end
    local function findHolding() for g = groups + 1, 8 do if countIn(g) < 5 then return g end end end
    local function moveTo(name, g) local idx = getIndex(name); if not idx then return false end pcall(SetRaidSubgroup, idx, g); return liveGroup(name) == g end
    local function trySwap(nm, t)
        local i1 = getIndex(nm); if not i1 then return false end
        for _, m in ipairs(roster) do
            if groupOf[m] ~= t and liveGroup(m) == t then
                local i2 = getIndex(m)
                if i2 then pcall(SwapRaidSubgroup, i1, i2); return liveGroup(nm) == t end
            end
        end
        return false
    end
    local function tryPlace(nm)
        local t = groupOf[nm]
        if not t or liveGroup(nm) == t or not getIndex(nm) then return true end
        if countIn(t) < 5 then moveTo(nm, t); return liveGroup(nm) == t end
        if trySwap(nm, t) then return true end
        local h = findHolding()
        if h then
            for _, m in ipairs(roster) do if groupOf[m] ~= t and liveGroup(m) == t then moveTo(m, h); break end end
            if countIn(t) < 5 then moveTo(nm, t) end
        end
        return liveGroup(nm) == t
    end

    local function announce()
        local auraParts, healParts, tanks = {}, {}, {}
        for g = 1, groups do
            local an, hn = {}, {}
            for _, nm in ipairs(roster) do
                if groupOf[nm] == g then
                    if info[nm].role == "tank" then tanks[#tanks + 1] = nm end
                    if info[nm].role == "healer" then hn[#hn + 1] = nm end
                    if info[nm].aura then an[#an + 1] = nm end
                end
            end
            if #hn > 0 then healParts[#healParts + 1] = ("G%d heal: %s"):format(g, table.concat(hn, ", ")) end
            if #an > 0 then auraParts[#auraParts + 1] = ("G%d aura: %s"):format(g, table.concat(an, ", ")) end
        end
        if #healParts > 0 then SendChatMessage(GB:Tag() .. ": " .. table.concat(healParts, "; "), "RAID") end
        if #auraParts > 0 then SendChatMessage(GB:Tag() .. ": " .. table.concat(auraParts, "; "), "RAID") end
        if #tanks > 0 then SendChatMessage(GB:Tag() .. ": tanks: " .. table.concat(tanks, ", "), "RAID") end
    end

    local finished = false
    local function finish()
        if finished then return end
        finished = true; sortRunning = false
        if tickFrame then tickFrame:SetScript("OnUpdate", nil) end
        local moved, failed = 0, 0
        for _, nm in ipairs(roster) do
            if groupOf[nm] then
                if liveGroup(nm) == groupOf[nm] then if currentGroup[nm] ~= groupOf[nm] then moved = moved + 1 end
                else failed = failed + 1 end
            end
        end
        if self and self.MarkTanks then self:MarkTanks() end
        announce()
        GB:Print(("groups sorted: %d moved, %d couldn't be placed."):format(moved, failed))
    end

    local pending = {}
    for _, nm in ipairs(roster) do if groupOf[nm] and liveGroup(nm) ~= groupOf[nm] then pending[#pending + 1] = nm end end

    local ticks, cursor = 0, 0
    local function tick()
        ticks = ticks + 1
        if ticks > 60 then finish(); return end
        local attempts, still = 0, {}
        for i = 1, #pending do
            local nm = pending[((cursor + i - 1) % #pending) + 1]
            if liveGroup(nm) == groupOf[nm] then
            elseif attempts < 2 then attempts = attempts + 1; if not tryPlace(nm) then still[#still + 1] = nm end
            else still[#still + 1] = nm end
        end
        cursor = (cursor + attempts) % math.max(1, #pending)
        pending = still
        if #pending == 0 then finish() end
    end

    if #pending == 0 then
        finish()
    else
        if not tickFrame then tickFrame = CreateFrame("Frame") end
        local elapsed = 0
        tickFrame:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + (dt or 0)
            if elapsed >= 0.15 then elapsed = 0; tick() end
        end)
    end
end

-- If a sort was requested in combat, run it when combat ends.
GB:On("PLAYER_REGEN_ENABLED", function()
    if pendingSort then pendingSort = false; GB:SortGroups() end
end)
