-- GroupBuilder :: Options.lua
-- A movable config window opened with /gb. Every setting the slash commands
-- expose is available here as a checkbox / field / cycle button, with a live
-- preview of the LFM line at the bottom.

local addonName, GB = ...

local frame
local refreshers = {}   -- functions that sync each widget from GB.db
local preview

-- Re-apply settings everywhere and refresh the widgets + preview.
local function apply()
    GB:UpdateAnnounce()
    GB:RefreshUI()
    GB:RefreshOptions()
end

-- ---- widget builders -------------------------------------------------------
local CYCLE_CHANNELS = { "SAY", "YELL", "PARTY", "RAID", "GUILD", "CHANNEL" }

local function makeHeader(text, x, y)
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    fs:SetTextColor(1, 0.82, 0)
end

local function makeCheck(label, x, y, get, set)
    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetWidth(22); cb:SetHeight(22)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); apply() end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(get() and true or false) end
    return cb
end

local function makeEdit(label, x, y, width, get, set, numeric)
    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(label)
    local eb = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetHeight(18); eb:SetWidth(width)
    eb:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    if numeric then
        -- numbers sit centered in a snug box so there's no trailing gap
        eb:SetNumeric(true)
        eb:SetJustifyH("CENTER")
        eb:SetMaxLetters(3)
    else
        eb:SetJustifyH("LEFT")
    end
    local function commit()
        local t = eb:GetText()
        if numeric then set(tonumber(t) or 0) else set(t) end
        eb:ClearFocus()
        apply()
    end
    eb:SetScript("OnEnterPressed", commit)
    eb:SetScript("OnEditFocusLost", commit)
    eb:SetScript("OnEscapePressed", function() eb:ClearFocus(); GB:RefreshOptions() end)
    refreshers[#refreshers + 1] = function() eb:SetText(tostring(get() or "")) end
    return eb, lbl
end

local function makeCycle(label, x, y, width, values, get, set)
    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(label)
    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btn:SetHeight(20); btn:SetWidth(width)
    btn:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    btn:SetScript("OnClick", function()
        local cur, idx = get(), 1
        for i, v in ipairs(values) do if v == cur then idx = i break end end
        idx = (idx % #values) + 1
        set(values[idx]); apply()
    end)
    refreshers[#refreshers + 1] = function() btn:SetText(tostring(get())) end
    return btn
end

local function makeButton(label, x, y, width, onClick)
    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetHeight(22); btn:SetWidth(width)
    btn:SetText(label)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- Channel picker: a dropdown of SAY/YELL/PARTY/RAID/GUILD plus every chat channel
-- you're currently in (parsed from GetChannelList), so you never type a name.
local function announceLabel()
    local a = GB.db.announce
    if a.type == "CHANNEL" then return a.channelName or "(pick a channel)" end
    return a.type
end

local function makeChannelDropdown(label, x, y)
    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", x, y); lbl:SetText(label)
    local dd = CreateFrame("Frame", "GroupBuilderChannelDD", frame, "UIDropDownMenuTemplate")
    dd:SetPoint("LEFT", lbl, "RIGHT", -6, -2)
    UIDropDownMenu_SetWidth(dd, 130)
    UIDropDownMenu_Initialize(dd, function()
        for _, t in ipairs({ "SAY", "YELL", "PARTY", "RAID", "GUILD" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = t
            info.func = function() GB.db.announce.type = t; UIDropDownMenu_SetText(dd, t); apply() end
            UIDropDownMenu_AddButton(info)
        end
        local list = { GetChannelList() }   -- id1, name1, id2, name2, ...
        for i = 2, #list, 2 do
            local nm = list[i]
            if nm and nm ~= "" then
                local info = UIDropDownMenu_CreateInfo()
                info.text = nm
                info.func = function()
                    GB.db.announce.type = "CHANNEL"; GB.db.announce.channelName = nm
                    UIDropDownMenu_SetText(dd, nm); apply()
                end
                UIDropDownMenu_AddButton(info)
            end
        end
    end)
    UIDropDownMenu_SetText(dd, announceLabel())
    refreshers[#refreshers + 1] = function() UIDropDownMenu_SetText(dd, announceLabel()) end
    return dd
end

-- ---- build -----------------------------------------------------------------
-- Self role <-> label mapping for the "You" cycle button.
local SELF_ROLES = { "None", "Tank", "Healer", "DPS" }
local LABEL_TO_ROLE = { None = nil, Tank = "tank", Healer = "healer", DPS = "dps" }
local ROLE_TO_LABEL = { tank = "Tank", healer = "Healer", dps = "DPS" }

local function build()
    frame = CreateFrame("Frame", "GroupBuilderOptions", UIParent)
    frame:SetWidth(340); frame:SetHeight(660)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.92)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("GroupBuilder")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)

    local L = 20                 -- left column x
    local y = -40                -- layout cursor (advanced downward)
    local function nl(step) local cur = y; y = y - (step or 24); return cur end
    local function gap(step) y = y - (step or 8) end

    makeCheck("|cff33ff99Active|r (auto reply / invite / reform)", L, nl(28),
        function() return GB.db.active end,
        function(v) GB.db.active = v; if v and GB.NotifyActive then GB:NotifyActive() end end)

    -- ---- You ----
    makeHeader("You (your own slot)", L, nl(22))
    makeCycle("My role", L, nl(26), 80, SELF_ROLES,
        function() local c = GB:GetSelfClaim(); return (c and ROLE_TO_LABEL[c.role]) or "None" end,
        function(v) GB:SetSelfField("role", LABEL_TO_ROLE[v]) end)
    makeCheck("I am bringing an aura", L, nl(22),
        function() local c = GB:GetSelfClaim(); return c and c.aura end,
        function(v) GB:SetSelfField("aura", v or nil) end)

    -- ---- Target comp ----
    gap()
    makeHeader("Target comp", L, nl(22))
    local compRow = nl(22)
    makeEdit("Tanks", L, compRow, 32,
        function() return GB.db.comp.tanks end,
        function(v) GB.db.comp.tanks = math.max(0, math.floor(v)); GB.db.comp.size = GB.db.comp.tanks + GB.db.comp.healers + GB.db.comp.dps end, true)
    makeEdit("Healers", L + 140, compRow, 32,
        function() return GB.db.comp.healers end,
        function(v) GB.db.comp.healers = math.max(0, math.floor(v)); GB.db.comp.size = GB.db.comp.tanks + GB.db.comp.healers + GB.db.comp.dps end, true)
    local compRow2 = nl(24)
    makeEdit("DPS", L, compRow2, 32,
        function() return GB.db.comp.dps end,
        function(v) GB.db.comp.dps = math.max(0, math.floor(v)); GB.db.comp.size = GB.db.comp.tanks + GB.db.comp.healers + GB.db.comp.dps end, true)
    makeEdit("Auras", L + 140, compRow2, 32,
        function() return GB.db.comp.auras end,
        function(v) GB.db.comp.auras = math.max(0, math.floor(v)) end, true)

    -- ---- Requirements ----
    gap()
    makeHeader("Require heirlooms? (per role)", L, nl(22))
    local loomRow = nl(22)
    makeCheck("Tanks", L, loomRow,
        function() return GB:RoleLooms("tank") end,
        function(v) GB.db.requireLooms.tank = v end)
    makeCheck("Healers", L + 90, loomRow,
        function() return GB:RoleLooms("healer") end,
        function(v) GB.db.requireLooms.healer = v end)
    makeCheck("DPS", L + 200, loomRow,
        function() return GB:RoleLooms("dps") end,
        function(v) GB.db.requireLooms.dps = v end)

    -- ---- Whisper options ----
    gap()
    makeHeader("Whisper options (auto-response)", L, nl(22))
    makeCheck("Auto-reply to whispers", L, nl(22),
        function() return GB.db.recruit.autoReply end,
        function(v) GB.db.recruit.autoReply = v end)
    makeCheck("Auto-invite matching applicants", L, nl(22),
        function() return GB.db.recruit.autoInvite end,
        function(v) GB.db.recruit.autoInvite = v end)
    makeCheck("Manual invite (pick from Applicants list)", L, nl(22),
        function() return GB.db.recruit.manualInvite end,
        function(v) GB.db.recruit.manualInvite = v; if GB.RefreshApplicants then GB:RefreshApplicants() end end)
    makeCheck("Ask if they have an aura?", L, nl(22),
        function() return GB.db.recruit.askAura end,
        function(v) GB.db.recruit.askAura = v end)
    makeCheck("Ask if they have heirlooms?", L, nl(22),
        function() return GB.db.recruit.askLooms end,
        function(v) GB.db.recruit.askLooms = v end)
    makeEdit("Reply cooldown (sec)", L, nl(24), 32,
        function() return GB.db.recruit.cooldown end,
        function(v) GB.db.recruit.cooldown = math.max(0, math.floor(v)) end, true)
    makeEdit("Reserve dps spots (for aura dps)", L, nl(24), 32,
        function() return GB.db.recruit.reserveDps end,
        function(v) GB.db.recruit.reserveDps = math.max(0, math.floor(v)) end, true)

    -- ---- Announce ----
    gap()
    makeHeader("Announce", L, nl(22))
    makeChannelDropdown("Channel", L, nl(30))

    -- ---- Leveling ----
    gap()
    makeHeader("Anti-scaling (reform on max level)", L, nl(22))
    makeCheck("Enable?", L, nl(24),
        function() return GB.db.leveling.enabled end,
        function(v) GB.db.leveling.enabled = v end)
    makeEdit("Kick at level (60 = reform only)", L, nl(24), 32,
        function() return GB.db.leveling.maxLevel end,
        function(v) GB.db.leveling.maxLevel = math.max(1, math.floor(v)) end, true)
    makeButton("Whitelist (exempt from autokick)", L, nl(26), 220, function()
        if GB.ShowWhitelist then GB:ShowWhitelist() end
    end)

    -- ---- Interface ----
    gap()
    makeHeader("Interface", L, nl(22))
    makeCheck("Auto-mark tanks (circle / square)", L, nl(22),
        function() return GB.db.markTanks end,
        function(v) GB.db.markTanks = v; if v and GB.MarkTanks then GB:MarkTanks() end end)
    makeCheck("Hide minimap button", L, nl(22),
        function() return GB.db.minimap.hide end,
        function(v) GB.db.minimap.hide = v; if GB.RefreshMinimap then GB:RefreshMinimap() end end)

    -- ---- live preview ----
    gap()
    makeHeader("LFM preview", L, nl(20))
    preview = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview:SetPoint("TOPLEFT", L, nl(44))
    preview:SetWidth(frame:GetWidth() - 40)
    preview:SetJustifyH("LEFT")
    preview:SetJustifyV("TOP")
    preview:SetHeight(40)

    -- ---- action buttons ----
    local btnRow = nl(28)
    makeButton("Announce", L, btnRow, 90, function() GB:AnnounceNow() end)
    makeButton("Reform", L + 100, btnRow, 90, function() GB:ReformGroup(nil) end)
    makeButton("Status window", L + 200, btnRow, 100, function()
        GB.db.ui.shown = not GB.db.ui.shown; GB:RefreshUI()
    end)

    -- size the window to fit the content
    frame:SetHeight(-y + 20)
end

-- Sync every widget + the preview from the current DB.
function GB:RefreshOptions()
    if not frame then return end
    for _, f in ipairs(refreshers) do f() end
    if preview then
        preview:SetText(self:BuildAnnounce() or "|cff888888(group full — nothing to announce)|r")
    end
end

-- Open/close the window (bound to /gb).
function GB:ToggleOptions()
    if not frame then build() end
    if frame:IsShown() then
        frame:Hide()
    else
        GB:RefreshOptions()
        frame:Show()
    end
end
