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

-- The level at which mobs actually scale up (game cap). The Max level box is the
-- (optionally lower) autokick threshold.
local SCALE_LEVEL = 60

-- Consider a member's level.
--  * Crossing SCALE_LEVEL (60) always means the group scaled -> full reform.
--  * If the Max level box is below 60, a non-whitelisted member who reaches it is
--    single-kicked (removed before they can scale the group) — no reform needed.
local function considerLevel(name, level)
    if not name or not level or level <= 0 then return end
    name = GB:NormName(name)
    if name == GB:NormName(UnitName("player")) then
        levelSeen[name] = level
        return -- never act on our own ding (we can't kick ourselves)
    end
    local prev = levelSeen[name]
    levelSeen[name] = level
    local maxLevel = (GB.db and GB.db.leveling.maxLevel) or SCALE_LEVEL

    -- hit 60 -> full reform (even whitelisted players)
    if prev and prev < SCALE_LEVEL and level >= SCALE_LEVEL then
        GB:OnMemberDinged(name)
        return
    end

    -- sub-60 autokick: any non-whitelisted member at/above the threshold (but
    -- still under 60) is removed. Level-based (also catches high-level joiners).
    if maxLevel < SCALE_LEVEL and level >= maxLevel and level < SCALE_LEVEL then
        if not GB:IsWhitelisted(name) then GB:AutoKick(name) end
    end
end

-- Best level reading we can get: GetRaidRosterInfo is 0 for distant members,
-- UnitLevel is 0 for members out of range — take whichever is higher.
local function bestLevel(unit, rosterLevel)
    return math.max(rosterLevel or 0, (unit and UnitLevel(unit)) or 0)
end

-- Scan the whole group's levels (backup for missed UNIT_LEVEL events).
local function scanLevels()
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local n, _, _, lvl = GetRaidRosterInfo(i)
            considerLevel(n, bestLevel("raid" .. i, lvl))
        end
    else
        considerLevel(UnitName("player"), UnitLevel("player"))
        for i = 1, GetNumPartyMembers() do
            local u = "party" .. i
            considerLevel(UnitName(u), UnitLevel(u))
        end
    end
end

-- Diagnostic: /gb levels — shows what the addon reads, so autokick issues are
-- easy to pin down (level 0 = the client can't see that member's level).
function GB:DebugLevels()
    local maxLevel = self.db.leveling.maxLevel or 60
    self:Print(("Kick at level: |cff33ff99%d|r  |  Anti-scaling enabled: %s  |  you lead: %s"):format(
        maxLevel, tostring(self.db.leveling.enabled), tostring(amLeader())))
    if maxLevel >= 60 then self:Print("  (set 'Kick at level' below 60 to enable the early autokick)") end
    local me = self:NormName(UnitName("player"))
    local function line(name, unit, rosterLvl)
        if not name then return end
        local n = self:NormName(name)
        local lvl = bestLevel(unit, rosterLvl)
        local tag = (n == me) and " (you)" or (self:IsWhitelisted(n) and " |cff55ff55[whitelist]|r"
            or (maxLevel < 60 and lvl >= maxLevel and lvl < 60 and " |cffff5555<- would kick|r" or ""))
        self:Print(("  %s: lvl %d%s"):format(n, lvl, tag))
    end
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do local nm, _, _, lvl = GetRaidRosterInfo(i); line(nm, "raid" .. i, lvl) end
    elseif GetNumPartyMembers() > 0 then
        line(UnitName("player"), "player", nil)
        for i = 1, GetNumPartyMembers() do line(UnitName("party" .. i), "party" .. i, nil) end
    else
        self:Print("  (not in a group)")
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

-- True while a non-self group member is at/above 60 (mobs are scaled).
local function scalingStillActive()
    local me = GB:NormName(UnitName("player"))
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local n, _, _, lvl = GetRaidRosterInfo(i)
            if n and GB:NormName(n) ~= me and (lvl or 0) >= SCALE_LEVEL then return true end
        end
    else
        for i = 1, GetNumPartyMembers() do
            if (UnitLevel("party" .. i) or 0) >= SCALE_LEVEL then return true end
        end
    end
    return false
end

function GB:ScalingTick()
    if not self._scalingAlertOn then return end
    self._scalingTicks = (self._scalingTicks or 0) + 1
    if scalingStillActive() and self._scalingTicks <= MAX_SCALING_TICKS then
        SendChatMessage(("Level %d scaling ACTIVE — hold pulls, reforming!"):format(SCALE_LEVEL),
            GetNumRaidMembers() > 0 and "RAID_WARNING" or "PARTY")
        self:After(3, function() GB:ScalingTick() end)
    else
        self._scalingAlertOn = false
        if self._scalingTicks > 1 then   -- we actually warned at least once
            SendChatMessage(("Level %d scaling cleared — good to go!"):format(SCALE_LEVEL),
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
--  Autokick (sub-60) and Reform (60)
-- ---------------------------------------------------------------------------

-- Single-kick a member who reached the sub-60 threshold, with a friendly whisper.
-- Once per member (the guard is cleared when they leave the group).
function GB:AutoKick(name)
    if not (self.db and self.db.leveling.enabled) then return end
    if not amLeader() then return end
    self._autoKicked = self._autoKicked or {}
    if self._autoKicked[name] then return end
    self._autoKicked[name] = true
    local role = self.claims[name] and self.claims[name].role
    self:Reply(name, ("%s: thanks for coming! I'm removing you now you've hit %d, so you don't scale the mobs to 60 for the rest of the group. GG — whisper me for a re-invite once you've rerolled!"):format(
        self:Tag(), self.db.leveling.maxLevel or 59))
    local entry = self.rosterByName[name]
    UninviteUnit(entry and entry.unit or name)
    self:Print("|cffffcc00" .. name .. "|r hit " .. (self.db.leveling.maxLevel or 59) .. " — auto-kicked (not whitelisted).")

    -- Private on-screen alert if we lost a tank or healer.
    if (role == "tank" or role == "healer") and self.KickAlert then
        local remaining = 0
        for _, m in ipairs(self.roster) do
            if m.name ~= name and self.claims[m.name] and self.claims[m.name].role == role then
                remaining = remaining + 1
            end
        end
        self:KickAlert(role, remaining)
    end
end

function GB:OnMemberDinged(dinger)
    if not (self.db and self.db.leveling.enabled) then return end
    -- Only the leader handles the ding (only they can reform); if you're not the
    -- leader, stay quiet — whoever leads the group takes care of it.
    if not amLeader() then return end
    self:Print("|cffffcc00" .. dinger .. " hit " .. SCALE_LEVEL .. "!|r")
    self:StartScalingAlert()   -- keep warning /rw every 3s until the 60 is gone
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
            self._reformList[m.name] = {
                role = self.claims[m.name] and self.claims[m.name].role or nil,
                level = m.level or 0,
            }
            keepers[#keepers + 1] = m.name
        end
    end
    self._lastDinger = dinger   -- so the "reform" failsafe won't re-invite them

    -- 1) Raid warning FIRST, while everyone is still grouped to see it.
    if self.db.leveling.announceReform then
        local msg = dinger
            and ("Level %d scaling detected — reforming to reset it! Kicking now; pst me 'reform' for a re-invite."):format(
                SCALE_LEVEL)
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

-- Send invites to everyone on the reform list who isn't already back and isn't
-- level 60 (re-inviting a 60 would just scale the group again).
function GB:ReinviteGroup()
    if not (self._reformList and next(self._reformList)) then
        self:Print("no reform list to re-invite.")
        return
    end
    self:RefreshRoster()
    local n, skipped = 0, 0
    for name, info in pairs(self._reformList) do
        local lvl = (type(info) == "table" and info.level) or 0
        if self.rosterByName[name] then
            -- already back
        elseif lvl >= SCALE_LEVEL then
            skipped = skipped + 1   -- a 60 — don't invite (would re-scale)
        else
            GB:Invite(name); n = n + 1
        end
    end
    self:Print(("sent %d re-invite(s)%s."):format(n, skipped > 0 and (", skipped " .. skipped .. " at 60") or ""))
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
