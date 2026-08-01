-- GroupBuilder :: UI.lua
-- A small movable status window: current comp vs target, per-group aura coverage,
-- and buttons to announce / reform.

local addonName, GB = ...

local frame
local AURA_ROWS = 8   -- pool of per-group aura-holder rows

-- Confirmation popup for removing a player's aura status.
StaticPopupDialogs["GROUPBUILDER_REMOVE_AURA"] = {
    text = "Remove aura status from %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        local n = self.data
        if n then
            GB:SetClaim(n, { aura = false })
            GB:Print(n .. " marked as |cffff5555NO aura|r.")
            GB:UpdateAnnounce(); GB:RefreshUI()
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Confirm before a manual reform (it disbands the group).
StaticPopupDialogs["GROUPBUILDER_REFORM"] = {
    text = "Are you sure? This will DISBAND the group.\n\nIf you're trying to bring back players from the previous group, use |cff33ff99Reinvite|r instead.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() GB:ReformGroup(nil) end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
function GB:ConfirmReform()
    if StaticPopup_Show then StaticPopup_Show("GROUPBUILDER_REFORM") else self:ReformGroup(nil) end
end

-- Confirm before clearing the tracked comp.
StaticPopupDialogs["GROUPBUILDER_CLEARCOMP"] = {
    text = "Clear the tracked comp?\n\nThis resets everyone's role and aura (T/H/D counts and aura holders go back to unassigned). Your target numbers are kept.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() GB:ClearComp() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
function GB:ConfirmClearComp()
    if StaticPopup_Show then StaticPopup_Show("GROUPBUILDER_CLEARCOMP") else self:ClearComp() end
end

-- Roles popup (who is tank / healer).
StaticPopupDialogs["GROUPBUILDER_ROLES"] = {
    text = "%s",
    button1 = OKAY,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
function GB:ShowRoles()
    self:RefreshRoster()
    local tanks, heals = {}, {}
    for _, m in ipairs(self.roster) do
        local c = self.claims[m.name]
        local r = c and c.role
        if r == "tank" then tanks[#tanks + 1] = m.name
        elseif r == "healer" then heals[#heals + 1] = m.name end
    end
    local t = #tanks > 0 and table.concat(tanks, ", ") or "-"
    local h = #heals > 0 and table.concat(heals, ", ") or "-"
    StaticPopup_Show("GROUPBUILDER_ROLES",
        ("|cffc79c6eTanks (%d):|r %s\n\n|cff40c7ebHealers (%d):|r %s"):format(#tanks, t, #heals, h))
end

local function savePoint()
    if not (frame and GB.db) then return end
    local point, _, relPoint, x, y = frame:GetPoint()
    GB.db.ui.point = { point, nil, relPoint, x, y }
end

local function createUI()
    frame = CreateFrame("Frame", "GroupBuilderFrame", UIParent)
    frame:SetWidth(240)
    frame:SetHeight(250)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not GB.db.ui.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing(); savePoint()
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("GroupBuilder")
    frame.title = title

    -- close (X) + minimize buttons, top-right
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() GB.db.ui.shown = false; GB:RefreshUI() end)

    local minBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    minBtn:SetWidth(18); minBtn:SetHeight(18)
    minBtn:SetPoint("TOPRIGHT", -26, -7)
    minBtn:SetText("_")
    minBtn:SetScript("OnClick", function()
        GB.db.ui.minimized = not GB.db.ui.minimized
        GB:RefreshUI()
    end)
    frame.minBtn = minBtn

    -- widgets hidden when minimized
    frame.fullOnly = {}

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 12, -30)
    status:SetPoint("TOPRIGHT", -12, -30)
    status:SetJustifyH("LEFT")
    status:SetJustifyV("TOP")
    frame.status = status

    -- per-group aura-holder rows (name + [x] to remove aura), below the status text
    frame.auraRows = {}
    for i = 1, AURA_ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetHeight(16); row:SetWidth(216)
        if i == 1 then
            row:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -4)
        else
            row:SetPoint("TOPLEFT", frame.auraRows[i - 1], "BOTTOMLEFT", 0, 0)
        end
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 0, 0); fs:SetWidth(196); fs:SetJustifyH("LEFT")
        row.text = fs
        local x = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        x:SetWidth(16); x:SetHeight(16); x:SetPoint("RIGHT", 0, 0); x:SetText("x")
        x:SetScript("OnClick", function()
            if row.playerName then
                StaticPopup_Show("GROUPBUILDER_REMOVE_AURA", row.playerName, nil, row.playerName)
            end
        end)
        row.x = x
        row:Hide()
        frame.auraRows[i] = row
    end

    -- manual-invite toggle
    local manual = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    manual:SetWidth(20); manual:SetHeight(20)
    manual:SetPoint("BOTTOMLEFT", 12, 120)
    local mlbl = manual:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mlbl:SetPoint("LEFT", manual, "RIGHT", 2, 0)
    mlbl:SetText("Manual invite (pick from list)")
    manual:SetScript("OnClick", function(self)
        GB.db.recruit.manualInvite = self:GetChecked() and true or false
        if GB.RefreshApplicants then GB:RefreshApplicants() end
        GB:RefreshUI()
    end)
    frame.manualCheck = manual
    frame.fullOnly[#frame.fullOnly + 1] = manual

    -- Call a GB method by name, but degrade gracefully if it isn't loaded (e.g. a
    -- newly-added file the client hasn't picked up until a full restart).
    local function call(method)
        if GB[method] then GB[method](GB)
        else GB:Print("|cffff5555" .. method .. " isn't loaded.|r Fully exit and restart the game client (not just /reload) so new addon files load.") end
    end

    local function btn(text, w, x, y, anchor, method)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetWidth(w); b:SetHeight(22); b:SetPoint(anchor, x, y); b:SetText(text)
        b:SetScript("OnClick", function() call(method) end)
        frame.fullOnly[#frame.fullOnly + 1] = b
        return b
    end

    -- button grid
    btn("Reform", 104, 12, 92, "BOTTOMLEFT", "ConfirmReform")
    btn("Reinvite", 104, -12, 92, "BOTTOMRIGHT", "ReinviteGroup")
    btn("Show Roles", 104, 12, 64, "BOTTOMLEFT", "ShowRoles")
    btn("Set Role / Aura", 104, -12, 64, "BOTTOMRIGHT", "ShowSetRole")
    btn("Role / Aura Check", 104, 12, 36, "BOTTOMLEFT", "AuraCheck")
    btn("Clear Comp", 104, -12, 36, "BOTTOMRIGHT", "ConfirmClearComp")

    -- restore position
    local p = GB.db.ui.point
    frame:ClearAllPoints()
    if p and p[1] then
        frame:SetPoint(p[1], UIParent, p[3] or p[1], p[4] or 0, p[5] or 0)
    else
        frame:SetPoint("CENTER")
    end
    GB.ui = frame
end

function GB:RefreshUI()
    if not self.db then return end
    if not frame then
        if not self.db.ui.shown then return end
        createUI()
    end
    if not self.db.ui.shown then frame:Hide(); return end
    frame:Show()
    if self.RefreshApplicants then self:RefreshApplicants() end

    local s = self:GetStatus()
    local minimized = self.db.ui.minimized
    if frame.minBtn then frame.minBtn:SetText(minimized and "+" or "_") end

    local activeTag = self.db.active and "|cff55ff55active|r" or "|cffff5555paused|r"
    local lines = {}
    lines[#lines + 1] = ("Status: %s   %d/%d"):format(activeTag, s.headcount, s.comp.size or s.headcount)
    lines[#lines + 1] = ("T %d/%d  H %d/%d  D %d/%d  A %d/%d"):format(
        s.have.tanks, s.comp.tanks, s.have.healers, s.comp.healers,
        s.have.dps, s.comp.dps, s.auraHave, s.comp.auras or 0)

    -- Minimized: just the two summary lines; hide rows, buttons and checkbox.
    if minimized then
        frame.status:SetText(table.concat(lines, "\n"))
        for i = 1, AURA_ROWS do frame.auraRows[i]:Hide() end
        for _, w in ipairs(frame.fullOnly) do w:Hide() end
        frame:SetHeight(30 + #lines * 13 + 12)
        return
    end
    for _, w in ipairs(frame.fullOnly) do w:Show() end

    if s.reservedFriends and #s.reservedFriends > 0 then
        local r = {}
        for _, f in ipairs(s.reservedFriends) do r[#r + 1] = ("%s(%s)"):format(f.name, f.role) end
        lines[#lines + 1] = "|cff88bbffReserved:|r " .. table.concat(r, ", ")
    end
    if s.unknown > 0 then
        lines[#lines + 1] = ("|cffaaaaaa%d unassigned|r"):format(s.unknown)
    end
    if s.full then
        lines[#lines + 1] = "|cff55ff55GROUP FULL|r"
    end
    frame.status:SetText(table.concat(lines, "\n"))

    -- Per-group aura coverage as rows, each holder with an [x] to remove aura.
    local byGroup = {}
    for _, m in ipairs(self.roster) do
        local c = self.claims[m.name]
        if c and c.aura then
            local g = m.subgroup or 1
            byGroup[g] = byGroup[g] or {}
            byGroup[g][#byGroup[g] + 1] = m.name
        end
    end
    local entries = {}
    for g = 1, (s.comp.auras or 0) do
        if byGroup[g] then
            for _, nm in ipairs(byGroup[g]) do entries[#entries + 1] = { group = g, name = nm } end
        else
            entries[#entries + 1] = { group = g, name = nil }
        end
    end
    for i = 1, AURA_ROWS do
        local row, e = frame.auraRows[i], entries[i]
        if e and e.name then
            row.text:SetText(("|cff55ff55G%d aura:|r %s"):format(e.group, e.name))
            row.playerName = e.name; row.x:Show(); row:Show()
        elseif e then
            row.text:SetText(("|cffff5555G%d aura: needed|r"):format(e.group))
            row.playerName = nil; row.x:Hide(); row:Show()
        else
            row.playerName = nil; row:Hide()
        end
    end

    -- size the window to fit the (variable) content above the bottom controls
    local visible = math.min(#entries, AURA_ROWS)
    local contentBottom = 30 + #lines * 13 + 6 + visible * 16
    frame:SetHeight(math.max(240, contentBottom + 152))

    if frame.manualCheck then frame.manualCheck:SetChecked(self.db.recruit.manualInvite and true or false) end
end
