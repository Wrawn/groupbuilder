-- GroupBuilder :: Debug.lua
-- /gb debug — a dry-run panel. Each button computes what GB WOULD do (using the
-- same logic) and shows it in a copy-pasteable text window. Nothing is performed.

local addonName, GB = ...

local function count(t) local n = 0 if t then for _ in pairs(t) do n = n + 1 end end return n end

-- ---------------------------------------------------------------------------
--  Shared copy-paste text window
-- ---------------------------------------------------------------------------
local textFrame
local function buildTextFrame()
    local f = CreateFrame("Frame", "GroupBuilderText", UIParent)
    f:SetWidth(440); f:SetHeight(380); f:SetPoint("CENTER", 220, 0)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.95); f:SetFrameStrata("DIALOG")
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10); f.title = title
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() f:Hide() end)
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 16, -30); hint:SetText("Click in the box, Ctrl+A to select all, Ctrl+C to copy.")

    local sf = CreateFrame("ScrollFrame", "GroupBuilderTextScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 14, -46); sf:SetPoint("BOTTOMRIGHT", -32, 14)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFontObject(ChatFontNormal); eb:SetWidth(390)
    eb:SetScript("OnEscapePressed", function() eb:ClearFocus() end)
    sf:SetScrollChild(eb)
    f.editBox = eb
    textFrame = f
end

function GB:ShowText(title, text)
    if not textFrame then buildTextFrame() end
    textFrame.title:SetText(title or "GroupBuilder")
    textFrame.editBox:SetText(text or "")
    textFrame.editBox:SetCursorPosition(0)
    textFrame:Show()
end

-- ---------------------------------------------------------------------------
--  Dry-run computations (return text; perform nothing)
-- ---------------------------------------------------------------------------
function GB:DryReinvite()
    if not (self._reformList and next(self._reformList)) then
        return "No reform list yet.\n(Reform first; Reinvite is what fires after you leave the instance.)"
    end
    self:RefreshRoster()
    local lines = { "Reinvite would send invites to:" }
    for name, info in pairs(self._reformList) do
        local lvl = (type(info) == "table" and info.level) or 0
        if self.rosterByName[name] then lines[#lines + 1] = "  " .. name .. " — already back (skip)"
        elseif lvl >= 60 then lines[#lines + 1] = "  " .. name .. " — SKIP (level 60, would re-scale)"
        else lines[#lines + 1] = "  " .. name .. " — INVITE" end
    end
    return table.concat(lines, "\n")
end

function GB:DryReform()
    self:RefreshRoster()
    local me = self:MyName()
    local lines = { "Reform = kick EVERYONE, then re-invite all but the level-60. Would kick:" }
    for _, m in ipairs(self.roster) do
        if m.name ~= me then
            local c = self.claims[m.name]
            local reason = (m.level or 0) >= 60 and "hit 60 (NOT re-invited — would re-scale)"
                or "reform kick (re-invited after you leave)"
            lines[#lines + 1] = ("  %s (%s, lvl %d) — %s"):format(m.name, (c and c.role) or "?", m.level or 0, reason)
        end
    end
    if #lines == 1 then lines[#lines + 1] = "  (nobody but you)" end
    return table.concat(lines, "\n")
end

function GB:DryClearComp()
    return ("Clear Comp would reset:\n  tracked roles/auras: %d players -> 0\n  applicant queue: %d -> 0\n  target numbers (T/H/D/auras): KEPT")
        :format(count(self.claims), count(self.applicants))
end

function GB:DrySetRole()
    self:RefreshRoster()
    local me = self:MyName()
    local lines = { "Tracked role / aura per player (and how we know it):" }
    for _, m in ipairs(self.roster) do
        local c = self.claims[m.name]
        local role = (c and c.role) or "unknown"
        local src = (c and c.source) or (m.name == me and "your own slot" or (c and c.role and "self-reported" or "not set"))
        local aura = c and (c.aura == true and "aura" or c.aura == false and "no aura" or "aura unknown") or "aura unknown"
        lines[#lines + 1] = ("  %s: %s  [%s]  |  %s"):format(m.name, role, src, aura)
    end
    return table.concat(lines, "\n")
end

function GB:DryAutokick()
    self:RefreshRoster()
    local s = self:GetStatus()
    local maxLevel = self.db.leveling.maxLevel or 60
    local me = self:MyName()
    local lines = {
        ("Group %d/%d  |  Kick at level: %d  |  Anti-scaling: %s  |  you lead: %s"):format(
            s.headcount, s.comp.size or s.headcount, maxLevel,
            tostring(self.db.leveling.enabled), tostring(self:CanLead())),
        maxLevel >= 60 and "Early autokick OFF — set 'Kick at level' below 60 to enable it."
            or "Early autokick ON.",
        "",
        "Player               Lvl  Gap  Role     Aura  Autokick",
        "------               ---  ---  ----     ----  --------",
    }
    for _, m in ipairs(self.roster) do
        local c = self.claims[m.name]
        local role = (c and c.role) or "?"
        local aura = c and (c.aura == true and "Y" or c.aura == false and "N" or "?") or "?"
        local lvl = m.level or 0
        local st
        if m.name == me then st = "(you)"
        elseif self:IsWhitelisted(m.name) then st = "whitelisted (exempt)"
        elseif lvl >= 60 then st = "at 60 -> REFORM"
        elseif maxLevel < 60 and lvl >= maxLevel then st = "ELIGIBLE (>= kick level)"
        else st = "-" end
        lines[#lines + 1] = ("%-20s %3d  %3d  %-7s  %-3s   %s"):format(
            m.name:sub(1, 20), lvl, maxLevel - lvl, role, aura, st)
    end
    return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
--  Debug panel
-- ---------------------------------------------------------------------------
local dbg
local function buildDebug()
    dbg = CreateFrame("Frame", "GroupBuilderDebug", UIParent)
    dbg:SetWidth(240); dbg:SetHeight(240); dbg:SetPoint("CENTER", -220, 0)
    dbg:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    dbg:SetBackdropColor(0, 0, 0, 0.92); dbg:SetFrameStrata("DIALOG")
    dbg:EnableMouse(true); dbg:SetMovable(true); dbg:RegisterForDrag("LeftButton")
    dbg:SetScript("OnDragStart", dbg.StartMoving); dbg:SetScript("OnDragStop", dbg.StopMovingOrSizing)

    local title = dbg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10); title:SetText("GB Debug (dry-run)")
    local close = CreateFrame("Button", nil, dbg, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() dbg:Hide() end)
    local hint = dbg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", 0, -28); hint:SetWidth(220); hint:SetText("Shows what GB WOULD do — nothing is performed.")

    local function b(label, y, fn)
        local btn = CreateFrame("Button", nil, dbg, "UIPanelButtonTemplate")
        btn:SetWidth(200); btn:SetHeight(22); btn:SetPoint("TOP", 0, y); btn:SetText(label)
        btn:SetScript("OnClick", fn)
        return btn
    end
    b("Reinvite (dry-run)",   -46, function() GB:ShowText("Reinvite — dry run",   GB:DryReinvite()) end)
    b("Reform (dry-run)",     -72, function() GB:ShowText("Reform — dry run",     GB:DryReform()) end)
    b("Clear Comp (dry-run)", -98, function() GB:ShowText("Clear Comp — dry run", GB:DryClearComp()) end)
    b("Set Role (dry-run)",  -124, function() GB:ShowText("Set Role — dry run",   GB:DrySetRole()) end)
    b("Autokick state",      -156, function() GB:ShowText("Autokick state",       GB:DryAutokick()) end)
end

function GB:ShowDebug()
    if not dbg then buildDebug() end
    if dbg:IsShown() then dbg:Hide() else dbg:Show() end
end
