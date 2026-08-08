-- GroupBuilder :: PassLead.lua
-- Hand the raid off and leave. Promotes EVERYONE to assist first (so a single AFK new
-- leader can't strand the group), picks a RANDOM member as the new leader (it's not
-- your call who leads — you're just doing the group a favor by reforming + handing
-- off), announces the key roles (tanks / healers / auras) to raid chat, then leaves.

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

-- Build the "name - role[- aura]" handoff lines from a roster + claims, excluding
-- `me`. Order: tanks, then healers, then any other aura-holders. Aura shown only if
-- true (unknown = no aura). Shared by the real hand-off and /gb ptest.
local function handoffLines(roster, claims, me)
    local lines, seen = {}, {}
    local function add(name, role, hasAura)
        if seen[name] then return end
        seen[name] = true
        lines[#lines + 1] = ("%s - %s%s"):format(name, role, hasAura and " - aura" or "")
    end
    for _, m in ipairs(roster) do local c = claims[m.name]
        if c and m.name ~= me and c.role == "tank" then add(m.name, "tank", c.aura == true) end
    end
    for _, m in ipairs(roster) do local c = claims[m.name]
        if c and m.name ~= me and c.role == "healer" then add(m.name, "healer", c.aura == true) end
    end
    for _, m in ipairs(roster) do local c = claims[m.name]
        if c and m.name ~= me and c.aura == true and c.role ~= "tank" and c.role ~= "healer" then
            add(m.name, c.role or "dps", true)
        end
    end
    return lines
end

-- A random group member who isn't you.
function GB:RandomMember()
    local me = self:MyName()
    local pool = {}
    for _, m in ipairs(self.roster) do if m.name ~= me then pool[#pool + 1] = m.name end end
    if #pool == 0 then return nil end
    return pool[math.random(#pool)]
end

-- ---------------------------------------------------------------------------
--  The handoff itself
-- ---------------------------------------------------------------------------
function GB:PassLead(name)
    if not amLeader() then
        self:Print("Only the current raid/party LEADER can pass lead.")
        return
    end
    self:RefreshRoster()
    local me = self:MyName()

    -- Target: an explicit name if it's a real other member, otherwise pick at random.
    local target = name and name ~= "" and self:NormName(name) or nil
    if not (target and self.rosterByName[target] and target ~= me) then
        target = self:RandomMember()
    end
    if not target then
        self:Print("no one else in the group to hand off to.")
        return
    end

    -- Key players only (tanks, healers, aura-holders), you (leaving) excluded.
    local lines = handoffLines(self.roster, self.claims, me)

    -- 1) Promote everyone to assist first, so an AFK new leader isn't a single point
    --    of failure. Must happen while WE are still leader.
    if GetNumRaidMembers() > 0 and PromoteToAssistant then
        for i = 1, GetNumRaidMembers() do
            local nm = UnitName("raid" .. i)
            if nm and self:NormName(nm) ~= me then pcall(PromoteToAssistant, "raid" .. i) end
        end
    end

    -- 2) Pass leadership to the chosen player.
    if PromoteToRaidLeader then pcall(PromoteToRaidLeader, target)
    else runLine("/promote " .. target) end

    -- 3) Announce to the group: a header, then one line per key player.
    local chan = GetNumRaidMembers() > 0 and "RAID" or "PARTY"
    SendChatMessage(("%s is now leader (everyone's been made assist). Key players:"):format(target), chan)
    for _, line in ipairs(lines) do SendChatMessage(line, chan) end
    self:Print(("Passed lead to |cffffcc00%s|r (all assist) and announced %d key player(s). Leaving."):format(target, #lines))

    if LeaveParty then self:After(2, function() if LeaveParty then LeaveParty() end end) end
end

-- ---------------------------------------------------------------------------
--  Confirmation (button on the monitor + /gb pass)
-- ---------------------------------------------------------------------------
-- NB: never assign to StaticPopupDialogs itself (e.g. `= StaticPopupDialogs or {}`) —
-- that taints the global table and blocks Blizzard's secure popups (ReplaceEnchant /
-- applying poisons, etc.). Only ever add keys to it, which is always safe.
StaticPopupDialogs["GROUPBUILDER_PASSLEAD"] = {
    text = "Pass raid lead to %s and LEAVE?\nEveryone is promoted to assist first, and the key roles are announced to the raid.",
    button1 = "Pass & Leave", button2 = "Cancel",
    OnAccept = function(self) GB:PassLead(self.data) end,   -- data = a name, or nil = random
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- name = nil -> hand off to a random member.
function GB:ConfirmPassLead(name)
    name = (name and name ~= "") and self:NormName(name) or nil
    if not StaticPopup_Show then return self:PassLead(name) end
    local who = name or "a random member"
    local d = StaticPopup_Show("GROUPBUILDER_PASSLEAD", who)
    if d then d.data = name end
end

function GB:PassLeadPrompt() self:ConfirmPassLead(nil) end

-- /gb ptest — dry formatting test. Builds a synthetic 15-man (2 tanks, 3 healers,
-- 10 dps; 3 auras split 1 tank / 1 healer / 1 dps), with YOU as a dps with no aura who
-- is leaving, and prints the exact hand-off announcement to /say — no group needed.
function GB:PassLeadTest()
    local me = self:MyName() or "You"
    local roster, claims = {}, {}
    local function put(name, role, aura, lvl)
        roster[#roster + 1] = { name = name, subgroup = 1, level = lvl }
        claims[name] = { role = role, aura = aura }
    end
    put(me, "dps", false, 57)             -- you: dps, no aura, leaving (excluded)
    put("Kusonoki", "tank", true, 59)     -- tank + aura
    put("Bruticus", "tank", false, 58)
    put("Homelessman", "healer", true, 57)-- healer + aura
    put("Imay", "healer", false, 56)
    put("Sylvara", "healer", false, 58)
    put("Topaze", "dps", true, 55)        -- dps + aura
    for i, n in ipairs({ "Mavrayn", "Deleted", "Aitutu", "Smithagent", "Iilflame", "Zugzug", "Boople", "Nyxen" }) do
        put(n, "dps", false, 54 + (i % 6))
    end

    local pool = {}
    for _, m in ipairs(roster) do if m.name ~= me then pool[#pool + 1] = m.name end end
    local target = pool[math.random(#pool)]
    local lines = handoffLines(roster, claims, me)

    SendChatMessage(("%s is now leader (everyone's been made assist). Key players:"):format(target), "SAY")
    for _, line in ipairs(lines) do SendChatMessage(line, "SAY") end
    self:Print(("ptest: sent a %d-key-player hand-off to /say (you = dps no aura, excluded)."):format(#lines))
end
