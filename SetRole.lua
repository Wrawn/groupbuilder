-- GroupBuilder :: SetRole.lua
-- A little form to manually set a player's role + aura (handy when you invite
-- someone by hand). Name box + Role dropdown + Has-aura dropdown + Set button.

local addonName, GB = ...

local frame
local selRole, selAura = "dps", false

local function build()
    frame = CreateFrame("Frame", "GroupBuilderSetRole", UIParent)
    frame:SetWidth(250); frame:SetHeight(180)
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
    title:SetPoint("TOP", 0, -12); title:SetText("Set Role / Aura")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- name
    local nlbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nlbl:SetPoint("TOPLEFT", 18, -42); nlbl:SetText("Name")
    local eb = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    eb:SetAutoFocus(false); eb:SetHeight(18); eb:SetWidth(140)
    eb:SetPoint("LEFT", nlbl, "RIGHT", 16, 0)
    frame.nameBox = eb

    -- role dropdown
    local rlbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rlbl:SetPoint("TOPLEFT", 18, -74); rlbl:SetText("Role")
    local rdd = CreateFrame("Frame", "GroupBuilderRoleDD", frame, "UIDropDownMenuTemplate")
    rdd:SetPoint("LEFT", rlbl, "RIGHT", 0, -2)
    UIDropDownMenu_SetWidth(rdd, 90)
    UIDropDownMenu_Initialize(rdd, function()
        for _, opt in ipairs({ { t = "DPS", v = "dps" }, { t = "Tank", v = "tank" }, { t = "Healer", v = "healer" } }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.t
            info.func = function() selRole = opt.v; UIDropDownMenu_SetText(rdd, opt.t) end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(rdd, "DPS")

    -- aura dropdown (defaults to No)
    local albl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    albl:SetPoint("TOPLEFT", 18, -104); albl:SetText("Has aura")
    local add = CreateFrame("Frame", "GroupBuilderAuraDD", frame, "UIDropDownMenuTemplate")
    add:SetPoint("LEFT", albl, "RIGHT", 0, -2)
    UIDropDownMenu_SetWidth(add, 90)
    UIDropDownMenu_Initialize(add, function()
        for _, opt in ipairs({ { t = "No", v = false }, { t = "Yes", v = true } }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.t
            info.func = function() selAura = opt.v; UIDropDownMenu_SetText(add, opt.t) end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(add, "No")

    -- set button
    local set = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    set:SetWidth(90); set:SetHeight(22); set:SetPoint("BOTTOM", 0, 16); set:SetText("Set")
    set:SetScript("OnClick", function()
        local name = frame.nameBox:GetText()
        if not name or name:gsub("%s", "") == "" then GB:Print("enter a name first."); return end
        name = GB:NormName(name)
        GB:SetClaim(name, { role = selRole, aura = selAura })
        GB:Print(("set |cffffff00%s|r = %s%s."):format(name, selRole, selAura and " + aura" or ", no aura"))
        GB:UpdateAnnounce(); GB:RefreshUI()
        frame.nameBox:SetText("")
        frame:Hide()
    end)
    frame.setButton = set

    GB.setRoleFrame = frame
end

function GB:ShowSetRole()
    if not frame then build() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
