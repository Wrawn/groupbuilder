# Changelog

All notable changes to GroupBuilder, in plain English. Newest first.
Versions use vMAJOR.MINOR.PATCH.

When you make changes, add them under **[Unreleased]** in the right section
(**Added** / **Changed** / **Fixed**). When you cut a release, rename that block to
the new version + date. The GitHub release notes are generated from the matching
section here.

## [Unreleased]
### Added
- **Sort Groups** (`/gb sort` or the status button) — arranges the raid subgroups so
  every group of 5 gets a healer and an aura, with tanks in group 1, using the roles/
  auras you've tracked. Waits for combat to end if needed, and announces the layout.
- An **Autokick Monitor** button on the status window opens the `/gb monitor` window, so
  it's discoverable without knowing the command.
- **Window Sizes** options tab — set the **width, height, and a scale slider** for the
  status window and the Autokick Monitor independently. Scale resizes both dimensions at
  once; the status window's height auto-fits its content unless you set a value. The
  **Autokick Monitor fits its list to the box** — rows/font shrink as more players near
  the cutoff (or the window shrinks) so nothing overlaps or spills out, with a "+N more"
  line when there are too many to show.
- **Auto-arrange groups** — when a newly-learned aura lands in a group that already has
  one (while another group has none), GroupBuilder quietly re-sorts on its own, so it
  stays one-aura-per-group hands-free. You only need to click Sort for edge cases.
  Toggle under Interface options.

### Changed
- **Consistent window styling** — the `/gb monitor` window now matches the status window
  (same see-through panel), all their buttons share the flat dark square look, and the
  close **[X]** is a muted-red square with a white X (matching the minimize button).
- **Batch role/aura check.** "Role / Aura Check" now asks the whole raid to reply **in
  raid chat** with their role + aura (words like `tank aura`, or numbers `1`/`2`/`3`),
  collects the replies for ~20s, then **whispers only the people who didn't answer**.

### Fixed
- **Autokick no longer gets blocked in combat.** `UninviteUnit` is protected on
  Ascension, so an automatic kick fired mid-combat was refused ("prevented the call of
  the secure function"). The kick is now **queued and runs the instant combat ends**.
- **Sub-60 autokick now actually removes the player** (before, it only sent the
  thanks-for-coming whisper). It was passing a `raidN` unit token to the kick, but on
  3.3.5 the kick needs the player's **name** — fixed here and in the reform kick. Added
  `/gb ktest` to verify kicking in isolation.

### Added
- **Editable roster table** (`/gb roles` or the status "Edit Roles" button) — a live list
  of everyone in your group with **Name / Role / Aura** columns, each row with dropdowns
  to set a player's role and toggle their aura Yes/No. Replaces the old "Set Role / Aura"
  pop-up (that button is gone) and the read-only roles popup.
- **Auto-Inv Blacklist** — permanently block players from ever being invited, with an
  optional reason. It's a **silent ghost-ban**: blacklisted players get no auto-reply at
  all, and every invite path skips them. Manage it in its own options tab or with
  `/gb blacklist add <name> [reason]` (list / remove / clear).
- The GroupBuilder options now have an **expandable (+) menu** with sub-tabs: **Basic
  Options**, **Auto-Kick Whitelist**, **Auto-Inv Blacklist**, **Help** (all the slash
  commands), and **About**.

### Changed
- The LFM line now shows **`(auras x/3)`** (how many auras you have vs need) instead of
  "(aura welcome)" — since auras aren't really "welcome" until you're covered. The
  "— all auras covered" message stays for when every group has one.
- **Options now live in the standard Interface panel** (Esc → Interface → AddOns →
  GroupBuilder) instead of a separate pop-up window. Applied live. `/gb` opens it.
- **The whitelist moved from a pop-up button into its own options tab** (Auto-Kick
  Whitelist). The `/gb whitelist` commands are unchanged.
- **Fresh, flatter look** — the status window and the debug/monitor/applicant/set-role
  pop-ups now use a modern dark panel with a thin border instead of the old gold frame.
- **Minimap button:** left-click now opens the **status window** (options moved to
  `/gb`); the **"GB" turns green when Active is on, red when off** at a glance.

### Added
- **Reform now auto-leaves the Manastorm.** After it kicks the group, Reform teleports
  you out (which resets the level-60 scaling) — then the re-invites fire automatically
  as soon as you load out, so you no longer click Reform *and* Reinvite. **Reinvite**
  (button, `/gb reinvite`, and the "pst reform" whisper) stays as a fallback for anyone
  who doesn't leave right away. There's a new **`/gb leave`** manual command too, and an
  **autoLeave** toggle. (Only fires when you're actually inside a Manastorm.)
- **Pass Lead & Leave** — a button on the `/gb monitor` window (and `/gb pass`) that
  hands the raid off and leaves. It promotes **everyone** to assist (so an AFK new leader
  can't strand the group), picks a **random** member as the new leader (not your call —
  you won't be there), and **announces the key roles to raid chat**: just **Tanks /
  Healers / Auras** (you're excluded since you're leaving; aura-unknown counts as no
  aura; no dps/whitelist noise). `/gb pass <name>` still lets you name someone. Confirms
  first, leader-only.
- **`/gb debug`** — a dry-run panel. Buttons for Reinvite / Reform / Clear Comp / Set
  Role / Autokick-state each show what GB *would* do (who it'd invite/kick and why, the
  live per-player autokick table) in a copy-pasteable window. Nothing is performed.
- **`/gb monitor`** — a live window of players within 5 levels of the autokick cutoff,
  shown as `Name (Role)`, auto-updating on level/roster changes. Plus a **private**
  (only-you) raid-warning-style alert when a **tank/healer** is autokicked, e.g.
  `WARNING HEALER AUTOKICKED, 2 HEALERS LEFT!`.
- **Manual-invite tracking** — when someone joins that GB didn't invite (e.g. a normal
  right-click invite), GB whispers them for role + aura so autokick/reform treat them
  consistently. No reply = they stay "unknown" (never assumed). Toggle in Whisper options.
- **Early autokick (no full reform).** Set **Kick at level** below 60 (e.g. 59) and a
  member who reaches it is single-kicked *before* they scale the group to 60 — with a
  friendly "thanks for coming, removed to avoid scaling" whisper — so you skip the full
  reform. Hitting **60** still does the full reform.
- **Whitelist** — a permanent, account-wide list of players exempt from the sub-60
  autokick (you, friends). Manage it from a **Whitelist window** (button in the
  Anti-scaling options) with add / Add Me / remove, or the `/gb whitelist` chat commands.
  Reserved friends are exempt automatically. Whitelisted players are still reformed at 60.

### Changed
- **Reinvite** no longer re-invites anyone at level 60 (that would just re-scale the group).

### Fixed
- Whispering a role when the group is full now gets "we're full — thanks for
  whispering!" instead of "We're set on healers. We still need: ." (dangling).

## [0.3.0] — 2026-08-01
### Added
- **Close (X) and Minimize buttons** on the status window. Minimize collapses it to a
  compact bar showing just the counts — Status, tanks/healers/dps, and auras (A x/x).
- **Auto-mark tanks** with raid icons — the 1st tank gets a circle, the 2nd a square,
  but only if they aren't already marked (and only when you're leader/assist). Toggle
  under Interface.
- **`/gb vers`** — prints the addon version in chat (handy for checking everyone's on
  the same version).
- A plain-English **CHANGELOG** — GitHub release notes are now generated from it.

### Changed
- The LFM announce now says **"— all auras covered"** when every group has an aura,
  and posts **"Leveling MS group is FULL — thanks for whispering!"** when the group is
  full (instead of announcing nothing).

### Fixed
- Names typed in the **Set Role / Aura** box now match group members regardless of
  capitalization (before, "bob" wouldn't match "Bob", so the role wasn't counted).
- Reply no longer says "**dpss**" — it now correctly reads "we're set on dps".
- Status-window buttons no longer throw an error if the game hasn't loaded a
  newly-added addon file yet — they show a "fully restart the client" note instead.

## [0.2.0] — 2026-08-01
### Added
- **Clear Comp** button (and `/gb clear`) — resets everyone's tracked role and aura
  back to unassigned for a fresh start. Asks you to confirm first; your target
  numbers (how many tanks/healers/dps/auras) are kept.

## [0.1.0] — 2026-07-31
First public release — a recruiting and composition helper for leveling raids on
Ascension.

### Added
- **Auto-recruiting from whispers** — answers people who whisper to join, asks their
  role (and whether they have an aura), and invites the ones you still need.
- **Live status window** — shows your comp vs target (tanks/healers/dps), which groups
  still need an aura and who's covering them, plus buttons for the common actions.
- **Auto-updating LFM macro** (`GB_LFM`) — one macro that always posts your current
  "what we need" line to the channel you choose.
- **Anti-scaling reform** — when someone hits max level in a Manastorm it warns the
  group, kicks everyone, and re-invites them (automatically when you leave the
  instance) so the mobs stop scaling up. Reform asks for confirmation; **Reinvite**
  sends the invites once you're able to.
- **Role / Aura check** — asks the raid who has an aura and privately messages anyone
  you invited by hand for their role/aura.
- **Reserved friend slots** — hold spots for named friends so randoms don't take them.
- **Manual-invite mode** — queue applicants in a list with Invite buttons so you can
  hand-pick who fills the last spots.
- **Set Role/Aura form, Roles popup, minimap button, Interface options panel**, and a
  **channel dropdown** that lists the chat channels you're currently in.

### Notes
- Only recruits/polls when you're the group **leader or assist**, so joining a group
  you don't lead stays silent.
- Starts **inactive** on login — turn **Active** on when you're recruiting.
