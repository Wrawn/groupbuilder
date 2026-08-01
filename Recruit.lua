-- GroupBuilder :: Recruit.lua
-- Whisper-driven recruiting. Parses whispers for role/aura/looms keywords,
-- auto-replies with what the group still needs, and invites matching applicants.

local addonName, GB = ...

-- Build a reverse word -> category lookup from GB.keywords once.
local kwLookup
local function buildLookup()
    kwLookup = {}
    for cat, words in pairs(GB.keywords) do
        for _, w in ipairs(words) do kwLookup[w] = cat end
    end
end

-- Parse a whisper body into intent flags.
local function parseWhisper(msg)
    if not kwLookup then buildLookup() end
    local roles, aura, looms, negative = {}, false, false, false
    local wordCount = 0
    for word in msg:lower():gmatch("[%a]+") do
        wordCount = wordCount + 1
        local cat = kwLookup[word]
        if cat == "tank" then roles.tank = true
        elseif cat == "healer" then roles.healer = true
        elseif cat == "dps" then roles.dps = true
        elseif cat == "aura" then aura = true
        elseif cat == "looms" then looms = true
        end
        if word == "no" or word == "nope" or word == "nah" or word == "none"
            or word == "dont" or word == "negative" then
            negative = true
        end
    end
    local low = " " .. msg:lower() .. " "

    -- Negated aura: "no aura", "not aura", "without aura", "don't have ... aura".
    -- This must beat the bare "aura" keyword so "no aura" doesn't read as HAS aura.
    local auraNo = low:find("no%s+auras?") or low:find("not%s+auras?")
        or low:find("without%s+auras?")
        or ((low:find("don'?t") or low:find("dont") or low:find("do not")) and low:find("auras?"))
    auraNo = auraNo and true or false
    if auraNo then aura = false end

    -- A bare "no"/"nope" (no role/aura/looms words) is a plain negative answer.
    local bareNo = negative and not (roles.tank or roles.healer or roles.dps) and not aura and not looms

    -- Explicit "I want in" intent only — NOT just short messages, so normal
    -- conversation ("sup", "ty", "lol", "?") doesn't get treated as recruiting.
    local joinish = low:find("inv") or low:find("join") or low:find("spot")
        or low:find("lfg") or low:find("lfm") or low:find("sign") or low:find("room")
        or low:find("got%s+room") or low:find("can%s+i")
    return {
        roles = roles,
        aura = aura,
        auraNo = auraNo,
        looms = looms,
        negative = negative and true or false,
        bareNo = bareNo and true or false,
        namedRole = (roles.tank or roles.healer or roles.dps) and true or false,
        joinish = joinish and true or false,
    }
end

-- Maps a singular role name to its plural key in status.need.
local NEED_KEY = { tank = "tanks", healer = "healers", dps = "dps" }

-- Choose which role to record for an applicant, preferring one we still need.
local function chooseRole(parsed, status)
    local need = status.need
    -- prefer a mentioned role that we still need, in tank>healer>dps order
    for _, r in ipairs({ "tank", "healer", "dps" }) do
        if parsed.roles[r] and need[NEED_KEY[r]] > 0 then return r end
    end
    -- otherwise any mentioned role (may be one we're full on)
    for _, r in ipairs({ "tank", "healer", "dps" }) do
        if parsed.roles[r] then return r end
    end
    return nil
end

-- Send an invite and confirm to the applicant.
function GB:InviteApplicant(name, role)
    InviteUnit(name)
    self:Reply(name, ("%s: Inviting you%s! Please accept."):format(
        self:Tag(), role and (" as " .. role) or ""))
end

-- Whisper helper. Records that WE sent this whisper, so CHAT_MSG_WHISPER_INFORM
-- can tell an addon whisper apart from you talking to someone.
function GB:Reply(target, text)
    self._addonSentTo = self._addonSentTo or {}
    self._addonSentTo[self:NormName(target)] = GetTime()
    SendChatMessage(text, "WHISPER", nil, target)
end

-- Send an auto-prompt at most ONCE per person (so we never spam the same reply).
function GB:ReplyOnce(name, text)
    self._autoReplied = self._autoReplied or {}
    if self._autoReplied[name] then return false end
    self._autoReplied[name] = true
    self:Reply(name, text)
    return true
end

-- Per-person auto-reply cooldown, and who we've asked about auras / roles.
local lastReply = {}
local askedAura = {}
local checkAsked = {}   -- last time /gb aura-check whispered this member

-- If YOU whisper someone (not one of the addon's own auto-replies), treat it as a
-- conversation and stop auto-recruiting them.
GB:On("CHAT_MSG_WHISPER_INFORM", function(_, msg, target)
    if not target then return end
    local name = GB:NormName(target)
    local sent = GB._addonSentTo and GB._addonSentTo[name]
    if not (sent and (GetTime() - sent) < 2) then
        GB._conversation = GB._conversation or {}
        GB._conversation[name] = GetTime()
    end
end)

-- Outstanding invites we've sent (by name), so we never invite past a role's cap
-- while people are still accepting and haven't shown up in the roster yet.
local pending = {}   -- [name] = { role = <role>, at = <time> }
function GB:MarkPending(name, role)
    pending[name] = { role = role, at = GetTime() }
end

-- Applicant queue for manual-invite mode: people who whispered to join, with the
-- role/aura/looms they reported, shown in the Applicants window with Invite buttons.
GB.applicants = GB.applicants or {}
function GB:AddApplicant(name, info)
    if self.rosterByName[name] then return end   -- already in the group
    local a = self.applicants[name] or { time = GetTime() }
    for k, v in pairs(info) do if v ~= nil then a[k] = v end end
    self.applicants[name] = a
end
function GB:RemoveApplicant(name)
    self.applicants[name] = nil
end
local function pendingCount(role)
    local now = GetTime()
    local n = 0
    for nm, p in pairs(pending) do
        if GB.rosterByName[nm] or (now - p.at) > 120 then
            pending[nm] = nil            -- joined, or invite went stale
        elseif p.role == role then
            n = n + 1
        end
    end
    return n
end

-- Can we invite this dps right now? Aura-dps are prioritised and may take the
-- reserved spots; non-aura dps are held out of the last `reserveDps` spots until
-- tanks and healers are full.
local function dpsSpotAvailable(status, claim)
    local need = status.need
    local dpsRoom = (need.dps or 0) - pendingCount("dps")
    if dpsRoom <= 0 then return false end
    if claim.aura then return true end
    local thFull = ((need.tanks or 0) - pendingCount("tank")) <= 0
               and ((need.healers or 0) - pendingCount("healer")) <= 0
    local reserve = thFull and 0 or math.min(GB.db.recruit.reserveDps or 0, status.comp.dps or 0)
    return (dpsRoom - reserve) > 0
end

local function groupsList(status)
    local t = {}
    for _, g in ipairs(status.missingGroups) do t[#t + 1] = "G" .. g end
    return table.concat(t, "/")
end

-- Group letter(s) a member's subgroup maps to, e.g. "G2".
local function groupLabel(sub) return "G" .. tostring(sub or 1) end

-- Handle a whisper from someone already in the group: record any role / aura /
-- looms they mention (all at once). Returns true if we consumed the message.
local function handleGroupMemberReply(name, parsed)
    local entry = GB.rosterByName[name]
    local c = {}
    if parsed.namedRole then
        c.role = parsed.roles.tank and "tank" or parsed.roles.healer and "healer" or "dps"
    end
    if parsed.aura then
        c.aura = true
    elseif parsed.auraNo or (parsed.bareNo and (askedAura[name] or checkAsked[name])) then
        c.aura = false
    end
    if parsed.looms then c.looms = true end
    if not next(c) then return false end

    GB:SetClaim(name, c)
    local bits = {}
    if c.role then bits[#bits + 1] = c.role end
    if c.aura == true then bits[#bits + 1] = "aura for " .. groupLabel(entry and entry.subgroup) end
    if c.aura == false then bits[#bits + 1] = "no aura" end
    GB:Reply(name, ("%s: Got it — %s. Thanks!"):format(GB:Tag(), table.concat(bits, ", ")))
    return true
end

-- While auras are still missing, ask group members in uncovered groups whether
-- they have one, so coverage fills in as the raid forms.
function GB:PollAuras()
    if not (self.db and self.db.active and self.db.recruit.askAura) then return end
    local now = GetTime()
    if self._lastAuraPoll and (now - self._lastAuraPoll) < 3 then return end
    self._lastAuraPoll = now

    local status = self:GetStatus()
    if status.auraNeed <= 0 then return end
    local missing = {}
    for _, g in ipairs(status.missingGroups) do missing[g] = true end

    local me = self:MyName()
    for _, m in ipairs(self.roster) do
        if m.name ~= me and missing[m.subgroup] then
            local c = self.claims[m.name]
            local known = c and c.aura ~= nil            -- true or false = answered
            -- Ask each person only ONCE (don't nag non-responders), and ask if
            -- THEY have an aura (not "anyone in your group") so replies are theirs.
            if not known and not askedAura[m.name] then
                askedAura[m.name] = now
                self:Reply(m.name, ("%s: do YOU have an aura for your group (%s)? Reply 'aura' or 'no'."):format(
                    self:Tag(), groupLabel(m.subgroup)))
            end
        end
    end
end

-- Manual aura check: print current per-group coverage to you and ask the raid
-- (in /raid) for anyone with an aura to report. Bound to /gb aura check and the
-- status window button.
function GB:AuraCheck()
    if not self:CanLead() then
        self:Print("you need to be raid/party leader or assist to run a role/aura check.")
        return
    end
    self:RefreshRoster()
    local comp = self.db.comp
    local nGroups = comp.auras or 0

    -- known aura holders by subgroup
    local byGroup = {}
    for _, m in ipairs(self.roster) do
        local c = self.claims[m.name]
        if c and c.aura then
            local g = m.subgroup or 1
            byGroup[g] = byGroup[g] or {}
            byGroup[g][#byGroup[g] + 1] = m.name
        end
    end

    -- report to yourself
    local covered, missing = 0, {}
    self:Print("Aura check:")
    for g = 1, nGroups do
        if byGroup[g] then
            covered = covered + 1
            self:Print(("  G%d: |cff55ff55%s|r"):format(g, table.concat(byGroup[g], ", ")))
        else
            missing[#missing + 1] = "G" .. g
            self:Print(("  G%d: |cffff5555none known|r"):format(g))
        end
    end
    self:Print(("  %d/%d groups covered."):format(covered, nGroups))

    -- ask the raid
    local msg
    if #missing == 0 then
        msg = ("Aura check: all %d groups have an aura. Whisper me 'aura' or 'no' to update."):format(nGroups)
    else
        msg = ("Aura check! Still need an aura for %s — whisper me 'aura' if you have one for your group."):format(
            table.concat(missing, ", "))
    end
    local chan = GetNumRaidMembers() > 0 and "RAID" or (GetNumPartyMembers() > 0 and "PARTY" or "SAY")
    SendChatMessage(msg, chan)

    -- Whisper anyone we don't have full info on — role (esp. hand-invited people
    -- with no recorded role) and/or aura for an uncovered group.
    local uncovered = {}
    for g = 1, nGroups do if not byGroup[g] then uncovered[g] = true end end
    local me = self:MyName()
    local now = GetTime()
    local asked = 0
    for _, m in ipairs(self.roster) do
        if m.name ~= me and (not checkAsked[m.name] or (now - checkAsked[m.name]) > 10) then
            local c = self.claims[m.name]
            local needRole = not (c and c.role)
            local auraUnknown = not (c and c.aura ~= nil)
            local needAura = self.db.recruit.askAura and auraUnknown and uncovered[m.subgroup or 1]
            if needRole or needAura then
                checkAsked[m.name] = now
                if needAura then askedAura[m.name] = now end   -- so a "no" reply counts
                local q
                if needRole and needAura then
                    q = ("what's your role (tank/heals/dps) and do you have an aura for %s? Reply e.g. 'dps aura' or 'tank no'."):format(groupLabel(m.subgroup))
                elseif needRole then
                    q = "what's your role? Reply tank, heals or dps."
                else
                    q = ("do you have an aura for your group (%s)? Reply 'aura' or 'no'."):format(groupLabel(m.subgroup))
                end
                self:Reply(m.name, self:Tag() .. ": " .. q)
                asked = asked + 1
            end
        end
    end
    if asked > 0 then
        self:Print(("asked %d member(s) for role/aura info."):format(asked))
    end
end

GB:On("CHAT_MSG_WHISPER", function(_, msg, author)
    if not (GB.db and GB.db.active) then return end
    -- Only recruit when you can actually run the group (leader/assist/solo), so it
    -- stays silent when you join a group you don't lead.
    if not GB:CanLead() then return end
    if not author or author == "" then return end
    -- Never react to another GroupBuilder's messages (all start with our tag) —
    -- otherwise two addon users whisper each other in an infinite loop.
    if msg:find("^GroupBuilder by ") then return end
    local name = GB:NormName(author)

    -- Failsafe: anyone who missed a reform invite can whisper "reform" for one.
    if msg:lower():find("reform") then
        if GB._lastDinger and name == GB._lastDinger then
            -- don't re-invite the person we just removed for hitting max level
            GB:Reply(name, GB:Tag() .. ": you hit max level — staying out so the mobs don't scale. GG!")
        else
            InviteUnit(name)
            GB:Reply(name, GB:Tag() .. ": invite sent — accept to rejoin!")
        end
        return
    end

    if not GB.db.recruit.autoReply then return end

    local parsed = parseWhisper(msg)

    -- Members already in the group: treat their whisper as an aura/role answer.
    if GB.rosterByName[name] then
        if handleGroupMemberReply(name, parsed) then
            GB:RefreshRoster(); GB:UpdateAnnounce(); GB:RefreshUI()
        end
        return
    end

    -- Someone on the reform list (a member we just kicked): re-invite them, no
    -- recruit prompt — they're already known with a role.
    if GB._reformList and GB._reformList[name] then
        InviteUnit(name)
        GB:Reply(name, GB:Tag() .. ": re-inviting you — accept to rejoin!")
        return
    end

    -- If you're just chatting with this person, don't auto-recruit them.
    if GB._conversation and GB._conversation[name] then return end

    if not (parsed.namedRole or parsed.joinish or parsed.aura or parsed.negative) then
        return -- looks like a normal conversation, stay quiet
    end

    -- Reserved friend: always get them in, bypassing caps/cooldown/aura-wait.
    if GB.db.friends[name] then
        local fstatus = GB:GetStatus()
        local frole = (parsed.namedRole and chooseRole(parsed, fstatus)) or GB.db.friends[name]
        local c = { role = frole }
        if parsed.aura then c.aura = true elseif parsed.auraNo or parsed.bareNo then c.aura = false end
        if parsed.looms then c.looms = true end
        GB:SetClaim(name, c)
        if GB.db.recruit.autoInvite then
            pending[name] = { role = frole, at = GetTime() }
            GB:InviteApplicant(name, frole)
        else
            GB:Reply(name, GB:Tag() .. ": you're on the reserved list — invite incoming!")
        end
        GB:RefreshRoster(); GB:UpdateAnnounce(); GB:RefreshUI()
        return
    end

    -- cooldown: informative answers (role / aura / no / looms) always go through
    -- so we can react to "do you have an aura?" replies.
    local now = GetTime()
    local cd = GB.db.recruit.cooldown or 20
    local informative = parsed.namedRole or parsed.aura or parsed.negative or parsed.looms
    if lastReply[name] and (now - lastReply[name]) < cd and not informative then
        return
    end
    lastReply[name] = now

    local status = GB:GetStatus()

    -- Group is full (or nothing left to recruit) — just say so.
    if status.full or GB:NeedSummary(status, { short = true }) == "" then
        GB:ReplyOnce(name, GB:Tag() .. ": we're full — thanks for whispering!")
        return
    end

    -- Their role: from this message, or one they told us earlier (so a later
    -- "aura"/"no" reply still maps to the right spot). Applicants aren't in the
    -- roster yet, so their earlier claim lives in the per-char DB.
    local prior = GB.claims[name] or (GB.cdb.claims and GB.cdb.claims[name])
    local role = parsed.namedRole and chooseRole(parsed, status) or (prior and prior.role)

    -- Record what they told us this time.
    local c = {}
    if role then c.role = role end
    if parsed.aura then c.aura = true elseif parsed.auraNo or parsed.bareNo then c.aura = false end
    if parsed.looms then c.looms = true end
    if next(c) then GB:SetClaim(name, c) end
    local claim = GB.claims[name] or (GB.cdb.claims and GB.cdb.claims[name]) or {}

    if not role then
        GB:ReplyOnce(name, GB:RecruitPrompt(status))   -- ask for a role, once
        GB:RefreshRoster(); GB:UpdateAnnounce(); GB:RefreshUI()
        return
    end

    -- Manual-invite mode: don't auto-invite; queue them in the Applicants list
    -- (with whatever role/aura/looms they reported) for you to pick from.
    if GB.db.recruit.manualInvite then
        GB:AddApplicant(name, { role = role, aura = claim.aura, looms = claim.looms })
        local ask = ""
        if GB.db.recruit.askAura and claim.aura == nil then
            ask = " Do you have an aura? Reply 'aura' or 'no'."
            askedAura[name] = GetTime()
        end
        GB:ReplyOnce(name, GB:Tag() .. ": you're on the list — the leader will invite shortly." .. ask)
        if GB.RefreshApplicants then GB:RefreshApplicants() end
        GB:RefreshRoster(); GB:UpdateAnnounce(); GB:RefreshUI()
        return
    end

    -- Random applicants recruit against recruitNeed (need minus friend reserves),
    -- so we don't give a friend's reserved slot to a stranger.
    local recruitNeed = status.recruitNeed or status.need
    local rk = NEED_KEY[role]
    local roleNeeded = rk and ((recruitNeed[rk] or 0) - pendingCount(role)) > 0
    local auraKnown = (claim.aura ~= nil)                 -- true or false = answered
    local auraBlocks = status.auraRequired and not claim.aura

    if not GB.db.recruit.autoInvite then
        GB:ReplyOnce(name, ("%s: Thanks! We still need: %s."):format(GB:Tag(), GB:NeedSummary(status, { short = true })))
    elseif not roleNeeded then
        -- role already full (or fully committed) — never over-invite it
        GB:ReplyOnce(name, ("%s: Thanks! We're set on %s. We still need: %s."):format(
            GB:Tag(), NEED_KEY[role] or role, GB:NeedSummary(status, { short = true })))
    elseif auraBlocks then
        -- last spots must bring an aura, and they can't
        GB:ReplyOnce(name, ("%s: Our last %d spot(s) need an aura for %s — whisper 'aura%s' if you can bring one!"):format(
            GB:Tag(), status.auraNeed, groupsList(status),
            (GB:AnyLooms() or GB.db.recruit.askLooms) and " looms" or ""))
    elseif role == "dps" and GB.db.recruit.askAura and status.auraNeed > 0 and not auraKnown then
        -- DPS only: wait for an aura answer before committing a spot, so we don't
        -- fill the plentiful dps slots without auras. Tanks/healers are scarce, so
        -- we invite them immediately (their aura is asked once they're in-group).
        GB:ReplyOnce(name, ("%s: Got a dps spot! Do you have an aura for your group? Reply 'aura' or 'no'."):format(GB:Tag()))
    elseif role == "dps" and not dpsSpotAvailable(status, claim) then
        -- hold the last few dps spots for aura-bringers / until tanks+heals fill
        GB:ReplyOnce(name, ("%s: Thanks! Holding our last dps spots — whisper 'aura' if you have one and I'll get you in!"):format(GB:Tag()))
    else
        pending[name] = { role = role, at = GetTime() }
        GB:InviteApplicant(name, role)
    end

    GB:RefreshRoster(); GB:UpdateAnnounce(); GB:RefreshUI()
end)

-- The question we ask an applicant who didn't name a role. We ask for their
-- role generically (never assume tank), plus aura/heirlooms per the toggles.
function GB:RecruitPrompt(status)
    status = status or self:GetStatus()
    local summary = self:NeedSummary(status, { short = true })
    if summary == "" then
        return self:Tag() .. ": We're basically full — thanks!"
    end

    local askAura = self.db.recruit.askAura and status.auraNeed > 0

    -- Ask role, and (if we still need auras) whether they have one, with a clear
    -- example so they know how to reply.
    local question, example
    if askAura then
        question = "What role are you — tank, heals or dps — and do you have an aura?"
        example = " Reply e.g. 'dps aura' or 'tank no aura'."
    else
        question = "What role are you — tank, heals or dps?"
        example = " Reply with your role."
    end

    local reply = ("We still need %s. %s%s"):format(summary, question, example)
    if askAura and status.auraRequired then
        reply = reply .. " (an aura is required for our last spot(s)!)"
    end
    return self:Tag() .. ": " .. reply
end
