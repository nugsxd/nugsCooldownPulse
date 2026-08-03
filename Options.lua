--------------------------------------------------------------------------------
-- nugsCooldownPulse
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsCooldownPulse  -  Options.lua
-- One movable settings window in a flat dark skin: display/behaviour/sound on the
-- left, the searchable spell picker on the right. Widgets are hand-rolled instead
-- of using Blizzard templates, which get renamed between expansions.
--------------------------------------------------------------------------------
local ADDON_NAME, CDP = ...

--------------------------------------------------------------------------------
-- Theme
--------------------------------------------------------------------------------
local C = {
    bg     = { 0.07, 0.07, 0.07, 0.96 },
    header = { 0.10, 0.10, 0.10, 1.00 },
    panel  = { 0.10, 0.10, 0.10, 0.90 },
    input  = { 0.14, 0.14, 0.14, 1.00 },
    btn    = { 0.16, 0.16, 0.16, 1.00 },
    btnHi  = { 0.24, 0.24, 0.24, 1.00 },
    accent = { 0.35, 0.72, 1.00, 1.00 },
    rowA   = { 1, 1, 1, 0.025 },
    rowB   = { 1, 1, 1, 0.055 },
    text   = { 0.82, 0.82, 0.82 },
    faint  = { 0.50, 0.50, 0.50 },
    gold   = { 1.00, 0.84, 0.42 },
}

local ADDON_ICON = "Interface\\AddOns\\nugsCooldownPulse\\icon"

local WIDTH, HEIGHT = 730, 618
local LEFT_W        = 274
local ROW_H         = 22

local window, list, searchBox, countText

-- Which face the right-hand pane is showing: "abilities" to choose what gets tracked,
-- "sounds" to assign a cue to each tracked ability. Two faces of one list rather than
-- a second list beside it - the pane already holds exactly the abilities you would be
-- assigning sounds to.
local paneMode = "abilities"
local widgets = {}   -- everything with a :Refresh()

--------------------------------------------------------------------------------
-- Widget helpers
--------------------------------------------------------------------------------
local function Backdrop(frame, color, borderAlpha)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(color))
    frame.bgTex = bg
    if borderAlpha then
        for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
            local t = frame:CreateTexture(nil, "BORDER")
            t:SetPoint(p[1]); t:SetPoint(p[2]); t:SetHeight(1)
            t:SetColorTexture(0, 0, 0, borderAlpha)
        end
        for _, p in ipairs({ { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local t = frame:CreateTexture(nil, "BORDER")
            t:SetPoint(p[1]); t:SetPoint(p[2]); t:SetWidth(1)
            t:SetColorTexture(0, 0, 0, borderAlpha)
        end
    end
    return bg
end

local function Panel(parent, color)
    local f = CreateFrame("Frame", nil, parent)
    Backdrop(f, color or C.panel, 1)
    return f
end

local function Label(parent, text, template, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    fs:SetText(text)
    fs:SetTextColor(unpack(color or C.text))
    return fs
end

local function SectionHeader(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(text)
    fs:SetTextColor(unpack(C.accent))
    return fs
end

local function Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    Backdrop(b, C.btn, 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b.text:SetTextColor(unpack(C.text))
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self.bgTex:SetColorTexture(unpack(C.btnHi)) end
    end)
    b:SetScript("OnLeave", function(self) self.bgTex:SetColorTexture(unpack(C.btn)) end)
    b:SetScript("OnClick", onClick)
    b.SetLabel = function(self, t) self.text:SetText(t) end
    -- Keeps its frame but drops to the faint colour and stops responding, so a
    -- control that is not in play right now says so instead of lying.
    b.SetGrey = function(self, grey)
        self.text:SetTextColor(unpack(grey and C.faint or C.text))
        if grey then self:Disable() else self:Enable() end
    end
    return b
end

-- Deliberately built to match RaidReady's header so the two read as one suite: a
-- 30px bar with a storm-blue underline, the addon icon on the left, a gold title
-- with a blue tail, and a small flat close button.
local function HeaderBar(f, titleText, tailText)
    local header = CreateFrame("Frame", nil, f)
    Backdrop(header, C.header, 1)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(30)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local accent = header:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetPoint("BOTTOMRIGHT", 0, 0)
    accent:SetHeight(3)
    accent:SetColorTexture(unpack(C.accent))

    local icon = header:CreateTexture(nil, "OVERLAY")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture(ADDON_ICON)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText(titleText .. (tailText and (" |cff8cd2ff" .. tailText .. "|r") or ""))
    title:SetTextColor(unpack(C.gold))

    local close = Button(header, "x", 22, 18, function() f:Hide() end)
    close:SetPoint("RIGHT", -6, 0)

    -- Shown only when nugsSuite is absent. _G.nugsSuite is the suite's own handle,
    -- so this also reads correctly when it is installed but switched off - a
    -- disabled suite is no more use than a missing one.
    --
    -- A note, never a warning, and never a dependency: this addon works perfectly
    -- well on its own and the suite is only worth having once you run more than one.
    if not _G.nugsSuite then
        local suite = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        suite:SetPoint("RIGHT", close, "LEFT", -10, 0)
        suite:SetText("Part of the |cff8cd2ffnugs suite|r")
        suite:SetTextColor(unpack(C.faint))
    end

    return header
end

-- Checkbox: a small square that fills with the accent colour when on.
local function Check(parent, text, getter, setter)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(ROW_H)

    local box = CreateFrame("Frame", nil, b)
    box:SetSize(14, 14)
    box:SetPoint("LEFT", 0, 0)
    Backdrop(box, C.input, 1)

    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(unpack(C.accent))

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", box, "RIGHT", 6, 0)
    fs:SetText(text)
    fs:SetTextColor(unpack(C.text))
    b:SetWidth(math.max(60, fs:GetStringWidth() + 26))

    b:SetScript("OnClick", function()
        setter(not getter())
        if CDP.RefreshOptions then CDP.RefreshOptions() end
    end)
    b:SetScript("OnEnter", function() fs:SetTextColor(1, 1, 1) end)
    b:SetScript("OnLeave", function() fs:SetTextColor(unpack(C.text)) end)

    b.Refresh = function() fill:SetShown(getter() and true or false) end
    widgets[#widgets + 1] = b
    return b
end

-- Slider: title on the left, live value on the right, bar underneath.
local sliderIndex = 0
-- `commit` (optional) runs once when the user lets go of the handle, for work
-- that is too expensive to redo on every tick of a drag.
local function Slider(parent, title, minV, maxV, step, getter, setter, fmt, commit)
    sliderIndex = sliderIndex + 1
    local name = "nugsCooldownPulseSlider" .. sliderIndex

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(40)

    local titleFS = Label(holder, title, "GameFontNormalSmall")
    titleFS:SetPoint("TOPLEFT", 0, 0)

    local valueFS = Label(holder, "", "GameFontHighlightSmall", C.accent)
    valueFS:SetPoint("TOPRIGHT", 0, 0)

    local sl
    local ok = pcall(function()
        sl = CreateFrame("Slider", name, holder, "OptionsSliderTemplate")
    end)
    if not ok or not sl then
        -- Template missing on this client: fall back to a bare slider we skin ourselves.
        sl = CreateFrame("Slider", name, holder)
        sl:SetOrientation("HORIZONTAL")
        local track = sl:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT"); track:SetPoint("RIGHT")
        track:SetHeight(4)
        track:SetColorTexture(0.25, 0.25, 0.25, 1)
        sl:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    end
    sl:SetPoint("TOPLEFT", 2, -18)
    sl:SetPoint("TOPRIGHT", -2, -18)
    sl:SetHeight(16)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end

    -- The template ships Low/High/Text labels we do not want.
    for _, suffix in ipairs({ "Low", "High", "Text" }) do
        local fs = sl[suffix] or _G[name .. suffix]
        if fs and fs.SetText then fs:SetText("") end
    end

    local applying = false
    sl:SetScript("OnValueChanged", function(self, value)
        if applying then return end
        -- SetValueStep does not round for us on every path, and the leftover
        -- float noise would end up in saved variables.
        value = tonumber(string.format("%.4f", math.floor(value / step + 0.5) * step))
        setter(value)
        valueFS:SetText(string.format(fmt or "%.2f", value))
        if CDP.Pulse then CDP.Pulse:ApplySettings() end
    end)
    if commit then
        sl:SetScript("OnMouseUp", function() commit() end)
    end

    holder.Refresh = function()
        applying = true
        local v = getter()
        sl:SetValue(v)
        valueFS:SetText(string.format(fmt or "%.2f", v))
        applying = false
    end
    widgets[#widgets + 1] = holder
    return holder
end

local function EditBox(parent, h, onEnter, onChanged)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetHeight(h or 22)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextInsets(6, 6, 0, 0)
    Backdrop(eb, C.input, 1)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onEnter then onEnter(self:GetText()) end
    end)
    if onChanged then
        eb:SetScript("OnTextChanged", function(self, user) if user then onChanged(self:GetText()) end end)
    end
    return eb
end

-- Wheel-scrolled area. No Blizzard scroll template, just a child frame we shift
-- plus a thin position indicator on the right edge.
local function ScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll.content = content

    -- Frames, not textures. The bar used to be two textures, and a texture cannot
    -- take mouse input - so it showed you where you were and gave you no way to act
    -- on it. On a long list that left the wheel as the only option.
    --
    -- BAR_W is the grab area and is wider than the 3px line you can see: a 3px
    -- target is not something anybody can reliably hit. It overlaps the right edge of
    -- the rows underneath, which is why it is hidden outright when everything fits -
    -- an invisible strip that eats row clicks would be worse than no bar at all.
    local BAR_W = 9

    local bar = CreateFrame("Frame", nil, scroll)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", 0, 0)
    bar:SetWidth(BAR_W)
    bar:EnableMouse(true)

    local track = bar:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", 0, 0)
    track:SetWidth(3)
    track:SetColorTexture(1, 1, 1, 0.05)

    local thumb = CreateFrame("Frame", nil, bar)
    thumb:SetWidth(BAR_W)
    thumb:EnableMouse(true)
    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetPoint("TOPRIGHT", 0, 0)
    thumbTex:SetPoint("BOTTOMRIGHT", 0, 0)
    thumbTex:SetWidth(3)
    thumbTex:SetColorTexture(unpack(C.accent))

    local function MaxScroll()
        return math.max(0, (content:GetHeight() or 1) - (scroll:GetHeight() or 1))
    end

    local function ScrollTo(value)
        local maxScrol = MaxScroll()
        scroll:SetVerticalScroll(math.max(0, math.min(maxScrol, value)))
        scroll:UpdateBar()
    end

    function scroll:UpdateBar()
        local viewH    = self:GetHeight() or 1
        local totalH   = content:GetHeight() or 1
        local maxScrol = math.max(0, totalH - viewH)
        if self:GetVerticalScroll() > maxScrol then self:SetVerticalScroll(maxScrol) end
        if maxScrol <= 0 then
            bar:Hide()
            return
        end
        bar:Show()
        local frac   = math.min(1, viewH / totalH)
        local thumbH = math.max(20, viewH * frac)
        local travel = viewH - thumbH
        local pos    = (self:GetVerticalScroll() / maxScrol) * travel
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -pos)
        -- Kept for the drag maths below, which needs the travel distance and cannot
        -- recompute it from a frame mid-drag without fighting its own SetPoint.
        self.thumbTravel = travel
    end

    -- Cursor position comes back in screen pixels at the *root* scale, so it has to
    -- be divided by the frame's effective scale before it can be compared with
    -- anything measured off the frame itself. Skipping that makes dragging track the
    -- cursor at the wrong speed on any UI scale other than 1.
    local function CursorY()
        local _, y = GetCursorPosition()
        return y / (thumb:GetEffectiveScale() or 1)
    end

    local function OnDrag(self)
        local travel = scroll.thumbTravel or 0
        if travel <= 0 then return end
        -- Cursor down is a decreasing y, and scrolling down is an increasing scroll
        -- value, hence grab minus now rather than the other way round.
        local delta = (self.grabY - CursorY()) * (MaxScroll() / travel)
        ScrollTo(self.grabScroll + delta)
    end

    thumb:SetScript("OnMouseDown", function(self)
        self.grabY      = CursorY()
        self.grabScroll = scroll:GetVerticalScroll()
        thumbTex:SetColorTexture(1, 1, 1, 0.9)
        self:SetScript("OnUpdate", OnDrag)
    end)
    -- OnHide as well as OnMouseUp: releasing the button outside the frame does not
    -- always deliver OnMouseUp, and an OnUpdate left running would drag the list
    -- around with the cursor forever.
    local function EndDrag(self)
        self:SetScript("OnUpdate", nil)
        thumbTex:SetColorTexture(unpack(C.accent))
    end
    thumb:SetScript("OnMouseUp", EndDrag)
    thumb:SetScript("OnHide", EndDrag)

    -- Clicking the track pages toward the click rather than jumping to it. A jump
    -- would be a guess at where in the list that pixel means; a page is the same
    -- thing the wheel does, only faster.
    bar:SetScript("OnMouseDown", function(self)
        local viewH = scroll:GetHeight() or 1
        local top   = thumb:GetTop()
        local bot   = thumb:GetBottom()
        local y     = CursorY()
        if top and bot and y <= top and y >= bot then return end   -- on the thumb
        ScrollTo(scroll:GetVerticalScroll() + ((top and y > top) and -viewH or viewH))
    end)

-- If the content frame is still sitting at zero when the scroll frame gets its
    -- real size, give it that size. A frame positioned by anchors measures 0 until a
    -- layout pass has run, so a caller that sized its content from scroll:GetWidth()
    -- on the very first call built every row zero-wide - which is the "the list is
    -- empty until I click a second time" bug, and it has now been found three times.
    --
    -- Only when it is zero: several callers set a deliberate width, and clobbering
    -- those would trade this bug for a layout one. Rows are anchored to the content's
    -- edges, so they take the corrected width with them.
    scroll:SetScript("OnSizeChanged", function(self)
        if (self.content:GetWidth() or 0) <= 1 then
            self.content:SetWidth(self:GetWidth() or 0)
        end
        if self.UpdateBar then self:UpdateBar() end
    end)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local viewH    = self:GetHeight() or 1
        local maxScrol = math.max(0, (content:GetHeight() or 1) - viewH)
        local new = math.max(0, math.min(maxScrol, self:GetVerticalScroll() - delta * 34))
        self:SetVerticalScroll(new)
        self:UpdateBar()
    end)

    return scroll
end

--------------------------------------------------------------------------------
-- Font picker
-- A dropdown would be the obvious widget, but Blizzard has renamed that one twice
-- in two expansions. This is a plain popup list, and every name is drawn in its own
-- font so the choice is visible before you make it.
--------------------------------------------------------------------------------

-- Popups share the window's near-black background, which makes a floating list hard
-- to separate from the panel behind it. This lifts the fill and draws an accent edge
-- so the thing reads as sitting ON TOP of the window rather than being part of it.
local POPUP_BG = { 0.13, 0.13, 0.15, 0.98 }
-- Shared behaviour for every floating list and panel: closes when you click away
-- from it, closes on Escape, and never outlives the window it belongs to.
--
-- `closeOnOutside` is false for panels that hold typed input. Dismissing a form on a
-- stray click loses whatever was in it, which is worse than an extra click on Close.
--
-- There is no "clicked anywhere" event, so the outside click is caught by a full
-- screen button underneath the popup, shown and hidden with it. It swallows the click
-- that dismisses - first click closes, second one acts - which is how every dropdown
-- in the game behaves, Blizzard's included.
local function AttachPopupBehaviour(popup, closeOnOutside)
    local catcher
    if closeOnOutside then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:RegisterForClicks("AnyUp")
        catcher:Hide()
        catcher:SetScript("OnClick", function() popup:Hide() end)
    end

    -- Escape closes the list rather than the window behind it. Propagation is left on
    -- for every other key, so this never swallows movement or typing; it is turned off
    -- only for the Escape that is actually being handled, which is what stops the same
    -- press also reaching CloseSpecialWindows and shutting the window.
    popup:EnableKeyboard(true)
    popup:SetPropagateKeyboardInput(true)
    popup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and not InCombatLockdown() then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- The anchor is read back from the popup's own SetPoint rather than passed in, so
    -- this works for every caller without any of them having to remember to say who
    -- owns them. IsVisible is false when any ancestor is hidden, which is exactly the
    -- case being watched for.
    local function WatchOwner(self)
        if self.owner and not self.owner:IsVisible() then self:Hide() end
    end

    popup:HookScript("OnShow", function(self)
        local _, relativeTo = self:GetPoint(1)
        self.owner = relativeTo
        self:SetScript("OnUpdate", WatchOwner)
        if catcher then
            catcher:SetFrameStrata(self:GetFrameStrata())
            catcher:SetFrameLevel(110)
            self:SetFrameLevel(120)
            catcher:Show()
        end
    end)
    popup:HookScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        self:SetPropagateKeyboardInput(true)
        if catcher then catcher:Hide() end
    end)
    return popup
end

local function PopupChrome(frame)
    Backdrop(frame, POPUP_BG, 1)
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" },
                         { "TOPLEFT", "BOTTOMLEFT", "v" }, { "TOPRIGHT", "BOTTOMRIGHT", "v" } }) do
        local edge = frame:CreateTexture(nil, "OVERLAY")
        edge:SetPoint(p[1]); edge:SetPoint(p[2])
        if p[3] == "h" then edge:SetHeight(1) else edge:SetWidth(1) end
        edge:SetColorTexture(0.35, 0.72, 1.00, 0.55)
    end
end

local fontPopup

local function ToggleFontPicker(parent, anchorTo, onPick)
    if fontPopup and fontPopup:IsShown() then
        fontPopup:Hide()
        return
    end

    if not fontPopup then
        fontPopup = CreateFrame("Frame", nil, UIParent)
        fontPopup:SetSize(232, 268)
        fontPopup:SetFrameStrata("FULLSCREEN_DIALOG")
        fontPopup:EnableMouse(true)
        fontPopup:SetClampedToScreen(true)
        PopupChrome(fontPopup)
        fontPopup.scroll = ScrollArea(fontPopup)
        fontPopup.scroll:SetPoint("TOPLEFT", 5, -5)
        fontPopup.scroll:SetPoint("BOTTOMRIGHT", -5, 5)
        fontPopup.rows = {}
        AttachPopupBehaviour(fontPopup, true)
    end

    local fonts   = CDP.FontList()
    local content = fontPopup.scroll.content
    -- Width from the popup's own SetSize, NOT from scroll:GetWidth(). The scroll is
    -- sized by anchors, so on the very first call - the frame having been created
    -- microseconds earlier with no layout pass yet - it measures 0, every row is
    -- built zero-wide, and the list looks empty until you click a second time.
    content:SetWidth(fontPopup:GetWidth() - 10)

    for index, font in ipairs(fonts) do
        local row = fontPopup.rows[index]
        if not row then
            row = CreateFrame("Button", nil, content)
            row:SetHeight(22)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * 22)
            row:SetPoint("TOPRIGHT", 0, -(index - 1) * 22)
            row.stripe = row:CreateTexture(nil, "BACKGROUND")
            row.stripe:SetAllPoints()
            row.stripe:SetColorTexture(1, 1, 1, 0)
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", 6, 0)
            row:SetScript("OnEnter", function(self) self.stripe:SetColorTexture(unpack(C.rowB)) end)
            row:SetScript("OnLeave", function(self) self.stripe:SetColorTexture(1, 1, 1, 0) end)
            fontPopup.rows[index] = row
        end

        row.label:SetText(font.name)
        -- Preview in the font itself; fall back quietly if the file will not load.
        local ok, applied = pcall(row.label.SetFont, row.label, font.path, 13, "")
        if not ok or applied == false then
            row.label:SetFontObject("GameFontHighlightSmall")
            row.label:SetText(font.name .. " |cff888888(unavailable)|r")
        end
        row:SetScript("OnClick", function()
            onPick(font.name)
            fontPopup:Hide()
        end)
        row:Show()
    end

    for index = #fonts + 1, #fontPopup.rows do fontPopup.rows[index]:Hide() end

    content:SetHeight(math.max(1, #fonts * 22))
    fontPopup.scroll:SetVerticalScroll(0)
    fontPopup.scroll:UpdateBar()

    fontPopup:ClearAllPoints()
    -- Drop down if there is room, otherwise open upwards. Clamping alone would slide
    -- the list over the button that opened it, which hides the thing being changed.
    local below = (anchorTo:GetBottom() or 0) - fontPopup:GetHeight()
    if below < 20 then
        fontPopup:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", 0, 2)
    else
        fontPopup:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -2)
    end
    fontPopup:Show()
end

--------------------------------------------------------------------------------
-- Sound picker
-- Same popup as the font one. Clicking a row picks it AND plays it, because a list
-- of sound names tells you nothing until you hear one - and the cycling button this
-- replaces already played on every change, so the behaviour is familiar.
--
-- `includeNone` adds a "no sound" row at the top. Per-ability assignment needs a way
-- back to silence; the main cue does not.
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Add your own sound
--
-- Paste a path, press Test, hear it, name it. The name then appears in every cue
-- list from here on, and in the other nugs addons too.
--
-- Test is not decoration: the client returns nothing at all for a file it cannot
-- find, so a path can be checked before it is kept. Without that this panel would be
-- asking people to type an exact string and find out it was wrong by hearing silence
-- during a raid, which is why the addon went years without offering it.
--
-- Declared above ToggleSoundPicker because the picker's last row opens it. A local
-- used above the statement that declares it binds to a nil global instead - a real
-- bug this addon has shipped before.
--------------------------------------------------------------------------------
local addSoundPopup

-- UIParent, not the frame that asked for it. The button that opens this sits inside
-- the left column, which is a ScrollFrame, and a ScrollFrame clips its children - so
-- parenting it there cut the panel off at the pane edge instead of letting it
-- overhang the window.
local function ToggleAddSound(anchorTo, onClose)
    if addSoundPopup and addSoundPopup:IsShown() then
        addSoundPopup:Hide()
        return
    end

    if not addSoundPopup then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(360, 404)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        PopupChrome(f)

        local title = Label(f, "Add your own sound", "GameFontNormal", C.accent)
        title:SetPoint("TOPLEFT", 10, -9)

        -- At the top, not tucked underneath. Everything anybody gets wrong about this
        -- is decided before they reach the box - which folder, whether the game was
        -- running when the file was copied in - so saying it afterwards is saying it
        -- too late.
        local how = Label(f,
            "|cffffd479 1.|r With the game closed, put your |cffffffff.ogg|r or "
            .. "|cffffffff.mp3|r inside any addon folder.\n"
            .. "|cffffd479 2.|r Start the game and paste the path to it below. It "
            .. "begins at |cffffffffInterface/AddOns/|r and includes every folder "
            .. "and the file extension:\n"
            .. "|cff8cd2ff      Interface/AddOns/EXBoss/Sound/testsplat.ogg|r\n"
            .. "|cffffd479 3.|r Press Test. If you hear it, name it and save it.",
            "GameFontDisableSmall", C.faint)
        how:SetPoint("TOPLEFT", 10, -32)
        how:SetPoint("TOPRIGHT", -10, -32)
        how:SetJustifyH("LEFT")
        how:SetJustifyV("TOP")
        how:SetHeight(92)

        local pathLabel = Label(f, "File path", "GameFontHighlightSmall", C.faint)
        pathLabel:SetPoint("TOPLEFT", 10, -130)

        -- Verification is cleared on every edit. A tick left over from the previous
        -- path would be claiming something about a string nobody has tested.
        local pathBox = EditBox(f, 22, nil, function() f.Reset() end)
        pathBox:SetPoint("TOPLEFT", 10, -146)
        pathBox:SetPoint("TOPRIGHT", -10, -146)
        f.pathBox = pathBox

        local status = Label(f, "", "GameFontHighlightSmall", C.faint)
        status:SetPoint("TOPLEFT", 10, -198)
        status:SetPoint("TOPRIGHT", -10, -198)
        status:SetJustifyH("LEFT")
        status:SetJustifyV("TOP")
        status:SetHeight(40)
        f.status = status

        local nameLabel = Label(f, "Name it", "GameFontHighlightSmall", C.faint)
        nameLabel:SetPoint("TOPLEFT", 10, -242)

        local nameBox = EditBox(f, 22, nil, nil)
        nameBox:SetPoint("TOPLEFT", 10, -258)
        nameBox:SetPoint("TOPRIGHT", -10, -258)
        f.nameBox = nameBox

        local save
        local test = Button(f, "Test", 70, 22, function()
            local ok, why = CDP.VerifySound(pathBox:GetText())
            f.verified = ok and (pathBox:GetText():gsub("^%s+", ""):gsub("%s+$", "")) or nil
            status:SetText(ok and "Played. Give it a name and save it." or why)
            status:SetTextColor(unpack(ok and C.accent or C.gold))
            save:SetGrey(not ok)
            if ok and (nameBox:GetText() or "") == "" then
                -- Seeded from the filename, because that is what people were going to
                -- type anyway.
                nameBox:SetText(f.verified:match("([^/\\]+)%.%w+$") or "")
            end
        end)
        test:SetPoint("TOPLEFT", 10, -172)

        save = Button(f, "Save", 70, 22, function()
            if not f.verified then return end
            local ok, why = CDP.AddCustomSound(nameBox:GetText(), f.verified)
            if not ok then
                status:SetText(why)
                status:SetTextColor(unpack(C.gold))
                return
            end
            f.Reset()
            pathBox:SetText("")
            nameBox:SetText("")
            f.RefreshOwn()
            CDP.RefreshOptions()
            status:SetText("Saved. It is in the cue list now.")
            status:SetTextColor(unpack(C.accent))
        end)
        save:SetPoint("TOPLEFT", 10, -284)
        save:SetGrey(true)

        -- Closing goes back to the picker rather than to nothing, since the reason
        -- anybody is here is to pick the cue they just added. Saving deliberately
        -- does NOT: adding two sounds in a row is common and being thrown out to the
        -- list after each one would be worse than an extra click at the end.
        local close = Button(f, "Close", 70, 22, function()
            f:Hide()
            if f.onClose then f.onClose() end
        end)
        close:SetPoint("TOPRIGHT", -10, -284)

        local ownLabel = Label(f, "Your sounds", "GameFontHighlightSmall", C.faint)
        ownLabel:SetPoint("TOPLEFT", 10, -314)

        local scroll = ScrollArea(f)
        scroll:SetPoint("TOPLEFT", 10, -330)
        scroll:SetPoint("BOTTOMRIGHT", -10, 28)
        f.scroll = scroll
        f.rows = {}

        -- The one failure that looks exactly like a wrong path but is not, so it gets
        -- said on its own rather than as a clause inside step 1.
        local warn = Label(f,
            "A file copied in while the game was running needs a full restart - "
            .. "|cffffffff/reload|r is not enough.",
            "GameFontDisableSmall", C.faint)
        warn:SetPoint("BOTTOMLEFT", 10, 7)
        warn:SetPoint("BOTTOMRIGHT", -10, 7)
        warn:SetJustifyH("LEFT")

        function f.Reset()
            f.verified = nil
            save:SetGrey(true)
            status:SetText("")
        end

        -- Only this addon's own entries are listed, and only they get a remove
        -- button. Cues coming from a sibling nugs addon show in the picker but are
        -- that addon's to delete - removing them from here would be reaching into
        -- somebody else's saved variables.
        function f.RefreshOwn()
            local own = (CDP.db and CDP.db.customSounds) or {}
            local content = f.scroll.content
            content:SetWidth(f:GetWidth() - 20)

            for i, entry in ipairs(own) do
                local row = f.rows[i]
                if not row then
                    row = CreateFrame("Frame", nil, content)
                    row:SetHeight(22)
                    row:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
                    row:SetPoint("TOPRIGHT", 0, -(i - 1) * 22)
                    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.label:SetPoint("LEFT", 4, 0)
                    row.label:SetJustifyH("LEFT")
                    row.play = Button(row, "Play", 46, 18, function()
                        if row.path then PlaySoundFile(row.path, "Master") end
                    end)
                    row.play:SetPoint("RIGHT", -30, 0)
                    row.remove = Button(row, "x", 22, 18, function()
                        if row.name then
                            CDP.RemoveCustomSound(row.name)
                            f.RefreshOwn()
                            CDP.RefreshOptions()
                        end
                    end)
                    row.remove:SetPoint("RIGHT", -2, 0)
                    f.rows[i] = row
                end
                row.name, row.path = entry.name, entry.path
                row.label:SetPoint("RIGHT", row.play, "LEFT", -6, 0)
                row.label:SetText(entry.name)
                row:Show()
            end
            for i = #own + 1, #f.rows do f.rows[i]:Hide() end

            content:SetHeight(math.max(1, #own * 22))
            f.scroll:UpdateBar()
        end

        AttachPopupBehaviour(f, false)

        addSoundPopup = f
    end

    addSoundPopup.onClose = onClose
    addSoundPopup.Reset()
    addSoundPopup.RefreshOwn()

    addSoundPopup:ClearAllPoints()
    local below = (anchorTo:GetBottom() or 0) - addSoundPopup:GetHeight()
    if below < 20 then
        addSoundPopup:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", 0, 2)
    else
        addSoundPopup:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -2)
    end
    addSoundPopup:Show()
end

local soundPopup

local function ToggleSoundPicker(parent, anchorTo, includeNone, onPick)
    if soundPopup and soundPopup:IsShown() then
        soundPopup:Hide()
        return
    end

    if not soundPopup then
        soundPopup = CreateFrame("Frame", nil, UIParent)
        soundPopup:SetSize(232, 268)
        soundPopup:SetFrameStrata("FULLSCREEN_DIALOG")
        -- Toplevel and clamped: this opens from rows near the bottom of a scrolling
        -- list, so without these it dropped off the screen edge and slid behind the
        -- buttons it was anchored to.
        soundPopup:SetToplevel(true)
        soundPopup:SetClampedToScreen(true)
        soundPopup:EnableMouse(true)
        PopupChrome(soundPopup)
        soundPopup.scroll = ScrollArea(soundPopup)
        soundPopup.scroll:SetPoint("TOPLEFT", 5, -5)
        soundPopup.scroll:SetPoint("BOTTOMRIGHT", -5, 5)
        soundPopup.rows = {}
        AttachPopupBehaviour(soundPopup, true)
    end

    -- First, not last. The cue list runs to a dozen stock entries before a
    -- LibSharedMedia pack adds however many more, and anything at the bottom of that
    -- is found by scrolling or not at all. CDP.SoundList already puts the player's
    -- own cues ahead of the stock ones for the same reason.
    local sounds = { { addRow = true, name = "|cff59b8ff+ Add your own sound file...|r" } }
    if includeNone then sounds[#sounds + 1] = { key = false, name = "|cff777777No sound|r" } end
    for _, s in ipairs(CDP.SoundList()) do sounds[#sounds + 1] = s end

    local content = soundPopup.scroll.content
    -- Width from the popup's own SetSize, NOT from scroll:GetWidth(). The scroll is
    -- sized by anchors, so on the very first call - the frame having been created
    -- microseconds earlier with no layout pass yet - it measures 0, every row is
    -- built zero-wide, and the list looks empty until you click a second time.
    content:SetWidth(soundPopup:GetWidth() - 10)

    for index, sound in ipairs(sounds) do
        local row = soundPopup.rows[index]
        if not row then
            row = CreateFrame("Button", nil, content)
            row:SetHeight(22)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * 22)
            row:SetPoint("TOPRIGHT", 0, -(index - 1) * 22)
            row.stripe = row:CreateTexture(nil, "BACKGROUND")
            row.stripe:SetAllPoints()
            row.stripe:SetColorTexture(1, 1, 1, 0)
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", 6, 0)
            row.label:SetPoint("RIGHT", -6, 0)
            row.label:SetJustifyH("LEFT")
            row:SetScript("OnEnter", function(self) self.stripe:SetColorTexture(unpack(C.rowB)) end)
            row:SetScript("OnLeave", function(self) self.stripe:SetColorTexture(1, 1, 1, 0) end)
            soundPopup.rows[index] = row
        end

        row.label:SetText(sound.name)
        row:SetScript("OnClick", function()
            if sound.addRow then
                -- Anchored to the button that opened the picker, not to the row, so
                -- the panel does not land wherever the list happened to be scrolled.
                soundPopup:Hide()
                ToggleAddSound(anchorTo, function()
                    ToggleSoundPicker(parent, anchorTo, includeNone, onPick)
                end)
                return
            end
            onPick(sound.key)
            if sound.key then CDP.PlayCue(sound.key) end
            soundPopup:Hide()
        end)
        row:Show()
    end

    for index = #sounds + 1, #soundPopup.rows do soundPopup.rows[index]:Hide() end

    content:SetHeight(math.max(1, #sounds * 22))
    soundPopup.scroll:SetVerticalScroll(0)
    soundPopup.scroll:UpdateBar()

    -- Drop down if there is room, otherwise open upwards. Clamping alone would slide
    -- the list over the button that opened it, which hides the thing you are trying
    -- to change.
    soundPopup:ClearAllPoints()
    local below = (anchorTo:GetBottom() or 0) - soundPopup:GetHeight()
    if below < 20 then
        soundPopup:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", 0, 2)
    else
        soundPopup:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -2)
    end
    soundPopup:Raise()
    soundPopup:Show()
end

--------------------------------------------------------------------------------
-- Name picker
-- A plain list of strings. Used for saved profile names, where typing an exact name
-- from memory is the sort of small friction that makes a feature go unused.
--------------------------------------------------------------------------------
local namePopup

local function ToggleNamePicker(parent, anchorTo, names, onPick)
    if namePopup and namePopup:IsShown() then
        namePopup:Hide()
        return
    end

    if not namePopup then
        namePopup = CreateFrame("Frame", nil, UIParent)
        namePopup:SetSize(200, 200)
        namePopup:SetFrameStrata("FULLSCREEN_DIALOG")
        namePopup:SetToplevel(true)
        namePopup:SetClampedToScreen(true)
        namePopup:EnableMouse(true)
        PopupChrome(namePopup)
        namePopup.scroll = ScrollArea(namePopup)
        namePopup.scroll:SetPoint("TOPLEFT", 5, -5)
        namePopup.scroll:SetPoint("BOTTOMRIGHT", -5, 5)
        namePopup.rows = {}
        AttachPopupBehaviour(namePopup, true)
    end

    local content = namePopup.scroll.content
    -- Width from the popup's own SetSize, NOT from scroll:GetWidth(). The scroll is
    -- sized by anchors, so on the very first call - the frame having been created
    -- microseconds earlier with no layout pass yet - it measures 0, every row is
    -- built zero-wide, and the list looks empty until you click a second time.
    content:SetWidth(namePopup:GetWidth() - 10)

    for index, name in ipairs(names) do
        local row = namePopup.rows[index]
        if not row then
            row = CreateFrame("Button", nil, content)
            row:SetHeight(22)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * 22)
            row:SetPoint("TOPRIGHT", 0, -(index - 1) * 22)
            row.stripe = row:CreateTexture(nil, "BACKGROUND")
            row.stripe:SetAllPoints()
            row.stripe:SetColorTexture(1, 1, 1, 0)
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", 6, 0)
            row.label:SetPoint("RIGHT", -6, 0)
            row.label:SetJustifyH("LEFT")
            row:SetScript("OnEnter", function(self) self.stripe:SetColorTexture(unpack(C.rowB)) end)
            row:SetScript("OnLeave", function(self) self.stripe:SetColorTexture(1, 1, 1, 0) end)
            namePopup.rows[index] = row
        end
        row.label:SetText(name)
        row:SetScript("OnClick", function()
            onPick(name)
            namePopup:Hide()
        end)
        row:Show()
    end
    for index = #names + 1, #namePopup.rows do namePopup.rows[index]:Hide() end

    content:SetHeight(math.max(1, #names * 22))
    namePopup.scroll:SetVerticalScroll(0)
    namePopup.scroll:UpdateBar()

    namePopup:ClearAllPoints()
    local below = (anchorTo:GetBottom() or 0) - namePopup:GetHeight()
    if below < 20 then
        namePopup:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", 0, 2)
    else
        namePopup:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -2)
    end
    namePopup:Raise()
    namePopup:Show()
end

--------------------------------------------------------------------------------
-- Priority window
-- Decides which icon wins when several cooldowns land together. Ordering is done
-- with arrows rather than drag-and-drop: the list is short, and arrows cannot drop
-- a row somewhere you did not mean.
--------------------------------------------------------------------------------
local priorityWindow, priorityList, priorityRows, priorityEmpty

local function RefreshPriority()
    if not priorityWindow then return end
    local entries = CDP.PriorityList()
    local content = priorityList.content

    for index, entry in ipairs(entries) do
        local row = priorityRows[index]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_H)

            row.stripe = row:CreateTexture(nil, "BACKGROUND")
            row.stripe:SetAllPoints()

            row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.rank:SetPoint("LEFT", 6, 0)
            row.rank:SetWidth(18)
            row.rank:SetJustifyH("RIGHT")

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", row.rank, "RIGHT", 6, 0)
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.name:SetJustifyH("LEFT")

            row.down = Button(row, "v", 20, 18, function()
                if CDP.MovePriority(row.key, 1) then RefreshPriority() end
            end)
            row.down:SetPoint("RIGHT", -6, 0)

            row.up = Button(row, "^", 20, 18, function()
                if CDP.MovePriority(row.key, -1) then RefreshPriority() end
            end)
            row.up:SetPoint("RIGHT", row.down, "LEFT", 3, 0)

            row.name:SetPoint("RIGHT", row.up, "LEFT", -6, 0)
            priorityRows[index] = row
        end

        row.key = entry.key
        row.rank:SetText(index)
        row.icon:SetTexture(entry.icon or 134400)
        row.name:SetText(entry.name)
        row.stripe:SetColorTexture(unpack(index % 2 == 0 and C.rowA or { 0, 0, 0, 0 }))
        row:Show()
    end

    for index = #entries + 1, #priorityRows do priorityRows[index]:Hide() end

    content:SetWidth(priorityList:GetWidth())
    content:SetHeight(math.max(1, #entries * ROW_H))
    priorityList:UpdateBar()
    priorityEmpty:SetShown(#entries == 0)
end

local function BuildPriorityWindow()
    local f = CreateFrame("Frame", "nugsCooldownPulsePriority", UIParent)
    f:SetSize(330, 430)
    f:SetPoint("CENTER", 200, 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Backdrop(f, C.bg, 1)
    tinsert(UISpecialFrames, "nugsCooldownPulsePriority")
    priorityWindow = f
    priorityRows   = {}

    HeaderBar(f, "nugsCooldownPulse", "priority")

    local note = Label(f, "When several cooldowns come back together, the one\nhighest in this list is shown first.",
        "GameFontDisableSmall", C.faint)
    note:SetPoint("TOPLEFT", 12, -40)
    note:SetJustifyH("LEFT")

    local panel = Panel(f, { 0.05, 0.05, 0.05, 0.9 })
    panel:SetPoint("TOPLEFT", 10, -74)
    panel:SetPoint("BOTTOMRIGHT", -10, 44)

    priorityList = ScrollArea(panel)
    priorityList:SetPoint("TOPLEFT", 4, -4)
    priorityList:SetPoint("BOTTOMRIGHT", -4, 4)

    priorityEmpty = Label(panel, "Nothing is being tracked yet.", "GameFontDisableSmall", C.faint)
    priorityEmpty:SetPoint("CENTER")

    local clear = Button(f, "Clear order", 100, 22, function()
        CDP.ResetPriority()
        RefreshPriority()
    end)
    clear:SetPoint("BOTTOMLEFT", 10, 12)

    local hint = Label(f, "unranked abilities follow, by name", "GameFontDisableSmall", C.faint)
    hint:SetPoint("BOTTOMRIGHT", -12, 18)

    f:SetScript("OnShow", RefreshPriority)
    f:Hide()
end

function CDP.TogglePriority()
    if not priorityWindow then BuildPriorityWindow() end
    if priorityWindow:IsShown() then
        priorityWindow:Hide()
    else
        priorityWindow:Show()
    end
end

--------------------------------------------------------------------------------
-- Spell picker
--------------------------------------------------------------------------------
local rows = {}

local function FilteredEntries()
    local filter = (searchBox and searchBox:GetText() or ""):lower()
    -- The Sounds pane only lists abilities that are actually tracked. Offering a cue
    -- for something that never pulses is a setting that can only disappoint.
    local trackedOnly = (paneMode == "sounds")
    local out, lastGroup = {}, nil
    for _, entry in ipairs(CDP.catalog) do
        if (not trackedOnly or CDP.IsEnabled(entry))
           and (filter == "" or entry.name:lower():find(filter, 1, true)) then
            if entry.group ~= lastGroup then
                out[#out + 1] = { header = entry.group }
                lastGroup = entry.group
            end
            out[#out + 1] = { entry = entry }
        end
    end
    return out
end

local function AcquireRow(index, parent)
    local row = rows[index]
    if row then return row end

    row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_H)

    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()

    row.box = CreateFrame("Frame", nil, row)
    row.box:SetSize(13, 13)
    row.box:SetPoint("LEFT", 4, 0)
    Backdrop(row.box, C.input, 1)
    row.fill = row.box:CreateTexture(nil, "ARTWORK")
    row.fill:SetPoint("TOPLEFT", 3, -3)
    row.fill:SetPoint("BOTTOMRIGHT", -3, 3)
    row.fill:SetColorTexture(unpack(C.accent))

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row.box, "RIGHT", 6, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetJustifyH("LEFT")

    row.cd = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.cd:SetPoint("RIGHT", -8, 0)
    row.cd:SetJustifyH("RIGHT")
    row.name:SetPoint("RIGHT", row.cd, "LEFT", -6, 0)

    -- Only shown in the Sounds pane. Built here rather than in a second row type so
    -- search, scrolling and the pool all keep working unchanged.
    row.sound = Button(row, "", 150, 18, nil)
    row.sound:SetPoint("RIGHT", -6, 0)
    row.sound:Hide()

    row.play = Button(row, "|cff8cd2ff>|r", 22, 18, nil)
    row.play:SetPoint("RIGHT", row.sound, "LEFT", -4, 0)
    row.play:Hide()

    row:SetScript("OnClick", function(self)
        if not self.entry then return end
        -- In the Sounds pane the row is not a checkbox; the buttons on it do the work.
        if paneMode == "sounds" then return end
        CDP.SetEnabled(self.entry, not CDP.IsEnabled(self.entry))
        if CDP.RefreshOptions then CDP.RefreshOptions() end
    end)
    row:SetScript("OnEnter", function(self)
        if self.entry then self.stripe:SetColorTexture(unpack(C.rowB)) end
    end)
    row:SetScript("OnLeave", function(self)
        if self.entry then self.stripe:SetColorTexture(unpack(self.baseColor or C.rowA)) end
    end)

    rows[index] = row
    return row
end

local function RefreshList()
    if not window then return end
    local items   = FilteredEntries()
    local content = list.content
    local shown   = 0

    for i, item in ipairs(items) do
        local row = AcquireRow(i, content)
        row:Show()
        if item.header then
            row.entry = nil
            row.box:Hide()
            row.icon:Hide()
            row.sound:Hide()
            row.play:Hide()
            row.cd:SetText("")
            row.name:SetText(item.header)
            row.name:SetTextColor(unpack(C.accent))
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", 6, 0)
            row.name:SetPoint("RIGHT", row.cd, "LEFT", -6, 0)
            row.baseColor = { 1, 1, 1, 0.08 }
            row.stripe:SetColorTexture(1, 1, 1, 0.08)
            row:SetScript("OnEnter", nil)
        else
            local entry = item.entry
            row.entry = entry
            row.icon:Show()
            row.icon:SetTexture(entry.icon or 134400)
            row.name:SetText(entry.name)

            if paneMode == "sounds" then
                -- No checkbox: everything listed here is already tracked. The icon
                -- shifts left into the space the box used.
                row.box:Hide()
                row.cd:SetText("")
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", 6, 0)
                row.name:ClearAllPoints()
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.name:SetPoint("RIGHT", row.play, "LEFT", -6, 0)
                row.name:SetTextColor(0.95, 0.95, 0.95)

                local assigned = CDP.char.sounds[entry.key]
                row.sound:Show()
                row.sound:SetLabel(assigned and CDP.SoundByKey(assigned).name
                                            or "|cff777777no sound|r")
                row.sound:SetScript("OnClick", function(self)
                    ToggleSoundPicker(window, self, true, function(key)
                        CDP.char.sounds[entry.key] = key or nil
                        RefreshList()
                    end)
                end)
                row.play:SetShown(assigned ~= nil)
                row.play:SetScript("OnClick", function()
                    if assigned then CDP.PlayCue(assigned) end
                end)
            else
                row.box:Show()
                row.sound:Hide()
                row.play:Hide()
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", row.box, "RIGHT", 6, 0)
                row.name:ClearAllPoints()
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.name:SetPoint("RIGHT", row.cd, "LEFT", -6, 0)
                local on = CDP.IsEnabled(entry)
                row.fill:SetShown(on)
                row.name:SetTextColor(on and 0.95 or 0.55, on and 0.95 or 0.55, on and 0.95 or 0.55)
                if entry.kind == "item" then
                    row.cd:SetText("trinket")
                elseif CDP.Length(entry) then
                    row.cd:SetText(string.format("%ds", math.floor(CDP.Length(entry) + 0.5)))
                else
                    row.cd:SetText("")
                end
            end
            row.baseColor = (i % 2 == 0) and C.rowA or { 0, 0, 0, 0 }
            row.stripe:SetColorTexture(unpack(row.baseColor))
            row:SetScript("OnEnter", function(self) self.stripe:SetColorTexture(unpack(C.rowB)) end)
        end
        shown = i
    end

    for i = shown + 1, #rows do rows[i]:Hide() end

    content:SetHeight(math.max(1, shown * ROW_H))
    content:SetWidth(list:GetWidth())
    list:UpdateBar()

    countText:SetText(string.format("tracking |cff8cd2ff%d|r of %d", #CDP.watch, #CDP.catalog))
end

local function ApplyToFiltered(on)
    for _, item in ipairs(FilteredEntries()) do
        if item.entry then CDP.SetEnabled(item.entry, on, true) end
    end
    CDP.BuildWatch()
    RefreshList()
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local function BuildWindow()
    local db = CDP.db

    local f = CreateFrame("Frame", "nugsCooldownPulseOptions", UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Backdrop(f, C.bg, 1)
    tinsert(UISpecialFrames, "nugsCooldownPulseOptions")   -- Escape closes it
    window = f

    -- Header ------------------------------------------------------------------
    HeaderBar(f, "nugsCooldownPulse", "v" .. CDP.version)

    -- Left column -------------------------------------------------------------
    local leftScroll = ScrollArea(f)
    leftScroll:SetPoint("TOPLEFT", 10, -40)
    leftScroll:SetSize(LEFT_W, HEIGHT - 40 - 44)
    local left = leftScroll.content
    left:SetWidth(LEFT_W - 6)

    local y = 0
    local function place(widget, height, indent)
        widget:SetPoint("TOPLEFT", left, "TOPLEFT", indent or 0, -y)
        widget:SetPoint("TOPRIGHT", left, "TOPRIGHT", -6, -y)
        y = y + height
    end
    local function gap(h) y = y + h end

    -- A labelled pair of numeric boxes. Commits on Enter AND on losing focus, so
    -- clicking away is not a silent discard; anything that is not a number reverts to
    -- the live value rather than becoming zero; and the result is clamped so a stray
    -- extra digit cannot park the anchor somewhere it can never be dragged back from.
    -- Both coordinates on one row: they are a pair, they are read together, and the
    -- column is wide enough that stacking them only spent height for nothing.
    local function CoordPairRow(limit, specs)
        local row = CreateFrame("Frame", nil, left)
        row:SetHeight(22)
        local boxes = {}

        local anchorTo, gapBefore = nil, 0
        for _, spec in ipairs(specs) do
            local lbl = Label(row, spec.label, "GameFontDisableSmall", C.faint)
            if anchorTo then lbl:SetPoint("LEFT", anchorTo, "RIGHT", gapBefore, 0)
            else lbl:SetPoint("LEFT", 0, 0) end
            lbl:SetWidth(12)

            local box
            local function commit(text)
                local n = tonumber(text)
                if n then
                    if n > limit then n = limit elseif n < -limit then n = -limit end
                    spec.set(math.floor(n + 0.5))
                end
                -- Whether the input took or not, show the truth afterwards.
                box:SetText(tostring(spec.get() or 0))
                box:SetCursorPosition(0)
                CDP.Pulse:ApplySettings()
                CDP.RefreshOptions()
            end

            box = EditBox(row, 22, commit)
            box:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
            box:SetWidth(72)
            box:SetScript("OnEditFocusLost", function(self) commit(self:GetText()) end)

            boxes[#boxes + 1] = { box = box, get = spec.get }
            anchorTo, gapBefore = box, 16
        end

        row.Refresh = function()
            for _, b in ipairs(boxes) do
                if not b.box:HasFocus() then
                    b.box:SetText(tostring(b.get() or 0))
                    b.box:SetCursorPosition(0)
                end
            end
        end
        widgets[#widgets + 1] = row
        return row
    end

    --------------------------------------------------------------------------
    -- Profile
    -- First, because which profile you are about to overwrite is context for
    -- everything below it.
    --------------------------------------------------------------------------
    local hProfile = SectionHeader(left, "Profile")
    hProfile:SetPoint("TOPLEFT", 0, -y); y = y + 20

    local profileHint = Label(left,
        "Saved account-wide, so a profile made on one character can be loaded on any "
        .. "other. Your tracked spells are NOT included - those stay per character.",
        "GameFontDisableSmall", C.faint)
    profileHint:SetPoint("TOPLEFT", 0, -y)
    profileHint:SetWidth(LEFT_W - 16)
    profileHint:SetJustifyH("LEFT")
    y = y + 40

    local profileName = EditBox(left, 22, nil)
    place(profileName, 26)
    local nameHint = Label(profileName, "profile name...", "GameFontDisableSmall", C.faint)
    nameHint:SetPoint("LEFT", 8, 0)
    profileName:SetScript("OnTextChanged", function(self)
        nameHint:SetShown((self:GetText() or "") == "")
    end)

    local profileRow = CreateFrame("Frame", nil, left)
    profileRow:SetHeight(22)
    local saveBtn = Button(profileRow, "Save", 62, 22, function()
        local name = CDP.TrimName(profileName:GetText())
        if name == "" then CDP.Print("give the profile a name first.") return end
        local existed = CDP.db.profiles[name] ~= nil
        if CDP.SaveProfile(name) then
            CDP.Print((existed and "profile updated: " or "profile saved: ") .. name)
            CDP.RefreshOptions()
        end
    end)
    saveBtn:SetPoint("LEFT", 0, 0)
    local loadBtn = Button(profileRow, "Load", 62, 22, function()
        local name = CDP.TrimName(profileName:GetText())
        if CDP.LoadProfile(name) then CDP.Print("profile loaded: " .. name)
        else CDP.Print("no profile called \"" .. name .. "\".") end
    end)
    loadBtn:SetPoint("LEFT", saveBtn, "RIGHT", 5, 0)
    local delBtn = Button(profileRow, "Delete", 66, 22, function()
        local name = CDP.TrimName(profileName:GetText())
        if CDP.DeleteProfile(name) then
            CDP.Print("profile deleted: " .. name)
            CDP.RefreshOptions()
        else CDP.Print("no profile called \"" .. name .. "\".") end
    end)
    delBtn:SetPoint("LEFT", loadBtn, "RIGHT", 5, 0)
    place(profileRow, 26)

    local savedList = Label(left, "", "GameFontDisableSmall", C.faint)
    savedList:SetPoint("TOPLEFT", 0, -y)
    savedList:SetWidth(LEFT_W - 16)
    savedList:SetJustifyH("LEFT")
    savedList.Refresh = function()
        local names = CDP.ProfileNames()
        local active, matches = CDP.ProfileStatus()

        -- "modified" is the honest state after loading a profile and then changing
        -- anything, and saying so is what stops somebody assuming their change was
        -- written back into the profile. It was not; Save does that.
        local current
        if not active then
            current = "Loaded: |cff777777none|r"
        elseif matches then
            current = "Loaded: |cff8cd2ff" .. active .. "|r"
        else
            current = "Loaded: |cff8cd2ff" .. active .. "|r |cffd8a13f(modified)|r"
        end

        savedList:SetText(current .. "\n" .. (#names > 0
            and ("Saved: |cff8cd2ff" .. table.concat(names, "|r, |cff8cd2ff") .. "|r")
            or  "No profiles saved yet."))
    end
    widgets[#widgets + 1] = savedList
    y = y + 44

    -- Clicking a saved name fills the box, so the three buttons above always act on
    -- something you can see rather than something you had to remember to type.
    local pickBtn = Button(left, "Pick a saved profile...", LEFT_W - 16, 22, function(self)
        local names = CDP.ProfileNames()
        if #names == 0 then CDP.Print("no profiles saved yet.") return end
        ToggleNamePicker(left, self, names, function(chosen)
            profileName:SetText(chosen)
            nameHint:Hide()
        end)
    end)
    place(pickBtn, 28)

    gap(6)
    local h1 = SectionHeader(left, "Display")
    h1:SetPoint("TOPLEFT", 0, -y); y = y + 20

    place(Slider(left, "Icon size", 16, 160, 2,
        function() return db.size end,
        function(v) db.size = v end, "%d px"), 42)
    place(Slider(left, "Max alpha", 0.05, 1, 0.05,
        function() return db.alpha end,
        function(v) db.alpha = v end, "%.2f"), 42)
    place(Slider(left, "Pop scale", 1, 3, 0.05,
        function() return db.popScale end,
        function(v) db.popScale = v end, "%.2fx"), 42)
    place(Slider(left, "Fade in", 0, 1.5, 0.05,
        function() return db.fadeIn end,
        function(v) db.fadeIn = v end, "%.2fs"), 42)
    place(Slider(left, "Hold", 0, 5, 0.05,
        function() return db.hold end,
        function(v) db.hold = v end, "%.2fs"), 42)
    place(Slider(left, "Fade out", 0, 3, 0.05,
        function() return db.fadeOut end,
        function(v) db.fadeOut = v end, "%.2fs"), 42)

    gap(6)
    local h2 = SectionHeader(left, "Behaviour")
    h2:SetPoint("TOPLEFT", 0, -y); y = y + 20

    -- First item in the section on purpose: this is the setting that decides how
    -- much of your spellbook gets picked up automatically.
    place(Slider(left, "Minimum cooldown length", 1, 300, 1,
        function() return db.minCooldown end,
        function(v) db.minCooldown = v; CDP.BuildWatch() end, "%ds",
        function() RefreshList() end), 42)
    local minHint = Label(left, "Abilities with a shorter cooldown are ignored.", "GameFontDisableSmall", C.faint)
    minHint:SetPoint("TOPLEFT", 0, -y); y = y + 16

    place(Slider(left, "Announce this early", 0, 2, 0.05,
        function() return db.lead end,
        function(v) db.lead = v end, "%.2fs"), 42)
    local leadHint = Label(left, "Fires before the cooldown ends, to cover the fade in\nand your reaction time.",
        "GameFontDisableSmall", C.faint)
    leadHint:SetJustifyH("LEFT")
    leadHint:SetPoint("TOPLEFT", 0, -y); y = y + 28

    place(Check(left, "Pulses enabled",
        function() return db.enabled end,
        function(v) db.enabled = v end), ROW_H)
    place(Check(left, "Show ability name",
        function() return db.showName end,
        function(v) db.showName = v; CDP.Pulse:ApplySettings() end), ROW_H)
    place(Check(left, "Only while in combat",
        function() return db.onlyInCombat end,
        function(v) db.onlyInCombat = v end), ROW_H)
    place(Check(left, "Include general/racial/profession",
        function() return db.includeGeneral end,
        function(v) db.includeGeneral = v; CDP.RebuildCatalog(); RefreshList() end), ROW_H)
    place(Check(left, "Track equipped trinkets",
        function() return db.trackTrinkets end,
        function(v) db.trackTrinkets = v; CDP.BuildWatch(); RefreshList() end), ROW_H)

    gap(6)
    local hLayout = SectionHeader(left, "Layout")
    hLayout:SetPoint("TOPLEFT", 0, -y); y = y + 20

    -- Typed position, for anyone who wants the icon in the same place on every
    -- character rather than wherever the drag happened to land. Offsets are from the
    -- centre of the screen, which is what the anchor has always stored.
    local posHint = Label(left, "Position, from the centre of the screen",
                          "GameFontDisableSmall", C.faint)
    posHint:SetPoint("TOPLEFT", 0, -y); y = y + 16

    place(CoordPairRow(4000, {
        { label = "X", get = function() return db.anchor and db.anchor.x end,
                       set = function(v) db.anchor.x = v end },
        { label = "Y", get = function() return db.anchor and db.anchor.y end,
                       set = function(v) db.anchor.y = v end },
    }), 26)

    local MODES = {
        { key = "single", label = "One at a time" },
        { key = "row",    label = "Show several at once" },
    }
    local modeRow = CreateFrame("Frame", nil, left)
    modeRow:SetHeight(22)
    local modeBtn = Button(modeRow, "", LEFT_W - 16, 22, function()
        local index = 1
        for i, m in ipairs(MODES) do if m.key == db.mode then index = i break end end
        db.mode = MODES[(index % #MODES) + 1].key
        CDP.Pulse:ApplySettings()
        CDP.RefreshOptions()
    end)
    modeBtn:SetPoint("LEFT", 0, 0)
    modeRow.Refresh = function()
        local label = "One at a time"
        for _, m in ipairs(MODES) do if m.key == db.mode then label = m.label end end
        modeBtn:SetLabel(label)
    end
    widgets[#widgets + 1] = modeRow
    place(modeRow, 26)

    local GROWS = { "centered", "right", "left", "up", "down" }
    local growRow = CreateFrame("Frame", nil, left)
    growRow:SetHeight(22)
    local growBtn = Button(growRow, "", LEFT_W - 16, 22, function()
        local index = 1
        for i, g in ipairs(GROWS) do if g == db.grow then index = i break end end
        db.grow = GROWS[(index % #GROWS) + 1]
        CDP.Pulse:ApplySettings()
        CDP.RefreshOptions()
    end)
    growBtn:SetPoint("LEFT", 0, 0)
    growRow.Refresh = function()
        growBtn:SetLabel("Grow: " .. tostring(db.grow))
        growBtn:SetAlpha(db.mode == "row" and 1 or 0.4)
    end
    widgets[#widgets + 1] = growRow
    place(growRow, 26)

    place(Slider(left, "Most icons at once", 1, 8, 1,
        function() return db.maxIcons end,
        function(v) db.maxIcons = v end, "%d"), 42)

    local priorityBtn = Button(left, "Set pulse priority...", LEFT_W - 16, 22, function()
        CDP.TogglePriority()
    end)
    place(priorityBtn, 26)

    gap(6)
    local hText = SectionHeader(left, "Ability name text")
    hText:SetPoint("TOPLEFT", 0, -y); y = y + 20

    local fontRow = CreateFrame("Frame", nil, left)
    fontRow:SetHeight(22)
    local fontBtn
    fontBtn = Button(fontRow, "", LEFT_W - 16, 22, function()
        ToggleFontPicker(window, fontBtn, function(name)
            db.fontKey = name
            CDP.Pulse:ApplyFont()
            CDP.RefreshOptions()
        end)
    end)
    fontBtn:SetPoint("LEFT", 0, 0)
    fontRow.Refresh = function() fontBtn:SetLabel("Font: " .. tostring(db.fontKey)) end
    widgets[#widgets + 1] = fontRow
    place(fontRow, 26)

    local outlineRow = CreateFrame("Frame", nil, left)
    outlineRow:SetHeight(22)
    local outlineBtn = Button(outlineRow, "", LEFT_W - 16, 22, function()
        local index = 1
        for i, name in ipairs(CDP.OUTLINES) do
            if name == db.fontOutline then index = i break end
        end
        index = (index % #CDP.OUTLINES) + 1
        db.fontOutline = CDP.OUTLINES[index]
        CDP.Pulse:ApplyFont()
        CDP.RefreshOptions()
    end)
    outlineBtn:SetPoint("LEFT", 0, 0)
    outlineRow.Refresh = function() outlineBtn:SetLabel("Outline: " .. tostring(db.fontOutline)) end
    widgets[#widgets + 1] = outlineRow
    place(outlineRow, 26)

    place(Slider(left, "Font size", 6, 32, 1,
        function() return db.fontSize end,
        function(v) db.fontSize = v; CDP.Pulse:ApplyFont() end, "%d"), 42)

    gap(6)
    local hSkin = SectionHeader(left, "Icon skin")
    hSkin:SetPoint("TOPLEFT", 0, -y); y = y + 20

    place(Check(left, "Let Masque skin the icon",
        function() return db.masque end,
        function(v)
            db.masque = v
            CDP.Print("Masque setting changed - /reload to apply.")
        end), ROW_H)
    local masqueHint = Label(left, "", "GameFontDisableSmall", C.faint)
    masqueHint:SetPoint("TOPLEFT", 0, -y); y = y + 16
    masqueHint:SetText(CDP.masqueActive and "Skinned by Masque: group \"nugsCooldownPulse\"."
                       or (_G.LibStub and _G.LibStub("Masque", true))
                          and "Masque found - enable, then /reload."
                          or "Masque is not installed.")

    gap(6)
    local h3 = SectionHeader(left, "Sound")
    h3:SetPoint("TOPLEFT", 0, -y); y = y + 20

    place(Check(left, "Play a sound cue",
        function() return db.soundEnabled end,
        function(v) db.soundEnabled = v end), ROW_H)

    -- One cue for everything, or a cue per ability. Cycling button to match the
    -- layout and grow controls above.
    local modeSoundRow = CreateFrame("Frame", nil, left)
    modeSoundRow:SetHeight(22)
    local soundModeBtn = Button(modeSoundRow, "", LEFT_W - 16, 22, function()
        db.soundMode = (db.soundMode == "per") and "one" or "per"
        db.soundEnabled = true
        CDP.RefreshOptions()
        RefreshList()          -- the right pane changes shape with the mode
    end)
    soundModeBtn:SetPoint("LEFT", 0, 0)
    modeSoundRow.Refresh = function()
        soundModeBtn:SetLabel(db.soundMode == "per"
            and "Cue: one per ability" or "Cue: one for everything")
    end
    widgets[#widgets + 1] = modeSoundRow
    place(modeSoundRow, 26)

    local soundRow = CreateFrame("Frame", nil, left)
    soundRow:SetHeight(22)
    -- Declared before it is assigned, deliberately. `local x = f(function() ... x ... end)`
    -- does NOT capture x: a local's scope starts after the statement that declares it,
    -- so the closure binds to a global of the same name and gets nil. Anchoring the
    -- popup to that nil is what threw.
    local soundBtn
    soundBtn = Button(soundRow, "", LEFT_W - 46, 22, function()
        ToggleSoundPicker(left, soundBtn, false, function(key)
            db.soundKey = key
            db.soundEnabled = true
            CDP.RefreshOptions()
        end)
    end)
    soundBtn:SetPoint("LEFT", 0, 0)
    local playBtn = Button(soundRow, "|cff8cd2ff>|r", 26, 22,
        function() CDP.PlayCue(db.soundKey) end)
    playBtn:SetPoint("LEFT", soundBtn, "RIGHT", 4, 0)
    soundRow.Refresh = function()
        soundBtn:SetLabel(CDP.SoundByKey(db.soundKey).name)
        -- In per-ability mode this cue is not used by anything, so say so rather
        -- than leave a live-looking control that does nothing.
        soundBtn:SetGrey(db.soundMode == "per")
        playBtn:SetGrey(db.soundMode == "per")
    end
    widgets[#widgets + 1] = soundRow
    place(soundRow, 26)

    local perHint = Label(left,
        "Assign cues in the |cff8cd2ffSounds|r pane on the right. Anything without one "
        .. "pulses silently.", "GameFontDisableSmall", C.faint)
    perHint:SetPoint("TOPLEFT", 0, -y)
    perHint:SetWidth(LEFT_W - 16)
    perHint:SetJustifyH("LEFT")
    perHint.Refresh = function() perHint:SetShown(db.soundMode == "per") end
    widgets[#widgets + 1] = perHint
    y = y + 28

    -- No custom-file box. See CDP.SoundList in Core.lua for why: it asked people to
    -- type an exact path to a file they had to install by hand, and a LibSharedMedia
    -- sound pack does the same job by just being installed. `/ncp sound file` is
    -- still there for anyone who wants it.
    local mediaHint = Label(left,
        "Install a LibSharedMedia sound pack and its cues appear in the list above.",
        "GameFontDisableSmall", C.faint)
    mediaHint:SetPoint("TOPLEFT", 0, -y)
    mediaHint:SetWidth(LEFT_W - 16)
    mediaHint:SetJustifyH("LEFT")
    y = y + 28

    left:SetHeight(y + 10)
    leftScroll:UpdateBar()

    -- Right column ------------------------------------------------------------
    local rightX = LEFT_W + 22

    -- Tabs, not buttons. They pick which face of the pane you are looking at, which
    -- is a different kind of thing from "Enable all", and looking identical to it was
    -- what made the row read as five equal buttons that happened to overflow.
    --
    -- Same shape as the tab strips in nugsCastBars and nugsComboBar: a text label
    -- with a storm-blue underline on the active one, no backdrop.
    local abilitiesTab, soundsTab

    -- Only records which face is showing. The look of the tabs and which controls
    -- belong to them is decided in one place, RefreshPaneChrome, so the two can never
    -- disagree about which pane you are on.
    local function SetPane(mode)
        paneMode = mode
        CDP.RefreshOptions()
    end

    local function MakeTab(text, width, onClick)
        local t = CreateFrame("Button", nil, f)
        t:SetSize(width, 24)
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t.text:SetPoint("LEFT", 2, 0)
        t.text:SetText(text)
        t.underline = t:CreateTexture(nil, "OVERLAY")
        t.underline:SetPoint("BOTTOMLEFT", 0, 0)
        t.underline:SetPoint("BOTTOMRIGHT", 0, 0)
        t.underline:SetHeight(2)
        t.underline:SetColorTexture(unpack(C.accent))
        t:SetScript("OnClick", onClick)
        t.SetActive = function(self, on)
            self.text:SetTextColor(unpack(on and C.gold or C.faint))
            self.underline:SetShown(on)
        end
        t:SetScript("OnEnter", function(self)
            if not self.underline:IsShown() then self.text:SetTextColor(1, 1, 1) end
        end)
        t:SetScript("OnLeave", function(self)
            self.text:SetTextColor(unpack(self.underline:IsShown() and C.gold or C.faint))
        end)
        return t
    end

    abilitiesTab = MakeTab("Abilities to watch", 132, function() SetPane("abilities") end)
    abilitiesTab:SetPoint("TOPLEFT", rightX, -42)
    soundsTab = MakeTab("Sounds", 60, function() SetPane("sounds") end)
    soundsTab:SetPoint("LEFT", abilitiesTab, "RIGHT", 10, 0)

    -- Hairline under the whole strip so the two tabs read as a strip rather than as
    -- two loose words.
    local tabRule = f:CreateTexture(nil, "ARTWORK")
    tabRule:SetPoint("TOPLEFT", rightX, -66)
    tabRule:SetPoint("TOPRIGHT", -12, -66)
    tabRule:SetHeight(1)
    tabRule:SetColorTexture(1, 1, 1, 0.07)

    countText = Label(f, "", "GameFontDisableSmall", C.faint)
    countText:SetPoint("TOPRIGHT", -12, -46)

    searchBox = EditBox(f, 22, nil, function() RefreshList() end)
    searchBox:SetPoint("TOPLEFT", rightX, -78)
    searchBox:SetPoint("TOPRIGHT", -12, -78)
    local searchHint = Label(searchBox, "search...", "GameFontDisableSmall", C.faint)
    searchHint:SetPoint("LEFT", 8, 0)
    searchBox:SetScript("OnTextChanged", function(self, user)
        searchHint:SetShown((self:GetText() or "") == "")
        if user then RefreshList() end
    end)

    -- Second row, under the tabs, so nothing has to share width with them. These
    -- three act on the ability list and only exist on that face.
    local allBtn = Button(f, "Enable all", 84, 20, function() ApplyToFiltered(true) end)
    allBtn:SetPoint("TOPLEFT", rightX, -106)
    local noneBtn = Button(f, "Disable all", 84, 20, function() ApplyToFiltered(false) end)
    noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)
    local autoBtn = Button(f, "Back to auto", 96, 20, function()
        CDP.ResetSelections()
        RefreshList()
    end)
    autoBtn:SetPoint("LEFT", noneBtn, "RIGHT", 6, 0)

    -- Occupies the same row on the Sounds face, so switching tabs does not make the
    -- list jump up and down. Said once, here, rather than leaving someone to assign a
    -- dozen cues and wonder why the game is silent.
    local soundNote = Label(f,
        "|cffd8a13fPer-ability cues are off.|r Set |cff8cd2ffCue|r on the left to "
        .. "\"one per ability\" for these to be used.", "GameFontDisableSmall", C.faint)
    soundNote:SetPoint("TOPLEFT", rightX, -108)
    soundNote:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    soundNote:SetJustifyH("LEFT")
    soundNote:Hide()

    local soundHint = Label(f,
        "Cues come from the game plus any LibSharedMedia sound pack you have installed.",
        "GameFontDisableSmall", C.faint)
    soundHint:SetPoint("TOPLEFT", rightX, -108)
    soundHint:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    soundHint:SetJustifyH("LEFT")
    soundHint:Hide()

    local function RefreshPaneChrome()
        local abilities = (paneMode == "abilities")
        allBtn:SetShown(abilities)
        noneBtn:SetShown(abilities)
        autoBtn:SetShown(abilities)
        local perOff = (not abilities) and CDP.db.soundMode ~= "per"
        soundNote:SetShown(perOff)
        soundHint:SetShown(not abilities and not perOff)
        if abilitiesTab then abilitiesTab:SetActive(abilities) end
        if soundsTab then soundsTab:SetActive(not abilities) end
    end
    CDP.RefreshPaneChrome = RefreshPaneChrome

    local listPanel = Panel(f, { 0.05, 0.05, 0.05, 0.9 })
    listPanel:SetPoint("TOPLEFT", rightX, -132)
    listPanel:SetPoint("BOTTOMRIGHT", -12, 44)

    list = ScrollArea(listPanel)
    list:SetPoint("TOPLEFT", 4, -4)
    list:SetPoint("BOTTOMRIGHT", -4, 4)

    -- Bottom bar --------------------------------------------------------------
    local anchorBtn = Button(f, "", 128, 22, function()
        CDP.Pulse:ToggleLock(not CDP.db.locked)
    end)
    anchorBtn:SetPoint("BOTTOMLEFT", 10, 12)
    anchorBtn.Refresh = function()
        anchorBtn:SetLabel(CDP.db.locked and "Unlock anchor" or "Lock anchor")
    end
    widgets[#widgets + 1] = anchorBtn

    local resetPos = Button(f, "Reset position", 110, 22, function()
        CDP.db.anchor = { point = "CENTER", x = 0, y = 150 }
        CDP.Pulse:ApplySettings()
    end)
    resetPos:SetPoint("LEFT", anchorBtn, "RIGHT", 6, 0)

    local testBtn = Button(f, "Test pulse", 90, 22, function() CDP.Pulse:Test() end)
    testBtn:SetPoint("LEFT", resetPos, "RIGHT", 6, 0)

    local hint = Label(f, "|cff8cd2ff/ncp|r for commands", "GameFontDisableSmall", C.faint)
    hint:SetPoint("BOTTOMRIGHT", -12, 18)

    f:SetScript("OnShow", function() CDP.RefreshOptions() end)
    f:SetScript("OnHide", function()
        if fontPopup then fontPopup:Hide() end
    end)

    -- The priority list only contains tracked abilities, so it has to follow any
    -- change to the selection.
    local baseCatalogChanged = CDP.OnCatalogChanged
    CDP.OnCatalogChanged = function()
        if baseCatalogChanged then baseCatalogChanged() end
        if priorityWindow and priorityWindow:IsShown() then RefreshPriority() end
    end

    -- Start on the abilities face, and let SetPane do the greying and labelling so
    -- there is one place that decides what a pane looks like.
    SetPane("abilities")

    -- CreateFrame hands back a *shown* frame, so without this the first /ncp
    -- would toggle the brand new window straight back off.
    f:Hide()
end

--------------------------------------------------------------------------------
-- Public entry points
--------------------------------------------------------------------------------
function CDP.RefreshOptions()
    if priorityWindow and priorityWindow:IsShown() then RefreshPriority() end
    if not window then return end
    for _, w in ipairs(widgets) do
        if w.Refresh then w.Refresh() end
    end
    if CDP.RefreshPaneChrome then CDP.RefreshPaneChrome() end
    RefreshList()
end

--------------------------------------------------------------------------------
-- Move bar
--
-- Placing the pulse means dragging a box that the settings window is usually sitting
-- on top of, so the window has to be shoved aside first and dragged back after. The
-- window gets out of the way on its own now: unlocking hides it and puts up a small
-- bar instead, and locking brings it back exactly where it was.
--
-- The bar carries the three things that are actually useful while positioning -
-- lock, reset, test - so it is a small toolbar rather than a single button. Test in
-- particular matters: an anchor with nothing in it is hard to place.
--
-- It is deliberately not a saved position. It moves if it is in the way, and starts
-- near the top of the screen next time; persisting it would mean a new saved
-- variable, and a setting nobody would ever go looking for.
--------------------------------------------------------------------------------
local moveBar

local function BuildMoveBar()
    local f = CreateFrame("Frame", "nugsCooldownPulseMoveBar", UIParent)
    f:SetSize(300, 78)
    f:SetPoint("TOP", UIParent, "TOP", 0, -60)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    -- PopupChrome draws its own backdrop plus the storm-blue edge, so it is the whole
    -- treatment - calling Backdrop as well would layer a second one underneath.
    PopupChrome(f)

    local title = Label(f, "Placing the pulse", "GameFontNormal", C.accent)
    title:SetPoint("TOPLEFT", 10, -9)

    local hint = Label(f, "Drag the blue box to where you want it.",
                       "GameFontDisableSmall", C.faint)
    hint:SetPoint("TOPLEFT", 10, -28)

    -- Lock is the way out of this state, so it is first and it is the wide one.
    local lockBtn = Button(f, "Lock anchor", 110, 22, function()
        CDP.Pulse:ToggleLock(true)
    end)
    lockBtn:SetPoint("BOTTOMLEFT", 10, 10)

    local resetBtn = Button(f, "Reset position", 105, 22, function()
        CDP.db.anchor = { point = "CENTER", x = 0, y = 150 }
        CDP.Pulse:ApplySettings()
        CDP.Pulse:Test()
    end)
    resetBtn:SetPoint("LEFT", lockBtn, "RIGHT", 6, 0)

    local testBtn = Button(f, "Test", 55, 22, function() CDP.Pulse:Test() end)
    testBtn:SetPoint("LEFT", resetBtn, "RIGHT", 6, 0)

    -- Escape locks rather than just dismissing the bar. Hiding it while the anchor
    -- was still unlocked would leave the state with nothing on screen to end it.
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and not InCombatLockdown() then
            self:SetPropagateKeyboardInput(false)
            CDP.Pulse:ToggleLock(true)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    return f
end

-- Whether the settings window was open when the anchor was unlocked, so locking can
-- put it back only if it was there to begin with. Unlocking from the slash command
-- with nothing open should not conjure a window on lock.
local windowWasOpen = false

function CDP.OnLockChanged(locked)
    if not locked then
        if window and window:IsShown() then
            windowWasOpen = true
            window:Hide()
        end
        moveBar = moveBar or BuildMoveBar()
        moveBar:SetPropagateKeyboardInput(true)
        moveBar:Show()
    else
        if moveBar then moveBar:Hide() end
        if windowWasOpen then
            windowWasOpen = false
            if window then window:Show() end
        end
    end
end

-- Builds the window once and hooks it once. Hooked here rather than inside
-- BuildWindow because moveBar is declared in this block: a closure written above its
-- declaration would bind to a nil global instead, silently, until somebody clicked.
--
-- The two hooks keep the pair consistent whichever one the player acts on. Opening
-- settings while the anchor is unlocked should not leave two lock buttons on screen,
-- and closing settings while unlocked should put the bar back rather than leaving the
-- state with no way out of it.
--
-- Every entry point goes through here rather than calling BuildWindow directly. There
-- is more than one, and the one that was not doing this would have built a window
-- with no hooks on it at all.
local function EnsureWindow()
    if window then return end
    BuildWindow()
    window:HookScript("OnShow", function()
        if moveBar then moveBar:Hide() end
    end)
    window:HookScript("OnHide", function()
        if not CDP.db.locked then CDP.OnLockChanged(false) end
    end)
end

--------------------------------------------------------------------------------
-- Combat
--
-- The settings window closes and the anchor locks the moment a fight starts.
--
-- Not because anything here would be blocked: none of these windows touch a secure
-- frame, so nothing throws "action blocked" the way an addon driving action bars
-- does. The reason is that both states put FAKE data on screen - unlocking runs a test pulse so the anchor has something to grab - and
-- sample data during a real pull is worse than none, because it cannot be told apart
-- from the real thing.
--
-- Nothing reopens when combat drops. A window appearing by itself while you are
-- looting is worse than pressing a button.
--------------------------------------------------------------------------------
local combatWatch = CreateFrame("Frame")
combatWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatch:SetScript("OnEvent", function()
    if CDP.db and not CDP.db.locked then
        -- SetLocked and OnLockChanged directly rather than ToggleLock: ToggleLock
        -- prints, and a line of chat on every pull is noise.
        --
        -- Clearing windowWasOpen FIRST is the part that matters. OnLockChanged puts
        -- the settings window back when it was open before the unlock, and doing that
        -- as a fight starts is precisely the wrong moment - it would read as a window
        -- popping open on every pull.
        windowWasOpen = false
        CDP.Pulse:SetLocked(true)
        CDP.OnLockChanged(true)
        if CDP.RefreshOptions then CDP.RefreshOptions() end
    end
    if window and window:IsShown() then window:Hide() end
end)

function CDP.ToggleOptions()
    EnsureWindow()
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end

-- Keep the picker honest when talents or gear change under us.
CDP.OnCatalogChanged = function()
    if window and window:IsShown() then RefreshList() end
end

-- A stub in the Blizzard settings list so the addon is findable there; the real
-- controls live in our own window, which stays movable.
function CDP.InitOptions()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end

    local panel = CreateFrame("Frame")
    panel.name = "nugsCooldownPulse"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("nugsCooldownPulse")

    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    note:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    note:SetJustifyH("LEFT")
    note:SetText("Pulses an icon on screen when one of your cooldowns comes back up.\n\nAll settings live in the nugsCooldownPulse window - open it with the button below or with |cffffd479/ncp|r.")

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(200, 24)
    open:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -16)
    open:SetText("Open nugsCooldownPulse options")
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        EnsureWindow()
        window:Show()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "nugsCooldownPulse")
    category.ID = "nugsCooldownPulse"
    Settings.RegisterAddOnCategory(category)
end
