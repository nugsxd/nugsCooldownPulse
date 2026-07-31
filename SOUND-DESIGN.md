# Sound cues — design

Working notes for rebuilding the sound feature. Not shipped behaviour yet.

## What is there now

`CDP.db.soundEnabled` / `soundKey` / `soundFile`, one cue for everything, six
hardcoded `SOUNDKIT` entries plus a raw file path typed into a box.
`Pulse:PlayCue()` fires once per batch at `Pulse.lua:372` — deliberately *one cue for
the batch, not one per icon*.

Three things are wrong with it:

- **It tells you something is ready, not what.** That is most of the value gone. If
  you already have to look at the icon, the sound only bought you the glance.
- **Fonts use LibSharedMedia and sounds do not**, in the same addon, for no reason
  anyone could defend.
- The custom path is unvalidated and unpreviewed except by one button that plays the
  currently selected cue.

## The shape

### 1. Sound source

`CDP.SoundList()` mirroring the existing `CDP.FontList()` exactly: stock entries
first, LibSharedMedia's `"sound"` media type appended if some other addon has loaded
it, no dependency either way.

The wrinkle is that the two kinds are not played the same way — `SOUNDKIT` entries are
numeric ids for `PlaySound`, LSM entries are file paths for `PlaySoundFile`. So the
list holds `{ name, id }` or `{ name, path }` and one function dispatches:

```lua
function CDP.PlayCue(name)   -- by name, not by key
```

Everything else calls that and never touches `PlaySound` directly.

### 2. Two modes

`db.soundMode = "one" | "per"`

- `one` — current behaviour, unchanged. One cue for every pulse.
- `per` — each ability has its own cue, held in `char.sounds[entryKey]`.

Per-character, keyed the same way as `char.priority`. Spell ids are class-specific, so
an account-wide table would be mostly empty on every character; and per-character data
already travels in a nugsSuite profile.

### 3. The actual design problem: three cooldowns come up at once

This is why per-ability sound is not just a data change. `Pulse:Add` batches, and the
existing comment says one cue per batch on purpose. With per-ability cues, a batch of
three wants three sounds.

| Option | Result |
|---|---|
| Play all together | Noise. Three cues in one frame is a crash, not a cue. |
| Stagger by `gap` | A little tune every pull. By the third you have stopped listening. |
| **Highest priority voices the batch** | One sound, and it is the one you cared most about. |

**Take the third.** It reuses the priority list that already decides which icon draws
first, so the sound and the icon agree, and there is no second ordering concept to
learn. `char.priority` is already keyed by `entry.key`.

Plus a global throttle — roughly 0.4s minimum between cues — so two batches landing
back to back do not overlap. Separate from the existing per-entry 1.5s dedup in
`Pulse:Add`, which stops the *same* ability double-firing; this stops *different*
abilities stacking.

### 4. Where it lives

**Not a new tab.** The right-hand pane already lists exactly the abilities you would
assign sounds to. A Sounds tab would rebuild that list beside it.

Add a two-state switch above the pane:

```
[ Abilities to watch ]  [ Sounds ]
```

In Sounds mode the same list shows **only tracked abilities**, each row carrying a
sound dropdown and a preview button. Search and scroll keep working because it is the
same list.

The alternative is a separate window like `Set pulse priority...`, which matches this
addon's own precedent. It is more consistent but more UI for the same result, and the
priority window exists because ordering needs drag handles that do not fit a row.

### 5. Migration

`soundEnabled`, `soundKey` and `soundFile` keep their current meaning and become the
`one` mode's settings. `soundMode` defaults to `"one"`. Nobody's setup changes.

---

## The open question

**In `per` mode, what does an ability with no assigned sound do?**

- **Falls back to the main cue** — every pulse still makes noise, some of them
  distinctive. Familiar, nothing goes quiet unexpectedly.
- **Stays silent** — sound becomes a spotlight. Assigning a cue is how you say *this
  one matters*, and everything else pulses silently.

**Leaning silent.** The realistic use is two or three abilities — an interrupt, a
defensive, a burst window — not twenty. Nobody can tell twenty cues apart through raid
noise anyway, so a design that encourages assigning a handful is the honest one. Silent
default makes `per` mode a whitelist, which is what people actually want when they ask
for this.

The cost is that switching to `per` mode makes everything go quiet until you assign
something, which needs saying plainly in the UI rather than leaving someone to think
it broke.

---

## Worth saying out loud

Twenty distinct cues is not a feature anyone can use. The UI should make assigning a
sound feel like the exception rather than the default — most rows empty, a few set.
If the design instead invites filling in all of them it will produce something
unpleasant and people will turn sound off entirely, which is worse than where we
started.
