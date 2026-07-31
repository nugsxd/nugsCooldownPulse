--------------------------------------------------------------------------------
-- nugsCooldownPulse
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsCooldownPulse  -  Pulse.lua
-- The on-screen display: a movable anchor and a pool of icons that pop in, hold and
-- fade out. In single mode one icon shows at a time and the rest wait their turn; in
-- row mode everything that came up together is shown side by side. Either way the
-- order is decided by the priority list, because a macro that fires two cooldowns at
-- once should not leave the choice of which you see first to a race.
--------------------------------------------------------------------------------
local ADDON_NAME, CDP = ...

local Pulse = {}
CDP.Pulse = Pulse

local anchor
local icons  = {}   -- every icon frame ever created
local active = {}   -- the ones animating right now, in display order
local queue  = {}   -- waiting their turn
Pulse.queue  = queue

local lastFired      = {}
local flushScheduled = false

local GAP_RATIO   = 0.15    -- spacing between icons, as a fraction of icon size
local NO_PRIORITY = 10000   -- sorts after anything explicitly ranked

--------------------------------------------------------------------------------
-- Anchor
--------------------------------------------------------------------------------
local function SavePosition()
    local point, _, _, x, y = anchor:GetPoint(1)
    if not point then return end
    CDP.db.anchor.point = point
    CDP.db.anchor.x     = math.floor(x + 0.5)
    CDP.db.anchor.y     = math.floor(y + 0.5)
end

function Pulse:Init()
    if anchor then return end
    local db = CDP.db

    anchor = CreateFrame("Frame", "nugsCooldownPulseAnchor", UIParent)
    anchor:SetSize(db.size, db.size)
    anchor:SetPoint(db.anchor.point, UIParent, db.anchor.point, db.anchor.x, db.anchor.y)
    anchor:SetFrameStrata("HIGH")
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    anchor:EnableMouse(false)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self) self:StartMoving() end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    -- Unlocked-only visuals.
    anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
    anchor.bg:SetAllPoints()
    anchor.bg:SetColorTexture(0.35, 0.72, 1.0, 0.20)
    anchor.bg:Hide()

    anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    anchor.label:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
    anchor.label:SetText("nugsCooldownPulse |cff888888(drag)|r")
    anchor.label:Hide()

    self:InitMasque()
    self:ApplySettings()
end

--------------------------------------------------------------------------------
-- Icon pool
--------------------------------------------------------------------------------
local function StyleIcon(ic)
    local db = CDP.db
    ic:SetSize(db.size, db.size)
    ic.name:SetShown(db.showName)

    if CDP.masqueActive then
        ic.border:Hide()            -- the skin owns the border and the icon's trim
    else
        ic.border:Show()
        ic.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end

    local flags = (db.fontOutline ~= "NONE") and db.fontOutline or ""
    local ok, applied = pcall(ic.name.SetFont, ic.name, CDP.FontPath(), db.fontSize, flags)
    -- SetFont reports failure rather than erroring when a font file will not load.
    if not ok or applied == false then
        ic.name:SetFontObject("GameFontNormal")
    end
end

local function NewIcon()
    -- A Button rather than a Frame: Masque skins buttons, and this costs nothing
    -- when Masque is absent since the mouse is disabled either way.
    local ic = CreateFrame("Button", "nugsCooldownPulseIcon" .. (#icons + 1), anchor)
    ic:EnableMouse(false)
    -- Size it before anything else touches it. A skin asked to dress a 0x0 button
    -- computes its border from nothing, and the result is a texture stretched across
    -- half the screen.
    ic:SetSize(CDP.db.size, CDP.db.size)
    ic:SetScale(1)
    ic:SetAlpha(0)
    ic:Hide()

    ic.border = ic:CreateTexture(nil, "BACKGROUND")
    ic.border:SetPoint("TOPLEFT", -2, 2)
    ic.border:SetPoint("BOTTOMRIGHT", 2, -2)
    ic.border:SetColorTexture(0, 0, 0, 0.9)

    ic.tex = ic:CreateTexture(nil, "ARTWORK")
    ic.tex:SetAllPoints()
    ic.icon = ic.tex   -- the name Masque and friends look for

    ic.name = ic:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ic.name:SetPoint("TOP", ic, "BOTTOM", 0, -4)
    ic.name:SetJustifyH("CENTER")

    ic:SetScript("OnUpdate", function(self, elapsed) Pulse:Advance(self, elapsed) end)

    icons[#icons + 1] = ic
    StyleIcon(ic)              -- final size and trim first
    Pulse:RegisterMasque(ic)   -- only then hand it to the skin
    return ic
end

local function AcquireIcon()
    for _, ic in ipairs(icons) do
        if not ic.busy then return ic end
    end
    return NewIcon()
end

-- Build the icons up front rather than during a fight. Creating one mid-pulse means
-- it gets skinned at whatever moment it is first needed, which is exactly when a
-- mistake is hardest to see.
local function EnsurePool(count)
    for _ = #icons + 1, count do NewIcon() end
end

--------------------------------------------------------------------------------
-- Masque
--------------------------------------------------------------------------------
function Pulse:InitMasque()
    if not CDP.db.masque then return end

    local Masque = _G.LibStub and _G.LibStub("Masque", true)
    if not Masque then return end

    local ok, group = pcall(Masque.Group, Masque, "nugsCooldownPulse", "Pulse Icon")
    if not ok or not group then return end

    self.masqueGroup = group
    CDP.masqueActive = true
end

function Pulse:RegisterMasque(ic)
    if not self.masqueGroup then return end
    pcall(self.masqueGroup.AddButton, self.masqueGroup, ic, { Icon = ic.tex }, "Legacy")
    -- Re-run the skin now that the group has one more correctly sized button in it.
    if self.masqueGroup.ReSkin then pcall(self.masqueGroup.ReSkin, self.masqueGroup) end
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------
local function SortActive()
    table.sort(active, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return (a.startedAt or 0) < (b.startedAt or 0)
    end)
end

local function LayoutIcons()
    local db   = CDP.db
    local size = db.size
    local step = size + size * GAP_RATIO
    local grow = db.grow
    local count = #active

    SortActive()

    for index, ic in ipairs(active) do
        local offset
        if grow == "centered" then
            offset = (index - (count + 1) / 2) * step
        else
            offset = (index - 1) * step
        end

        ic:ClearAllPoints()
        if grow == "up" then
            ic:SetPoint("CENTER", anchor, "CENTER", 0, offset)
        elseif grow == "down" then
            ic:SetPoint("CENTER", anchor, "CENTER", 0, -offset)
        elseif grow == "left" then
            ic:SetPoint("CENTER", anchor, "CENTER", -offset, 0)
        else   -- "right" and "centered" both run horizontally
            ic:SetPoint("CENTER", anchor, "CENTER", offset, 0)
        end
    end
end

-- Re-read anything in the DB that affects layout. Safe to call after any option
-- change; running animations just pick up the new numbers.
function Pulse:ApplySettings()
    if not anchor then return end
    local db = CDP.db

    anchor:ClearAllPoints()
    anchor:SetPoint(db.anchor.point, UIParent, db.anchor.point, db.anchor.x, db.anchor.y)
    anchor:SetSize(db.size, db.size)

    EnsurePool(db.mode == "row" and db.maxIcons or 1)
    for _, ic in ipairs(icons) do
        if not ic.busy then ic:SetScale(1) end   -- never re-skin a mid-animation scale
        StyleIcon(ic)
    end
    LayoutIcons()
    self:SetLocked(db.locked)

    if self.masqueGroup and self.masqueGroup.ReSkin then
        pcall(self.masqueGroup.ReSkin, self.masqueGroup)
    end
end

function Pulse:ApplyFont()
    for _, ic in ipairs(icons) do StyleIcon(ic) end
end

function Pulse:ApplyIconStyle()
    for _, ic in ipairs(icons) do StyleIcon(ic) end
end

--------------------------------------------------------------------------------
-- Lock
--------------------------------------------------------------------------------

-- Silent: ApplySettings calls this on every slider tick, so anything chatty or
-- expensive (printing, rebuilding the options list) belongs in ToggleLock.
function Pulse:SetLocked(locked)
    if not anchor then return end
    CDP.db.locked = locked and true or false
    anchor:EnableMouse(not locked)
    anchor.bg:SetShown(not locked)
    anchor.label:SetShown(not locked)
end

function Pulse:ToggleLock(locked)
    self:SetLocked(locked)
    if locked then
        CDP.Print("anchor locked.")
    else
        CDP.Print("anchor unlocked - drag the blue box, then |cffffd479/ncp lock|r.")
        self:Test()   -- give the box something to grab
    end
    if CDP.RefreshOptions then CDP.RefreshOptions() end
end

function Pulse:IsLocked()
    return CDP.db.locked
end

--------------------------------------------------------------------------------
-- Queue
--------------------------------------------------------------------------------
-- Two cues landing in the same breath is a crash, not a cue. This is separate from
-- the 1.5s guard in Pulse:Add, which stops one ability firing twice; this stops two
-- different abilities stacking on top of each other.
local SOUND_GAP = 0.4
local lastCueAt = 0

-- Which cue voices a batch, and whether it is allowed to sound at all.
--
-- `entry` is the highest-priority ability in the batch - Flush sorts the queue before
-- taking any slots, so the first one started is the winner. The sound and the icon
-- therefore agree on what mattered most, with no second ordering concept to learn.
function Pulse:PlayCueFor(entry)
    local db = CDP.db
    if not db.soundEnabled then return end

    local key
    if db.soundMode == "per" then
        -- Unassigned is deliberately silent. See char.sounds in Core.lua.
        key = entry and CDP.char and CDP.char.sounds and CDP.char.sounds[entry.key]
    else
        key = db.soundKey
    end
    if not key then return end

    local now = GetTime()
    if now - lastCueAt < SOUND_GAP then return end
    lastCueAt = now

    CDP.PlayCue(key)
end

function Pulse:Add(entry)
    if not CDP.db.enabled or not anchor then return end

    -- Two tracking paths can spot the same ability coming up within a few frames
    -- of each other, and charge spells can report two recoveries in a row. Nothing
    -- with a real cooldown deserves a second icon this soon.
    local now = GetTime()
    if now - (lastFired[entry.key] or 0) < 1.5 then return end

    for _, ic in ipairs(active) do
        if ic.key == entry.key then return end
    end
    for i = 1, #queue do
        if queue[i].key == entry.key then return end
    end
    lastFired[entry.key] = now

    queue[#queue + 1] = {
        key      = entry.key,
        name     = entry.name,
        icon     = CDP.EntryIcon(entry),
        priority = CDP.GetPriority and CDP.GetPriority(entry) or NO_PRIORITY,
        added    = now,
    }

    -- Over capacity, drop the least important rather than the oldest: if the queue
    -- is overflowing, what you want kept is the cooldown you ranked highest.
    if #queue > CDP.db.maxQueue then
        table.sort(queue, function(a, b)
            if a.priority ~= b.priority then return a.priority < b.priority end
            return a.added < b.added
        end)
        while #queue > CDP.db.maxQueue do table.remove(queue) end
    end

    -- Wait a beat before showing anything. Two cooldowns fired by one macro do not
    -- come back in the same frame, and without this the one that happened to be
    -- noticed first would win regardless of the priority list.
    if not flushScheduled then
        flushScheduled = true
        C_Timer.After(CDP.db.gather, function()
            flushScheduled = false
            Pulse:Flush()
        end)
    end
end

local function StartIcon(item)
    local db = CDP.db
    local ic = AcquireIcon()

    ic.busy      = true
    ic.key       = item.key
    ic.priority  = item.priority or NO_PRIORITY
    ic.startedAt = GetTime()
    ic.elapsed   = 0

    StyleIcon(ic)
    ic.tex:SetTexture(item.icon or 134400)
    ic.name:SetText(item.name or "")
    ic:SetScale(db.popScale)
    ic:SetAlpha(0)
    ic:Show()

    active[#active + 1] = ic
    return ic
end

function Pulse:Flush()
    if #queue == 0 then return end

    table.sort(queue, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.added < b.added
    end)

    local db    = CDP.db
    local slots = (db.mode == "row") and (db.maxIcons - #active) or (1 - #active)

    -- The queue is sorted above, so the first entry taken is the highest priority in
    -- the batch. It is the one that gets to speak for the whole batch.
    local started, voice = 0, nil
    while slots > 0 and #queue > 0 do
        local entry = table.remove(queue, 1)
        voice = voice or entry
        StartIcon(entry)
        slots   = slots - 1
        started = started + 1
    end

    if started > 0 then
        LayoutIcons()
        self:PlayCueFor(voice)   -- one cue for the batch, not one per icon
    end
end

--------------------------------------------------------------------------------
-- Animation
-- Hand-rolled instead of an AnimationGroup so every duration is a live setting:
-- change a slider and the very next pulse uses it, with no frame rebuild.
--------------------------------------------------------------------------------
local function FinishIcon(ic)
    ic.busy = false
    ic.key  = nil
    -- Park it at a neutral scale so it is never re-skinned mid-pop.
    ic:SetScale(1)
    ic:SetAlpha(0)
    ic:Hide()
    for index, other in ipairs(active) do
        if other == ic then
            table.remove(active, index)
            break
        end
    end
    LayoutIcons()

    if #queue > 0 and not flushScheduled then
        flushScheduled = true
        -- A pause between icons in single mode; in row mode the freed slot is
        -- filled as soon as the sorting settles.
        local delay = (CDP.db.mode == "row") and 0 or math.max(0, CDP.db.gap)
        C_Timer.After(delay, function()
            flushScheduled = false
            Pulse:Flush()
        end)
    end
end

function Pulse:Advance(ic, elapsed)
    if not ic.busy then return end

    local db      = CDP.db
    local fadeIn  = math.max(0, db.fadeIn)
    local hold    = math.max(0, db.hold)
    local fadeOut = math.max(0, db.fadeOut)
    local peak    = db.alpha
    local pop     = db.popScale

    ic.elapsed = (ic.elapsed or 0) + elapsed
    local t = ic.elapsed

    if t < fadeIn then
        local p = (fadeIn > 0) and (t / fadeIn) or 1
        ic:SetAlpha(peak * p)
        ic:SetScale(pop + (1 - pop) * p)     -- shrink from "popped" down to size
    elseif t < fadeIn + hold then
        ic:SetAlpha(peak)
        ic:SetScale(1)
    elseif t < fadeIn + hold + fadeOut then
        local p = (fadeOut > 0) and ((t - fadeIn - hold) / fadeOut) or 1
        ic:SetAlpha(peak * (1 - p))
        ic:SetScale(1)
    else
        ic:SetAlpha(0)
        FinishIcon(ic)
    end
end

--------------------------------------------------------------------------------
-- Test
--------------------------------------------------------------------------------
function Pulse:Test()
    if not anchor then return end

    local shown = 0
    for _, entry in ipairs(CDP.watch) do
        self:Add(entry)
        shown = shown + 1
        if shown >= (CDP.db.mode == "row" and CDP.db.maxIcons or 3) then break end
    end

    if shown == 0 then
        -- Nothing selected yet: fall back to a stock icon so the preview still works.
        self:Add({ key = "test", kind = "spell", id = 0, name = "Test Pulse", icon = 135726 })
    end
end
