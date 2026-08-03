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
local MAXROWS = 20

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
    frame:SetWidth(250); frame:SetHeight(230); frame:SetPoint("CENTER", 0, -120)
    GB:Skin(frame, 0.92); frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10); title:SetText("Autokick Monitor"); frame.title = title
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() frame:Hide() end)

    for i = 1, MAXROWS do rows[i] = makeRow(i) end

    local pass = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pass:SetWidth(190); pass:SetHeight(22); pass:SetPoint("BOTTOM", 0, 12)
    pass:SetText("Pass Lead & Leave")
    pass:SetScript("OnClick", function() if GB.PassLeadPrompt then GB:PassLeadPrompt() end end)

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
    for i = 1, MAXROWS do
        local fs, e = rows[i], near[i]
        if e then
            local col = e.gap <= 1 and "|cffff5555" or (e.gap <= 3 and "|cffffcc00" or "|cffffffff")
            fs:SetText(("%s%s (%s)|r  — lvl %d"):format(col, e.name, e.role, e.lvl))
            fs:Show()
        else
            fs:Hide()
        end
    end
    frame.title:SetText(("Autokick Monitor (%d near lvl %d)"):format(#near, maxLevel))
    if #near == 0 then rows[1]:SetText("|cff888888(nobody within 5 levels)|r"); rows[1]:Show() end
end

function GB:ShowMonitor()
    if not frame then build() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show(); GB:RefreshMonitor()
    end
end
