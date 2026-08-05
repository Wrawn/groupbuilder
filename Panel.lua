-- GroupBuilder :: Panel.lua
--   1) the Esc -> Interface -> AddOns -> GroupBuilder category, which holds all the
--      settings inline (populated by GB:BuildOptions)
--   2) a draggable minimap button that opens it (left-click) / toggles Active (right-click)

local addonName, GB = ...

-- ---------------------------------------------------------------------------
--  Interface Options category (Esc -> Interface -> AddOns -> GroupBuilder)
-- ---------------------------------------------------------------------------
-- Register one Interface Options category. Children pass the parent's name, which
-- gives the parent a +/- expander and nests them underneath.
local function addCategory(name, parentName, builder)
    local p = CreateFrame("Frame", parentName and nil or "GroupBuilderInterfacePanel", UIParent)
    p.name = name
    if parentName then p.parent = parentName end
    if builder then builder(p) end
    p.refresh = function() if GB.RefreshOptions then GB:RefreshOptions() end end
    p.okay = function() end
    p.cancel = function() end
    -- Repopulate every widget from the DB whenever the panel is actually shown — the
    -- Blizzard `refresh` hook doesn't fire reliably, which left number fields blank.
    p:SetScript("OnShow", function() if GB.RefreshOptions then GB:RefreshOptions() end end)
    if InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(p) end
    return p
end

local function buildInterfacePanel()
    -- Parent node + its sub-pages. Parent must be registered before its children.
    GB.interfacePanel = addCategory("GroupBuilder", nil, function(p) if GB.BuildLanding then GB:BuildLanding(p) end end)
    addCategory("Basic Options", "GroupBuilder", function(p) if GB.BuildOptions then GB:BuildOptions(p) end end)
    addCategory("Window Sizes", "GroupBuilder", function(p) if GB.BuildWindows then GB:BuildWindows(p) end end)
    addCategory("Auto-Kick Whitelist", "GroupBuilder", function(p) if GB.BuildListPanel then GB:BuildListPanel(p, "whitelist") end end)
    addCategory("Auto-Inv Blacklist", "GroupBuilder", function(p) if GB.BuildListPanel then GB:BuildListPanel(p, "blacklist") end end)
    addCategory("Help", "GroupBuilder", function(p) if GB.BuildHelp then GB:BuildHelp(p) end end)
    addCategory("About", "GroupBuilder", function(p) if GB.BuildAbout then GB:BuildAbout(p) end end)

    if GB.RefreshOptions then GB:RefreshOptions() end   -- prime every widget from the DB
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
    button.label = label   -- recolored red/green by RefreshMinimap based on Active

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
            GB:UpdateAnnounce(); GB:RefreshUI(); GB:RefreshOptions(); GB:RefreshMinimap()
        else
            GB.db.ui.shown = not GB.db.ui.shown   -- left-click toggles the status window
            GB:RefreshUI()
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("GroupBuilder")
        GameTooltip:AddLine("Left-click: status window", 1, 1, 1)
        GameTooltip:AddLine("Right-click: toggle Active", 1, 1, 1)
        GameTooltip:AddLine("Drag: move around minimap", 1, 1, 1)
        GameTooltip:AddLine("(/gb for options)", 0.6, 0.6, 0.6)
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
    if button.label then
        if self.db.active then
            button.label:SetTextColor(0.2, 1, 0.4)      -- green = Active on
        else
            button.label:SetTextColor(1, 0.25, 0.25)    -- red = Active off
        end
    end
    if self.db.minimap.hide then button:Hide() else button:Show() end
end

GB:On("PLAYER_LOGIN", function()
    buildInterfacePanel()
    buildMinimapButton()
    GB:RefreshMinimap()
end)
