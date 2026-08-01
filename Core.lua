-- GroupBuilder :: Core.lua
-- Addon bootstrap: saved variables, a shared event dispatcher, and slash commands.

local addonName, GB = ...

GB.name = addonName
GB.version = GetAddOnMetadata and GetAddOnMetadata(addonName, "Version") or "0.1.0"

-- Simple print helper with a colored tag.
local TAG = "|cff33ff99GroupBuilder|r: "
function GB:Print(...)
    local msg = ""
    for i = 1, select("#", ...) do
        msg = msg .. tostring(select(i, ...)) .. (i < select("#", ...) and " " or "")
    end
    DEFAULT_CHAT_FRAME:AddMessage(TAG .. msg)
end

-- Branding tag used in the addon's chat/whisper messages, e.g. "GroupBuilder by Aol".
function GB:Tag()
    return "GroupBuilder by " .. (UnitName("player") or "?")
end

-- Per-role heirloom requirement helpers (requireLooms is a { tank/healer/dps }
-- table; these also tolerate a legacy boolean).
function GB:RoleLooms(role)
    local r = self.db and self.db.requireLooms
    if type(r) == "table" then return r[role] and true or false end
    return r and true or false
end

function GB:AnyLooms()
    local r = self.db and self.db.requireLooms
    if type(r) == "table" then return (r.tank or r.healer or r.dps) and true or false end
    return r and true or false
end

-- True if you can actually run the group: raid leader/assist, party leader, or
-- solo (about to form your own). Recruiting/polling/reform only happen when true.
function GB:CanLead()
    if GetNumRaidMembers() > 0 then
        return (IsRaidOfficer and IsRaidOfficer()) and true or false   -- leader OR assist
    elseif GetNumPartyMembers() > 0 then
        return (IsPartyLeader and IsPartyLeader()) and true or false
    end
    return true   -- solo
end

-- ---------------------------------------------------------------------------
--  Event dispatch: modules register handlers by event name via GB:On(evt, fn).
--  Multiple handlers per event are allowed.
-- ---------------------------------------------------------------------------
local handlers = {}
local frame = CreateFrame("Frame", "GroupBuilderEventFrame", UIParent)

function GB:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        -- ADDON_LOADED / PLAYER_LOGIN are registered up front below; register any
        -- other event lazily the first time someone subscribes to it.
        if event ~= "ADDON_LOADED" and event ~= "PLAYER_LOGIN" then
            frame:RegisterEvent(event)
        end
    end
    table.insert(handlers[event], fn)
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        -- Isolate handler errors so one bad module can't kill the others.
        local ok, err = pcall(fn, event, ...)
        if not ok then
            GB:Print("|cffff5555error in", event, "handler:|r", err)
        end
    end
end)

-- ---------------------------------------------------------------------------
--  Saved variables: deep-merge defaults into GroupBuilderDB without clobbering
--  user changes, so new default keys appear on upgrade.
-- ---------------------------------------------------------------------------
local function mergeDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            mergeDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

GB:On("ADDON_LOADED", function(_, loaded)
    if loaded ~= addonName then return end
    GroupBuilderDB = GroupBuilderDB or {}
    GroupBuilderCharDB = GroupBuilderCharDB or {}
    GB.db = mergeDefaults(GroupBuilderDB, GB.defaults)
    GB.cdb = GroupBuilderCharDB
    if GB.OnConfigReady then GB:OnConfigReady() end
end)

GB:On("PLAYER_LOGIN", function()
    GB.db.active = false   -- always start inactive on login; you turn it on when recruiting
    GB:Print(("v%s loaded (inactive). /gb opens options; toggle Active when recruiting."):format(GB.version))
    if GB.RefreshRoster then GB:RefreshRoster() end
    if GB.UpdateAnnounce then GB:UpdateAnnounce() end
    if GB.RefreshUI then GB:RefreshUI() end

    -- Ask what role you're filling if you haven't set it yet — you count in the
    -- comp like everyone else.
    local mine = GB.GetSelfClaim and GB:GetSelfClaim()
    if not (mine and mine.role) then
        GB:Print("|cffffcc00What role are you filling?|r Set 'My role' at the top of the window that just opened.")
        if GB.ToggleOptions then GB:ToggleOptions() end
    end
end)

-- ---------------------------------------------------------------------------
--  Slash commands
-- ---------------------------------------------------------------------------
local function toggle(v) return v and "|cff55ff55on|r" or "|cffff5555off|r" end

-- One-time notice (per session) shown when the player turns the addon on, so they
-- know about the auto-created announce macro.
StaticPopupDialogs["GROUPBUILDER_ACTIVE"] = {
    text = "GroupBuilder is now ACTIVE.\n\nA macro named |cff33ff99%s|r was created in your General macro tab. Drag it onto an action bar — clicking it announces your current LFM to your chosen channel (it always stays up to date).",
    button1 = OKAY,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
function GB:NotifyActive()
    -- Re-check / recreate the macro EVERY time (in case it was deleted).
    if self.EnsureMacro then self:EnsureMacro() end
    -- Show the explanation popup only once, ever (persisted).
    if self.db.macroNoticeShown then return end
    self.db.macroNoticeShown = true
    if StaticPopup_Show then StaticPopup_Show("GROUPBUILDER_ACTIVE", self.db.macro.name) end
end

-- Noisy events hidden from the /gb events logger.
local EV_SKIP = {
    COMBAT_LOG_EVENT_UNFILTERED = true, COMBAT_LOG_EVENT = true,
    UNIT_HEALTH = true, UNIT_HEALTH_FREQUENT = true, UNIT_MAXHEALTH = true,
    UNIT_POWER = true, UNIT_POWER_UPDATE = true, UNIT_POWER_FREQUENT = true,
    UNIT_MANA = true, UNIT_ENERGY = true, UNIT_RAGE = true, UNIT_FOCUS = true,
    UNIT_AURA = true, UNIT_TARGET = true, UNIT_THREAT_SITUATION_UPDATE = true,
    UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_SENT = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
    SPELL_UPDATE_COOLDOWN = true, SPELL_UPDATE_USABLE = true, ACTIONBAR_UPDATE_COOLDOWN = true,
    UPDATE_WORLD_STATES = true, UPDATE_SHAPESHIFT_COOLDOWN = true, CURSOR_UPDATE = true,
}

local function handleSlash(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "options" or cmd == "config" then
        GB:ToggleOptions(); return
    elseif cmd == "help" then
        GB:Print("|cff33ff99GroupBuilder commands:|r")
        GB:Print("  /gb                - open the options window")
        GB:Print("  /gb help           - show this command list")
        GB:Print("  /gb on | off       - master switch (auto reply/invite/reform)", " [", toggle(GB.db.active), "]")
        GB:Print("  /gb status         - print current comp & needs to chat")
        GB:Print("  /gb show           - show the status window")
        GB:Print("  /gb hide           - hide the status window")
        GB:Print("  /gb lock           - lock/unlock the status window position")
        GB:Print("  /gb say            - announce the LFM line to your channel now")
        GB:Print("  /gb aura check     - show aura coverage, ask /raid, and pm members missing role/aura")
        GB:Print("  /gb aura set|clear <name> - manually mark a member as having / not having an aura")
        GB:Print("  /gbsay             - same as /gb say (used by the GB_LFM macro)")
        GB:Print("  /gb comp T H D A   - set target comp (e.g. /gb comp 3 2 10 3)")
        GB:Print("  /gb looms <role> on | off - require heirlooms per role (tank/healer/dps/all)")
        GB:Print("  /gb channel <where> - say|yell|party|raid|guild|<channelName>")
        GB:Print("  /gb reform         - kick everyone & whisper them to pst 'reform'")
        GB:Print("  /gb reinvite       - send invites to the reform list (once you've left)")
        GB:Print("  /gb roles          - popup of who is tank / healer")
        GB:Print("  /gb events         - toggle event logging (find the leave-instance event)")
        GB:Print("  /gb friend add <name> [role] - reserve a slot for a friend (list/remove/clear)")
        return
    elseif cmd == "on" then
        GB.db.active = true;  GB:Print("master switch", toggle(true)); GB:UpdateAnnounce(); GB:NotifyActive(); GB:RefreshUI(); return
    elseif cmd == "off" then
        GB.db.active = false; GB:Print("master switch", toggle(false)); GB:RefreshUI(); return
    elseif cmd == "status" then
        GB:PrintStatus(); return
    elseif cmd == "show" then
        GB.db.ui.shown = true; GB:RefreshUI(); return
    elseif cmd == "hide" then
        GB.db.ui.shown = false; GB:RefreshUI(); return
    elseif cmd == "lock" then
        GB.db.ui.locked = not GB.db.ui.locked; GB:Print("window", GB.db.ui.locked and "locked" or "unlocked"); GB:RefreshUI(); return
    elseif cmd == "say" then
        GB:AnnounceNow(); return
    elseif cmd == "aura" or cmd == "auracheck" then
        local sub, arg = rest:match("^(%S*)%s*(.-)%s*$")
        sub = (sub or ""):lower()
        local pname = arg:match("^(%S+)")
        if (sub == "clear" or sub == "remove" or sub == "no" or sub == "off") and pname then
            pname = GB:NormName(pname); GB:SetClaim(pname, { aura = false })
            GB:Print(pname .. " marked as |cffff5555NO aura|r."); GB:UpdateAnnounce(); GB:RefreshUI(); return
        elseif (sub == "set" or sub == "add" or sub == "yes" or sub == "on") and pname then
            pname = GB:NormName(pname); GB:SetClaim(pname, { aura = true })
            GB:Print(pname .. " marked as |cff55ff55having an aura|r."); GB:UpdateAnnounce(); GB:RefreshUI(); return
        elseif sub == "clear" or sub == "set" or sub == "add" or sub == "remove" then
            GB:Print("usage: /gb aura set <name>  |  /gb aura clear <name>"); return
        end
        GB:AuraCheck(); return
    elseif cmd == "comp" then
        local t, h, d, a = rest:match("^(%d+)%s+(%d+)%s+(%d+)%s*(%d*)$")
        if not t then GB:Print("usage: /gb comp <tanks> <healers> <dps> [auras]"); return end
        GB.db.comp.tanks = tonumber(t); GB.db.comp.healers = tonumber(h); GB.db.comp.dps = tonumber(d)
        if a ~= "" then GB.db.comp.auras = tonumber(a) end
        GB.db.comp.size = GB.db.comp.tanks + GB.db.comp.healers + GB.db.comp.dps
        GB:Print(("target set: T%d H%d D%d, auras %d (size %d)"):format(
            GB.db.comp.tanks, GB.db.comp.healers, GB.db.comp.dps, GB.db.comp.auras, GB.db.comp.size))
        GB:UpdateAnnounce(); GB:RefreshUI(); return
    elseif cmd == "looms" then
        if type(GB.db.requireLooms) ~= "table" then
            GB.db.requireLooms = { tank = true, healer = true, dps = true }
        end
        local role, state = rest:lower():match("^(%S*)%s*(%S*)$")
        -- normalise role aliases
        if role == "tanks" then role = "tank"
        elseif role == "heal" or role == "heals" or role == "healer" or role == "healers" then role = "healer"
        elseif role == "dd" or role == "dps" then role = "dps" end
        local function report()
            GB:Print("heirlooms required —",
                "tank:", toggle(GB:RoleLooms("tank")),
                " healer:", toggle(GB:RoleLooms("healer")),
                " dps:", toggle(GB:RoleLooms("dps")))
        end
        if role == "" then
            report(); GB:Print("usage: /gb looms tank|healer|dps|all on|off"); return
        end
        local targets = role == "all" and { "tank", "healer", "dps" }
            or (role == "tank" or role == "healer" or role == "dps") and { role } or nil
        if not targets then
            GB:Print("usage: /gb looms tank|healer|dps|all on|off"); return
        end
        local onoff
        if state == "on" or state == "yes" or state == "true" then onoff = true
        elseif state == "off" or state == "no" or state == "false" then onoff = false end
        for _, r in ipairs(targets) do
            GB.db.requireLooms[r] = (onoff == nil) and (not GB:RoleLooms(r)) or onoff
        end
        report()
        GB:UpdateAnnounce(); GB:RefreshUI(); return
    elseif cmd == "channel" then
        rest = rest:gsub("^%s+", ""):gsub("%s+$", "")
        local upper = rest:upper()
        if upper == "SAY" or upper == "YELL" or upper == "PARTY" or upper == "RAID" or upper == "GUILD" then
            GB.db.announce.type = upper
            GB:Print("announcing to", upper)
        elseif rest ~= "" then
            GB.db.announce.type = "CHANNEL"; GB.db.announce.channelName = rest
            GB:Print("announcing to channel:", rest)
        else
            GB:Print("current:", GB.db.announce.type, GB.db.announce.channelName or "")
        end
        GB:UpdateAnnounce(); return
    elseif cmd == "reform" then
        GB:ConfirmReform(); return
    elseif cmd == "reinvite" or cmd == "ri" then
        GB:ReinviteGroup(); return
    elseif cmd == "roles" then
        GB:ShowRoles(); return
    elseif cmd == "macro" then
        GB:EnsureMacro(); return
    elseif cmd == "events" then
        if not GB._evFrame then
            GB._evFrame = CreateFrame("Frame")
            GB._evFrame:SetScript("OnEvent", function(_, e, a1)
                if GB._evLog and not EV_SKIP[e] then
                    GB:Print("|cff888888evt:|r " .. e .. (a1 and (" |cffaaaaaa" .. tostring(a1) .. "|r") or ""))
                end
            end)
            GB._evFrame:RegisterAllEvents()
        end
        GB._evLog = not GB._evLog
        GB:Print("event logging " .. (GB._evLog and "|cff55ff55ON|r — do the thing, then /gb events to stop" or "|cffff5555OFF|r"))
        return
    elseif cmd == "friend" or cmd == "friends" then
        GB.db.friends = GB.db.friends or {}
        local sub, arg = rest:match("^(%S*)%s*(.-)%s*$")
        sub = (sub or ""):lower()
        if sub == "add" then
            local pname, prole = arg:match("^(%S+)%s*(%S*)$")
            if not pname or pname == "" then GB:Print("usage: /gb friend add <name> [tank|healer|dps]"); return end
            pname = GB:NormName(pname)
            prole = (prole or ""):lower()
            if prole == "tanks" then prole = "tank"
            elseif prole == "heal" or prole == "heals" or prole == "healer" or prole == "healers" then prole = "healer"
            elseif prole == "dd" then prole = "dps" end
            if prole ~= "tank" and prole ~= "healer" and prole ~= "dps" then prole = "dps" end
            GB.db.friends[pname] = prole
            GB:Print(("reserved a %s spot for %s."):format(prole, pname))
        elseif sub == "remove" or sub == "rem" or sub == "del" then
            local pname = arg:match("^(%S+)")
            pname = pname and GB:NormName(pname)
            if pname and GB.db.friends[pname] then GB.db.friends[pname] = nil; GB:Print("removed " .. pname .. " from the reserved list.")
            else GB:Print("that name isn't on the reserved list.") end
        elseif sub == "clear" then
            GB.db.friends = {}; GB:Print("cleared all reserved friends.")
        else
            GB:Print("reserved friends:")
            local any = false
            for n, r in pairs(GB.db.friends) do
                any = true
                GB:Print(("  %s (%s)%s"):format(n, r, GB.rosterByName and GB.rosterByName[n] and " |cff55ff55here|r" or " |cffffcc00reserved|r"))
            end
            if not any then GB:Print("  (none). Add one: /gb friend add <name> [tank|healer|dps]") end
        end
        GB:UpdateAnnounce(); GB:RefreshUI(); return
    else
        GB:Print("unknown command. /gb help")
    end
end

SLASH_GROUPBUILDER1 = "/gb"
SLASH_GROUPBUILDER2 = "/groupbuilder"
SlashCmdList["GROUPBUILDER"] = handleSlash

-- /gbsay is a thin command a macro can call to fire the current announce text.
SLASH_GBSAY1 = "/gbsay"
SlashCmdList["GBSAY"] = function() GB:AnnounceNow() end
