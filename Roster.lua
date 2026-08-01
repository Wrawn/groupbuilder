-- GroupBuilder :: Roster.lua
-- Tracks the current party/raid and each member's claimed role/aura/looms, then
-- computes what the group still needs. Claims come from the whisper recruit flow
-- (Recruit.lua) or manual assignment, keyed by player name.

local addonName, GB = ...

-- Per-name claims. Persisted for the session in the char DB so a reload keeps
-- what people told us. { [name] = { role = "tank"|"healer"|"dps", aura=bool, looms=bool } }
GB.claims = GB.claims or {}

-- Current membership, rebuilt on roster changes: array of { name, subgroup, level }.
GB.roster = GB.roster or {}
GB.rosterByName = GB.rosterByName or {}

local function normName(name)
    if not name then return nil end
    -- strip a realm suffix if one ever appears, and normalise case for keys
    name = name:match("^([^-]+)") or name
    return name
end
GB.NormName = function(_, n) return normName(n) end

-- Assign / merge a claim for a player (used by recruit flow and manual commands).
function GB:SetClaim(name, fields)
    name = normName(name)
    if not name then return end
    local c = self.claims[name] or {}
    for k, v in pairs(fields) do c[k] = v end
    self.claims[name] = c
    if self.cdb then
        self.cdb.claims = self.cdb.claims or {}
        self.cdb.claims[name] = c
    end
end

function GB:GetClaim(name)
    return self.claims[normName(name)]
end

function GB:ClearClaim(name)
    name = normName(name)
    self.claims[name] = nil
    if self.cdb and self.cdb.claims then self.cdb.claims[name] = nil end
end

-- Reset the tracked comp: wipe every player's role/aura (target numbers stay).
function GB:ClearComp()
    wipe(self.claims)
    if self.cdb then self.cdb.claims = {} end
    if self.applicants then wipe(self.applicants) end
    self._autoReplied = {}   -- let people be prompted again after a reset
    self:RefreshRoster(); self:UpdateAnnounce(); self:RefreshUI()
    if self.RefreshApplicants then self:RefreshApplicants() end
    self:Print("cleared all tracked roles & auras — comp reset.")
end

-- Your own character's name.
function GB:MyName()
    return normName(UnitName("player"))
end

-- Your own claim (role/aura/looms). You count in the comp just like anyone else.
function GB:GetSelfClaim()
    local me = self:MyName()
    return self.claims[me] or (self.cdb and self.cdb.claims and self.cdb.claims[me])
end

-- Set one field of your own claim. Pass value = nil to clear it (e.g. role = None).
function GB:SetSelfField(field, value)
    local me = self:MyName()
    if not me then return end
    local c = self.claims[me] or {}
    c[field] = value
    self.claims[me] = c
    if self.cdb then
        self.cdb.claims = self.cdb.claims or {}
        self.cdb.claims[me] = c
    end
end

-- Rebuild GB.roster from the live group. Preserves claims by name.
function GB:RefreshRoster()
    -- restore persisted claims once config is ready
    if self.cdb and self.cdb.claims and not self._claimsRestored then
        for n, c in pairs(self.cdb.claims) do self.claims[n] = c end
        self._claimsRestored = true
    end

    wipe(self.roster)
    wipe(self.rosterByName)

    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, subgroup, level = GetRaidRosterInfo(i)
            if name then
                name = normName(name)
                local entry = { name = name, subgroup = subgroup or 1, level = level or 0, unit = "raid" .. i }
                self.roster[#self.roster + 1] = entry
                self.rosterByName[name] = entry
            end
        end
    else
        -- party (including solo self)
        local me = normName(UnitName("player"))
        local meEntry = { name = me, subgroup = 1, level = UnitLevel("player") or 0, unit = "player" }
        self.roster[#self.roster + 1] = meEntry
        self.rosterByName[me] = meEntry
        local numParty = GetNumPartyMembers()
        for i = 1, numParty do
            local unit = "party" .. i
            local name = normName(UnitName(unit))
            if name then
                local entry = { name = name, subgroup = 1, level = UnitLevel(unit) or 0, unit = unit }
                self.roster[#self.roster + 1] = entry
                self.rosterByName[name] = entry
            end
        end
    end

    -- Drop claims for people no longer in the group so counts stay honest.
    for name in pairs(self.claims) do
        if not self.rosterByName[name] then
            -- keep in char DB history but not in live claims
            self.claims[name] = nil
        end
    end
    -- re-apply persisted claims for anyone currently present
    if self.cdb and self.cdb.claims then
        for name, entry in pairs(self.rosterByName) do
            if self.cdb.claims[name] then self.claims[name] = self.cdb.claims[name] end
        end
    end

    if self.MarkTanks then self:MarkTanks() end
end

-- Auto-mark tanks: 1st tank -> circle (2), 2nd -> square (6), only if unmarked.
-- Needs you to be leader/assist (SetRaidTarget is restricted otherwise).
function GB:MarkTanks()
    if not (self.db and self.db.markTanks) then return end
    if not self:CanLead() then return end
    if not SetRaidTarget then return end
    if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then return end   -- solo
    local icons = { 2, 6 }   -- circle, square
    local n = 0
    for _, m in ipairs(self.roster) do
        local c = self.claims[m.name]
        if c and c.role == "tank" and m.unit then
            n = n + 1
            if n > #icons then break end
            local cur = (GetRaidTargetIndex and GetRaidTargetIndex(m.unit)) or 0
            if cur == 0 then SetRaidTarget(m.unit, icons[n]) end
        end
    end
end

-- Compute the current status vs the target comp.
-- Returns a table describing have/need per role and aura coverage per group.
function GB:GetStatus()
    local comp = self.db and self.db.comp or GB.defaults.comp
    local have = { tanks = 0, healers = 0, dps = 0 }
    local unknown = 0
    local auraGroups = {}   -- [subgroup] = true if that group has an aura holder

    for _, m in ipairs(self.roster) do
        local c = self.claims[m.name]
        local role = c and c.role
        if role == "tank" then have.tanks = have.tanks + 1
        elseif role == "healer" then have.healers = have.healers + 1
        elseif role == "dps" then have.dps = have.dps + 1
        else unknown = unknown + 1 end
        if c and c.aura then auraGroups[m.subgroup or 1] = true end
    end

    local need = {
        tanks   = math.max(0, comp.tanks   - have.tanks),
        healers = math.max(0, comp.healers - have.healers),
        dps     = math.max(0, comp.dps     - have.dps),
    }

    -- Slots reserved for friends who aren't in the group yet (one per role).
    local reserved = { tanks = 0, healers = 0, dps = 0 }
    local reservedFriends = {}   -- { {name=, role=}, ... } not yet present
    for fname, frole in pairs(self.db and self.db.friends or {}) do
        if not self.rosterByName[fname] then
            reservedFriends[#reservedFriends + 1] = { name = fname, role = frole }
            if frole == "tank" then reserved.tanks = reserved.tanks + 1
            elseif frole == "healer" then reserved.healers = reserved.healers + 1
            elseif frole == "dps" then reserved.dps = reserved.dps + 1 end
        end
    end
    -- What we still recruit from randoms = need minus reserved-for-friends.
    local recruitNeed = {
        tanks   = math.max(0, need.tanks   - reserved.tanks),
        healers = math.max(0, need.healers - reserved.healers),
        dps     = math.max(0, need.dps     - reserved.dps),
    }

    -- Aura coverage across the first `comp.auras` subgroups (G1..GN).
    local missingGroups = {}
    for g = 1, (comp.auras or 0) do
        if not auraGroups[g] then missingGroups[#missingGroups + 1] = g end
    end
    local auraNeed = #missingGroups
    local auraHave = (comp.auras or 0) - auraNeed

    local headcount = #self.roster
    local size = comp.size or headcount
    local openSpots = math.max(0, size - headcount)
    -- Aura is *required* of new recruits only when we're running out of room:
    -- open spots <= auras still needed. Otherwise it's merely preferred, so we
    -- don't reject bodies we still have room for.
    local auraRequired = auraNeed > 0 and openSpots <= auraNeed

    return {
        headcount     = headcount,
        unknown       = unknown,
        have          = have,
        need          = need,
        recruitNeed   = recruitNeed,
        reserved      = reserved,
        reservedFriends = reservedFriends,
        auraHave      = auraHave,
        auraNeed      = auraNeed,
        auraRequired  = auraRequired,
        openSpots     = openSpots,
        missingGroups = missingGroups,
        comp          = comp,
        full          = (need.tanks + need.healers + need.dps == 0 and auraNeed == 0
                         and headcount >= size),
    }
end

function GB:PrintStatus()
    local s = self:GetStatus()
    self:Print(("Raid status. T %d/%d, H %d/%d, D %d/%d."):format(
        s.have.tanks, s.comp.tanks, s.have.healers, s.comp.healers, s.have.dps, s.comp.dps))
    if s.auraNeed > 0 then
        local g = {}
        for _, n in ipairs(s.missingGroups) do g[#g + 1] = "G" .. n end
        self:Print("Auras needed: " .. table.concat(g, ", "))
    else
        self:Print("Auras: all groups covered.")
    end
    if s.unknown > 0 then
        self:Print(("%d member(s) have no assigned role — use whispers or /gb to assign."):format(s.unknown))
    end
end

-- Keep the model fresh as the group changes.
-- Convert a party to a raid once we're recruiting a >5 comp, so invites (incl.
-- the reform re-invites) don't get dropped when the party hits 5 members.
function GB:EnsureRaid()
    if not (self.db and self.db.active) then return end
    if (self.db.comp.size or 0) <= 5 then return end
    if GetNumRaidMembers() > 0 then return end            -- already a raid
    if GetNumPartyMembers() == 0 then return end          -- solo: nothing to convert
    if not (IsPartyLeader and IsPartyLeader()) then return end
    if InCombatLockdown() then return end
    pcall(ConvertToRaid)
end

-- Keep the model fresh as the group changes. We do NOT auto-poll members for
-- aura/role here — that only happens when someone whispers to join, or when you
-- press the Role/Aura Check button — so joining random groups stays quiet.
GB:On("RAID_ROSTER_UPDATE", function()
    GB:RefreshRoster(); GB:UpdateAnnounce(); GB:RefreshUI()
end)
GB:On("PARTY_MEMBERS_CHANGED", function()
    GB:EnsureRaid()
    GB:RefreshRoster(); GB:UpdateAnnounce(); GB:RefreshUI()
end)
