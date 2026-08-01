-- GroupBuilder :: Config.lua
-- Default configuration. Saved to GroupBuilderDB on first load and merged with
-- any user changes. Edit values here to change the shipped defaults, or use the
-- /gb slash commands to change them live.

local addonName, GB = ...

-- Note on Manastorm scaling: mobs scale to the highest level in the group, so
-- when someone dings 60 the mobs jump to 60. There is no command to fix this —
-- the fix is to get the 60 out and reform, which is exactly what the level-60
-- handling below does (kick everyone, re-invite all but the dinger).

GB.defaults = {
    -- Target composition for a full group. Defaults match a 15-man leveling raid
    -- (3 groups of 5): 3 tanks, 2 healers, 10 dps, and 3 auras (one per group).
    comp = {
        tanks   = 3,
        healers = 2,
        dps     = 10,
        auras   = 3,   -- number of subgroups that must each have an aura holder
        size    = 15,  -- total headcount target (used for "14/15" style messaging)
    },

    -- Heirloom requirement, per role. Only the roles set true "need" looms, so
    -- you can require them for just tanks (say) without a blanket rule.
    requireLooms = {
        tank   = true,
        healer = true,
        dps    = true,
    },

    -- Where the /gbsay macro / announce sends. type is one of:
    --   "SAY" "YELL" "PARTY" "RAID" "GUILD" "CHANNEL"
    -- For "CHANNEL", set channelName to the channel's name (e.g. "LookingForGroup"
    -- or a custom channel). We resolve it to a number at send time.
    announce = {
        type        = "CHANNEL",
        channelName = "LookingForGroup",
    },

    -- Auto-updating macro that mirrors the current LFM text.
    macro = {
        enabled = true,
        name    = "GB_LFM",       -- macro name; created if missing
        icon    = "INV_Misc_GroupNeedMore",
    },

    -- Whisper options (auto-response behaviour).
    recruit = {
        autoReply  = true,   -- auto-answer whispers with what we need
        autoInvite = true,   -- auto-invite an applicant who names a role we need
        manualInvite = false,-- queue applicants in a list with Invite buttons instead
        askAura    = true,   -- ask about auras (recruit prompts + poll group members)
        askLooms   = true,   -- ask applicants whether they have heirlooms
        cooldown   = 20,     -- seconds between auto-replies to the same person
        reserveDps = 3,      -- keep this many dps spots open (for aura-dps) until tanks+healers fill
    },

    -- Level-60 handling: when anyone dings maxLevel, reform so the Manastorm
    -- mobs stop scaling to their level.
    leveling = {
        enabled    = true,   -- watch for group members hitting maxLevel
        maxLevel   = 60,
        autoReform = true,   -- kick all & re-invite everyone except the dinger
        announceReform = true,
    },

    -- UI.
    ui = {
        shown = true,
        minimized = false,
        point = { "CENTER", nil, "CENTER", 0, 0 },
        locked = false,
    },

    -- Minimap button.
    minimap = {
        hide  = false,
        angle = 200,   -- degrees around the minimap
    },

    -- Auto-mark tanks with raid icons: 1st tank -> circle (2), 2nd -> square (6),
    -- only if they aren't already marked. Needs you to be leader/assist.
    markTanks = true,

    -- Reserved slots for friends: [name] = "tank"|"healer"|"dps". Each friend not
    -- yet in the group holds a slot of their role, so random applicants don't take
    -- it; the friend themselves is always invited when they whisper.
    friends = {},

    -- Master switch. When false, no auto-replies/invites/reforms happen; slash
    -- commands and the status window still work.
    active = false,

    -- Set true after the one-time "macro created" explanation has been shown.
    macroNoticeShown = false,
}

-- Keyword sets used to parse whispers. Matching is case-insensitive, word-ish.
GB.keywords = {
    tank   = { "tank", "prot", "protection", "tanking" },
    healer = { "heal", "heals", "healer", "healing", "hps" },
    dps    = { "dps", "dd", "damage", "deeps", "mdps", "rdps" },
    aura   = { "aura", "auras" },
    looms  = { "loom", "looms", "heirloom", "heirlooms", "boa" },
}
