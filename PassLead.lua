-- GroupBuilder :: PassLead.lua
-- Hand the raid off to someone else and leave. Promotes EVERYONE to assist first
-- (so a single AFK new leader can't strand the group), passes lead to your pick,
-- prints/whispers a handoff report, then leaves.

local addonName, GB = ...

local function amLeader()
    if GetNumRaidMembers() > 0 then return IsRaidLeader() and true or false end
    if GetNumPartyMembers() > 0 then return IsPartyLeader() and true or false end
    return false
end

-- Run a slash line (fallback path for passing lead). Guarded for the test harness.
local function runLine(line)
    local eb = (ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend())
        or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
    if eb and ChatEdit_SendText then
        eb:SetText(line)
        ChatEdit_SendText(eb, 0)
    end
end

-- ---------------------------------------------------------------------------
--  Handoff report (structured once, rendered for both the local frame & whisper)
-- ---------------------------------------------------------------------------
function GB:CollectHandoff()
    self:RefreshRoster()
    local me = self:MyName()
    local maxLevel = self.db.leveling.maxLevel or 60
    local out = {}
    for _, m in ipairs(self.roster) do
        local c = self.claims[m.name]
        local lvl = m.level or 0
        local flags = {}
        if maxLevel < 60 and lvl > 0 and lvl >= (maxLevel - 5) and lvl < 60 then
            flags[#flags + 1] = ("near autokick (lvl %d/%d)"):format(lvl, maxLevel)
        end
        if m.name ~= me and not (self._gbInvited and self._gbInvited[m.name]) then
            flags[#flags + 1] = "manual invite / unverified"
        end
        if self._askedNew and self._askedNew[m.name] and not (c and c.role) then
            flags[#flags + 1] = "awaiting whisper reply"
        end
        if self:IsWhitelisted(m.name) then flags[#flags + 1] = "whitelisted" end
        local role = (c and c.role) or "unknown"
        local aura = c and (c.aura == true and "has aura" or c.aura == false and "MISSING aura" or "aura unknown")
            or "aura unknown"
        out[#out + 1] = {
            name = m.name, role = role, aura = aura, flags = flags,
            important = (role == "tank" or role == "healer" or #flags > 0),
        }
    end
    return out
end

function GB:HandoffReport()
    local rows = self:CollectHandoff()
    local lines = {
        "== GroupBuilder handoff ==",
        "You lead now. Promote/kick from the raid UI. Tracked state:",
        "",
    }
    for _, r in ipairs(rows) do
        local ftxt = (#r.flags > 0) and ("  {" .. table.concat(r.flags, ", ") .. "}") or ""
        lines[#lines + 1] = ("%s — %s — %s%s"):format(r.name, r.role, r.aura, ftxt)
    end
    if #rows == 0 then lines[#lines + 1] = "(nobody tracked)" end
    return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
--  The handoff itself
-- ---------------------------------------------------------------------------
function GB:PassLead(name)
    name = self:NormName(name)
    if not amLeader() then
        self:Print("Only the current raid/party LEADER can pass lead.")
        return
    end
    self:RefreshRoster()
    if not self.rosterByName[name] then
        self:Print(name .. " isn't in your group — can't pass lead to them.")
        return
    end
    if name == self:MyName() then
        self:Print("That's you — pick someone else to hand off to.")
        return
    end

    -- Report BEFORE we change anything (so it reflects the group you're handing off).
    local report = self:HandoffReport()

    -- 1) Promote everyone to assist first (raid only), so an AFK new leader isn't
    --    a single point of failure. Must happen while WE are still leader.
    if GetNumRaidMembers() > 0 and PromoteToAssistant then
        local me = self:MyName()
        for i = 1, GetNumRaidMembers() do
            local u = "raid" .. i
            local nm = UnitName(u)
            if nm and self:NormName(nm) ~= me then pcall(PromoteToAssistant, u) end
        end
    end

    -- 2) Pass leadership to the chosen player.
    if PromoteToRaidLeader then pcall(PromoteToRaidLeader, name)
    else runLine("/promote " .. name) end

    -- 3) Whisper the new leader a plain tanks / healers / auras summary. They don't
    --    have the addon, so no flags or jargon — just who's what.
    local me = self:MyName()
    local tanks, heals, auras = {}, {}, {}
    for _, m in ipairs(self.roster) do
        local c = self.claims[m.name]
        if c and m.name ~= me then   -- you're leaving, so leave yourself out of the handoff
            if c.role == "tank" then tanks[#tanks + 1] = m.name
            elseif c.role == "healer" then heals[#heals + 1] = m.name end
            if c.aura == true then auras[#auras + 1] = m.name end
        end
    end
    local function listOr(t) return #t > 0 and table.concat(t, ", ") or "none" end
    self:Reply(name, "You're raid lead now (everyone's been made assist). Group setup:")
    self:Reply(name, "Tanks: " .. listOr(tanks))
    self:Reply(name, "Healers: " .. listOr(heals))
    self:Reply(name, "Auras: " .. listOr(auras))

    -- 4) Show the full report locally, print, and leave.
    if self.ShowText then self:ShowText("Raid handed off to " .. name, report) end
    self:Print("Passed lead to " .. name .. " (all promoted to assist). Leaving group.")

    if LeaveParty then self:After(2, function() if LeaveParty then LeaveParty() end end) end
end

-- ---------------------------------------------------------------------------
--  Confirmations
-- ---------------------------------------------------------------------------
StaticPopupDialogs = StaticPopupDialogs or {}

-- /gb pass <name> — name known, ask yes/no.
StaticPopupDialogs["GROUPBUILDER_PASSLEAD_CONFIRM"] = {
    text = "Pass raid lead to %s and LEAVE?\nEveryone is promoted to assist first, then %s becomes leader.",
    button1 = "Pass Lead", button2 = "Cancel",
    OnAccept = function(self) if self.data then GB:PassLead(self.data) end end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function GB:ConfirmPassLead(name)
    if not StaticPopup_Show then return self:PassLead(name) end
    local d = StaticPopup_Show("GROUPBUILDER_PASSLEAD_CONFIRM", name, name)
    if d then d.data = name end
end

-- Button on the monitor — ask for the name, then hand off.
StaticPopupDialogs["GROUPBUILDER_PASSLEAD"] = {
    text = "Pass raid lead to whom (and LEAVE)?\nEveryone is promoted to assist first.",
    button1 = "Pass Lead", button2 = "Cancel",
    hasEditBox = true, maxLetters = 24,
    OnShow = function(self)
        local eb = self.editBox or getglobal(self:GetName() .. "EditBox")
        if eb then eb:SetText(""); eb:SetFocus() end
    end,
    OnAccept = function(self)
        local eb = self.editBox or getglobal(self:GetName() .. "EditBox")
        local n = eb and eb:GetText()
        if n and n ~= "" then GB:PassLead(GB:NormName(n)) end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local n = self:GetText()
        if n and n ~= "" then GB:PassLead(GB:NormName(n)) end
        if parent then parent:Hide() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function GB:PassLeadPrompt()
    if StaticPopup_Show then StaticPopup_Show("GROUPBUILDER_PASSLEAD") end
end
