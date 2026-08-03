--------------------------------------------------------------------------------
-- nugsCooldownPulse
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsCooldownPulse  -  Core.lua
-- Tracking engine. Builds a catalog of trackable spells (from the spellbook) and
-- items (equipped trinkets), watches their cooldowns on a light polling loop, and
-- hands anything that just became available to the pulse display.
--
-- Shared namespace: the second vararg is the same table across every Lua file in
-- this addon, so all state and functions hang off of it.
--------------------------------------------------------------------------------
local ADDON_NAME, CDP = ...

CDP.name    = ADDON_NAME
CDP.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version"))
              or "0.1.0"

local PREFIX = "|cff6fc2ffnugsCooldownPulse|r: "
function CDP.Print(msg)
    print(PREFIX .. tostring(msg))
end

--------------------------------------------------------------------------------
-- API shims
-- Retail 11.x moved most spell functions into C_Spell / C_SpellBook and changed
-- them to return tables. We normalize everything to plain values here so the rest
-- of the file never has to care which client it is running on.
--------------------------------------------------------------------------------
local BANK_PLAYER = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
local TYPE_SPELL  = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell)  or 1
local TYPE_FLYOUT = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout) or 2

--------------------------------------------------------------------------------
-- Secret values (Midnight / 12.0)
-- Combat data is now handed to addons as opaque "secret" values. Reading one is
-- fine; doing arithmetic or comparisons on it raises a Lua error. Every number we
-- pull out of a combat API therefore goes through Plain(), which hands back nil
-- rather than something we are not allowed to compute with. nil simply means
-- "cannot know right now" and the numeric code paths stand down.
--------------------------------------------------------------------------------
local issecretvalue = _G.issecretvalue
CDP.secretsExist = (issecretvalue ~= nil)

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
CDP.Plain = Plain

-- name, icon
local function SpellInfo(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then return info.name, info.iconID end
        return nil
    end
    if _G.GetSpellInfo then
        local name = _G.GetSpellInfo(spellID)
        local icon = _G.GetSpellTexture and _G.GetSpellTexture(spellID)
        return name, icon
    end
    return nil
end

-- Talents can swap one spell for another (e.g. a base ability becoming its
-- upgraded version). The cooldown API follows the override automatically, but the
-- icon does not, so we resolve it for display.
local function OverrideID(spellID)
    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, id = pcall(C_Spell.GetOverrideSpell, spellID)
        if ok and type(id) == "number" and id > 0 then return id end
    end
    return spellID
end

-- Map a transformed ability back to the one it came from. Wake of Ashes becoming
-- Hammer of Light is a different spell id, and the spellbook reports the new id, so
-- without this every identity in the addon changes the moment you press the button.
local function BaseSpellID(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetBaseSpell then
        local ok, id = pcall(C_Spell.GetBaseSpell, spellID)
        if ok and type(id) == "number" and id > 0 then return id end
    end
    if _G.FindBaseSpellByID then
        local ok, id = pcall(_G.FindBaseSpellByID, spellID)
        if ok and type(id) == "number" and id > 0 then return id end
    end
    return spellID
end
CDP.BaseSpellID = BaseSpellID

-- Base (unmodified) cooldown in seconds, or nil when the client will not tell us.
local function BaseCD(spellID)
    local fn = (C_Spell and C_Spell.GetSpellBaseCooldown) or _G.GetSpellBaseCooldown
    if not fn then return nil end
    local ok, ms = pcall(fn, spellID)
    if ok and type(ms) == "number" and ms > 0 then return ms / 1000 end
    return nil
end

-- The spell an on-use item casts. Item cooldowns have no readable "is it running"
-- flag, but the spell they cast does, so trinkets ride the same rails as everything
-- else. A trinket with no use effect simply is not trackable.
local function ItemSpellID(itemID)
    local fn = (C_Item and C_Item.GetItemSpell) or _G.GetItemSpell
    if not fn then return nil end
    local ok, _, spellID = pcall(fn, itemID)
    if ok and type(spellID) == "number" then return spellID end
    return nil
end

local function ItemName(itemID)
    if C_Item and C_Item.GetItemNameByID then
        local n = C_Item.GetItemNameByID(itemID)
        if n then return n end
    end
    local n = _G.GetItemInfo and _G.GetItemInfo(itemID)
    return n or ("Item " .. tostring(itemID))
end

local function ItemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then
        local i = C_Item.GetItemIconByID(itemID)
        if i then return i end
    end
    if _G.GetItemIcon then return _G.GetItemIcon(itemID) end
    return 134400 -- question mark
end

CDP.SpellInfo = SpellInfo

--------------------------------------------------------------------------------
-- Sound cues
-- No LibSharedMedia dependency: a short list of built-in cues, plus a custom file
-- path for anyone who wants their own. Constants are guarded with numeric
-- fallbacks in case a SOUNDKIT entry gets renamed.
--------------------------------------------------------------------------------
local SK = _G.SOUNDKIT or {}
CDP.SOUNDS = {
    { key = "readycheck", name = "Ready Check",  id = SK.READY_CHECK               or 8960  },
    { key = "raidwarn",   name = "Raid Warning", id = SK.RAID_WARNING              or 8959  },
    { key = "ping",       name = "Map Ping",     id = SK.MAP_PING                  or 3175  },
    { key = "levelup",    name = "Level Up",     id = SK.LEVEL_UP                  or 888   },
    { key = "alarm",      name = "Alarm Clock",  id = SK.ALARM_CLOCK_WARNING_3     or 12867 },
    { key = "click",      name = "UI Click",     id = SK.IG_MAINMENU_OPTION_CHECKBOX_ON or 856 },
}

-- The stock list plus whatever LibSharedMedia has, exactly as FontList does it a few
-- lines below. Sounds used to be the one media kind in this addon that ignored LSM,
-- for no reason anybody could defend.
--
-- The two kinds are not played the same way: stock entries are numeric SOUNDKIT ids
-- for PlaySound, LSM entries are file paths for PlaySoundFile. Both shapes live in
-- this list and CDP.PlayCue is the only place that has to know the difference.
--
-- LSM keys are prefixed so they can never collide with a stock key. If LSM is not
-- loaded next session the key simply will not resolve and the cue falls back to the
-- default, which is the honest outcome - the file is genuinely not there.
-- The custom-file slot is deliberately NOT offered in the list.
--
-- WoW can only play a file that already sits inside an addon folder, so "custom
-- sound" really means: quit the game, drop an .ogg somewhere, and type its exact
-- path. That is a setting that mostly produces silence and a shrug. Anyone who wants
-- their own sounds is far better served by a LibSharedMedia pack, which shows up in
-- this list on its own with no path typing at all.
--
-- It stays available to anyone who already set one, and to `/ncp sound file`, so
-- nobody's cue goes quiet because the option stopped being advertised.
--
-- UPDATE: the reasoning above was right about the friction and wrong about one fact.
-- A typed path CAN be verified - see the Custom sounds block further down - so the
-- shrug is gone and named custom cues are now first class. `soundFile` survives as
-- the migration source and nothing else.
--
-- The player's own come FIRST, ahead of the stock cues and anything LibSharedMedia
-- has. A list that opens with a dozen cues somebody else chose buries the one you
-- added thirty seconds ago, and a long LSM pack pushes it off the bottom entirely.
--
-- The old single `soundFile` no longer gets a row of its own: InitDB moves it into
-- customSounds on load, so it is already in the list below under its own name.
function CDP.SoundList()
    local list, seen = {}, {}

    for _, e in ipairs(CDP.CustomSoundList()) do
        -- Same prefixing convention as lsm: below, so a player's cue name can never
        -- collide with a stock key.
        list[#list + 1] = { key = "file:" .. e.name, name = e.name, path = e.path }
        seen[e.name] = true
    end

    for _, s in ipairs(CDP.SOUNDS) do
        if not seen[s.name] then
            list[#list + 1] = s
            seen[s.name] = true
        end
    end

    local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local ok, names = pcall(LSM.List, LSM, "sound")
        if ok and type(names) == "table" then
            for _, name in ipairs(names) do
                if not seen[name] then
                    local ok2, path = pcall(LSM.Fetch, LSM, "sound", name)
                    if ok2 and type(path) == "string" and path ~= "" then
                        list[#list + 1] = { key = "lsm:" .. name, name = name, path = path }
                        seen[name] = true
                    end
                end
            end
        end
    end
    return list
end

--------------------------------------------------------------------------------
-- Custom sounds
--
-- The WoW Lua sandbox has no filesystem API - no directory listing, no existence
-- check, nothing. An addon therefore cannot notice that a player dropped an .ogg
-- into a folder, and no amount of UI changes that. It is also why a LibSharedMedia
-- pack is Lua code: the Register call IS the discovery.
--
-- What the client will do is play any file you name outright, and tell you whether
-- it worked. Measured on 12.0.7:
--
--   PlaySoundFile("Interface/AddOns/EXBoss/Sound/testsplat.ogg", "Master")
--       -> true, 4856          a real file
--       -> (nothing at all)    a missing one - zero return values, not false
--
-- So a typed path can be verified, which is the whole reason this is worth having.
-- The player pastes a path, hears it, names it, and the name joins the cue list.
--------------------------------------------------------------------------------

-- A falsy return from PlaySoundFile means "did not play", which is NOT the same as
-- "file is missing" - a muted client may well produce the same answer. Reading the
-- two CVars first means the message is right either way, and means we never have to
-- know which of the two cases a nil actually was.
function CDP.VerifySound(path)
    path = tostring(path or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if path == "" then return false, "Paste the path to an .ogg or .mp3 file." end

    if (GetCVar("Sound_EnableAllSound") or "1") == "0" then
        return false, "Your game sound is turned off, so nothing can be tested yet."
    end
    if (tonumber(GetCVar("Sound_MasterVolume")) or 1) <= 0 then
        return false, "Master volume is at zero, so nothing can be tested yet."
    end

    local ok = PlaySoundFile(path, "Master")
    if ok then return true, path end
    return false, "No file there. Check the folder name, every subfolder, and that "
        .. "the path ends in .ogg or .mp3. A file added while the game was running "
        .. "needs a full restart, not a /reload."
end

-- Every nugs addon writes its own library into the shared registry, so a cue added
-- in one shows up in the others. The registry is a plain global that each addon
-- creates for itself, so this works with nugsSuite absent - it is not the suite.
--
-- Deduped by path rather than by name: the same file added on two addons under two
-- names is one sound, and showing it twice is just noise.
function CDP.CustomSoundList()
    local list, seenPath = {}, {}

    local function take(entries)
        -- Either shape is accepted: a plain list, or a function returning one. The
        -- nugs addons publish the function form, since the table they would otherwise
        -- hand over is replaced wholesale by a profile import.
        if type(entries) == "function" then
            local ok, resolved = pcall(entries)
            entries = ok and resolved or nil
        end
        if type(entries) ~= "table" then return end
        for _, e in ipairs(entries) do
            if type(e) == "table" and type(e.name) == "string"
               and type(e.path) == "string" and e.path ~= "" and not seenPath[e.path] then
                seenPath[e.path] = true
                list[#list + 1] = { name = e.name, path = e.path }
            end
        end
    end

    take(CDP.db and CDP.db.customSounds)
    local reg = _G.nugsSuiteRegistry
    if type(reg) == "table" then
        for name, entry in pairs(reg) do
            if name ~= ADDON_NAME and type(entry) == "table" then take(entry.sounds) end
        end
    end
    return list
end

function CDP.AddCustomSound(name, path)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false, "Give it a name." end

    local db = CDP.db
    db.customSounds = db.customSounds or {}
    for _, e in ipairs(db.customSounds) do
        if e.name == name then return false, "You already have a cue called that." end
    end
    -- A custom cue that shares a name with a stock or LibSharedMedia one would be
    -- unreachable: SoundList skips a name it has already seen.
    for _, s in ipairs(CDP.SoundList()) do
        if s.name == name then return false, "That name is already taken by a cue in the list." end
    end

    db.customSounds[#db.customSounds + 1] = { name = name, path = path }
    return true
end

function CDP.RemoveCustomSound(name)
    local db = CDP.db
    for i, e in ipairs(db.customSounds or {}) do
        if e.name == name then
            table.remove(db.customSounds, i)
            -- Settings pointing at the cue that just went away would fail silently on
            -- the next pulse, which is the worst way to find out.
            local key = "file:" .. name
            if db.soundKey == key then db.soundKey = CDP.defaults.soundKey end
            local char = CDP.char
            if char and char.sounds then
                for entryKey, assigned in pairs(char.sounds) do
                    if assigned == key then char.sounds[entryKey] = nil end
                end
            end
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Fonts
-- The four stock game fonts always work. If LibSharedMedia happens to be loaded by
-- some other addon we borrow its list too, but nothing here depends on it.
--------------------------------------------------------------------------------
local STOCK_FONTS = {
    { name = "Friz Quadrata TT", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",     path = "Fonts\\ARIALN.TTF"   },
    { name = "Skurri",           path = "Fonts\\SKURRI.TTF"   },
    { name = "Morpheus",         path = "Fonts\\MORPHEUS.TTF" },
}

function CDP.FontList()
    local list, seen = {}, {}
    for _, font in ipairs(STOCK_FONTS) do
        list[#list + 1] = font
        seen[font.name] = true
    end

    local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local ok, names = pcall(LSM.List, LSM, "font")
        if ok and type(names) == "table" then
            for _, name in ipairs(names) do
                if not seen[name] then
                    local ok2, path = pcall(LSM.Fetch, LSM, "font", name)
                    if ok2 and type(path) == "string" then
                        list[#list + 1] = { name = name, path = path }
                        seen[name] = true
                    end
                end
            end
        end
    end
    return list
end

function CDP.FontPath()
    for _, font in ipairs(CDP.FontList()) do
        if font.name == CDP.db.fontKey then return font.path end
    end
    return STOCK_FONTS[1].path
end

CDP.OUTLINES = { "NONE", "OUTLINE", "THICKOUTLINE" }

function CDP.SoundByKey(key)
    for _, s in ipairs(CDP.SoundList()) do
        if s.key == key then return s end
    end
    return CDP.SOUNDS[1]
end

-- Plays one cue, right now, with no gating. Previews call this directly; the pulse
-- path goes through Pulse:PlayCueFor, which decides *which* cue and whether it is
-- allowed to sound at all.
--
-- "Master" on purpose: on any other channel the cue disappears for anyone who has
-- turned sound effects down, which is most of the people who want a cue.
function CDP.PlayCue(key)
    local s = CDP.SoundByKey(key)
    if not s then return end
    if s.key == "custom" then
        local path = CDP.db and CDP.db.soundFile
        if path and path ~= "" then PlaySoundFile(path, "Master") end
    elseif s.path then
        PlaySoundFile(s.path, "Master")
    elseif s.id then
        PlaySound(s.id, "Master")
    end
end

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------
CDP.defaults = {
    enabled       = true,
    size          = 72,      -- icon size in pixels
    alpha         = 1.0,     -- peak alpha
    popScale      = 1.6,     -- icon starts this much larger and shrinks in
    fadeIn        = 0.25,
    hold          = 0.90,
    fadeOut       = 0.50,
    gap           = 0.12,    -- pause between queued icons
    maxQueue      = 8,
    mode          = "single",  -- "single" = one at a time, "row" = several at once
    grow          = "centered",-- row mode: centered | right | left | up | down
    maxIcons      = 4,         -- row mode: most icons on screen at once
    gather        = 0.15,      -- wait this long before showing, so a batch can be
                               -- sorted by priority instead of by luck
    showName      = false,
    fontKey       = "Friz Quadrata TT",
    fontSize      = 14,
    fontOutline   = "OUTLINE",
    masque        = true,
    minCooldown   = 20,      -- ignore anything shorter than this, in seconds. Low
                             -- values sweep in rotational abilities (a 12s
                             -- Judgment) alongside the big cooldowns.
    lead          = 0.5,     -- announce this many seconds early. Between the fade
                             -- in and human reaction time, being told at the exact
                             -- moment means pressing it late.
    onlyInCombat  = false,
    includeGeneral = false,  -- racials, professions, mounts, hearthstone
    trackTrinkets = true,
    -- NOTE: there used to be settings here for charge handling and for early
    -- resets. Both are now decided by the client rather than by us. A charge
    -- ability reports a cooldown until it is back at full charges, and how many
    -- charges are currently held is a secret value we are not shown, so "pulse on
    -- every charge" cannot be honoured. A cooldown wiped early simply stops
    -- reporting, which is indistinguishable from finishing - so it always pulses.
    soundEnabled  = false,
    -- "one": every pulse uses soundKey below, which is what this addon has always
    -- done. "per": each ability uses its own cue from char.sounds, and anything
    -- unassigned pulses silently - see the note on char.sounds.
    soundMode     = "one",
    soundKey      = "readycheck",
    soundFile     = "",
    -- Sound files the player pointed us at themselves: { name = , path = }.
    -- Account wide, so a cue added on one character is there on all of them. See
    -- the Custom sounds block above CDP.VerifySound for why this exists at all.
    customSounds  = {},
    locked        = true,
    anchor        = { point = "CENTER", x = 0, y = 150 },
}

CDP.charDefaults = {
    spells   = {},   -- [spellID]  = true/false   (absent = use the auto rule)
    items    = {},   -- [itemID]   = true/false
    priority = {},   -- [entryKey] = rank, 1 first. Absent = after everything ranked.
    learned  = {},   -- [entryKey] = longest cooldown we have actually watched run

    -- [entryKey] = sound key, used only when db.soundMode == "per".
    --
    -- Absent means SILENT, not "use the default cue". That makes per-ability sound a
    -- whitelist: assigning a cue is how you say this one matters. Nobody can pick
    -- twenty cues apart through raid noise, so the design should make assigning one
    -- the exception rather than something you do to every row.
    --
    -- Per character, like spells and priority, because spell ids are class-specific
    -- and an account-wide table would be empty on every character but one.
    sounds   = {},
}

local function CopyDefaults(dst, src)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local function InitDB()
    CooldownPulseDB     = CopyDefaults(CooldownPulseDB     or {}, CDP.defaults)
    CooldownPulseCharDB = CopyDefaults(CooldownPulseCharDB or {}, CDP.charDefaults)
    CDP.db   = CooldownPulseDB
    CDP.char = CooldownPulseCharDB
    CooldownPulseDB.profiles = CooldownPulseDB.profiles or {}

    -- The old single custom file becomes the first entry in the library, keeping the
    -- cue anyone had set. `soundFile` is left in place rather than cleared: a player
    -- who downgrades should get their sound back, not silence.
    local db = CooldownPulseDB
    if db.soundFile and db.soundFile ~= "" and not db.customSoundsMigrated then
        db.customSoundsMigrated = true
        db.customSounds = db.customSounds or {}
        local already = false
        for _, e in ipairs(db.customSounds) do
            if e.path == db.soundFile then already = true break end
        end
        if not already then
            db.customSounds[#db.customSounds + 1] =
                { name = "Custom file", path = db.soundFile }
        end
        if db.soundKey == "custom" then db.soundKey = "file:Custom file" end
    end
end

--------------------------------------------------------------------------------
-- Profiles
-- Named snapshots of the look, kept in the account-wide saved variables - which is
-- the whole trick. Save one on any character and every other character can see and
-- load it, with no strings to copy and nothing to export.
--
-- Loading is a deliberate act, not something bound to a character. A fresh character
-- is left alone; you load a profile when you want one.
--
-- What a profile does NOT contain: the tracked spell list, the item list and the
-- pulse priority. Those live per character because a rogue and a mage do not have
-- the same spells, and a profile that quietly rewrote them would be a trap rather
-- than a convenience. A profile is the look, and only the look.
--
-- Everything in db is profiled EXCEPT what is listed here, so a setting added later
-- is carried automatically rather than being silently left out until somebody
-- notices.
--------------------------------------------------------------------------------
local PROFILE_SKIP = {
    profiles = true,      -- the store itself, obviously
    activeProfile = true, -- a record ABOUT profiles, never part of one
}

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, sub in pairs(v) do out[k] = DeepCopy(sub) end
    return out
end

-- Written out rather than using `s:trim()`: that is a WoW helper, not Lua, and this
-- file has no business assuming which of them is present.
local function Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
CDP.TrimName = Trim

function CDP.ProfileNames()
    local names = {}
    for name in pairs(CDP.db.profiles or {}) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function CDP.SaveProfile(name)
    name = Trim(name)
    if name == "" then return false end
    local snap = {}
    for k, v in pairs(CDP.db) do
        if not PROFILE_SKIP[k] then snap[k] = DeepCopy(v) end
    end
    CDP.db.profiles[name] = snap
    CDP.db.activeProfile = name
    return true
end

function CDP.LoadProfile(name)
    local snap = CDP.db.profiles and CDP.db.profiles[name]
    if not snap then return false end
    for k, v in pairs(snap) do
        if not PROFILE_SKIP[k] then CDP.db[k] = DeepCopy(v) end
    end
    -- Anything the profile predates stays at whatever it is now; CopyDefaults has
    -- already guaranteed every key exists, so nothing can end up nil.
    CDP.db.activeProfile = name
    if CDP.Pulse and CDP.Pulse.ApplySettings then CDP.Pulse:ApplySettings() end
    if CDP.RefreshOptions then CDP.RefreshOptions() end
    return true
end


-- Which profile the current settings correspond to.
--
-- Returns the name and whether the live settings still MATCH it. Loading a profile
-- and then nudging one slider leaves you on "Raid, modified" - which is the honest
-- answer, and the one that stops somebody assuming their change was saved.
local function ProfileSnapshot()
    local snap = {}
    for k, v in pairs(CDP.db) do
        if not PROFILE_SKIP[k] then snap[k] = DeepCopy(v) end
    end
    return snap
end

local function SameSettings(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not SameSettings(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function CDP.ProfileStatus()
    local name = CDP.db.activeProfile
    local stored = name and CDP.db.profiles and CDP.db.profiles[name]
    if not stored then return nil, false end
    return name, SameSettings(ProfileSnapshot(), stored)
end

function CDP.DeleteProfile(name)
    if not (CDP.db.profiles and CDP.db.profiles[name]) then return false end
    CDP.db.profiles[name] = nil
    return true
end

function CDP.RenameProfile(old, new)
    new = Trim(new)
    if new == "" then return false end
    if not (CDP.db.profiles and CDP.db.profiles[old]) then return false end
    if CDP.db.profiles[new] then return false end          -- never silently overwrite
    CDP.db.profiles[new] = CDP.db.profiles[old]
    CDP.db.profiles[old] = nil
    return true
end

--------------------------------------------------------------------------------
-- Catalog
-- Every spell we could plausibly track, built from the active spellbook. The user
-- picks from this list in the options panel; anything they have not explicitly
-- toggled falls back to the auto rule in DefaultFor().
--------------------------------------------------------------------------------
CDP.catalog = {}          -- array of entries, sorted by group then name
CDP.watch   = {}          -- subset of catalog that is currently enabled
CDP.state   = {}          -- [entry.key] = tracking state

local function AddSpell(list, seen, spellID, group, core)
    spellID = BaseSpellID(spellID)
    if not spellID or seen[spellID] then return end
    local name, icon = SpellInfo(spellID)
    if not name then return end
    seen[spellID] = true
    list[#list + 1] = {
        key    = "s" .. spellID,
        kind   = "spell",
        id     = spellID,
        name   = name,
        icon   = icon,
        baseCD = BaseCD(spellID),
        group  = group or "Spells",
        core   = core and true or false,
    }
end

-- Which spellbook tabs hold the abilities anyone actually wants pulsed: the class
-- tab and the active spec's. Comparing localized names keeps this working in any
-- client language, since both sides come from the same source.
local function CoreLineNames()
    local names = {}
    local className = UnitClass("player")
    if className then names[className] = true end

    local getSpec     = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or _G.GetSpecialization
    local getSpecInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or _G.GetSpecializationInfo
    if getSpec and getSpecInfo then
        local ok, index = pcall(getSpec)
        if ok and index then
            local ok2, _, specName = pcall(getSpecInfo, index)
            if ok2 and specName then names[specName] = true end
        end
    end
    return names
end

local function ScanSpellbook(list, seen)
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
    local coreNames = CoreLineNames()
    local numLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
    for lineIndex = 1, numLines do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
        -- Skip inactive-spec tabs: their spells are not castable right now.
        local usable = line and not line.shouldHide and (not line.offSpecID or line.offSpecID == 0)
        -- Racials, professions, mounts and the rest of the General tab are noise in
        -- the picker, so they are left out of the catalog entirely unless asked for.
        if usable and not (coreNames[line.name or ""] or CDP.db.includeGeneral) then
            usable = false
        end
        if usable then
            local group  = line.name or "Spells"
            local core   = coreNames[group] and true or false
            local offset = line.itemIndexOffset or 0
            local count  = line.numSpellBookItems or 0
            for i = offset + 1, offset + count do
                local info = C_SpellBook.GetSpellBookItemInfo(i, BANK_PLAYER)
                if info and not info.isPassive then
                    if info.itemType == TYPE_SPELL then
                        -- actionID is the ability itself; spellID is whatever it has
                        -- been transformed into right now, which is not an identity
                        -- we can key anything on.
                        AddSpell(list, seen, info.actionID or info.spellID, group, core)
                    elseif info.itemType == TYPE_FLYOUT and info.actionID and _G.GetFlyoutInfo then
                        -- Flyouts (portals, call pets) hide several real spells behind one slot.
                        local _, _, numSlots = _G.GetFlyoutInfo(info.actionID)
                        for slot = 1, (numSlots or 0) do
                            local flyoutSpell, overrideSpell, isKnown = _G.GetFlyoutSlotInfo(info.actionID, slot)
                            if isKnown then
                                AddSpell(list, seen, flyoutSpell or overrideSpell, group, core)
                            end
                        end
                    end
                end
            end
        end
    end
end

local TRINKET_SLOTS = { 13, 14 }

local function ScanItems(list)
    for _, slot in ipairs(TRINKET_SLOTS) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            list[#list + 1] = {
                key   = "i" .. itemID,
                kind  = "item",
                id    = itemID,
                name  = ItemName(itemID),
                icon  = ItemIcon(itemID),
                group = "Trinkets",
            }
        end
    end
end

--------------------------------------------------------------------------------
-- How long is this cooldown?
--
-- GetSpellBaseCooldown cannot be trusted on 12.0: it reports 2s for Blessing of
-- Freedom (really 25s), 1s for Divine Steed (really 45s) and nothing at all for
-- Judgment. Three separate decisions were resting on it - which abilities to track,
-- which pulses to discard, and when to announce early - so a lie there turned into
-- abilities that never pulsed and early notices that fired a second after the cast.
--
-- So we learn instead. Any time the client lets us read a real duration we remember
-- the longest one seen for that ability. Observed data beats a lookup that lies, it
-- accounts for talents automatically, and it persists per character.
--------------------------------------------------------------------------------
function CDP.LearnLength(entry, seconds)
    if not seconds or seconds < 1.6 then return end   -- ignore the global cooldown
    local store = CDP.char.learned
    local known = store[entry.key]
    if not known or seconds > known then
        store[entry.key] = math.floor(seconds * 10 + 0.5) / 10
    end
end

-- Learned length if we have one, otherwise the client's claim, otherwise nil.
function CDP.Length(entry)
    return CDP.char.learned[entry.key] or entry.baseCD
end

-- Only a length we watched with our own eyes is trusted enough to discard a pulse.
function CDP.TrustedLength(entry)
    return CDP.char.learned[entry.key]
end

-- Auto rule for anything the user has not explicitly toggled: on if its base
-- cooldown is at least the minimum. When the client will not report a base
-- cooldown we default to on, because the observed-duration filter at fire time
-- already keeps short cooldowns quiet.
function CDP.DefaultFor(entry)
    if entry.kind == "item" then return CDP.db.trackTrinkets end
    -- Racials, professions, mounts and the rest of the General tab are almost never
    -- what someone wants pulsed. They stay listed in the picker, just unticked.
    if not entry.core and not CDP.db.includeGeneral then return false end
    local length = CDP.Length(entry)
    if length == nil then return entry.core and true or false end
    return length >= CDP.db.minCooldown
end

function CDP.IsEnabled(entry)
    local store = (entry.kind == "item") and CDP.char.items or CDP.char.spells
    local v = store[entry.id]
    if v == nil then return CDP.DefaultFor(entry) end
    return v and true or false
end

-- `defer` skips the watch rebuild so bulk edits (Enable all / Disable all) only
-- pay for it once, at the end.
function CDP.SetEnabled(entry, on, defer)
    local store = (entry.kind == "item") and CDP.char.items or CDP.char.spells
    if CDP.DefaultFor(entry) == on then
        store[entry.id] = nil   -- back to auto
    else
        store[entry.id] = on and true or false
    end
    if not defer then CDP.BuildWatch() end
end

--------------------------------------------------------------------------------
-- Priority
-- Which icon wins when a macro fires two cooldowns together, or haste lines three
-- of them up. Ranks are per character, since they follow the spellbook.
--------------------------------------------------------------------------------
local NO_PRIORITY = 10000

function CDP.GetPriority(entry)
    return CDP.char.priority[entry.key] or NO_PRIORITY
end

-- Tracked abilities in the order they would be shown.
function CDP.PriorityList()
    local list = {}
    for _, entry in ipairs(CDP.watch) do list[#list + 1] = entry end
    table.sort(list, function(a, b)
        local pa, pb = CDP.GetPriority(a), CDP.GetPriority(b)
        if pa ~= pb then return pa < pb end
        return a.name < b.name
    end)
    return list
end

-- Moving one ability assigns explicit ranks to all of them, so the order you see is
-- the order that is stored and nothing shuffles later.
function CDP.MovePriority(key, delta)
    local list = CDP.PriorityList()
    local index
    for i, entry in ipairs(list) do
        if entry.key == key then index = i break end
    end
    if not index then return false end

    local target = index + delta
    if target < 1 or target > #list then return false end

    list[index], list[target] = list[target], list[index]
    wipe(CDP.char.priority)
    for rank, entry in ipairs(list) do
        CDP.char.priority[entry.key] = rank
    end
    return true
end

function CDP.ResetPriority()
    wipe(CDP.char.priority)
end

function CDP.ResetSelections()
    wipe(CDP.char.spells)
    wipe(CDP.char.items)
    CDP.BuildWatch()
end

local watchedKeys = {}

function CDP.BuildWatch()
    wipe(CDP.watch)
    wipe(watchedKeys)
    for _, entry in ipairs(CDP.catalog) do
        if CDP.IsEnabled(entry) then
            CDP.watch[#CDP.watch + 1] = entry
            watchedKeys[entry.key] = true
        end
    end
    -- Drop tracking state for anything no longer watched.
    for key in pairs(CDP.state) do
        if not watchedKeys[key] then CDP.state[key] = nil end
    end
end

function CDP.RebuildCatalog()
    local list, seen = {}, {}
    ScanSpellbook(list, seen)
    ScanItems(list)
    table.sort(list, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.name < b.name
    end)

    -- Reuse the previous entry table whenever the ability is the same one. Running
    -- timers hold a reference to it, and swapping in a fresh table underneath them
    -- would leave those timers pointing at something the addon no longer knows.
    local previous = {}
    for _, entry in ipairs(CDP.catalog) do previous[entry.key] = entry end
    for i, entry in ipairs(list) do
        local old = previous[entry.key]
        if old then
            old.name, old.icon, old.baseCD  = entry.name, entry.icon, entry.baseCD
            old.group, old.core             = entry.group, entry.core
            list[i] = old
        end
    end

    CDP.catalog = list
    CDP.BuildWatch()
    -- NOTE: deliberately no quiet window here. SPELLS_CHANGED fires constantly in
    -- combat (form swaps, procs, spell overrides), so opening a quiet window on
    -- every rebuild kept the addon permanently muted mid-fight. Rebuilding is safe
    -- on its own: tracking state is keyed by entry key and survives, and a brand
    -- new entry starts inactive, which cannot produce a false pulse.
    if CDP.OnCatalogChanged then CDP.OnCatalogChanged() end
end

-- Suppress pulses briefly. Only for moments when every cooldown legitimately
-- changes at once - login, a loading screen, a spec or talent swap - where the
-- client's readings are unreliable or would fire dozens of icons in one frame.
function CDP.Quiet(seconds)
    CDP.quietUntil = math.max(CDP.quietUntil or 0, GetTime() + seconds)
end

--------------------------------------------------------------------------------
-- Tracking loop
--
-- Midnight hides cooldown *numbers* from addons in combat, but it does not hide the
-- fact that a cooldown is running. C_Spell.GetSpellCooldown returns isActive and
-- isOnGCD, both flagged NeverSecret, readable everywhere including a raid boss
-- fight. That single boolean is the whole engine now: poll it, watch for the moment
-- it stops being true, and time the cooldown with our own clock - our timestamps
-- are ours, so measuring and comparing them is always allowed.
--
-- This replaced a much larger machine of hidden Cooldown widgets, cast events,
-- duration objects, probes and watchdogs, which only ever existed because I
-- believed nothing about a cooldown was readable in combat. It was wrong, and
-- everything built on top of it inherited the mistake.
--------------------------------------------------------------------------------
local SCAN_INTERVAL = 0.1
local MIN_REAL      = 1.5   -- anything shorter was a global cooldown or noise

local function EntryIcon(entry)
    if entry.kind == "spell" then
        local _, icon = SpellInfo(OverrideID(entry.id))
        return icon or entry.icon
    end
    return entry.icon
end
CDP.EntryIcon = EntryIcon

--------------------------------------------------------------------------------
-- Single funnel for every pulse, so /ncp debug can explain both what fired and
-- what was held back.
--------------------------------------------------------------------------------
local function CanFire()
    local db = CDP.db
    if not db or not db.enabled then
        CDP.holdReason = "addon disabled"
        return false
    end
    local quiet    = GetTime() < (CDP.quietUntil or 0)
    local combatOK = (not db.onlyInCombat) or InCombatLockdown()
    CDP.holdReason = (quiet and "quiet window") or ((not combatOK) and "out of combat") or nil
    return (not quiet) and combatOK
end

function CDP.FireEntry(entry, why)
    -- The selection can change while a cooldown is running, so it is confirmed at
    -- the moment the icon would appear rather than when tracking started.
    if not CDP.IsEnabled(entry) then
        if CDP.debug then CDP.Print("|cffff8080held|r " .. tostring(entry.name) .. " (not selected)") end
        return
    end
    if not CanFire() then
        if CDP.debug then
            CDP.Print("|cffff8080held|r " .. tostring(entry.name) .. " (" .. (CDP.holdReason or "?") .. ")")
        end
        return
    end
    if CDP.debug then
        CDP.Print("|cff80ff80pulse|r " .. tostring(entry.name) .. " (" .. why .. ")")
    end
    CDP.Pulse:Add(entry)
end

--------------------------------------------------------------------------------
-- Reading state
--------------------------------------------------------------------------------

-- The spell whose cooldown actually represents this entry. For an on-use trinket
-- that is the spell the item casts.
local function EntrySpellID(entry)
    if entry.kind == "spell" then return entry.id end
    return ItemSpellID(entry.id)
end

-- Returns: isRunningACooldown, isThatJustTheGCD, exactEndTime (nil when withheld).
local function ReadState(entry)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local spellID = EntrySpellID(entry)
    if not spellID then return nil end

    local info = C_Spell.GetSpellCooldown(spellID)
    if not info then return nil end

    -- isActive and isOnGCD are NeverSecret. startTime and duration are not, so they
    -- come back nil in combat and we simply do without them.
    local expires
    local start, duration = Plain(info.startTime), Plain(info.duration)
    if start and duration and start > 0 and duration > MIN_REAL then
        expires = start + duration
    end

    return info.isActive and true or false, info.isOnGCD and true or false, expires
end

local function HandleEntry(entry, st, now)
    local active, onGCD, expires = ReadState(entry)
    if active == nil then return end

    local db      = CDP.db
    local running = active and not onGCD

    if running then
        if not st.on then
            st.on        = true
            st.startedAt = now
            st.prefired  = false
        end
        if expires then st.expires = expires end

        -- Early notice. Exact whenever the client is willing to show the end time -
        -- out of combat, or for a spell Blizzard has left readable. Otherwise it is
        -- predicted from the longest run we have timed ourselves. Predicting from a
        -- length that turns out to be too long costs an early icon; it can never
        -- produce a wrong one, because the ability is demonstrably still counting.
        local lead = db.lead or 0
        if lead > 0 and not st.prefired then
            local due
            if st.expires then
                due = st.expires - lead
            else
                local length = CDP.TrustedLength(entry)
                if length and length >= db.minCooldown then
                    due = (st.startedAt or now) + length - lead
                end
            end
            if due and now >= due then
                st.prefired = true
                CDP.FireEntry(entry, "early")
            end
        end

    elseif st.on then
        -- Either the cooldown ended, or the only thing left running is a global
        -- cooldown sitting on top of it. Both mean this ability is back.
        st.on = false
        local elapsed = now - (st.startedAt or now)

        -- We timed that ourselves, so it is real data even in combat - which is how
        -- cooldown lengths get learned during a fight and not just in a city.
        CDP.LearnLength(entry, elapsed)

        local length = math.max(elapsed, CDP.TrustedLength(entry) or 0)
        if elapsed >= MIN_REAL and length >= db.minCooldown and not st.prefired then
            CDP.FireEntry(entry, "ready")
        end
        st.startedAt, st.expires, st.prefired = nil, nil, false
    end
end

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------

-- Reports what the client is actually letting us see. Worth running in combat on a
-- target dummy, since several of the answers change there.
function CDP.Diagnostics()
    local yes = function(v) return v and "|cff80ff80yes|r" or "|cffff8080no|r" end

    CDP.Print("diagnostics (v" .. CDP.version .. ")")
    print("  secret values present: " .. yes(CDP.secretsExist)
        .. "   in combat: " .. yes(InCombatLockdown()))

    local sample = CDP.watch[1]
    if sample then
        local active, onGCD, expires = ReadState(sample)
        print("  isActive readable: " .. yes(active ~= nil)
            .. "   |cff888888(the signal everything runs on)|r")
        print("  exact end times readable right now: " .. yes(expires ~= nil)
            .. (expires and "" or " |cff888888(expected in combat)|r"))
    else
        print("  |cffff8080nothing is being tracked|r")
    end

    local running = 0
    for _, st in pairs(CDP.state) do
        if st.on then running = running + 1 end
    end
    print(string.format("  watching %d abilities, %d on cooldown right now",
        #CDP.watch, running))

    -- Lengths are what the early notice rides on, so an unlearned ability is worth
    -- knowing about.
    local unknown = {}
    for _, entry in ipairs(CDP.watch) do
        if not CDP.TrustedLength(entry) then unknown[#unknown + 1] = entry.name end
    end
    print(string.format("  cooldown lengths learned: %d of %d", #CDP.watch - #unknown, #CDP.watch))
    if #unknown > 0 then
        print("  |cffff8080not yet timed:|r " .. table.concat(unknown, ", "))
        print("  |cff888888they pulse on time; the early notice starts after one run|r")
    end
end

-- Answers "why is this pulsing / why is this not pulsing" for one ability.
function CDP.Explain(text)
    text = (text or ""):lower()
    if text == "" then
        CDP.Print("usage: /ncp find <part of an ability name>")
        return
    end

    local hits = 0
    for _, entry in ipairs(CDP.catalog) do
        if entry.name:lower():find(text, 1, true) then
            hits = hits + 1
            local store    = (entry.kind == "item") and CDP.char.items or CDP.char.spells
            local explicit = store[entry.id]
            local how      = (explicit == nil) and "auto" or (explicit and "you ticked it" or "you unticked it")

            CDP.Print(string.format("%s |cff888888(id %d)|r", entry.name, entry.id))
            print(string.format("   tracked: %s |cff888888(%s)|r   min setting: %ds",
                CDP.IsEnabled(entry) and "|cff80ff80yes|r" or "|cffff8080no|r",
                how, CDP.db.minCooldown))

            -- Both numbers on purpose: where they disagree the client is wrong, and
            -- that disagreement is usually the bug being chased.
            local learned = CDP.TrustedLength(entry)
            print(string.format("   cooldown: %s timed by this addon, %s claimed by the client",
                learned and (learned .. "s") or "|cffff8080not yet timed|r",
                entry.baseCD and (math.floor(entry.baseCD + 0.5) .. "s") or "nothing"))

            local active, onGCD, expires = ReadState(entry)
            if active == nil then
                print("   state: |cffff8080unreadable|r")
            else
                print(string.format("   state: %s%s%s",
                    active and "cooldown running" or "ready",
                    onGCD and " |cff888888(global cooldown)|r" or "",
                    expires and " |cff888888(end time visible)|r" or ""))
            end

            if entry.kind == "spell" then
                local override = OverrideID(entry.id)
                if override ~= entry.id then
                    print(string.format("   currently transformed into: %s |cff888888(id %d)|r",
                        tostring(SpellInfo(override)), override))
                end
            end
        end
    end

    if hits == 0 then
        CDP.Print("nothing in the spellbook matches \"" .. text .. "\".")
    end
end

--------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------
local driver = CreateFrame("Frame")
local sinceScan = 0

driver:SetScript("OnUpdate", function(_, elapsed)
    sinceScan = sinceScan + elapsed
    if sinceScan < SCAN_INTERVAL then return end
    sinceScan = 0

    local db = CDP.db
    if not db or not db.enabled then return end

    local now   = GetTime()
    local state = CDP.state
    for i = 1, #CDP.watch do
        local entry = CDP.watch[i]
        local st = state[entry.key]
        if not st then st = {}; state[entry.key] = st end
        HandleEntry(entry, st, now)
    end
end)
--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local rebuildPending = false
local function ScheduleRebuild()
    if rebuildPending then return end
    rebuildPending = true
    -- One second, not a fraction: SPELLS_CHANGED can fire many times a second
    -- during a fight and a rebuild walks the whole spellbook.
    C_Timer.After(1.0, function()
        rebuildPending = false
        CDP.RebuildCatalog()
    end)
end
CDP.ScheduleRebuild = ScheduleRebuild

--------------------------------------------------------------------------------
-- nugsSuite
--------------------------------------------------------------------------------
-- One entry in a plain global table, which the nugsSuite launcher reads to list
-- this addon, open its options and carry its settings between characters.
--
-- Written unconditionally and without checking whether nugsSuite exists: the table
-- is inert on its own, so this costs nothing when the suite is not installed, and
-- being a global rather than a call into it means neither addon has to load first.
--
-- No SetMinimap here, deliberately - this addon never had a minimap button of its
-- own, so the suite has nothing to fold in. The saved variable names are the old
-- unprefixed ones for the reason spelled out in the .toc.
local function RegisterWithSuite()
    _G.nugsSuiteRegistry = _G.nugsSuiteRegistry or {}
    _G.nugsSuiteRegistry[ADDON_NAME] = {
        title     = "nugsCooldownPulse",
        version   = CDP.version,
        icon      = "Interface\\AddOns\\nugsCooldownPulse\\icon",
        slash     = "/ncp",
        Open      = function() CDP.ToggleOptions() end,
        GetDB     = function() return CooldownPulseDB, CDP.defaults end,
        GetCharDB = function() return CooldownPulseCharDB, CDP.charDefaults end,
        -- Published so the other nugs addons can offer the same cues. A function
        -- rather than the table itself: this runs before the saved variables exist,
        -- and a profile import replaces db.customSounds outright, either of which
        -- would leave a captured reference pointing at the wrong table forever.
        sounds    = function() return CDP.db and CDP.db.customSounds end,
        -- `learned` is a measured cooldown cache: machine written, per character,
        -- and meaningless to anybody else. The spell list and priority order are
        -- the parts of this addon worth sharing, and they stay.
        excludeChar = { learned = true },
    }
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
if C_EventUtils and C_EventUtils.IsEventValid then
    for _, name in ipairs({ "TRAIT_CONFIG_UPDATED", "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" }) do
        if C_EventUtils.IsEventValid(name) then events:RegisterEvent(name) end
    end
end

events:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            InitDB()
            CDP.Pulse:Init()
            if CDP.InitOptions then CDP.InitOptions() end
            RegisterWithSuite()
        end

    elseif event == "PLAYER_LOGIN" then
        CDP.RebuildCatalog()
        CDP.Quiet(3.0)

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Cooldowns read as unreliable garbage across a loading screen.
        CDP.Quiet(3.0)
        ScheduleRebuild()

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
        -- A spec or talent swap wipes every cooldown at once; without this the
        -- next tick would fire an icon for each one.
        if event ~= "PLAYER_SPECIALIZATION_CHANGED" or arg1 == nil or arg1 == "player" then
            CDP.Quiet(2.0)
            ScheduleRebuild()
        end

    else
        -- SPELLS_CHANGED / PLAYER_EQUIPMENT_CHANGED: refresh the catalog, but stay
        -- armed. These fire mid-combat and must not mute the addon.
        ScheduleRebuild()
    end
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------
local function Usage()
    CDP.Print("v" .. CDP.version .. " commands:")
    print("  |cffffd479/ncp|r - open the options window")
    print("  |cffffd479/ncp on|off|r - enable or disable pulses")
    print("  |cffffd479/ncp unlock|lock|r - move the icon anchor")
    print("  |cffffd479/ncp test|r - show a test pulse")
    print("  |cffffd479/ncp debug|r - log every pulse and every suppressed pulse")
    print("  |cffffd479/ncp diag|r - report what the client lets the addon see")
    print("  |cffffd479/ncp find <name>|r - why an ability is or is not being tracked")
    print("  |cffffd479/ncp priority|r - order the icons when several land together")
    print("  |cffffd479/ncp size <16-160>|r, |cffffd479/ncp alpha <0-1>|r")
    print("  |cffffd479/ncp hold <0-5>|r - seconds the icon stays at full alpha")
    print("  |cffffd479/ncp min <1-600>|r - ignore cooldowns shorter than this")
    print("  |cffffd479/ncp lead <0-2>|r - how early to announce, in seconds")
    print("  |cffffd479/ncp sound on|off|r, |cffffd479/ncp sound one|per|r, |cffffd479/ncp sound file <path>|r")
    print("  |cffffd479/ncp resetpos|r, |cffffd479/ncp resetspells|r, |cffffd479/ncp resetall|r")
end

-- One command, deliberately. Aliases only make it ambiguous which one the notes and
-- the options window should say.
SLASH_NUGSCOOLDOWNPULSE1 = "/ncp"
SlashCmdList["NUGSCOOLDOWNPULSE"] = function(msg)
    local db = CDP.db
    if not db then return end

    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "config" or cmd == "options" then
        CDP.ToggleOptions()

    elseif cmd == "on" or cmd == "off" then
        db.enabled = (cmd == "on")
        CDP.Print("pulses " .. (db.enabled and "enabled" or "disabled") .. ".")

    elseif cmd == "unlock" then
        CDP.Pulse:ToggleLock(false)

    elseif cmd == "lock" then
        CDP.Pulse:ToggleLock(true)

    elseif cmd == "test" then
        CDP.Pulse:Test()

    elseif cmd == "diag" then
        CDP.Diagnostics()

    elseif cmd == "find" or cmd == "why" then
        CDP.Explain(rest)

    elseif cmd == "priority" then
        CDP.TogglePriority()

    elseif cmd == "resetpriority" then
        CDP.ResetPriority()
        CDP.Print("pulse priority cleared.")

    elseif cmd == "debug" then
        CDP.debug = not CDP.debug
        CDP.Print("debug " .. (CDP.debug and "on - every pulse and every hold-back is logged."
                                        or "off."))
        if CDP.debug then
            CDP.Print(string.format("watching %d of %d entries, in combat: %s, quiet for %.1fs",
                #CDP.watch, #CDP.catalog, tostring(InCombatLockdown() and true or false),
                math.max(0, (CDP.quietUntil or 0) - GetTime())))
        end

    elseif cmd == "size" then
        local n = tonumber(rest)
        if n then
            db.size = math.max(16, math.min(160, n))
            CDP.Pulse:ApplySettings()
            CDP.Print("icon size set to " .. db.size .. ".")
        else
            CDP.Print("usage: /ncp size <16-160>")
        end

    elseif cmd == "alpha" then
        local n = tonumber(rest)
        if n then
            db.alpha = math.max(0.05, math.min(1, n))
            CDP.Print(string.format("alpha set to %.2f.", db.alpha))
        else
            CDP.Print("usage: /ncp alpha <0-1>")
        end

    elseif cmd == "hold" then
        local n = tonumber(rest)
        if n then
            db.hold = math.max(0, math.min(5, n))
            CDP.Print(string.format("hold time set to %.2fs.", db.hold))
        else
            CDP.Print("usage: /ncp hold <0-5>")
        end

    elseif cmd == "lead" then
        local n = tonumber(rest)
        if n then
            db.lead = math.max(0, math.min(2, n))
            CDP.Print(string.format("announcing %.2fs before cooldowns end.", db.lead))
        else
            CDP.Print("usage: /ncp lead <0-2>")
        end

    elseif cmd == "min" then
        local n = tonumber(rest)
        if n then
            db.minCooldown = math.max(1, math.min(600, n))
            CDP.BuildWatch()
            CDP.Print("ignoring cooldowns shorter than " .. db.minCooldown .. "s.")
        else
            CDP.Print("usage: /ncp min <1-600>")
        end

    elseif cmd == "sound" then
        local sub, arg = rest:match("^(%S*)%s*(.-)$")
        sub = (sub or ""):lower()
        if sub == "on" or sub == "off" then
            db.soundEnabled = (sub == "on")
            CDP.Print("sound " .. sub .. ".")
        elseif sub == "file" and arg ~= "" then
            -- Verified before it is kept. The old version of this took any string and
            -- the player found out it was wrong by hearing nothing.
            local ok, why = CDP.VerifySound(arg)
            if not ok then
                CDP.Print(why)
                return
            end
            local name = arg:match("([^/\\]+)%.%w+$") or "Custom file"
            local added, addWhy = CDP.AddCustomSound(name, arg)
            if not added then
                -- Already in the library under this name: select it rather than
                -- refusing, since asking for it twice plainly means "use this one".
                CDP.Print(addWhy)
            end
            db.soundKey     = "file:" .. name
            db.soundEnabled = true
            CDP.Print("custom sound '" .. name .. "' set from: " .. arg)
        elseif sub == "one" or sub == "per" then
            db.soundMode = sub
            db.soundEnabled = true
            CDP.Print(sub == "per"
                and "one cue per ability. Assign them in the Sounds pane; anything unassigned is silent."
                or  "one cue for every pulse.")
        else
            CDP.Print("usage: /ncp sound on|off | one|per | file <path>")
        end

    elseif cmd == "resetpos" then
        db.anchor = { point = "CENTER", x = 0, y = 150 }
        CDP.Pulse:ApplySettings()
        CDP.Print("anchor position reset.")

    elseif cmd == "resetspells" then
        CDP.ResetSelections()
        CDP.Print("spell selections reset to automatic.")

    elseif cmd == "resetall" then
        for k, v in pairs(CDP.defaults) do
            if type(v) == "table" then
                db[k] = CopyDefaults({}, v)
            else
                db[k] = v
            end
        end
        CDP.ResetSelections()
        CDP.Pulse:ApplySettings()
        CDP.Print("all settings reset to defaults.")

    else
        Usage()
    end

    if CDP.RefreshOptions then CDP.RefreshOptions() end
end
