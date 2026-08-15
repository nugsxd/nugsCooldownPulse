--------------------------------------------------------------------------------
-- nugsCooldownPulse
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsCooldownPulse  -  ActionGlow.lua
-- Glows the real action bar button when a cooldown comes back.
--
-- The pulse answers "something is ready" in one place you choose. This answers the
-- same question where your eyes already are - on the button you are about to press.
-- Both come off the same signal, so an ability cannot pulse and not glow.
--
-- Two things make this work on other people's user interfaces, which is where every
-- naive version of this falls over:
--
--   * Buttons are found by ASKING, not by guessing names. Anything carrying an
--     "action" attribute is an action button, whoever built it - Blizzard, Bartender,
--     Dominos, ElvUI, a whole UI suite. The frame walk lives in Core.lua and found
--     120 EllesmereUI buttons and zero Blizzard ones on the machine this was written
--     on, which is exactly the case a name-based version would have missed silently.
--
--   * The glow is OURS. Blizzard's ActionButtonSpellAlertManager draws the proc
--     glow, and borrowing it would make "your cooldown is back" indistinguishable
--     from "this ability just procced" - as well as fighting Blizzard over who owns
--     the state when both want it at once.
--
-- Attaching a texture to a secure button is unrestricted, in and out of combat. What
-- is restricted is changing a button's attributes or moving it, and nothing here
-- does either. The glow is a sibling frame anchored to the button, not a child, so
-- nothing about the button itself is touched.
--------------------------------------------------------------------------------

local ADDON_NAME, CDP = ...

local Glow = {}
CDP.Glow = Glow

-- [button] = our overlay frame. Keyed by the button itself rather than by name,
-- because a fair number of bar addons leave their buttons unnamed.
local overlays = {}

-- entryKey -> the buttons currently holding that ability. Rebuilt from the scan.
local buttonsFor = {}

--------------------------------------------------------------------------------

local function EnsureOverlay(button)
    local o = overlays[button]
    if o then return o end

    -- A sibling of the button, not a child: parenting to a secure frame is legal but
    -- means our frame inherits its visibility rules, and a button hidden by a bar
    -- addon's paging would take the glow with it in ways that are hard to reason
    -- about. Anchored instead, so it follows position without inheriting behaviour.
    o = CreateFrame("Frame", nil, UIParent)
    -- Above the bars, whoever drew them. A bar addon is free to put its buttons on
    -- any strata it likes, and a glow underneath one is a glow nobody sees.
    o:SetFrameStrata("HIGH")
    o:SetFrameLevel(500)
    o:Hide()

    o.tex = o:CreateTexture(nil, "OVERLAY")
    o.tex:SetAllPoints()
    o.tex:SetBlendMode("ADD")
    -- UI-ActionButton-Border, which is the soft square halo Blizzard puts around a
    -- button. The first attempt used Interface\Cooldown\star4 - that is a sparkle
    -- sprite from the spell-alert art, not a border, and at button size it drew
    -- nothing at all: the glow fired on four buttons and none of them changed.
    o.tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")

    o.anim = o:CreateAnimationGroup()
    local grow = o.anim:CreateAnimation("Scale")
    grow:SetScaleFrom(0.7, 0.7)
    grow:SetScaleTo(1.25, 1.25)
    grow:SetDuration(0.35)
    grow:SetOrder(1)
    local fade = o.anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.45)
    fade:SetOrder(2)
    -- Kept so the hold can be re-timed per ability without rebuilding the animation.
    o.fade = fade
    o.anim:SetScript("OnFinished", function() o:Hide() end)

    overlays[button] = o
    return o
end

-- Puts the glow on one button. Everything about placement is read from the button,
-- which is allowed - it is only writing to a secure frame that is restricted.
local function GlowButton(button, hold, color)
    local db = CDP.db
    local o = EnsureOverlay(button)

    local w, h = button:GetWidth(), button:GetHeight()
    if not w or w == 0 then return end          -- a button mid-layout tells us nothing
    -- That border art is mostly transparent margin, so it has to be drawn well
    -- outside the button or the visible part lands under the icon.
    local pad = (db.glowSize or 8) + w * 0.3
    o:SetSize(w + pad * 2, h + pad * 2)
    o:ClearAllPoints()
    o:SetPoint("CENTER", button, "CENTER", 0, 0)

    local c = color or db.glowColor or { 0.35, 0.72, 1.00, 1 }
    o.tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)

    o.anim:Stop()
    o:SetAlpha(1)
    o:Show()
    -- How long it stays before fading. The scale-in is fixed and quick; this is the
    -- part worth varying per ability, because the whole reason to want a longer one
    -- is that you might not be looking at the bar the instant it comes back.
    o.fade:SetStartDelay(math.max(0, (hold or db.glowHold or 0.8) - 0.35))
    o.anim:Play()
end

--------------------------------------------------------------------------------
-- Which buttons hold what
--
-- Rebuilt from the shared scan rather than kept in step by hand. The scan is spread
-- over several frames, so this is asynchronous and callers must not assume the map
-- is populated the instant they ask for it.
--------------------------------------------------------------------------------

-- No "already rebuilding" flag. The scan below queues overlapping requests and
-- answers all of them, so a second call is cheap - and a flag here was what turned
-- one dropped callback into a permanently empty map.
function Glow.Rebuild(force, onDone)
    CDP.ActionButtonReport(function(_, _, _, _, spellSlots, itemSlots)
        wipe(buttonsFor)
        for _, entry in ipairs(CDP.watch or {}) do
            local pool = (entry.kind == "item") and itemSlots or spellSlots
            local hits = entry.id and pool[entry.id]
            if hits then
                buttonsFor[entry.key] = hits
            end
        end
        if onDone then onDone() end
    end, force)
end

--------------------------------------------------------------------------------

-- Called from the same place the on-screen pulse is raised, so the two can never
-- disagree about whether an ability is ready.
-- What this ability should look like, or nil if it should not glow at all.
--
-- "one" mode treats the glow as a single setting that applies to everything watched.
-- "per" mode makes it a whitelist: only abilities you have given a colour to glow,
-- each in its own, for as long as you asked. That is the mode the feature is really
-- for - a bar where everything glows flickers constantly and stops meaning anything,
-- and the useful setup is the three or four that matter most.
local function GlowStyle(entry)
    local db = CDP.db
    if db.glowMode ~= "per" then
        return db.glowColor, db.glowHold
    end
    local per = CDP.char and CDP.char.glows and CDP.char.glows[entry.key]
    if not per then return nil end
    return per.color or db.glowColor, per.hold or db.glowHold
end

function Glow.Fire(entry)
    if not (CDP.db and CDP.db.actionGlow) then return end
    if not entry or not entry.key then return end

    local color, hold = GlowStyle(entry)
    if not color then return end

    local list = buttonsFor[entry.key]
    if not list then return end
    -- Every button holding it, not just the first. The same ability can sit on two
    -- bars, and glowing one of them while the player is looking at the other reads
    -- as the feature being broken.
    for _, b in ipairs(list) do
        if b.frame and b.frame:IsVisible() then GlowButton(b.frame, hold, color) end
    end
end

-- Exposed so the options list can show each ability exactly as it will look.
function Glow.StyleFor(entry) return GlowStyle(entry) end

function Glow.Preview(entry)
    local color, hold = GlowStyle(entry)
    if not color then return end
    for _, b in ipairs(buttonsFor[entry.key] or {}) do
        if b.frame and b.frame:IsVisible() then GlowButton(b.frame, hold, color) end
    end
end

function Glow.Test()
    -- Turning the feature on is what builds the map, so a test run before that has
    -- nothing to work with. Rebuilding here and reporting the wait is better than
    -- saying "nothing is on a bar" about a bar full of abilities.
    if not (CDP.db and CDP.db.actionGlow) then
        CDP.Print("action bar glow is off - switch it on first.")
        return
    end
    -- Always rebuilt, never the cache. A cached map can hold buttons that no longer
    -- exist: bar addons rebuild their frames and the old ones stay around as hidden
    -- orphans, so every glow lands on something real and permanently invisible.
    --
    -- No longer worth announcing - the named lookup makes this instant for anyone
    -- whose bars name themselves by slot, which is most of them.
    Glow.Rebuild(true, function() Glow.ShowAll() end)
end

function Glow.ShowAll()
    local n, names = 0, {}
    for _, list in pairs(buttonsFor) do
        for _, b in ipairs(list) do
            if b.frame and b.frame:IsVisible() then
                GlowButton(b.frame, 4)
                n = n + 1
                if #names < 4 then names[#names + 1] = b.name or ("slot " .. b.slot) end
            end
        end
    end
    -- The button NAMES are printed, so a glow that cannot be seen can still be
    -- chased: /fstack over that button says whether anything is on top of it.
    if n > 0 then
        CDP.Print("glowing " .. n .. " button(s) for 4s: "
                  .. table.concat(names, ", ") .. (n > #names and ", ..." or ""))
        return
    end

    -- Nothing glowed. Which of the two reasons matters, so both are separated:
    -- either no ability matched a button at all, or they matched buttons that are
    -- not on screen.
    local mapped, hidden = 0, 0
    for _, list in pairs(buttonsFor) do
        for _, b in ipairs(list) do
            mapped = mapped + 1
            if b.frame and not b.frame:IsVisible() then hidden = hidden + 1 end
        end
    end
    if mapped == 0 then
        CDP.Print("no watched ability is on any action bar.")
    else
        CDP.Print(string.format(
            "%d button(s) matched but all are hidden - a paged or inactive bar.", hidden))
    end
end

-- The map goes stale whenever the bars change under it. Cheap events only - the full
-- frame walk is not rerun for a single slot being dragged.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
events:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
events:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
events:SetScript("OnEvent", function(_, event)
    -- Nothing is scanned unless the feature is on. Same reasoning as in BuildWatch:
    -- this is not a cost to pay on behalf of a switch nobody has flipped.
    if not (CDP.db and CDP.db.actionGlow) then return end
    -- Coalesced: dragging one ability fires several of these in a row, and each one
    -- would otherwise start its own walk of every frame in the client.
    if events.pending then return end
    events.pending = true

    -- Login gets a long wait, everything else a short one.
    --
    -- The walk is cheap once the interface exists and expensive while it is still
    -- being built - every addon is creating its frames at that moment, which is both
    -- the worst time to be counting them and the time the count is most likely to be
    -- wrong. Waiting costs nothing: nobody is watching an action bar during a
    -- loading screen.
    local delay = (event == "PLAYER_ENTERING_WORLD") and 8 or 1
    C_Timer.After(delay, function()
        events.pending = false
        Glow.Rebuild()
    end)
end)
