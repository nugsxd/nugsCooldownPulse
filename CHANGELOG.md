# Changelog

## 0.19.1

- **The settings window gets out of the way while you place the pulse.** Unlocking the
  anchor hides it and puts up a small bar instead - Lock anchor, Reset position, Test -
  and locking brings the window back exactly where it was. Placing the icon meant
  dragging a box the window was usually sitting on top of, so the window had to be
  shoved aside and dragged back every time.
- The bar can be dragged if it is in the way, and Escape locks the anchor rather than
  just dismissing it - hiding it while the anchor was still unlocked would have left
  nothing on screen to end that state.
- `/ncp unlock` puts the bar up too. If the settings window was not open when you
  unlocked, locking does not conjure one.
- **Fixed: a dropdown could run off the bottom of a smaller screen.** Four of them
  dropped straight down from their button with no check that there was room below and
  no clamping, while the lists beside them already handled it. They now open upwards
  when there is no room, and are clamped as a backstop - clamping alone would slide a
  list up over the button that opened it, hiding the thing being changed.
- **The settings window closes when a fight starts, and the anchor locks.** Not because
  anything here would be blocked - none of these windows touch a secure frame, so
  nothing throws "action blocked" the way an addon driving action bars does. The
  reason is that both states put fake data on screen: unlocking runs a test pulse so the anchor has something to grab, and sample
  data during a real pull cannot be told apart from the real thing. Nothing reopens
  when combat drops.

## 0.19.0

- **Use your own sound files.** Open any cue list, pick **+ Add your own**, paste the
  path to an `.ogg` or `.mp3`, and press Test. It plays straight away if the path is
  right, and says what is wrong if it is not. Name it and it joins the cue list — so
  it can be the main cue, or assigned to a single cooldown in the Sounds pane.
- **Test really does test.** The client returns nothing at all for a file it cannot
  find, so the path is verified before it is kept rather than failing silently mid
  pull. The game's own sound settings are checked first, so a muted client is reported
  as a muted client instead of being blamed on the path.
- **Cues are shared with the other nugs addons.** A sound added here shows up in
  nugsCastBars and the other way round, through the same plain global the addons
  already use to find each other. Neither depends on the other, and nugsSuite is not
  required for it.
- **Your own cues are at the top of the list**, with **+ Add your own sound file** as
  the first row. With a LibSharedMedia pack loaded that list runs to dozens, and
  anything at the bottom of it was found by scrolling or not at all.
- **The scroll bar can be grabbed and dragged.** It was drawn as a texture, and a
  texture cannot take mouse input at all - so it showed you where you were in a list
  and gave you no way to act on it, leaving the wheel as the only way down a long one.
  It is a real bar now: drag the thumb, or click the track to page toward the click.
  The wheel still works exactly as before.
- `/ncp sound file <path>` now verifies the path, names the cue after the file, and
  adds it to the library instead of filling a single unnamed slot. An existing custom
  file is carried over automatically and keeps working.
- **Lists close when you click away from them.** They stayed open until something was
  selected or the button was pressed again.
- **Fixed: a list could be cut off at the edge of the panel it opened from.** It was
  attached to whichever frame its button sat in, and when that was a scrolling pane the
  list was clipped by it - a scroll frame clips its children. Lists now hang off the
  screen itself, so they overhang the window instead of being cut in half.
- **Fixed: closing the window with Escape left an open list floating on screen.**
  Lists hang off the screen itself now rather than off the window, which is what stops
  a scrolling pane clipping them - and also cut the tie that used to take them down
  with it. A list now watches the control it was opened from and closes when that goes
  away, so it cannot outlive its window however the window was closed. Escape closes
  the list first and the window second, which is the order people expect.

## 0.18.1

- **Fixed: a pop-up list came up empty the first time and only filled in on the
  second click.** Its width was read from the scroll frame, which is sized by
  anchors and so still measures zero on the frame it was created in - every row was
  built zero-wide. The width now comes from the pop-up's own size, which is known
  immediately.
- Pop-up lists are lifted off the window's near-black background and edged in
  storm-blue, so a floating list reads as sitting on top of the panel rather than
  disappearing into it.

## 0.18.0

- X and Y sit side by side. They are a pair and are read together, and stacking them
  spent height in a column that had room to spare.
- The profile section now says which profile is **loaded**, and marks it
  |cffd8a13f(modified)|r the moment you change anything - because after that you are no
  longer on it, and a label that just echoed the last name you clicked would be wrong
  within seconds. Save writes your changes back; Load throws them away.

## 0.17.0

- **Profiles.** Save the current look under a name, then load it on any other
  character. Profiles live in the account-wide saved variables, so one made on your
  main is visible from every alt - no strings to copy, no export and re-import.
- **Your tracked spells are not part of a profile.** They stay per character, because
  a rogue and a mage do not have the same spells and a profile that quietly rewrote
  that list would be a trap rather than a convenience. A profile is the look.
- Loading is always something you ask for. A fresh character is left alone.
- **The pulse position can be typed.** X and Y boxes under Layout, as offsets from
  the centre of the screen, for anyone who wants the icon in exactly the same place
  on every character rather than wherever the drag landed. Dragging still works.
- The boxes commit on Enter or when you click away, ignore anything that is not a
  number rather than zeroing the value, and clamp - so a stray extra digit cannot
  park the anchor somewhere it can never be dragged back from.

## 0.16.1

- **Fixed: clicking the sound cue button threw an error and opened nothing.** The
  button was written as `local soundBtn = Button(..., function() ... soundBtn ... end)`,
  and a local's scope starts *after* the statement that declares it - so the click
  handler was reaching for a global of that name and finding nil. Declaring it on
  its own line first fixes it.
- The cue list opens **upwards** when there is no room below, instead of dropping
  off the bottom of the screen, and now sits above the window rather than behind
  the buttons it was anchored to.

## 0.16.0

**Sound was rebuilt.** It used to play one cue for everything, which told you that
*something* was ready but not what - so you still had to look, and the cue only
bought you the glance.

- **A cue per ability.** Set `Cue` on the left to "one per ability", then use the
  new **Sounds** face of the right-hand pane to give each tracked ability its own.
  "One for everything" is still there and is still the default, so nothing changes
  unless you go looking.
- Anything you have not assigned a cue to **pulses silently**. That makes sound a
  whitelist: picking a cue is how you say this one matters. Nobody can tell twenty
  cues apart through raid noise, and a design that invites filling in every row
  produces something you end up switching off entirely.
- **LibSharedMedia sounds are picked up**, exactly as fonts already were. Sounds
  were the one media kind in this addon that ignored it, for no good reason. The
  six built-in cues are still there and nothing depends on LSM being installed.
- Cues are chosen from a scrolling list now rather than a button you clicked
  repeatedly to cycle. Clicking a name plays it, because a list of sound names
  tells you nothing until you hear one.

**When several cooldowns come up together, the highest-priority one voices the
batch.** Playing all of them is a crash rather than a cue, and staggering them is a
little tune every pull that you stop hearing by the third note. This reuses the
existing pulse priority list, so the sound and the icon always agree about what
mattered most. A 0.4s floor between cues stops two batches landing on top of each
other - separate from the 1.5s guard that stops one ability firing twice.

- The Sounds pane lists only abilities that are actually tracked. Offering a cue
  for something that never pulses is a setting that can only disappoint.
- `/ncp sound one|per` switches modes from chat.

## 0.15.3

- CurseForge project id (**1628365**) recorded in the .toc, so addon managers can
  tie an installed copy back to the project and offer updates.
- Dropped the placeholder note that stood in for it.

## 0.15.2

- A single line in the options window - "Part of the nugs suite" - shown only when
  nugsSuite is not installed. A note, not a warning, and not a dependency: this
  addon works exactly the same on its own, and the suite is only worth having once
  you run more than one of them.

## 0.15.1

- Registers with **nugsSuite**, the new hub addon: it can now list this addon, open
  this window, and carry these settings to another character as part of one profile
  string. Your spell list and priority order travel with it, which is the part of
  this addon actually worth sharing.
- The registration is a single entry written into a plain global table. nugsSuite
  does not have to be installed for it to be harmless, and does not have to load
  first for it to be found - so nothing here changes if you never install it.
- The measured cooldown cache (`learned`) is marked as never exported: it is
  machine-written, per character, and meaningless to anybody else.

## 0.15.0

**The tracking engine was rebuilt on the right foundation.**

`C_Spell.GetSpellCooldown` returns `isActive` and `isOnGCD`, both flagged
NeverSecret - readable in a raid boss fight, in a key, anywhere. Cooldown *numbers*
are hidden in combat; the fact that a cooldown is running never was. Everything
before this was built around the belief that nothing was readable, and every bug
since has been a consequence of that mistake.

- Tracking is now a 10 Hz poll of `isActive`, gated by `isOnGCD`, firing on the
  moment it stops being true. Cooldowns are timed with our own clock, which is
  always legal, so lengths are now learned **during combat** instead of only in a
  city.
- Deleted, as no longer needed: the hidden `Cooldown` widget pool, cast-event
  arming, duration objects, probes, the once-a-second sweep, re-sync passes, the
  stuck-timer watchdog and the spell-id resolution table. Core.lua lost about 200
  lines and gained accuracy.
- Abilities that transform are handled by the same signal, so Wake of Ashes needs no
  special case. A minimum-elapsed guard means the transform window cannot produce a
  false pulse.
- Early notice is exact whenever the client shows an end time, and predicted from a
  timed length otherwise.
- Removed the charge-handling and early-reset settings: both are now decided by the
  client, not by us. Charge counts are secret, so "on every charge" cannot be
  honoured; a cooldown wiped early is indistinguishable from one that finished, so
  it always pulses.

## 0.14.0

- **Stopped trusting `GetSpellBaseCooldown`.** On 12.0 it reports 2s for Blessing of
  Freedom (really 25s), 1s for Divine Steed (really 45s) and nothing for Judgment,
  and three separate decisions were resting on it:
  - the combat filter discarded any pulse whose cooldown looked shorter than the
    minimum, which is why Blessing of Freedom never appeared in a fight;
  - the early notice was scheduled from it, so an ability the client called "2s"
    announced itself as ready a second and a half after being cast;
  - the auto-select rule mis-sorted the same abilities.
- Cooldown lengths are now **learned by watching**. Whenever the client permits a
  real duration to be read, the longest one seen is remembered per character. It is
  real data, it accounts for talents, and it persists.
  - Pulses are only ever discarded on a length actually observed. Unknown means show
    it - the previous behaviour silently dropped abilities.
  - The early notice only schedules once an ability has run its cooldown in view at
    least once. Until then it fires at the true end rather than at a guess.
- `/ncp find` now prints the observed length beside the client's claim, so the two
  can be compared directly.

## 0.13.0

- **Early notice.** Pulses now fire slightly before the cooldown actually ends, so
  that between the fade in and human reaction time the ability is ready the moment
  you reach for it. Default half a second; "Announce this early" under Behaviour, or
  `/ncp lead <0-2>`. Set it to 0 for the old behaviour.
  - Out of combat the end time is readable, so the timing is exact.
  - In combat it is measured from the cast against the ability's base cooldown, since
    the real end time is a secret value. Cooldown reduction pulls the notice back
    towards the true moment rather than overshooting it, and it will not fire at all
    if the ability is already up.
  - The pulse at the true end is suppressed when an early one already fired.
- Window headers now match RaidReady: 30px bar with a storm-blue underline, the addon
  icon, a gold title with a blue tail, and the same small close button. The priority
  window uses the same header, so the two addons read as one suite.

## 0.12.0

- **Fixed: a stretched skin texture smeared across the screen behind the icons.**
  New icons were handed to Masque before they had been given a size, so the skin
  calculated its border from a 0x0 button. Changing the icon size re-skinned them and
  cleared it, which is why it kept coming back - the next icon created from the pool
  brought it straight back. Icons are now sized and styled before the skin ever sees
  them, and the pool is built up front instead of during a fight.
- Icons are parked at a neutral scale when they finish, so a re-skin can never catch
  one mid-pop.
- **`/ncp` is now the only slash command.** `/cdp`, `/ncdp`, `/cooldownpulse` and
  `/nugscooldownpulse` are gone.

## 0.11.0

- Added the addon's own icon (`icon.blp`) and pointed `IconTexture` at it, so the
  in-game addon list shows the mark rather than a borrowed game texture.
  If it does not load on your client, the .toc carries the one-line revert.

## 0.10.0

- Renamed to **nugsCooldownPulse**. Folder, .toc, window titles, frame names, the
  Masque group and the Blizzard settings entry all carry the name now.
- `/cdp` still works, and so do `/ncdp`, `/nugscooldownpulse` and `/cooldownpulse`.
- The saved-variable names inside the files are deliberately unchanged. WoW names
  saved-variable files after the addon folder, so the rename orphans the old ones;
  copying them across only preserves your settings if the variables inside still
  have the names the file was written with.

## 0.9.0

- **Priority list.** When several cooldowns come back together - a macro firing two
  at once, or haste lining three up - the one you ranked highest is shown first.
  `/cdp priority`, or the button under Layout. Ranks are per character.
- **Row mode.** The display can now show several icons at once instead of one at a
  time, growing centered, left, right, up or down, up to a configurable maximum.
  Single-icon mode is still the default.
- Pulses wait a fraction of a second before appearing so a batch can be sorted by
  priority. Two cooldowns fired by one macro do not come back in the same frame, and
  without the pause the one noticed first would win regardless of the ranking.
- When the queue overflows it now drops the lowest-ranked cooldown rather than the
  oldest, and the queue cap was raised from 5 to 8.
- One sound cue per batch rather than one per icon.

## 0.8.0

First public build. Packaging only - no behaviour changes.

- Added LICENSE (All Rights Reserved) and copyright headers.
- Addon list icon, and author/copyright/license metadata in the .toc.
- README rewritten for release, including a known-issues note: abilities that
  transform into a second ability can still miss a pulse.

## 0.7.0

- General, racial and profession abilities are no longer in the picker at all.
  "Include general/racial/profession" puts them back for anyone who wants them.
- The minimum cooldown length is now the first setting under Behaviour, with a note
  explaining what it does - it decides how much of the spellbook gets picked up.
- Ability name text is configurable: font, outline and size. The font list is the
  four stock game fonts, plus everything from LibSharedMedia when another addon has
  loaded it. Picking one shows a preview list drawn in each font.
- Masque support. If Masque is installed the icon is registered to the group
  "nugsCooldownPulse" and the skin draws the border; without it the plain border is
  used as before. Toggleable, needs a `/reload` to change.

## 0.6.0

- **Cooldowns are now picked up whenever they become visible, not only at the
  instant of the cast.** Arming on the cast assumes the cooldown is queryable right
  then, and for a transforming ability it is not: while Wake of Ashes is Hammer of
  Light, its cooldown reads as the replacement's, which is none - and by the time it
  reverts, the cast is long gone. A once-a-second sweep now retries anything that is
  not already counting, which also catches cooldowns no cast of ours started.
- Added a way to ask whether a hidden timer is actually counting: a cleared cooldown
  reports a plain zero, a running one reports a secret value, and "the client
  refuses to show me this" is itself the answer. That replaces most of the timing
  guesswork - idle timers are released immediately instead of after a grace window,
  and a timer that stops without reporting done is recognised as an early reset.
- Watchdog: no timer can stay armed for longer than twice its own cooldown, so a
  misread can never block an ability permanently.
- `/cdp diag` reports whether timer state is readable; `/cdp find` lists each
  timer and whether it is counting.

## 0.5.0

- **Root cause of the transforming-ability failures.** The spellbook reports
  `spellID` as whatever an ability is transformed into *right now* - press Wake of
  Ashes and the slot becomes Hammer of Light. The addon keyed everything on that,
  so the catalog re-keyed itself mid-cooldown, which destroyed the running timer
  and lost the selection. Identity is now taken from `actionID` (the ability
  itself) and normalized through `C_Spell.GetBaseSpell`, so a transform no longer
  changes anything the addon has hold of.
  - Rebuilds reuse the existing entry table for an ability instead of replacing it,
    so running timers keep pointing at something real.
  - Timers that are still counting are never torn down by a rebuild.
  - Casting the transformed ability arms the ability it came from.
- General, racial and profession abilities are no longer selected automatically -
  only the class and active-spec tabs are. They stay listed in the picker, and
  "Include general/racial/profession" turns the old behaviour back on.

## 0.4.0

- **Fixed: abilities that transform were never pulsing.** Wake of Ashes becoming
  Hammer of Light meant the cooldown was reported under an id the timer was not
  watching. Timers are now keyed per ability *and* per spell id, both the base and
  the current override get one, cast ids that no longer match the spellbook are
  resolved against the watch list, and a transforming ability is re-armed shortly
  after the cast (it has not swapped yet at the instant it goes off).
- **Fixed: a probe timer against an ability that was already up stayed "armed"
  forever**, which blocked every later arm of that ability.
- Pulses re-check that the ability is still selected at the moment they fire, so a
  timer cannot outlive the tick that created it.
- Raised the default minimum cooldown from 5s to 20s. At 5s, rotational abilities
  (a 12s Judgment) were auto-selected alongside the real cooldowns. Existing
  profiles keep their saved value - change it with `/cdp min 30`.
- Added `/cdp find <name>`: says whether an ability is tracked, whether that was
  automatic or your choice, its base cooldown, what it is currently transformed
  into, and how many of its timers are running.

## 0.3.0

- **Fixed for real: combat tracking.** Midnight's Secret Values system hands addons
  opaque cooldown data in combat; any arithmetic on it raises a Lua error, so the
  polling engine died on its first comparison every tick of every fight.
  - Every combat number now goes through a `Plain()` guard that returns nil rather
    than something illegal to compute with. The numeric engine simply stands down
    when it is not allowed to look.
  - Added a second, sanctioned tracking path that does not read numbers at all: one
    invisible `Cooldown` widget per ability, driven by the `DurationObject` from
    `C_Spell.GetSpellCooldownDuration(spellID, ignoreGCD)`, pulsing on the widget's
    own `OnCooldownDone`. Timers are armed from `UNIT_SPELLCAST_SUCCEEDED`.
  - Length filtering in combat falls back to base cooldown (static spell data)
    since actual durations are unreadable.
- Added `/cdp diag`: reports what the client is letting the addon see - useful in
  combat, where the answers differ.
- Repeat-pulse guard so the two tracking paths cannot double up on one ability.

## 0.2.0

- **Fixed: no pulses during combat.** Every `SPELLS_CHANGED` opened a two-second
  quiet window, and that event fires constantly mid-fight (spell overrides, form
  swaps, proc-granted abilities), so the addon spent whole fights muted. Quiet
  windows are now only used where every cooldown really does change at once:
  login, loading screens, and spec/talent swaps.
- **Fixed:** the first `/cdp` after logging in closed the options window instead of
  opening it, because a freshly created frame starts shown.
- Added `/cdp debug`: logs every pulse and every pulse that was held back, with the
  reason. Useful for confirming tracking works in a live fight.
- Spellbook rebuilds throttled from 0.5s to 1s, since they walk the whole spellbook.

## 0.1.0

- Initial build: spellbook/trinket cooldown tracking, single pulsing icon on a
  movable anchor, options window and slash commands.
