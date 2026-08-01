-- GroupBuilder :: Leveling.lua
-- Detects a group member reaching max level and reforms the group: issues the
-- (configurable) scaling command, kicks everyone, and re-invites all but the
-- player who just dinged.

local addonName, GB = ...

-- ---------------------------------------------------------------------------
--  Tiny delay scheduler (3.3.5 has no C_Timer). GB:After(seconds, fn)
-- ---------------------------------------------------------------------------
local scheduled = {}
local schedFrame = CreateFrame("Frame")
schedFrame:Hide()
schedFrame:SetScript("OnUpdate", function(self, elapsed)
    local now = GetTime()
    for i = #scheduled, 1, -1 do
        local task = scheduled[i]
        if now >= task.at then
            table.remove(scheduled, i)
            local ok, err = pcall(task.fn)
            if not ok then GB:Print("|cffff5555timer error:|r", err) end
        end
    end
    if #scheduled == 0 then self:Hide() end
end)
function GB:After(sec, fn)
    scheduled[#scheduled + 1] = { at = GetTime() + sec, fn = fn }
    schedFrame:Show()
end

-- ---------------------------------------------------------------------------
--  Ding detection
-- ---------------------------------------------------------------------------
local levelSeen = {}       -- [name] = last observed level
GB._reforming = false

local function amLeader()
    if GetNumRaidMembers() > 0 then
        return IsRaidLeader() and true or false
    end
    return IsPartyLeader() and true or false
end

-- Consider a member's level; fire a reform if they just crossed maxLevel.
local function considerLevel(name, level)
    if not name or not level or level <= 0 then return end
    name = GB:NormName(name)
    if name == GB:NormName(UnitName("player")) then
        levelSeen[name] = level
        return -- never reform on our own ding (we can't kick ourselves)
    end
    local prev = levelSeen[name]
    levelSeen[name] = level
    local maxLevel = (GB.db and GB.db.leveling.maxLevel) or 60
    if prev and prev < maxLevel and level >= maxLevel then
        GB:OnMemberDinged(name)
    end
end

-- Scan the whole group's levels (backup for missed UNIT_LEVEL events).
local function scanLevels()
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local n, _, _, lvl = GetRaidRosterInfo(i)
            considerLevel(n, lvl)
        end
    else
        considerLevel(UnitName("player"), UnitLevel("player"))
        for i = 1, GetNumPartyMembers() do
            local u = "party" .. i
            considerLevel(UnitName(u), UnitLevel(u))
        end
    end
end

GB:On("UNIT_LEVEL", function(_, unit)
    if not unit then return end
    if unit == "player" or unit:match("^party%d") or unit:match("^raid%d") then
        considerLevel(UnitName(unit), UnitLevel(unit))
    end
end)

-- periodic backup scan
local scanFrame = CreateFrame("Frame")
local acc = 0
scanFrame:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc >= 3 then acc = 0; scanLevels() end
end)

-- Prime levels so pre-existing 60s never trigger a reform.
GB:On("PLAYER_ENTERING_WORLD", function() scanLevels() end)
GB:On("PARTY_MEMBERS_CHANGED", function() scanLevels() end)
GB:On("RAID_ROSTER_UPDATE", function() scanLevels() end)

-- ---------------------------------------------------------------------------
--  Repeating "scaling active" raid warning
-- ---------------------------------------------------------------------------
local MAX_SCALING_TICKS = 40   -- safety cap (~2 min) so it can't spam forever

-- True while a non-self group member is at/above maxLevel (mobs are scaled).
local function scalingStillActive()
    local maxLevel = GB.db.leveling.maxLevel or 60
    local me = GB:NormName(UnitName("player"))
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local n, _, _, lvl = GetRaidRosterInfo(i)
            if n and GB:NormName(n) ~= me and (lvl or 0) >= maxLevel then return true end
        end
    else
        for i = 1, GetNumPartyMembers() do
            if (UnitLevel("party" .. i) or 0) >= maxLevel then return true end
        end
    end
    return false
end

function GB:ScalingTick()
    if not self._scalingAlertOn then return end
    local maxLevel = self.db.leveling.maxLevel or 60
    self._scalingTicks = (self._scalingTicks or 0) + 1
    if scalingStillActive() and self._scalingTicks <= MAX_SCALING_TICKS then
        SendChatMessage(("Level %d scaling ACTIVE — hold pulls, reforming!"):format(maxLevel),
            GetNumRaidMembers() > 0 and "RAID_WARNING" or "PARTY")
        self:After(3, function() GB:ScalingTick() end)
    else
        self._scalingAlertOn = false
        if self._scalingTicks > 1 then   -- we actually warned at least once
            SendChatMessage(("Level %d scaling cleared — good to go!"):format(maxLevel),
                GetNumRaidMembers() > 0 and "RAID_WARNING" or "PARTY")
        end
    end
end

-- Begin the repeating warning (first one after 3s, so the reform notice goes first).
function GB:StartScalingAlert()
    if self._scalingAlertOn then return end
    self._scalingAlertOn = true
    self._scalingTicks = 0
    self:After(3, function() GB:ScalingTick() end)
end

-- ---------------------------------------------------------------------------
--  Reform
-- ---------------------------------------------------------------------------
function GB:OnMemberDinged(dinger)
    if not (self.db and self.db.leveling.enabled) then return end
    -- Only the leader handles the ding (only they can reform); if you're not the
    -- leader, stay quiet — whoever leads the group takes care of it.
    if not amLeader() then return end
    self:Print("|cffffcc00" .. dinger .. " reached max level!|r")
    self:StartScalingAlert()   -- keep warning /rw every 3s until the 60 is gone
    if not self.db.active then
        self:Print("(master switch off — not reforming. /gb on to enable, or /gb reform to do it now.)")
        return
    end
    if not self.db.leveling.autoReform then
        self:Print("(auto-reform disabled — /gb reform to do it manually.)")
        return
    end
    self:ReformGroup(dinger)
end

-- Reform: raid-warn, whisper everyone "pst reform for a reinvite", store the
-- reform list, and kick everyone. It does NOT re-invite — you often can't invite
-- until you leave the Manastorm, so the re-invites are sent later by ReinviteGroup
-- (auto on leaving the instance, via /gb reinvite, or when a member pst's 'reform').
function GB:ReformGroup(dinger)
    if not amLeader() then
        self:Print("|cffff5555can't reform:|r you must be the party/raid leader.")
        return
    end
    dinger = dinger and self:NormName(dinger) or nil
    local me = self:NormName(UnitName("player"))

    -- Build the reform list (everyone present except me and the dinger), keeping
    -- each one's known role so re-invites skip the recruit questions.
    self:RefreshRoster()
    self._reformList = {}
    local keepers = {}
    for _, m in ipairs(self.roster) do
        if m.name ~= me and m.name ~= dinger then
            self._reformList[m.name] = (self.claims[m.name] and self.claims[m.name].role) or true
            keepers[#keepers + 1] = m.name
        end
    end
    self._lastDinger = dinger   -- so the "reform" failsafe won't re-invite them

    -- 1) Raid warning FIRST, while everyone is still grouped to see it.
    if self.db.leveling.announceReform then
        local msg = dinger
            and ("Level %d scaling detected — reforming to reset it! Kicking now; pst me 'reform' for a re-invite."):format(
                self.db.leveling.maxLevel)
            or  "Reforming group — kicking now; pst me 'reform' for a re-invite."
        SendChatMessage(msg, GetNumRaidMembers() > 0 and "RAID_WARNING" or "PARTY")
    end

    -- 2) Whisper each member as a backup in case they miss the raid warning.
    for _, name in ipairs(keepers) do
        self:Reply(name, self:Tag() .. ": reforming to reset scaling — pst me 'reform' for a re-invite!")
    end

    -- 3) Kick everyone. Primary (raid): uninvite every other raid member then
    --    LeaveParty() to fully dissolve. Fallback: uninvite by name, dinger first.
    local usedFast = false
    if GetNumRaidMembers() > 0 and LeaveParty then
        local n = (GetNumGroupMembers and GetNumGroupMembers()) or GetNumRaidMembers()
        for i = 1, n do
            local u = "raid" .. i
            local uname = UnitName(u)
            if uname and GB:NormName(uname) ~= me then UninviteUnit(u) end
        end
        LeaveParty()
        usedFast = true
    end
    if not usedFast then
        if dinger then UninviteUnit(dinger) end
        for _, m in ipairs(self.roster) do
            if m.name ~= me and m.name ~= dinger then UninviteUnit(m.name) end
        end
    end

    self._reformPending = true   -- auto-reinvite once we leave the instance
    self:Print(("Kicked & whispered %d member(s). Leave the Manastorm and I'll auto-reinvite (or /gb reinvite)."):format(#keepers))
    self:RefreshRoster(); GB:UpdateAnnounce(); GB:RefreshUI()
end

-- Send invites to everyone on the reform list who isn't already back in the group.
function GB:ReinviteGroup()
    if not (self._reformList and next(self._reformList)) then
        self:Print("no reform list to re-invite.")
        return
    end
    self:RefreshRoster()
    local n = 0
    for name in pairs(self._reformList) do
        if not self.rosterByName[name] then InviteUnit(name); n = n + 1 end
    end
    self:Print(("sent %d re-invite(s)."):format(n))
end

-- Leaving the Manastorm changes zone. On Ascension that fires
-- ZONE_CHANGED_NEW_AREA (there's no PLAYER_ENTERING_WORLD for the phased area),
-- so watch both — if a reform is pending, that's our cue to send re-invites.
local function reformLeaveCheck()
    if GB._reformPending then
        GB._reformPending = false
        GB:After(2, function() GB:ReinviteGroup() end)
    end
end
GB:On("ZONE_CHANGED_NEW_AREA", reformLeaveCheck)
GB:On("PLAYER_ENTERING_WORLD", reformLeaveCheck)
