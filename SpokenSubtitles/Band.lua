-- SpokenSubtitles -- the cinematic band: a player of its own, drawn as a soft dark band.
--
-- A full player on Spoken's public API. Playback, the queue and every action stay Spoken's:
-- this file only draws them and calls TogglePause, Skip, StopAll, source:Remove and the
-- actions' own onClick. While it is the chosen style, Spoken's own window is kept hidden
-- for this session only -- nothing in Spoken's settings is written, so disabling this addon
-- brings Spoken's window straight back.
--
-- At rest it is only words: name, title, the line being spoken and a hairline
-- with the cast spark. No portrait, because the target frame already shows the speaker's
-- face; a small one appears only when the speaker is not your target.
--
--   click          pause / resume (resume replays the line: the client has no seek)
--   hover          pause and skip glyphs fade in beside the name
--   +N             opens the waiting lines above the band; clicking one removes it
--   right-click    stop everything, the queue, the clip's actions (Report), settings
--   drag           moves the band

local _, ns = ...
ns = ns or {}

local Band = {}
ns.Band = Band

local MEDIA = [[Interface\AddOns\SpokenSubtitles\Media\]]
local SKIP = [[Interface\Buttons\UI-SpellbookIcon-NextPage-Up]]
local SPARK = [[Interface\CastingBar\UI-CastingBar-Spark]]
local FACE = 34
local QUEUE_ROWS = 6
local GOLD = { 1, 0.82, 0 }
local LABEL = { 0.86, 0.82, 0.72 }
local REMOVE = { 1, 0.28, 0.2 }
local PAD_TOP, PAD_BOTTOM, WORD_GAP, LINE_GAP = 14, 14, 5, 9
-- How far beyond the name row and the words the band still takes clicks.
local HIT_PAD = 12

Band.FADE_SECONDS = 0.2
Band.HOVER_FADE_SECONDS = 0.15
-- Clicks this soon after a drag ended are the drag's own button release.
Band.DRAG_CLICK_GUARD = 0.15

local function Config()
    return ns.db or ns.defaults
end

local function Present(clip)
    return clip and type(clip.present) == "table" and clip.present or {}
end

local function Face()
    local face = GameFontNormal:GetFont()
    return face
end

local function Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(Face(), size, "")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    return fs
end

local function Tooltip(owner, title, ...)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(title)
    for index = 1, select("#", ...) do
        local line = select(index, ...)
        if line then GameTooltip:AddLine(line, 1, 1, 1, true) end
    end
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

--- Whether the cursor is over `frame`, less `inset` on each side. The region method, not
--- MouseIsOver: that is a FrameXML helper the Classic client does not have (Spoken defines
--- its own copy, but only inside its private environment).
local function IsOver(frame, inset)
    inset = inset or 0
    return frame ~= nil and frame.IsMouseOver ~= nil
        and frame:IsMouseOver(0, 0, inset, -inset) and true or false
end

--- The source's own Remove, which is Spoken's queue removal.
local function Remove(clip)
    local source = clip and clip.source
    if type(source) == "table" and source.Remove then
        source:Remove(clip)
    end
end

local function CanControl()
    return Spoken:GetNowPlaying() ~= nil or Spoken:IsPaused()
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

function Band:IsActive()
    return Config().style == "band" and ns.connected and true or false
end

function Band:Build()
    if self.frame then
        return self.frame
    end
    local frame = CreateFrame("Frame", "SpokenSubtitlesBand", UIParent)
    self.frame = frame
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetAlpha(0)
    frame:Hide()
    frame:SetScript("OnDragStart", function() self:StartDrag() end)
    frame:SetScript("OnDragStop", function() self:StopDrag() end)
    frame:SetScript("OnMouseUp", function(_, button) self:OnClick(button) end)
    frame:SetScript("OnUpdate", function(_, elapsed) self:Tick(elapsed) end)

    local shade = frame:CreateTexture(nil, "BACKGROUND")
    shade:SetTexture(MEDIA .. "BandShade")
    shade:SetAllPoints()
    self.shade = shade

    self:BuildRow()
    self:BuildWords()
    self:BuildQueue()
    self:BuildMenu()
    self:ApplySettings()
    return frame
end

--- A face-sized round portrait, a glyph button, the name line and its queue count.
function Band:BuildRow()
    local row = CreateFrame("Frame", nil, self.frame)
    self.row = row
    row:SetHeight(FACE)

    local face = CreateFrame("Frame", nil, row)
    self.face = face
    face:SetSize(FACE, FACE)
    local disc = face:CreateTexture(nil, "BACKGROUND")
    disc:SetTexture(MEDIA .. "FaceDisc")
    disc:SetSize(FACE * 0.84, FACE * 0.84)
    disc:SetPoint("CENTER")
    local art = face:CreateTexture(nil, "ARTWORK")
    art:SetSize(FACE * 0.8, FACE * 0.8)
    art:SetPoint("CENTER")
    if face.CreateMaskTexture then
        local mask = face:CreateMaskTexture()
        mask:SetTexture(MEDIA .. "FaceMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(art)
        art:AddMaskTexture(mask)
        self.mask = mask
    end
    self.art = art
    local ring = face:CreateTexture(nil, "OVERLAY", nil, 2)
    ring:SetTexture(MEDIA .. "FaceRing")
    ring:SetAllPoints()
    face:Hide()

    self.name = Text(row, 15, GOLD)
    self.label = Text(row, 13, LABEL)

    local fold = CreateFrame("Button", nil, row)
    self.fold = fold
    fold:SetHeight(18)
    fold.text = Text(fold, 13, GOLD)
    fold.text:SetPoint("LEFT", fold, "LEFT", 0, 0)
    fold:SetScript("OnClick", function() self:ToggleQueue() end)
    fold:SetScript("OnEnter", function()
        fold.text:SetTextColor(1, 1, 1)
        Tooltip(fold, "Waiting lines", self.expanded and "Click to close the list."
            or "Click to see what is waiting.")
    end)
    fold:SetScript("OnLeave", function()
        fold.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        HideTooltip()
    end)
    fold:Hide()

    -- Controls beside the name, shown on hover (and the pause glyph while paused).
    local pause = CreateFrame("Button", nil, row)
    self.pause = pause
    pause:SetSize(18, 18)
    pause.icon = pause:CreateTexture(nil, "ARTWORK")
    pause.icon:SetAllPoints()
    pause:SetScript("OnClick", function() if CanControl() then Spoken:TogglePause() end end)
    pause:SetScript("OnEnter", function()
        Tooltip(pause, Spoken:IsPaused() and "Play" or "Pause",
            Spoken:IsPaused() and "Starts the line again from the beginning." or nil)
    end)
    pause:SetScript("OnLeave", HideTooltip)

    local skip = CreateFrame("Button", nil, row)
    self.skip = skip
    skip:SetSize(20, 20)
    skip:SetNormalTexture(SKIP)
    skip:SetHighlightTexture(SKIP, "ADD")
    skip:SetScript("OnClick", function() if self.clip then Spoken:Skip() end end)
    skip:SetScript("OnEnter", function() Tooltip(skip, "Skip this line") end)
    skip:SetScript("OnLeave", HideTooltip)

    self.controlsAlpha = 0
end

function Band:BuildWords()
    local words = Text(self.frame, 18, { 1, 1, 1 })
    self.words = words
    words:SetShadowOffset(1.5, -1.5)
    words:SetJustifyH("CENTER")
    if words.SetWordWrap then words:SetWordWrap(true) end
    if words.SetMaxLines then words:SetMaxLines(3) end
    words:SetAlpha(0)

    local track = self.frame:CreateTexture(nil, "ARTWORK")
    track:SetColorTexture(0, 0, 0, 0.5)
    track:SetHeight(1.5)
    self.track = track
    local fill = self.frame:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetTexture(MEDIA .. "BandLine")
    fill:SetHeight(1.5)
    fill:SetPoint("LEFT", track, "LEFT")
    self.fill = fill
    local spark = self.frame:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(SPARK)
    spark:SetBlendMode("ADD")
    spark:SetSize(14, 14)
    spark:SetPoint("CENTER", fill, "RIGHT")
    self.spark = spark
end

function Band:BuildQueue()
    local drawer = CreateFrame("Frame", nil, self.frame)
    self.drawer = drawer
    drawer:Hide()
    local shade = drawer:CreateTexture(nil, "BACKGROUND")
    shade:SetTexture(MEDIA .. "BandShade")
    shade:SetPoint("TOPLEFT", -40, 8)
    shade:SetPoint("BOTTOMRIGHT", 40, -8)
    self.rows = {}
    self.more = Text(drawer, 12, LABEL)
end

function Band:QueueRow(index)
    local row = self.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, self.drawer)
    row:SetHeight(20)
    row.text = Text(row, 13, LABEL)
    row.text:SetPoint("CENTER", row, "CENTER", 0, 0)
    row.text:SetJustifyH("CENTER")
    row:SetScript("OnEnter", function()
        row.text:SetTextColor(REMOVE[1], REMOVE[2], REMOVE[3])
        Tooltip(row, row.text:GetText() or "", "Click to remove it from the queue.")
    end)
    row:SetScript("OnLeave", function()
        row.text:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
        HideTooltip()
    end)
    row:SetScript("OnClick", function() Remove(row.clip) end)
    self.rows[index] = row
    return row
end

function Band:BuildMenu()
    local menu = CreateFrame("Frame", "SpokenSubtitlesBandMenu", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    self.menu = menu
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetWidth(210)
    if menu.SetBackdrop then
        menu:SetBackdrop({ bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
            edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]], tile = true, tileSize = 16,
            edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        menu:SetBackdropColor(0.07, 0.065, 0.05, 0.98)
        menu:SetBackdropBorderColor(0.6, 0.57, 0.48, 1)
    end
    menu:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "SpokenSubtitlesBandMenu") end
    pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
    menu:SetScript("OnEvent", function()
        if menu:IsShown() and not IsOver(menu) and not IsOver(self.frame, self.hitInset) then
            menu:Hide()
        end
    end)
    self.menuRows = {}
end

function Band:MenuRow(index)
    local row = self.menuRows[index]
    if row then return row end
    row = CreateFrame("Button", nil, self.menu)
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", self.menu, "TOPLEFT", 10, -8 - (index - 1) * 22)
    row:SetPoint("TOPRIGHT", self.menu, "TOPRIGHT", -10, -8 - (index - 1) * 22)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.text = Text(row, 12, GOLD)
    row:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]])
    if row.GetHighlightTexture and row:GetHighlightTexture() then
        row:GetHighlightTexture():SetAlpha(0.25)
    end
    row:SetScript("OnClick", function()
        self.menu:Hide()
        if row.enabled ~= false and row.fn then row.fn() end
    end)
    self.menuRows[index] = row
    return row
end

--------------------------------------------------------------------------------
-- Clicks and menu
--------------------------------------------------------------------------------

function Band:OnClick(button)
    if button == "RightButton" then
        self:ToggleMenu()
        return
    end
    -- Only the left button drags, so only its release can be the end of a drag.
    if self.dragging or (self.dragEnded and GetTime() - self.dragEnded < self.DRAG_CLICK_GUARD) then
        return
    end
    if button == "LeftButton" and CanControl() then
        self.menu:Hide()
        Spoken:TogglePause()
    end
end

--- The rows the menu shows for the current clip: { text, fn, icon, enabled }.
function Band:MenuItems()
    local items = {}
    table.insert(items, { text = Spoken:IsPaused() and "Play (from the start)" or "Pause",
        fn = function() Spoken:TogglePause() end, enabled = CanControl() })
    table.insert(items, { text = "Skip this line", fn = function() Spoken:Skip() end,
        enabled = self.clip ~= nil })
    table.insert(items, { text = "Stop everything", fn = function() Spoken:StopAll() end,
        enabled = self.clip ~= nil })
    local waiting = Spoken:GetWaitingCount()
    table.insert(items, { text = ("Waiting lines (%d)"):format(waiting),
        fn = function() self:ToggleQueue() end, enabled = waiting > 0 })

    -- The clip's own actions (Report, Read ...). Buttons an addon builds itself, and the
    -- header ones such as Stop Gossip, have no plain onClick to call, so they are skipped
    -- here just as Spoken's Minimal player skips them.
    for _, action in ipairs(Present(self.clip).actions or {}) do
        if type(action) == "table" and action.onClick and action.anchor ~= "header"
            and (not action.visible or action.visible()) then
            local text = action.label or action.text
            if type(text) == "function" then text = text() end
            if text then
                local clip = self.clip
                table.insert(items, { text = text, icon = action.icon,
                    fn = function() action.onClick(clip) end })
            end
        end
    end

    table.insert(items, { text = "Subtitle settings", fn = function() ns.OpenOptions() end })
    if Spoken.OpenSettings then
        table.insert(items, { text = "Spoken settings", fn = function() Spoken:OpenSettings() end })
    end
    return items
end

function Band:ToggleMenu()
    local menu = self.menu
    if menu:IsShown() then
        menu:Hide()
        return
    end
    if not self.clip then
        return
    end
    HideTooltip()
    local items = self:MenuItems()
    for index, item in ipairs(items) do
        local row = self:MenuRow(index)
        row.fn, row.enabled = item.fn, item.enabled
        row.text:ClearAllPoints()
        if item.icon then
            row.icon:SetTexture(item.icon)
            row.icon:Show()
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        else
            row.icon:Hide()
            row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
        end
        row.text:SetText(item.text)
        row.text:SetAlpha(item.enabled == false and 0.35 or 1)
        row:Show()
    end
    for index = #items + 1, #self.menuRows do
        self.menuRows[index]:Hide()
    end
    menu:SetHeight(16 + #items * 22)
    menu:SetScale(self.frame:GetScale())
    menu:ClearAllPoints()
    -- Above the band: it lives near the bottom of the screen.
    menu:SetPoint("BOTTOM", self.frame, "TOP", 0, 4)
    menu:Show()
end

--------------------------------------------------------------------------------
-- Layout and state
--------------------------------------------------------------------------------

function Band:ApplySettings()
    local frame, db = self.frame, Config()
    if not frame then return end
    frame:SetScale(db.bandScale or 1)
    frame:SetWidth(db.bandWidth or 760)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", db.bandX or 0, db.bandY or 150)
    self.words:SetFont(Face(), db.fontSize or 18, "")
    self:Relayout()
end

--- Whether the clip's speaker is the player's current target (whose frame shows the face).
function Band:IsTarget(clip)
    if not (UnitExists and UnitExists("target")) then return false end
    local portrait = Present(clip).portrait
    local creature = type(portrait) == "table" and tonumber(portrait.creatureID) or nil
    local id = ns.Portraits.CreatureID("target")
    if creature and id then return id == creature end
    local name = Present(clip).header
    return name ~= nil and name ~= "" and UnitName("target") == name
end

--- The small face: only when the speaker is not your target, and there is a face to show.
function Band:ConfigureFace()
    local clip = self.clip
    if self.snapshot then
        self.snapshot.inUse = nil
        self.snapshot:Hide()
        self.snapshot = nil
    end
    self.showFace = false
    if not clip or Config().bandFace == false then
        self.face:Hide()
        return
    end
    local portrait = Present(clip).portrait
    local snapshot = ns.Portraits:Snapshot(clip)
    local art = type(portrait) == "table" and portrait.kind == "texture" and portrait.texture
    if snapshot and not self:IsTarget(clip) then
        snapshot:SetParent(self.face)
        snapshot:SetDrawLayer("ARTWORK", 1)
        snapshot:ClearAllPoints()
        snapshot:SetSize(FACE * 0.8, FACE * 0.8)
        snapshot:SetPoint("CENTER", self.face, "CENTER")
        if self.mask and snapshot.AddMaskTexture and snapshot.bandMask ~= self.mask then
            snapshot:AddMaskTexture(self.mask)
            snapshot.bandMask = self.mask
        end
        snapshot:Show()
        snapshot.inUse = true
        self.snapshot = snapshot
        self.art:Hide()
        self.showFace = true
    elseif art then
        -- Zones and books bring their own picture; there is no target frame showing it.
        self.art:SetTexture(art)
        local coords = portrait.texCoord
        if coords then
            self.art:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            self.art:SetTexCoord(0, 1, 0, 1)
        end
        self.art:Show()
        self.showFace = true
    end
    self.face:SetShown(self.showFace)
end

--- Lay the row out left to right and centre it; size the band to what it holds.
function Band:Relayout()
    local frame = self.frame
    if not frame then return end
    local width = frame:GetWidth()
    local row, x = self.row, 0
    local function Place(region, w, gap, y)
        region:ClearAllPoints()
        region:SetPoint("LEFT", row, "LEFT", x, y or 0)
        x = x + w + (gap or 0)
    end
    if self.showFace then Place(self.face, FACE, 8) end
    local nameWidth = self.name:GetStringWidth() or 0
    Place(self.name, nameWidth, 7)
    local labelWidth = self.label:GetText() ~= "" and (self.label:GetStringWidth() or 0) or 0
    if labelWidth > 0 then Place(self.label, labelWidth, 8, -1) end
    if self.fold:IsShown() then
        local foldWidth = (self.fold.text:GetStringWidth() or 0) + 4
        self.fold:SetWidth(foldWidth)
        Place(self.fold, foldWidth, 0)
    end
    row:SetWidth(math.max(1, x))
    row:SetHeight(self.showFace and FACE or 18)
    row:ClearAllPoints()
    row:SetPoint("TOP", frame, "TOP", 0, -PAD_TOP)

    self.pause:ClearAllPoints()
    self.pause:SetPoint("RIGHT", row, "LEFT", -10, 0)
    self.skip:ClearAllPoints()
    self.skip:SetPoint("LEFT", row, "RIGHT", 10, 0)

    local words = self.words
    words:SetWidth(width - 80)
    words:ClearAllPoints()
    words:SetPoint("TOP", row, "BOTTOM", 0, -WORD_GAP)
    local hasWords = self.clip ~= nil and ns.Display:HasWords(self.clip)
    local wordsHeight = hasWords and math.max(18, words:GetStringHeight() or 0) or 0

    self.track:ClearAllPoints()
    local lineWidth = math.floor(width * 0.45)
    self.track:SetWidth(lineWidth)
    if hasWords then
        self.track:SetPoint("TOP", words, "BOTTOM", 0, -LINE_GAP)
    else
        self.track:SetPoint("TOP", row, "BOTTOM", 0, -LINE_GAP)
    end
    local height = PAD_TOP + row:GetHeight() + (hasWords and (WORD_GAP + wordsHeight) or 0)
        + LINE_GAP + 2 + PAD_BOTTOM
    frame:SetHeight(height)

    -- Only what the band shows takes clicks: the name row with its glyphs, and the words.
    -- The shade's soft sides pass them on, so a click on an NPC or the ground beside the
    -- words does not pause the voice.
    local content = row:GetWidth() + 2 * (10 + 20)
    if hasWords then
        content = math.max(content, math.min(words:GetWidth(), words:GetStringWidth() or 0))
    end
    self.hitInset = math.max(0, math.floor((width - content) / 2) - HIT_PAD)
    frame:SetHitRectInsets(self.hitInset, self.hitInset, 0, 0)
    self:LayoutQueue()
end

function Band:UpdateRow()
    local clip = self.clip
    if not clip then return end
    local present = Present(clip)
    self.name:SetText(present.header or "")
    local label = present.label or ""
    local held = not Spoken:IsPaused() and Spoken:GetNowPlaying() == nil
        and Spoken:GetHeldReason(clip)
    if held then
        label = ("%s |cff9c9580(%s)|r"):format(label, tostring(held))
    end
    -- A quiet dot keeps name and title apart without another icon in the line.
    self.label:SetText(label ~= "" and ("|cff6f685a\194\183|r  " .. label) or "")
end

function Band:UpdateControls()
    if not self.clip then return end
    local paused = Spoken:IsPaused()
    self.pause.icon:SetTexture(MEDIA .. (paused and "GlyphPlay" or "GlyphPause"))
    self.fill:SetVertexColor(paused and 0.6 or 1, paused and 0.56 or 1, paused and 0.45 or 1)
    self.spark:SetShown(not paused and self.started ~= nil and self.startedClip == self.clip)
    self:UpdateRow()
end

function Band:LayoutQueue()
    local drawer = self.drawer
    if not drawer then return end
    local queue = self.clip and Spoken:GetQueue() or {}
    local waiting = math.max(0, #queue - 1)
    if waiting == 0 then self.expanded = false end
    self.fold.text:SetText(waiting > 0 and ("+" .. waiting) or "")
    self.fold:SetShown(waiting > 0)

    local shown = self.expanded and math.min(QUEUE_ROWS, waiting) or 0
    for index = 1, QUEUE_ROWS do
        local row = self.rows[index]
        if index <= shown then
            row = self:QueueRow(index)
            local clip = queue[index + 1]
            local present = Present(clip)
            local text = present.header or ""
            if present.label and present.label ~= "" then
                text = text .. "  |cff9c9580" .. present.label .. "|r"
            end
            local held = Spoken:GetHeldReason(clip)
            if held then text = text .. " |cff9c9580(" .. tostring(held) .. ")|r" end
            row.clip = clip
            row.text:SetText(text)
            row:ClearAllPoints()
            row:SetPoint("BOTTOMLEFT", drawer, "BOTTOMLEFT", 0, (shown - index) * 20)
            row:SetPoint("BOTTOMRIGHT", drawer, "BOTTOMRIGHT", 0, (shown - index) * 20)
            row:Show()
        elseif row then
            row:Hide()
            row.clip = nil
        end
    end
    local extra = waiting - shown
    self.more:ClearAllPoints()
    self.more:SetPoint("TOP", drawer, "TOP", 0, 14)
    self.more:SetText(shown > 0 and extra > 0 and ("and %d more"):format(extra) or "")
    drawer:SetSize(420, math.max(1, shown * 20))
    drawer:ClearAllPoints()
    drawer:SetPoint("BOTTOM", self.frame, "TOP", 0, 2)
    drawer:SetShown(shown > 0)
end

function Band:ToggleQueue()
    if Spoken:GetWaitingCount() == 0 then
        self.expanded = false
    else
        self.expanded = not self.expanded
    end
    self:LayoutQueue()
end

--- Rebuild from the queue. Cheap; called on every change the player reports.
function Band:Update()
    self:SuppressSpoken()
    if not self:IsActive() then
        if self.frame then self:SetVisible(false, true) end
        return
    end
    self:Build()
    local clip = Spoken:GetCurrent()
    if not clip then
        if self.previewUntil and GetTime() < self.previewUntil then
            return
        end
        self.previewUntil = nil
        self.expanded = false
        self:SetVisible(false)
        return
    end
    self.previewUntil = nil
    if clip ~= self.clip then
        self.menu:Hide()
        self.clip = clip
        self:ConfigureFace()
    end
    self:SetVisible(true)
    self:UpdateControls()
    self:Relayout()
end

--- The target changed: the small face may now be redundant, or needed.
function Band:OnTargetChanged()
    if self.clip and self.frame and self.frame:IsShown() then
        self:ConfigureFace()
        self:Relayout()
    end
end

--- A sample line so the style can be seen without a quest: /spsub test.
function Band:Preview(clip)
    self:Build()
    self.menu:Hide()
    self.clip = clip
    self.previewUntil = GetTime() + (clip.length or 14) + 1.5
    self:ConfigureFace()
    self:OnClipStarted(clip)
    self:SetVisible(true)
    self:UpdateControls()
    self:Relayout()
end

--- CLIP_STARTED: the clock for the hairline starts (again, after a pause).
function Band:OnClipStarted(clip)
    self.startedClip = clip
    self.started = GetTime()
    self.frozen = nil
end

function Band:Progress()
    local clip = self.clip
    local length = clip and ((tonumber(clip.length) or 0) + (tonumber(clip.delay) or 0)) or 0
    if length <= 0 or not self.started or self.startedClip ~= clip then
        return 0
    end
    if Spoken:IsPaused() then
        self.frozen = self.frozen or (GetTime() - self.started)
        return math.min(1, self.frozen / length)
    end
    return math.min(1, (GetTime() - self.started) / length)
end

--- The FontString the subtitles render into, and how it fades.
function Band:SubtitleView()
    self:Build()
    return {
        text = self.words, fader = self.words, band = true,
        -- Paused, the words stay readable but dim, next to the play glyph.
        pausedAlpha = 0.45,
        onText = function() Band:Relayout() end,
    }
end

function Band:SetVisible(visible, immediate)
    local frame = self.frame
    if not frame then return end
    if not visible then
        self.menu:Hide()
        if self.snapshot then self.snapshot.inUse = nil end
    end
    -- Fading out, it is no longer a player: clicks go to the world at once.
    frame:EnableMouse(visible and true or false)
    if immediate then
        self.wanted = false
        frame:SetAlpha(0)
        frame:Hide()
        self.clip = nil
        return
    end
    if self.wanted == visible then return end
    self.wanted = visible
    if visible then frame:Show() end
end

local function Approach(value, target, step)
    if value < target then return math.min(target, value + step) end
    if value > target then return math.max(target, value - step) end
    return value
end

function Band:Tick(elapsed)
    local frame = self.frame
    elapsed = elapsed or 0
    if self.previewUntil and GetTime() >= self.previewUntil and not Spoken:GetCurrent() then
        self.previewUntil = nil
        self.wanted = false
    end
    frame:SetAlpha(Approach(frame:GetAlpha(), self.wanted and 1 or 0, elapsed / self.FADE_SECONDS))
    if not self.wanted and frame:GetAlpha() <= 0 then
        frame:Hide()
        self.clip = nil
        return
    end

    local progress = self:Progress()
    self.fill:SetWidth(math.max(0.01, self.track:GetWidth() * progress))

    -- Controls: visible on hover; the play glyph also stays while paused.
    -- Over the part that takes clicks, so the glyphs never promise a click the world gets.
    local hover = (self.wanted and IsOver(frame, self.hitInset))
        or (self.menu and self.menu:IsShown())
    self.hover = hover and true or false
    self.controlsAlpha = Approach(self.controlsAlpha or 0, self.hover and 1 or 0,
        elapsed / self.HOVER_FADE_SECONDS)
    self.skip:SetAlpha(self.controlsAlpha)
    self.skip:EnableMouse(self.controlsAlpha > 0.5)
    local paused = Spoken:IsPaused()
    self.pause:SetAlpha(paused and 1 or self.controlsAlpha)
    self.pause:EnableMouse(paused or self.controlsAlpha > 0.5)

    self.poll = (self.poll or 0) + elapsed
    if self.poll >= 0.2 then
        self.poll = 0
        self:UpdateControls()
    end
end

--------------------------------------------------------------------------------
-- Moving
--------------------------------------------------------------------------------

function Band:StartDrag()
    if Config().bandLocked then return end
    self.menu:Hide()
    self.frame:StartMoving()
    self.dragging = true
end

function Band:StopDrag()
    if not self.dragging then return end
    self.dragging = false
    self.dragEnded = GetTime()
    local frame = self.frame
    frame:StopMovingOrSizing()
    if frame.SetUserPlaced then frame:SetUserPlaced(false) end
    local scale = frame:GetScale()
    local centre = frame:GetCenter()
    local db = Config()
    db.bandX = math.floor(centre - UIParent:GetWidth() / scale / 2 + 0.5)
    db.bandY = math.floor(frame:GetBottom() + 0.5)
    self:ApplySettings()
end

--------------------------------------------------------------------------------
-- Spoken's own window
--------------------------------------------------------------------------------

local hooked = setmetatable({}, { __mode = "k" })

--- While the band is the style, Spoken's window is hidden whenever it shows.
--- Only this session: nothing of Spoken's settings is written.
function Band:SuppressSpoken()
    local spokenFrame = Spoken.GetPlayerFrame and Spoken:GetPlayerFrame()
    if not spokenFrame then return end
    if not hooked[spokenFrame] then
        hooked[spokenFrame] = true
        spokenFrame:HookScript("OnShow", function(shown)
            if Band:IsActive() then shown:Hide() end
        end)
    end
    if self:IsActive() and spokenFrame:IsShown() then
        spokenFrame:Hide()
    end
end

--- Back to Spoken's player: show its window for the line in progress and let it decide.
function Band:ReleaseSpoken()
    if self.frame then self:SetVisible(false, true) end
    local spokenFrame = Spoken.GetPlayerFrame and Spoken:GetPlayerFrame()
    if spokenFrame and Spoken:GetCurrent() then
        spokenFrame:Show()
    end
    if Spoken.RefreshPlayer then Spoken:RefreshPlayer() end
end

return Band
