-- GroupBuilder :: Options.lua
-- Every setting the slash commands expose, built into the Blizzard Interface
-- Options panel (Esc -> Interface -> AddOns -> GroupBuilder) as checkboxes / fields /
-- cycle buttons, with a live LFM preview. Opened with /gb. Settings apply immediately.

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

-- boxOffset: if given, anchor the box a fixed distance right of the label's LEFT edge
-- (so a column of boxes lines up regardless of label width). Otherwise the box just
-- follows the end of the label (fine for long, single labels).
-- InputBoxTemplate anchors its middle fill texture to child textures named
-- "$parentLeft"/"$parentRight" — so each EditBox MUST have a unique name or the
-- fill doesn't render (you get a hollow gap). Hence the counter below.
local editCount = 0
local function makeEdit(label, x, y, width, get, set, numeric, boxOffset)
    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(label)
    editCount = editCount + 1
    local eb = CreateFrame("EditBox", "GroupBuilderOptEdit" .. editCount, frame, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetHeight(18); eb:SetWidth(width)
    if boxOffset then
        eb:SetPoint("LEFT", lbl, "LEFT", boxOffset, 0)
    else
        eb:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    end
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

-- Build every setting straight into the Blizzard Interface Options panel (passed in
-- by Panel.lua). Two columns so it all fits without a scrollbar. Settings apply live.
function GB:BuildOptions(parent)
    frame = parent

    local L1, L2 = 16, 330       -- two column x-origins
    local y1, y2 = -66, -66      -- per-column layout cursors (advance downward)
    local function nl1(s) local c = y1; y1 = y1 - (s or 24); return c end
    local function nl2(s) local c = y2; y2 = y2 - (s or 24); return c end
    local function gap1(s) y1 = y1 - (s or 8) end
    local function gap2(s) y2 = y2 - (s or 8) end

    -- master switch, just under the panel title
    makeCheck("|cff33ff99Active|r (auto reply / invite / reform)", L1, -42,
        function() return GB.db.active end,
        function(v) GB.db.active = v; if v and GB.NotifyActive then GB:NotifyActive() end end)

    -- ===== Column 1 =====
    makeHeader("You (your own slot)", L1, nl1(22))
    makeCycle("My role", L1, nl1(26), 80, SELF_ROLES,
        function() local c = GB:GetSelfClaim(); return (c and ROLE_TO_LABEL[c.role]) or "None" end,
        function(v) GB:SetSelfField("role", LABEL_TO_ROLE[v]) end)
    makeCheck("I am bringing an aura", L1, nl1(22),
        function() local c = GB:GetSelfClaim(); return c and c.aura end,
        function(v) GB:SetSelfField("aura", v or nil) end)

    gap1()
    makeHeader("Target comp", L1, nl1(22))
    -- 2x2 grid: labels at a fixed x, boxes at a fixed x, so all four align.
    local BOX = 58           -- box sits this far right of each label's left edge (clears "Healers")
    local r1 = nl1(24)
    makeEdit("Tanks", L1, r1, 38,
        function() return GB.db.comp.tanks end,
        function(v) GB.db.comp.tanks = math.max(0, math.floor(v)); GB.db.comp.size = GB.db.comp.tanks + GB.db.comp.healers + GB.db.comp.dps end, true, BOX)
    makeEdit("Healers", L1 + 150, r1, 38,
        function() return GB.db.comp.healers end,
        function(v) GB.db.comp.healers = math.max(0, math.floor(v)); GB.db.comp.size = GB.db.comp.tanks + GB.db.comp.healers + GB.db.comp.dps end, true, BOX)
    local r2 = nl1(26)
    makeEdit("DPS", L1, r2, 38,
        function() return GB.db.comp.dps end,
        function(v) GB.db.comp.dps = math.max(0, math.floor(v)); GB.db.comp.size = GB.db.comp.tanks + GB.db.comp.healers + GB.db.comp.dps end, true, BOX)
    makeEdit("Auras", L1 + 150, r2, 38,
        function() return GB.db.comp.auras end,
        function(v) GB.db.comp.auras = math.max(0, math.floor(v)) end, true, BOX)

    gap1()
    makeHeader("Whisper options (auto-response)", L1, nl1(22))
    makeCheck("Auto-reply to whispers", L1, nl1(22),
        function() return GB.db.recruit.autoReply end,
        function(v) GB.db.recruit.autoReply = v end)
    makeCheck("Auto-invite matching applicants", L1, nl1(22),
        function() return GB.db.recruit.autoInvite end,
        function(v) GB.db.recruit.autoInvite = v end)
    makeCheck("Manual invite (pick from Applicants list)", L1, nl1(22),
        function() return GB.db.recruit.manualInvite end,
        function(v) GB.db.recruit.manualInvite = v; if GB.RefreshApplicants then GB:RefreshApplicants() end end)
    makeCheck("Ask if they have an aura?", L1, nl1(22),
        function() return GB.db.recruit.askAura end,
        function(v) GB.db.recruit.askAura = v end)
    makeCheck("Ask if they have heirlooms?", L1, nl1(22),
        function() return GB.db.recruit.askLooms end,
        function(v) GB.db.recruit.askLooms = v end)
    makeCheck("Ask manually-invited members for role/aura", L1, nl1(22),
        function() return GB.db.recruit.askNewMembers end,
        function(v) GB.db.recruit.askNewMembers = v end)
    makeEdit("Reply cooldown (sec)", L1, nl1(24), 32,
        function() return GB.db.recruit.cooldown end,
        function(v) GB.db.recruit.cooldown = math.max(0, math.floor(v)) end, true)
    makeEdit("Reserve dps spots (for aura dps)", L1, nl1(24), 32,
        function() return GB.db.recruit.reserveDps end,
        function(v) GB.db.recruit.reserveDps = math.max(0, math.floor(v)) end, true)

    -- ===== Column 2 =====
    makeHeader("Require heirlooms? (per role)", L2, nl2(22))
    local lr = nl2(22)
    makeCheck("Tanks", L2, lr,
        function() return GB:RoleLooms("tank") end,
        function(v) GB.db.requireLooms.tank = v end)
    makeCheck("Healers", L2 + 90, lr,
        function() return GB:RoleLooms("healer") end,
        function(v) GB.db.requireLooms.healer = v end)
    makeCheck("DPS", L2 + 200, lr,
        function() return GB:RoleLooms("dps") end,
        function(v) GB.db.requireLooms.dps = v end)

    gap2()
    makeHeader("Announce", L2, nl2(22))
    makeChannelDropdown("Channel", L2, nl2(30))

    gap2()
    makeHeader("Anti-scaling (reform on max level)", L2, nl2(22))
    makeCheck("Enable?", L2, nl2(24),
        function() return GB.db.leveling.enabled end,
        function(v) GB.db.leveling.enabled = v end)
    makeEdit("Kick at level (60 = reform only)", L2, nl2(24), 32,
        function() return GB.db.leveling.maxLevel end,
        function(v) GB.db.leveling.maxLevel = math.max(1, math.floor(v)) end, true)
    makeCheck("Auto-leave the Manastorm after reform", L2, nl2(22),
        function() return GB.db.leveling.autoLeave end,
        function(v) GB.db.leveling.autoLeave = v end)
    local wlhint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wlhint:SetPoint("TOPLEFT", L2, nl2(18)); wlhint:SetWidth(280); wlhint:SetJustifyH("LEFT")
    wlhint:SetText("Whitelist / blacklist are their own tabs on the left.")

    gap2()
    makeHeader("Interface", L2, nl2(22))
    makeCheck("Auto-mark tanks (circle / square)", L2, nl2(22),
        function() return GB.db.markTanks end,
        function(v) GB.db.markTanks = v; if v and GB.MarkTanks then GB:MarkTanks() end end)
    makeCheck("Hide minimap button", L2, nl2(22),
        function() return GB.db.minimap.hide end,
        function(v) GB.db.minimap.hide = v; if GB.RefreshMinimap then GB:RefreshMinimap() end end)

    gap2()
    makeHeader("LFM preview", L2, nl2(20))
    preview = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview:SetPoint("TOPLEFT", L2, nl2(44))
    preview:SetWidth(280); preview:SetJustifyH("LEFT"); preview:SetJustifyV("TOP"); preview:SetHeight(40)

    local br = nl2(28)
    makeButton("Announce", L2, br, 80, function() GB:AnnounceNow() end)
    makeButton("Reform", L2 + 88, br, 80, function() GB:ReformGroup(nil) end)
    makeButton("Status window", L2 + 176, br, 100, function()
        GB.db.ui.shown = not GB.db.ui.shown; GB:RefreshUI()
    end)

    GB:RefreshOptions()   -- prime widgets from the DB
end

-- Sync every widget + the preview from the current DB.
function GB:RefreshOptions()
    if not frame then return end
    for _, f in ipairs(refreshers) do f() end
    if preview then
        preview:SetText(self:BuildAnnounce() or "|cff888888(group full — nothing to announce)|r")
    end
end

-- Open (or close) the Blizzard Interface Options to the GroupBuilder category.
-- Bound to /gb and the minimap button's left-click.
function GB:ToggleOptions()
    if not self.interfacePanel then return end
    if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
        InterfaceOptionsFrame:Hide()
        return
    end
    if InterfaceOptionsFrame_OpenToCategory then
        -- called twice on purpose: a long-standing Blizzard quirk means the first
        -- call can land on the wrong category.
        InterfaceOptionsFrame_OpenToCategory(self.interfacePanel)
        InterfaceOptionsFrame_OpenToCategory(self.interfacePanel)
    end
end

-- ---------------------------------------------------------------------------
--  Sub-panels (registered as children of the GroupBuilder category by Panel.lua)
-- ---------------------------------------------------------------------------
local function panelTitle(panel, text, sub)
    local t = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16); t:SetText(text)
    if sub then
        local d = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        d:SetPoint("TOPLEFT", 16, -42); d:SetWidth(560); d:SetJustifyH("LEFT"); d:SetText(sub)
    end
    return t
end

-- The landing page (the "GroupBuilder" parent node).
function GB:BuildLanding(panel)
    frame = panel
    panelTitle(panel, "GroupBuilder",
        "Builds a leveling raid comp from whispers, keeps an auto-updating LFM macro, "
        .. "and reforms the group when someone hits max level.")

    makeCheck("|cff33ff99Active|r  (master switch: auto reply / invite / reform)", 16, -74,
        function() return GB.db.active end,
        function(v) GB.db.active = v; if v and GB.NotifyActive then GB:NotifyActive() end end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 16, -104); hint:SetWidth(560); hint:SetJustifyH("LEFT")
    hint:SetText("Expand the (+) on the left for Basic Options, Auto-Kick Whitelist, "
        .. "Auto-Inv Blacklist, Help and About.  Type /gb to open this anytime.")
end

-- Whitelist / blacklist manager. which = "whitelist" | "blacklist".
local MAXLISTROWS = 14
function GB:BuildListPanel(panel, which)
    frame = panel
    local isBlack = (which == "blacklist")
    panelTitle(panel, isBlack and "Auto-Inv Blacklist" or "Auto-Kick Whitelist",
        isBlack and "Players here are NEVER invited (silent ghost-ban — they get no auto-reply)."
            or "Players here are exempt from the sub-60 autokick. You and reserved friends are always exempt.")

    local nameLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    nameLbl:SetPoint("TOPLEFT", 20, -62); nameLbl:SetText("name")
    local name = CreateFrame("EditBox", "GroupBuilder" .. which .. "Name", panel, "InputBoxTemplate")
    name:SetAutoFocus(false); name:SetHeight(18); name:SetWidth(120)
    name:SetPoint("TOPLEFT", 22, -76)

    local reason
    if isBlack then
        local rl = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        rl:SetPoint("TOPLEFT", 200, -62); rl:SetText("reason (optional)")
        reason = CreateFrame("EditBox", "GroupBuilderBlacklistReason", panel, "InputBoxTemplate")
        reason:SetAutoFocus(false); reason:SetHeight(18); reason:SetWidth(180)
        reason:SetPoint("TOPLEFT", 202, -76)
    end

    local function addEntry()
        local n = name:GetText()
        if not n or n:gsub("%s", "") == "" then return end
        n = GB:NormName(n)
        GB.db.whitelist = GB.db.whitelist or {}; GB.db.blacklist = GB.db.blacklist or {}
        if isBlack then GB.db.blacklist[n] = (reason and reason:GetText()) or "" else GB.db.whitelist[n] = true end
        name:SetText(""); name:ClearFocus()
        if reason then reason:SetText(""); reason:ClearFocus() end
        GB:RefreshOptions()
    end
    name:SetScript("OnEnterPressed", addEntry)
    if reason then reason:SetScript("OnEnterPressed", addEntry) end

    local add = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    add:SetHeight(20); add:SetWidth(46); add:SetText("Add")
    add:SetPoint("LEFT", (reason or name), "RIGHT", 10, 0)
    add:SetScript("OnClick", addEntry)

    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", 20, -108); header:SetText(isBlack and "|cffffcc00Blacklisted:|r" or "|cffffcc00Whitelisted:|r")

    local rows = {}
    for i = 1, MAXLISTROWS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetWidth(540); row:SetHeight(16)
        if i == 1 then row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
        else row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -2) end
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 2, 0); fs:SetWidth(500); fs:SetJustifyH("LEFT")
        row.text = fs
        local x = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        x:SetWidth(18); x:SetHeight(16); x:SetPoint("LEFT", 508, 0); x:SetText("x")
        x:SetScript("OnClick", function()
            if not row.name then return end
            if isBlack then GB.db.blacklist[row.name] = nil else GB.db.whitelist[row.name] = nil end
            GB:RefreshOptions()
        end)
        row.x = x
        row:Hide(); rows[i] = row
    end

    refreshers[#refreshers + 1] = function()
        local src = isBlack and (GB.db.blacklist or {}) or (GB.db.whitelist or {})
        local list = {}
        for n in pairs(src) do list[#list + 1] = n end
        table.sort(list)
        for i = 1, MAXLISTROWS do
            local row, nm = rows[i], list[i]
            if nm then
                if isBlack then
                    local why = src[nm]
                    row.text:SetText(nm .. (why ~= "" and ("   |cffaaaaaa- " .. why .. "|r") or ""))
                else
                    row.text:SetText(nm)
                end
                row.name = nm; row.x:Show(); row:Show()
            else
                row.name = nil; row:Hide()
            end
        end
        if #list == 0 then
            rows[1].text:SetText("|cff888888(none yet — add a name above)|r"); rows[1].name = nil; rows[1].x:Hide(); rows[1]:Show()
        end
    end
end

-- Help: the available slash commands.
function GB:BuildHelp(panel)
    panelTitle(panel, "GroupBuilder — Help", "Chat commands (type /gb help in-game for the full list):")
    local lines = {
        "|cffffd200/gb|r  — open these options",
        "|cffffd200/gb on|r / |cffffd200off|r  — master switch (auto reply / invite / reform)",
        "|cffffd200/gb say|r (or the GB_LFM macro)  — post the LFM line to your channel",
        "|cffffd200/gb comp T H D A|r  — set target comp, e.g. /gb comp 3 2 10 3",
        "|cffffd200/gb reform|r  — kick everyone, leave the Manastorm, re-invite on load-out",
        "|cffffd200/gb reinvite|r  — manually send the reform re-invites",
        "|cffffd200/gb leave|r  — leave the Manastorm now (resets scaling)",
        "|cffffd200/gb pass <name>|r  — hand lead to someone & leave (everyone made assist)",
        "|cffffd200/gb roles|r  — popup of who is tank / healer",
        "|cffffd200/gb aura check|r  — poll aura coverage, PM anyone missing role/aura",
        "|cffffd200/gb clear|r  — reset the tracked comp",
        "|cffffd200/gb whitelist add <name>|me|r  — exempt from the sub-60 autokick",
        "|cffffd200/gb blacklist add <name> [reason]|r  — never invite (silent ghost-ban)",
        "|cffffd200/gb debug|r  — dry-run panel (shows what actions WOULD do)",
        "|cffffd200/gb monitor|r  — live list of players near the autokick level",
        "|cffffd200/gb levels|r  — print each member's detected level",
    }
    local body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", 20, -70); body:SetWidth(560); body:SetJustifyH("LEFT"); body:SetJustifyV("TOP")
    body:SetText(table.concat(lines, "\n"))
    body:SetSpacing(3)
end

-- About: authorship & thanks.
function GB:BuildAbout(panel)
    panelTitle(panel, "GroupBuilder — About")
    local function line(y, label, value, valueColor)
        local l = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", 24, y); l:SetWidth(110); l:SetJustifyH("RIGHT"); l:SetText(label)
        l:SetTextColor(1, 0.82, 0)
        local v = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        v:SetPoint("TOPLEFT", 145, y); v:SetWidth(430); v:SetJustifyH("LEFT"); v:SetText(value)
        if valueColor then v:SetTextColor(unpack(valueColor)) end
        return v
    end
    line(-64, "Version", (GB.version or "dev"))
    line(-84, "Author", "Aol - Darkmoon")
    line(-114, "Special thanks", "Elitist Jerks, Qinan, and Schweizerhof for testing.")
end
