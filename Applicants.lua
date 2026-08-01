-- GroupBuilder :: Applicants.lua
-- Manual-invite mode: a movable window listing everyone who whispered to join,
-- with the role / aura / looms they reported and an Invite button each, so you
-- can hand-pick who fills the last spots.

local addonName, GB = ...

local frame
local rows = {}
local MAXROWS = 14

local function yn(v)
    if v == true then return "|cff55ff55Y|r"
    elseif v == false then return "|cffff5555N|r"
    else return "|cff888888?|r" end
end

local function makeRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(258); row:SetHeight(18)
    row:SetPoint("TOPLEFT", 12, -30 - (i - 1) * 20)

    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 0, 0); fs:SetWidth(168); fs:SetJustifyH("LEFT")
    row.text = fs

    local inv = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    inv:SetWidth(48); inv:SetHeight(18); inv:SetPoint("LEFT", 170, 0); inv:SetText("Invite")
    inv:SetScript("OnClick", function()
        local n = row.applicantName
        if not n then return end
        local a = GB.applicants[n]
        GB:InviteApplicant(n, a and a.role)
        if a and a.role then GB:MarkPending(n, a.role) end
        GB:RemoveApplicant(n)
        GB:RefreshApplicants(); GB:UpdateAnnounce(); GB:RefreshUI()
    end)
    row.invite = inv

    local x = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    x:SetWidth(20); x:SetHeight(18); x:SetPoint("LEFT", 222, 0); x:SetText("X")
    x:SetScript("OnClick", function()
        local n = row.applicantName
        if not n then return end
        GB:RemoveApplicant(n); GB:RefreshApplicants()
    end)
    row.decline = x

    row:Hide()
    return row
end

local function build()
    frame = CreateFrame("Frame", "GroupBuilderApplicants", UIParent)
    frame:SetWidth(290); frame:SetHeight(56 + MAXROWS * 20)
    frame:SetPoint("LEFT", UIParent, "CENTER", 260, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10); title:SetText("Applicants")
    frame.title = title

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        GB.db.recruit.manualInvite = false
        GB:RefreshApplicants(); GB:RefreshUI()
    end)

    for i = 1, MAXROWS do rows[i] = makeRow(frame, i) end
    GB.applicantsFrame = frame
end

-- Rebuild the list from GB.applicants. Hidden unless manual-invite mode is on.
function GB:RefreshApplicants()
    if not (self.db and self.db.recruit.manualInvite) then
        if frame then frame:Hide() end
        return
    end
    if not frame then build() end

    -- drop anyone who has since joined the group
    for n in pairs(self.applicants) do
        if self.rosterByName[n] then self.applicants[n] = nil end
    end

    local list = {}
    for n, a in pairs(self.applicants) do list[#list + 1] = { name = n, a = a } end
    table.sort(list, function(p, q) return (p.a.time or 0) < (q.a.time or 0) end)

    for i = 1, MAXROWS do
        local row, e = rows[i], list[i]
        if e then
            row.applicantName = e.name
            row.text:SetText(("%s |cffaaaaaa(%s)|r  aura:%s looms:%s"):format(
                e.name, e.a.role or "?", yn(e.a.aura), yn(e.a.looms)))
            row:Show()
        else
            row.applicantName = nil
            row:Hide()
        end
    end
    frame.title:SetText(("Applicants (%d)"):format(#list))
    frame:Show()
end
