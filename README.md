# nugsCooldownPulse

Pops an icon on screen the moment one of your cooldowns comes back up, then fades
it out. Retail World of Warcraft (The War Within / Midnight).

A spiritual successor to the old cooldown-pulse addons: one icon, wherever you drag
it, for a second or so. No bars, no timers, no permanent screen furniture.

## Features

- Builds the list of trackable abilities from your class and active-spec spellbook,
  then lets you tick exactly which ones you want.
- Movable anchor; position is remembered.
- Show one icon at a time, or several side by side when cooldowns land together
  (grows centered, left, right, up or down).
- A priority list decides which cooldown is shown first when a macro fires two at
  once, or haste lines three of them up.
- Icon size, peak alpha, pop scale, fade-in, hold and fade-out are all sliders.
- Optional ability name under the icon, with configurable font, outline and size -
  the stock game fonts plus everything LibSharedMedia offers when it is loaded.
- Masque support: the icon registers to the group "nugsCooldownPulse" when Masque is
  installed, and the skin draws the border.
- Optional sound cue - six built-ins, or point it at your own sound file.
- Charge abilities pulse when the last charge comes back, or on every charge.
- Equipped trinkets are tracked alongside spells.
- Cooldowns wiped early by a reset ability count as "back up" too.
- A minimum-cooldown setting keeps the global cooldown and filler abilities quiet.

## Usage

`/ncp` opens the options window. Everything is also reachable from slash commands:

| Command | Effect |
| --- | --- |
| `/ncp` | open/close the options window |
| `/ncp on` / `/ncp off` | enable or disable pulses |
| `/ncp unlock` / `/ncp lock` | move the anchor |
| `/ncp test` | show a test pulse |
| `/ncp size <16-160>` | icon size in pixels |
| `/ncp alpha <0-1>` | peak alpha |
| `/ncp hold <0-5>` | seconds at full alpha before fading |
| `/ncp min <1-600>` | ignore cooldowns shorter than this |
| `/ncp lead <0-2>` | how early to announce, in seconds |
| `/ncp sound on\|off` | sound cue toggle |
| `/ncp sound file <path>` | use a custom sound file |
| `/ncp resetpos` | recenter the anchor |
| `/ncp resetspells` | clear your picks, back to automatic |
| `/ncp resetall` | factory reset |
| `/ncp priority` | order the icons when several land together |
| `/ncp resetpriority` | clear that order |
| `/ncp find <name>` | why an ability is or is not being tracked |
| `/ncp diag` | what the client currently lets the addon see |
| `/ncp debug` | log every pulse and every suppressed pulse |

## Known issues

**Abilities that transform into a second ability can still miss a pulse.** Wake of
Ashes becoming Hammer of Light is the example this was built against, and it works,
but the family of abilities that behave this way is not fully mapped yet. If one of
yours misbehaves, `/ncp find <name>` and `/ncp debug` will show whether the cast was
recognised and whether a timer is counting - that is the information needed to fix
it.

## How tracking works

Display settings are account-wide (`CooldownPulseDB`); which abilities you watch is
saved per character (`CooldownPulseCharDB`), since spellbooks differ.

An ability you have never touched in the picker follows the automatic rule: on if
its base cooldown is at least the minimum-cooldown setting. Tick or untick it and
your choice sticks; "Back to auto" clears the overrides again. General, racial and
profession abilities are left out entirely unless you ask for them.

Since Midnight, cooldown *numbers* are Secret Values: an addon may display them but
never read or calculate with them. What is not secret is the fact that a cooldown is
running - `C_Spell.GetSpellCooldown` returns `isActive` and `isOnGCD`, both readable
everywhere, including inside a raid encounter.

So that is the whole engine. Watched abilities are polled ten times a second, the
pulse fires the moment `isActive` stops being true, and `isOnGCD` keeps the global
cooldown from being mistaken for an ability coming back. Cooldown lengths are timed
with the addon's own clock, which is always allowed, so they are learned during real
fights rather than only in a city.

The early notice is exact whenever the client is willing to show an end time - out
of combat, or for abilities Blizzard leaves readable. In combat it is predicted from
a length the addon has timed itself. Cooldown reduction can only make that
prediction late, never early, so it degrades to an on-time pulse rather than a wrong
one.

Pulses are suppressed for a few seconds after login, a zone change, or a talent swap
so a fresh spellbook does not spam the screen.

`/ncp diag` prints which of these the client is currently permitting - run it in
combat on a target dummy, that is where the answers matter.

## Install

Copy the `nugsCooldownPulse` folder into
`World of Warcraft\_retail_\Interface\AddOns\`, then `/reload` or restart the game.

## License

Copyright (c) 2026 nugs. All Rights Reserved. See [LICENSE](LICENSE).
