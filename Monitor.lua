-- GroupBuilder :: Monitor.lua
-- /gb monitor — a live frame of players within 5 levels of the autokick threshold,
-- plus a private (GB-only) raid-warning-style alert when a tank/healer is autokicked.

local addonName, GB = ...

-- ---------------------------------------------------------------------------
--  Private kick alert (a local RaidWarningFrame lookalike — NOT broadcast)
-- ---------------------------------------------------------------------------
local alert
local function buildAlert()
    alert = CreateFrame("Frame", "GroupBuilderKickAlert", UIParent)
    alert:SetWidth(700); alert:SetHeight(60)
    alert:SetPoint("TOP", 0, -190)
    alert:SetFrameStrata("FULLSCREEN_DIALOG")
    local fs = alert:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 32, "THICKOUTLINE")
    fs:SetPoint("CENTER")
    fs:SetTextColor(1, 0.15, 0.15)
    alert.text = fs
    alert:Hide()
end

-- Show the alert. role/remaining -> "WARNING HEALER AUTOKICKED, 2 HEALERS LEFT!"
function GB:KickAlert(role, remaining)
    if not alert then buildAlert() end
    local up = tostring(role):upper()
    local plural = (remaining == 1) and "" or "S"
    alert.text:SetText(("WARNING %s AUTOKICKED, %d %s%s LEFT!"):format(up, remaining or 0, up, plural))
    alert:Show()
    if GB.After then GB:After(4.5, function() if alert then alert:Hide() end end) end
end

-- ---------------------------------------------------------------------------
--  Monitor frame
-- ---------------------------------------------------------------------------
local frame
local rows = {}
local MAXROWS = 30   -- with font-fit we can show more; capped by what fits the box
local MINROW, MAXROW = 11, 18

-- Given the available vertical space and how many players are near the cutoff, decide
-- how many rows to place, the row height and font size — so rows always fit the box
-- (shrinking as the list grows / the window shrinks) and overflow shows a "+N" line.
function GB:MonitorFit(avail, total)
    avail = math.max(20, avail or 20)
    local capacity = math.max(1, math.min(MAXROWS, math.floor(avail / MINROW)))
    local slots = math.min(math.max(total, 1), capacity)
    local hasMore = total > slots
    local realShown = hasMore and (slots - 1) or slots
    local rowH = math.min(MAXROW, avail / math.max(slots, 1))
    local fontSize = math.max(8, math.min(13, math.floor(rowH) - 2))
    return { slots = slots, realShown = realShown, hasMore = hasMore, rowH = rowH, fontSize = fontSize }
end

local function makeRow(i)
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if i == 1 then fs:SetPoint("TOPLEFT", 16, -40)
    else fs:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -3) end
    fs:SetWidth(210); fs:SetJustifyH("LEFT")
    fs:Hide()
    return fs
end

local function build()
    frame = CreateFrame("Frame", "GroupBuilderMonitor", UIParent)
    frame:SetWidth(GB.db.monitor.width or 250); frame:SetHeight(GB.db.monitor.height or 230); frame:SetPoint("CENTER", 0, -120)
    GB:Skin(frame, 0.55); frame:SetFrameStrata("MEDIUM")   -- match the status window
    frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10); title:SetText("Autokick Monitor"); frame.title = title
    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetWidth(18); close:SetHeight(18); close:SetPoint("TOPRIGHT", -6, -7); close:SetText("X")
    close:SetScript("OnClick", function() frame:Hide() end)
    GB:SkinButton(close, true)   -- muted red, white X

    for i = 1, MAXROWS do rows[i] = makeRow(i) end

    local pass = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pass:SetWidth(190); pass:SetHeight(22); pass:SetPoint("BOTTOM", 0, 12)
    pass:SetText("Pass Lead & Leave")
    pass:SetScript("OnClick", function() if GB.PassLeadPrompt then GB:PassLeadPrompt() end end)
    GB:SkinButton(pass)

    GB.monitorFrame = frame
end

-- Rebuild the list: players within 5 levels of the kick threshold (and under 60).
function GB:RefreshMonitor()
    if not (frame and frame:IsShown()) then return end
    self:RefreshRoster()
    local maxLevel = self.db.leveling.maxLevel or 60
    local near = {}
    for _, m in ipairs(self.roster) do
        local lvl = m.level or 0
        if lvl > 0 and lvl >= (maxLevel - 5) and lvl < 60 then
            local c = self.claims[m.name]
            near[#near + 1] = { name = m.name, role = (c and c.role) or "?", lvl = lvl, gap = maxLevel - lvl }
        end
    end
    table.sort(near, function(a, b) return a.gap < b.gap end)   -- closest to the cutoff first

    -- Fit the rows to the box: shrink the row height + font as more people appear (or
    -- as the window gets shorter) so they never overlap or spill past the bottom. If
    -- there are more than fit even at the minimum size, the last row shows "+N more".
    local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local topPad, bottomPad = 40, 44                 -- title area / Pass-Lead button
    local h = frame.GetHeight and frame:GetHeight()
    local w = frame.GetWidth and frame:GetWidth()
    if type(h) ~= "number" then h = self.db.monitor.height or 230 end
    if type(w) ~= "number" then w = self.db.monitor.width or 250 end
    local avail = math.max(20, h - topPad - bottomPad)
    local total = #near
    local fit = self:MonitorFit(avail, total)
    local slots, realShown, hasMore, rowH, fontSize = fit.slots, fit.realShown, fit.hasMore, fit.rowH, fit.fontSize

    for i = 1, MAXROWS do
        local fs = rows[i]
        if total > 0 and i <= slots then
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 16, -(topPad + (i - 1) * rowH))
            fs:SetWidth(w - 32); fs:SetJustifyH("LEFT")
            if fs.SetFont then fs:SetFont(FONT, fontSize) end
            if hasMore and i == slots then
                fs:SetText(("|cff888888+%d more near cutoff…|r"):format(total - realShown))
            else
                local e = near[i]
                local col = e.gap <= 1 and "|cffff5555" or (e.gap <= 3 and "|cffffcc00" or "|cffffffff")
                fs:SetText(("%s%s (%s)|r — lvl %d"):format(col, e.name, e.role, e.lvl))
            end
            fs:Show()
        else
            fs:Hide()
        end
    end
    frame.title:SetText(("Autokick Monitor (%d near lvl %d)"):format(total, maxLevel))
    if total == 0 then
        rows[1]:ClearAllPoints(); rows[1]:SetPoint("TOPLEFT", 16, -topPad)
        if rows[1].SetFont then rows[1]:SetFont(FONT, 11) end
        rows[1]:SetText("|cff888888(nobody within 5 levels)|r"); rows[1]:Show()
    end
end

-- Apply the configured width / height / scale (live from options), then re-fit rows.
function GB:ApplyMonitorSize()
    if not frame then return end
    frame:SetWidth(self.db.monitor.width or 250)
    frame:SetHeight(self.db.monitor.height or 230)
    if frame.SetScale then frame:SetScale(self.db.monitor.scale or 1.0) end
    self:RefreshMonitor()   -- re-fit the list to the new box
end

function GB:ShowMonitor()
    if not frame then build() end
    GB:ApplyMonitorSize()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show(); GB:RefreshMonitor()
    end
end
