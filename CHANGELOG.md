# Changelog

All notable changes to GroupBuilder, in plain English. Newest first.
Versions use vMAJOR.MINOR.PATCH.

When you make changes, add them under **[Unreleased]** in the right section
(**Added** / **Changed** / **Fixed**). When you cut a release, rename that block to
the new version + date. The GitHub release notes are generated from the matching
section here.

## [Unreleased]
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
