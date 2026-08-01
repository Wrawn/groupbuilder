-- GroupBuilder :: Panel.lua
-- Two extra entry points to the options window:
--   1) a category in Esc -> Interface -> AddOns
--   2) a draggable minimap button
-- Both just open GB:ToggleOptions().

local addonName, GB = ...

-- ---------------------------------------------------------------------------
--  Interface Options category (Esc -> Interface -> AddOns -> GroupBuilder)
-- ---------------------------------------------------------------------------
local function buildInterfacePanel()
    local panel = CreateFrame("Frame", "GroupBuilderInterfacePanel", UIParent)
    panel.name = "GroupBuilder"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("GroupBuilder")

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetText("Builds a leveling raid comp from whispers, keeps an auto-updating "
        .. "LFM macro, and reforms the group when someone hits max level.")

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetWidth(200); open:SetHeight(24)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    open:SetText("Open GroupBuilder Options")
    open:SetScript("OnClick", function() GB:ToggleOptions() end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 2, -10)
    hint:SetText("Or type /gb, or click the minimap button.")

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
    GB.interfacePanel = panel
end

-- ---------------------------------------------------------------------------
--  Minimap button
-- ---------------------------------------------------------------------------
local button

local function updatePosition()
    if not button then return end
    local angle = math.rad(GB.db.minimap.angle or 200)
    local r = 80
    button:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(angle), r * math.sin(angle))
end

local function onDragUpdate(self)
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px, py = px / scale, py / scale
    GB.db.minimap.angle = math.deg(math.atan2(py - my, px - mx))
    updatePosition()
end

local function buildMinimapButton()
    button = CreateFrame("Button", "GroupBuilderMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetWidth(31); button:SetHeight(31)
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    -- dark round-ish icon with "GB" over it
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Buttons\\WHITE8X8")
    icon:SetVertexColor(0.06, 0.06, 0.06, 1)
    icon:SetWidth(19); icon:SetHeight(19)
    icon:SetPoint("CENTER", 0, 1)

    local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("CENTER", icon, "CENTER", 0, 0)
    label:SetText("GB")
    label:SetTextColor(0.2, 1, 0.6)

    -- the standard round minimap-button border ring
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53); overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)

    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    button:SetScript("OnClick", function(_, clicked)
        if clicked == "RightButton" then
            GB.db.active = not GB.db.active
            GB:Print("master switch", GB.db.active and "|cff55ff55on|r" or "|cffff5555off|r")
            if GB.db.active and GB.NotifyActive then GB:NotifyActive() end
            GB:UpdateAnnounce(); GB:RefreshUI(); GB:RefreshOptions()
        else
            GB:ToggleOptions()
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("GroupBuilder")
        GameTooltip:AddLine("Left-click: open options", 1, 1, 1)
        GameTooltip:AddLine("Right-click: toggle Active", 1, 1, 1)
        GameTooltip:AddLine("Drag: move around minimap", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    updatePosition()
    GB.minimapButton = button
end

-- Apply hide/position from the DB (called on load and when toggled in options).
function GB:RefreshMinimap()
    if not button then return end
    updatePosition()
    if self.db.minimap.hide then button:Hide() else button:Show() end
end

GB:On("PLAYER_LOGIN", function()
    buildInterfacePanel()
    buildMinimapButton()
    GB:RefreshMinimap()
end)
