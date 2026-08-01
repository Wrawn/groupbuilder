# GroupBuilder

A WotLK 3.3.5 (Ascension) addon for running a leveling raid: it builds and
maintains a group comp (tanks / healers / dps + one aura per group) from
whispers, keeps an auto-updating LFM macro, and reforms the group to reset mob
scaling whenever a member dings max level.

## Install

Copy or symlink the `groupbuilder/` folder into your game AddOns directory:

```
.../Interface/AddOns/groupbuilder/
```

From this repo the live AddOns folder is the `Live Addons` symlink under
`addons/`, e.g.:

```
ln -s "$PWD/groupbuilder" "../Live Addons/GroupBuilder"
```

Then `/reload` in-game.

## Configure it

Open the options window any of three ways: type **`/gb`**, click the **minimap
button** (the green "GB"), or go to **Esc → Interface → AddOns → GroupBuilder →
Open GroupBuilder Options**. Everything is set there: the master switch, target
comp, per-role heirloom requirements, announce channel, whisper options, and the
anti-scaling (reform on max level) settings.

The minimap button: left-click opens options, right-click toggles Active, drag to
move it around the minimap. Hide it via Interface → "Hide minimap button".

### Anti-scaling — the point of the level-60 handling

In a Manastorm, mobs scale to the **highest level in the group**. When someone
dings 60, the mobs jump to 60 — too hard for a sub-60 leveling group. There's no
command to undo that; the fix is to get the 60 out and reform. So when anyone
hits max level, GroupBuilder:

1. raid-warns (`/rw`): *"Level 60 scaling detected — kicking & reforming! If you
   don't get an invite, whisper me 'reform' for one."*
2. disbands the raid — uninvites every other member in one pass, then
   `LeaveParty()` to fully dissolve the group so scaling resets. (In a party, or
   if that API isn't available, it falls back to kicking member-by-member, dinger
   first.)
3. re-invites everyone **except** the person who dinged.

**Failsafe:** if the auto-reinvite misses someone, they whisper you **`reform`**
and GroupBuilder invites them back automatically — except the person who just
dinged, who is kept out so the mobs don't scale again.

## Usage

1. `/gb` — open the options window; set **My role** (you count in the comp too), your target comp, and channel.
2. Tick **Active** (or `/gb on`) to enable auto-reply to whispers, auto-invite, aura polling, and auto-reform.
3. Press the **`GB_LFM`** macro to announce. It's created automatically in your General macro tab and its body is just `/gbsay`, so it always posts the current, freshly-computed LFM line to your chosen channel — you never edit it or touch the Announce button. Drag it to an action bar once.

### The macro

GroupBuilder makes an account-wide macro named `GB_LFM` (General tab) that runs
`/gbsay`. Because the text is computed each time you press it, it always reflects
the current headcount and needs — no editing, no re-making it as people join.

The channel line reads `LF<N>M Leveling MS - need <what's needed>. (have/size)`
— the leading `<N>` is how many people you still need, and the current headcount
is at the end so nobody misreads it (e.g. `LF14M Leveling MS - need 3 tanks, 2
healers, 10 dps (aura welcome). (1/15)`). As people
whisper you, GroupBuilder answers with exactly what's still needed and invites
anyone who names a role you need. Its whispers are signed **"GroupBuilder by
&lt;you&gt;"** (the broadcast LFM line and raid warnings stay unbranded). When
someone hits max level, it announces, kicks everyone, and re-invites all but the
person who dinged.

### Aura selectivity (not too picky)

You need one aura per group (3 total by default). An aura is only stated as
**required** — and non-aura applicants declined — once the open spots run low
(open spots ≤ auras still needed), e.g. at 14/15 with one aura group missing.
While there's still room it's just "aura welcome", so you don't turn away bodies
you need. Heirlooms are **per role** — set which of tank/healer/dps need them in
**Requirements**; a role is tagged `(looms)` in messages only if it requires them.

### Commands

All settings live in the `/gb` window; the slash commands below are shortcuts.

| Command | Effect |
|---|---|
| `/gb` | open the options window |
| `/gb on` / `/gb off` | master switch (auto reply/invite/reform) |
| `/gb status` | print current comp & needs |
| `/gb say` (or `/gbsay`) | announce LFM to your chosen channel now |
| `/gb comp T H D [A]` | set target comp (persists across sessions) |
| `/gb looms <role> on\|off` | require heirlooms per role (tank/healer/dps/all) |
| `/gb channel <where>` | set announce channel |
| `/gb show` / `hide` / `lock` | status window |
| `/gb reform` | manually run the kick & re-invite flow |

## How roles/auras are known

The server is classless, so GroupBuilder doesn't guess — it records what people
tell it, keyed by name and remembered across reloads while they're in the group:

- **You** set your own role and whether you bring an aura at the top of the `/gb`
  window (you're prompted on login until you do). You count in the comp like
  anyone else.
- **Applicants** who whisper `tank aura looms` are marked tank + aura + looms.
- **Aura polling:** while any of your groups still lack an aura, GroupBuilder
  whispers the members of those groups asking *"do you have an aura? reply 'aura'
  or 'no'"*, so per-group coverage fills in as the raid forms. Their `aura` /
  `no` replies update the counts. Toggle this under **Whisper options** →
  "Ask if they have an aura?".

The `/gb` window is grouped into sections: **You** (your own slot — role, whether
*you* bring an aura/looms), **Target comp**, **Requirements** (require heirlooms?),
**Whisper options** (auto-reply, auto-invite, ask-aura, ask-heirlooms, cooldown),
**Announce**, and **Leveling**.

That's what the T/H/D counts and per-group aura coverage (G1/G2/G3) are built from.

## Notes / caveats

- Level-60 handling watches **every** party/raid member (not just you); your own
  ding is ignored since you can't kick yourself.
- Only the **party/raid leader** can kick & re-invite; the reform flow no-ops
  with a warning otherwise.
- Macros can't be edited in combat — updates are deferred until combat ends.
- Re-invites depend on players accepting the invite popup, same as any invite.
