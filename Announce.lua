-- GroupBuilder :: Announce.lua
-- Turns the current needs into text, keeps the LFM macro in sync, and posts to
-- the chosen channel.

local addonName, GB = ...

GB.currentAnnounce = GB.currentAnnounce or ""

local function plural(n, word)
    if word == "dps" then return n .. " dps" end
    return n .. " " .. word .. (n == 1 and "" or "s")
end

-- Role part of what we need, e.g. "1 tank (heirlooms required), 3 dps". Each role
-- is tagged "(heirlooms required)" only if THAT role has the toggle ticked.
local function roleParts(status)
    local n = status.recruitNeed or status.need   -- exclude slots reserved for friends
    local LOOM = " (heirlooms required)"
    local parts = {}
    if n.tanks   > 0 then parts[#parts + 1] = plural(n.tanks, "tank")     .. (GB:RoleLooms("tank")   and LOOM or "") end
    if n.healers > 0 then parts[#parts + 1] = plural(n.healers, "healer") .. (GB:RoleLooms("healer") and LOOM or "") end
    if n.dps     > 0 then parts[#parts + 1] = plural(n.dps, "dps")        .. (GB:RoleLooms("dps")    and LOOM or "") end
    return table.concat(parts, ", ")
end

-- A compact list of what we still need, used in whispers.
-- opts.short omits the group letters after auras.
function GB:NeedSummary(status, opts)
    opts = opts or {}
    status = status or self:GetStatus()
    local roleStr = roleParts(status)

    if status.auraNeed > 0 then
        local auraStr
        if opts.short then
            auraStr = plural(status.auraNeed, "aura")
        else
            local g = {}
            for _, gi in ipairs(status.missingGroups) do g[#g + 1] = "G" .. gi end
            auraStr = "aura " .. table.concat(g, ", ")
        end
        if roleStr ~= "" then return roleStr .. " + " .. auraStr end
        return auraStr
    end
    return roleStr
end

-- The "<whats needed>" portion of the channel line: roles (with per-role heirloom
-- tags) + aura requirement / welcome.
function GB:AnnounceNeeds(status)
    status = status or self:GetStatus()
    local roleStr = roleParts(status)
    -- When every group already has an aura, say so at the end.
    local covered = ((status.comp.auras or 0) > 0 and status.auraNeed == 0)
        and " — all auras covered" or ""

    if roleStr ~= "" then
        if status.auraRequired then return roleStr .. " + aura" end
        if status.auraNeed > 0 then return roleStr .. " (aura welcome)" end
        return roleStr .. covered
    else
        -- roles full; only aura coverage missing
        if status.auraRequired then return "aura" end
        return ""  -- nothing hard-required to announce
    end
end

-- Build the channel-facing LFM line:
--   "LF<needed>M Leveling MS - need <needs>. (<have>/<size>)"
-- The leading number is how many people we still need; the have/size is moved to
-- the end so nobody reads "1/15" as "need 1 of 15".
function GB:BuildAnnounce(status)
    status = status or self:GetStatus()
    if status.full then return "Leveling MS group is FULL — thanks for whispering!" end

    local size = status.comp.size or status.headcount
    local needs = self:AnnounceNeeds(status)
    if needs == "" then return nil end

    local open = status.openSpots or math.max(0, size - status.headcount)
    local lead = open >= 1 and ("LF%dM"):format(open) or "LFM"
    return ("%s Leveling MS - need %s. (%d/%d)"):format(lead, needs, status.headcount, size)
end

-- ---------------------------------------------------------------------------
--  Announce macro. Its body is simply "/gbsay", so pressing it always posts the
--  freshly-computed LFM line to your chosen channel — no editing, ever. The body
--  never changes, so we only need to create it once (in the general macro tab).
-- ---------------------------------------------------------------------------
local MACRO_BODY = "/gbsay"

local pendingMacro = false

-- Create (or fix) the account-wide GB_LFM macro so pressing it runs /gbsay.
-- Robust: never permanently disables, and falls back to a guaranteed-valid icon.
function GB:EnsureMacro()
    if not (self.db and self.db.macro) then return end
    local m = self.db.macro
    if InCombatLockdown() then pendingMacro = true; return end

    local idx = GetMacroIndexByName(m.name)
    if idx and idx > 0 then
        pcall(EditMacro, idx, m.name, m.icon, MACRO_BODY)   -- keep body correct
        return idx
    end

    -- create an account macro; retry with progressively safer icon forms
    -- (configured name -> known-good name -> numeric icon index) since clients
    -- vary in what CreateMacro accepts for the icon argument.
    local ok, res
    for _, icon in ipairs({ m.icon, "INV_MISC_QUESTIONMARK", 1 }) do
        ok, res = pcall(CreateMacro, m.name, icon, MACRO_BODY, nil)
        if ok then break end
    end
    if ok then
        self:Print("made the |cff33ff99" .. m.name .. "|r macro (General tab) — drag it to a bar to announce.")
        return res
    end
    self:Print("|cffff5555couldn't make the " .. m.name .. " macro|r (" .. tostring(res) ..
        "). Your account macro tab may be full — free a slot, then /gb macro.")
end

local function writeMacro() GB:EnsureMacro() end

GB:On("PLAYER_REGEN_ENABLED", function()
    if pendingMacro then pendingMacro = false; GB:EnsureMacro() end
end)

-- Recompute the announce text + refresh the macro. Called on any roster change.
function GB:UpdateAnnounce()
    if not self.db then return end
    self:RefreshRoster()
    local status = self:GetStatus()
    self.currentAnnounce = self:BuildAnnounce(status) or ""
    writeMacro()
end

-- Resolve the configured channel and post the current line right now.
function GB:AnnounceNow()
    local status = self:GetStatus()
    local text = self:BuildAnnounce(status)
    if not text then
        self:Print("group is full — nothing to announce.")
        return
    end
    self.currentAnnounce = text
    local a = self.db.announce

    if a.type == "CHANNEL" then
        local idx = GetChannelName(a.channelName)
        if not idx or idx == 0 then
            self:Print(("you're not in channel '%s' — /join %s first."):format(
                a.channelName or "?", a.channelName or "?"))
            return
        end
        SendChatMessage(text, "CHANNEL", nil, idx)
    elseif a.type == "RAID" then
        SendChatMessage(text, GetNumRaidMembers() > 0 and "RAID" or "PARTY")
    elseif a.type == "PARTY" then
        SendChatMessage(text, (GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0) and "PARTY" or "SAY")
    else
        SendChatMessage(text, a.type)  -- SAY/YELL/GUILD
    end
end
