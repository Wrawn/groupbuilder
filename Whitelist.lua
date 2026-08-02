-- GroupBuilder :: Whitelist.lua
-- A little window to manage the autokick whitelist (players exempt from the
-- sub-60 kick). Add by name or "Add me", remove with the [x] next to each.
-- The /gb whitelist chat commands still work too.

local addonName, GB = ...

local frame
local rows = {}
local MAXROWS = 12

local function addName(name)
    if not name or name:gsub("%s", "") == "" then return end
    name = GB:NormName(name)                 -- case-insensitive, like everywhere else
    GB.db.whitelist = GB.db.whitelist or {}
    GB.db.whitelist[name] = true
    GB:Print(name .. " added to the autokick whitelist.")
    GB:RefreshWhitelist()
end

local function makeRow(i)
    local row = CreateFrame("Frame", nil, frame)
    row:SetWidth(210); row:SetHeight(16)
    if i == 1 then
        row:SetPoint("TOPLEFT", frame.listAnchor, "BOTTOMLEFT", 0, -4)
    else
        row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -2)
    end
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 0, 0); fs:SetWidth(180); fs:SetJustifyH("LEFT")
    row.text = fs
    local x = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    x:SetWidth(18); x:SetHeight(16); x:SetPoint("RIGHT", 0, 0); x:SetText("x")
    x:SetScript("OnClick", function()
        if row.name then GB.db.whitelist[row.name] = nil; GB:RefreshWhitelist() end
    end)
    row.x = x
    row:Hide()
    return row
end

local function build()
    frame = CreateFrame("Frame", "GroupBuilderWhitelist", UIParent)
    frame:SetWidth(250); frame:SetHeight(240)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.92)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -12); title:SetText("Autokick Whitelist")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() frame:Hide() end)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 14, -32); hint:SetWidth(220); hint:SetJustifyH("LEFT")
    hint:SetText("Exempt from the sub-60 autokick. Reserved friends are also exempt.")

    local eb = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    eb:SetAutoFocus(false); eb:SetHeight(18); eb:SetWidth(120)
    eb:SetPoint("TOPLEFT", 16, -56)
    eb:SetScript("OnEnterPressed", function() addName(eb:GetText()); eb:SetText(""); eb:ClearFocus() end)
    frame.nameBox = eb

    local add = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    add:SetWidth(44); add:SetHeight(20); add:SetPoint("LEFT", eb, "RIGHT", 8, 0); add:SetText("Add")
    add:SetScript("OnClick", function() addName(eb:GetText()); eb:SetText("") end)
    frame.addButton = add

    local addMe = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addMe:SetWidth(52); addMe:SetHeight(20); addMe:SetPoint("LEFT", add, "RIGHT", 4, 0); addMe:SetText("Add Me")
    addMe:SetScript("OnClick", function() addName(GB:MyName()) end)

    -- rows anchor
    frame.listAnchor = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.listAnchor:SetPoint("TOPLEFT", 16, -84)
    frame.listAnchor:SetText("|cffffcc00Whitelisted:|r")

    for i = 1, MAXROWS do rows[i] = makeRow(i) end
    GB.whitelistFrame = frame
end

-- Rebuild the list from GB.db.whitelist.
function GB:RefreshWhitelist()
    if not frame then return end
    local list = {}
    for n in pairs(self.db.whitelist or {}) do list[#list + 1] = n end
    table.sort(list)
    for i = 1, MAXROWS do
        local row, name = rows[i], list[i]
        if name then
            row.text:SetText(name); row.name = name; row:Show()
        else
            row.name = nil; row:Hide()
        end
    end
    frame:SetHeight(96 + math.max(1, math.min(#list, MAXROWS)) * 18 + 12)
    if #list == 0 then
        rows[1].text:SetText("|cff888888(none — add a name above)|r"); rows[1].name = nil; rows[1]:Show()
    end
end

function GB:ShowWhitelist()
    if not frame then build() end
    if frame:IsShown() then
        frame:Hide()
    else
        GB:RefreshWhitelist(); frame:Show()
    end
end
