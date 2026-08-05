-- GroupBuilder :: SetRole.lua
-- /gb roles (and the status "Edit Roles" button) — an editable table of the current
-- group: one row per player with Name, a Role dropdown, and an Aura (Yes/No) dropdown,
-- so you can fix anyone's tracked role/aura by hand.

local addonName, GB = ...

local frame
local rows = {}
local MAXROWS = 40

local ROLE_OPTS = { { t = "Unknown", v = nil }, { t = "Tank", v = "tank" }, { t = "Healer", v = "healer" }, { t = "DPS", v = "dps" } }
local AURA_OPTS = { { t = "Unknown", v = nil }, { t = "Yes", v = true }, { t = "No", v = false } }
local ROLE_LABEL = { tank = "Tank", healer = "Healer", dps = "DPS" }

local function roleText(role) return ROLE_LABEL[role] or "Unknown" end
local function auraText(a) if a == true then return "Yes" elseif a == false then return "No" else return "Unknown" end end

-- What the Role / Aura dropdowns call (also directly unit-testable).
function GB:EditRole(name, role)
    self:SetClaim(name, { role = role, source = "manual override" })
    self:UpdateAnnounce(); self:RefreshUI(); self:RefreshRosterEditor()
end
function GB:EditAura(name, aura)
    self:SetClaim(name, { aura = aura, source = "manual override" })
    self:UpdateAnnounce(); self:RefreshUI(); self:RefreshRosterEditor()
end

local function makeRow(i)
    local row = CreateFrame("Frame", nil, frame)
    row:SetWidth(360); row:SetHeight(30)
    if i == 1 then row:SetPoint("TOPLEFT", 10, -52)
    else row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, 0) end

    local nm = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nm:SetPoint("LEFT", 6, 0); nm:SetWidth(96); nm:SetJustifyH("LEFT")
    row.nameFS = nm

    local rdd = CreateFrame("Frame", "GroupBuilderRosterRole" .. i, row, "UIDropDownMenuTemplate")
    rdd:SetPoint("LEFT", 92, -1)
    UIDropDownMenu_SetWidth(rdd, 68)
    UIDropDownMenu_Initialize(rdd, function()
        for _, opt in ipairs(ROLE_OPTS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.t
            info.func = function() if row.name then GB:EditRole(row.name, opt.v) end end
            UIDropDownMenu_AddButton(info)
        end
    end)
    row.roleDD = rdd

    local add = CreateFrame("Frame", "GroupBuilderRosterAura" .. i, row, "UIDropDownMenuTemplate")
    add:SetPoint("LEFT", 226, -1)
    UIDropDownMenu_SetWidth(add, 58)
    UIDropDownMenu_Initialize(add, function()
        for _, opt in ipairs(AURA_OPTS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.t
            info.func = function() if row.name then GB:EditAura(row.name, opt.v) end end
            UIDropDownMenu_AddButton(info)
        end
    end)
    row.auraDD = add

    row:Hide()
    return row
end

local function build()
    frame = CreateFrame("Frame", "GroupBuilderRoster", UIParent)
    frame:SetWidth(360); frame:SetHeight(200); frame:SetPoint("CENTER")
    GB:Skin(frame, 0.94); frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10); title:SetText("Raid Roles & Auras")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() frame:Hide() end)

    local function hdr(text, x)
        local h = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", x, -34); h:SetText(text); h:SetTextColor(1, 0.82, 0)
    end
    hdr("Name", 16); hdr("Role", 116); hdr("Aura", 250)

    local empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("TOPLEFT", 16, -54); empty:SetText("(not in a group)")
    frame.empty = empty

    for i = 1, MAXROWS do rows[i] = makeRow(i) end
    GB.rosterFrame = frame
end

function GB:RefreshRosterEditor()
    if not (frame and frame:IsShown()) then return end
    self:RefreshRoster()
    local n = 0
    for i, m in ipairs(self.roster) do
        if i > MAXROWS then break end
        local row = rows[i]
        row.name = m.name
        local c = self.claims[m.name]
        row.nameFS:SetText(m.name)
        UIDropDownMenu_SetText(row.roleDD, roleText(c and c.role))
        UIDropDownMenu_SetText(row.auraDD, auraText(c and c.aura))
        row:Show()
        n = i
    end
    for i = n + 1, MAXROWS do rows[i]:Hide() end
    if frame.empty then if n == 0 then frame.empty:Show() else frame.empty:Hide() end end
    frame:SetHeight(58 + math.max(1, n) * 30 + 10)
end

-- /gb roles and the status "Edit Roles" button both open this.
function GB:ShowRoles()
    if not frame then build() end
    if frame:IsShown() then frame:Hide() else frame:Show(); self:RefreshRosterEditor() end
end

-- Backward-compat: anything that still calls ShowSetRole opens the roster editor.
GB.ShowSetRole = GB.ShowRoles
