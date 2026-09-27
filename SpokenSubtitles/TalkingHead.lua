-- SpokenSubtitles -- the talking head: a player of its own, drawn as portrait, name and words.
--
-- A full player on Spoken's public API. Playback, the queue and every action stay Spoken's:
-- this file only draws them and calls TogglePause, Skip, StopAll, source:Remove and the
-- actions' own onClick. While it is the chosen style, Spoken's own window is kept hidden
-- for this session only -- nothing in Spoken's settings is written, so disabling this addon
-- brings Spoken's window straight back.
--
--   portrait    left-click pauses / restarts, drag moves, right-click opens the menu
--   name line   left-click skips the line (red on hover, as in Spoken's players)
--   +N          opens the waiting lines; clicking one removes it
--   menu        pause, skip, stop all, the queue, the clip's actions, settings

local _, ns = ...
ns = ns or {}

local TalkingHead = {}
ns.TalkingHead = TalkingHead

local MEDIA = [[Interface\AddOns\SpokenSubtitles\Media\]]
local RING = 92                      -- the ring texture's drawn size
local FACE = RING * 206 / 256        -- the opening inside the ring
local BADGE_X, BADGE_Y = RING * 207.2 / 256, RING * 208.1 / 256
local GAP = 12
local QUEUE_ROWS = 6
local GOLD = { 1, 0.82, 0 }
local LABEL = { 0.86, 0.82, 0.72 }
local REMOVE = { 1, 0.28, 0.2 }

TalkingHead.FADE_SECONDS = 0.2

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
        GameTooltip:AddLine((select(index, ...)), 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
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

function TalkingHead:IsActive()
    return Config().style == "head" and ns.connected and true or false
end

function TalkingHead:Build()
    if self.frame then
        return self.frame
    end
    local frame = CreateFrame("Frame", "SpokenSubtitlesTalkingHead", UIParent)
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
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then self:ToggleMenu() end
    end)
    frame:SetScript("OnUpdate", function(_, elapsed) self:Tick(elapsed) end)

    self:BuildPortrait()
    self:BuildColumn()
    self:BuildQueue()
    self:BuildMenu()
    self:ApplySettings()
    return frame
end

function TalkingHead:BuildPortrait()
    local portrait = CreateFrame("Button", nil, self.frame)
    self.portrait = portrait
    portrait:SetSize(RING, RING)
    portrait:SetPoint("LEFT", self.frame, "LEFT", 0, 0)
    portrait:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    portrait:RegisterForDrag("LeftButton")
    portrait:SetScript("OnDragStart", function() self:StartDrag() end)
    portrait:SetScript("OnDragStop", function() self:StopDrag() end)
    portrait:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            self:ToggleMenu()
        elseif CanControl() then
            Spoken:TogglePause()
        end
    end)
    portrait:SetScript("OnEnter", function()
        self.hoverPortrait = true
        Tooltip(portrait, Spoken:IsPaused() and "Play" or "Pause",
            Spoken:IsPaused() and "Starts the line again from the beginning." or nil,
            "Right-click for more.")
        self:UpdateControls()
    end)
    portrait:SetScript("OnLeave", function()
        self.hoverPortrait = false
        HideTooltip()
        self:UpdateControls()
    end)

    local disc = portrait:CreateTexture(nil, "BACKGROUND")
    disc:SetTexture(MEDIA .. "TalkingHeadDisc")
    disc:SetSize(FACE + 2, FACE + 2)
    disc:SetPoint("CENTER")

    -- Fallback art, masked round. Snapshots are round already and are parented in place.
    local art = portrait:CreateTexture(nil, "ARTWORK")
    art:SetSize(FACE, FACE)
    art:SetPoint("CENTER")
    if portrait.CreateMaskTexture then
        local mask = portrait:CreateMaskTexture()
        mask:SetTexture(MEDIA .. "TalkingHeadMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(art)
        art:AddMaskTexture(mask)
        self.mask = mask
    end
    self.art = art

    local wash = portrait:CreateTexture(nil, "ARTWORK", nil, 5)
    wash:SetTexture(MEDIA .. "TalkingHeadDisc")
    wash:SetSize(FACE, FACE)
    wash:SetPoint("CENTER")
    wash:SetAlpha(0.55)
    self.wash = wash

    self.pauseBars = {}
    for index, x in ipairs({ -6, 6 }) do
        local bar = portrait:CreateTexture(nil, "OVERLAY", nil, 1)
        bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.95)
        bar:SetSize(6, 22)
        bar:SetPoint("CENTER", x, 0)
        self.pauseBars[index] = bar
    end

    local ring = portrait:CreateTexture(nil, "OVERLAY", nil, 2)
    ring:SetTexture(MEDIA .. "TalkingHeadRing")
    ring:SetAllPoints()

    local badge = portrait:CreateTexture(nil, "OVERLAY", nil, 3)
    badge:SetSize(18, 18)
    badge:SetPoint("CENTER", portrait, "TOPLEFT", BADGE_X, -BADGE_Y)
    self.badge = badge
end

function TalkingHead:BuildColumn()
    local column = CreateFrame("Frame", nil, self.frame)
    self.column = column
    column:SetHeight(RING)

    -- The name line doubles as the "skip this line" button, as the title does in Spoken.
    local title = CreateFrame("Button", nil, column)
    self.title = title
    title:SetHeight(18)
    title:SetPoint("TOPLEFT", column, "TOPLEFT")
    title:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() self:StartDrag() end)
    title:SetScript("OnDragStop", function() self:StopDrag() end)
    self.name = Text(title, 15, GOLD)
    self.name:SetPoint("LEFT", title, "LEFT", 0, 0)
    self.label = Text(title, 13, LABEL)
    self.label:SetPoint("LEFT", self.name, "RIGHT", 8, -1)
    title:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            self:ToggleMenu()
        elseif self.clip then
            Remove(self.clip)
        end
    end)
    title:SetScript("OnEnter", function()
        if not self.clip then return end
        self.hoverTitle = true
        self:UpdateTitle()
        Tooltip(title, Present(self.clip).label or Present(self.clip).header or "",
            "Click to skip this line.", "Right-click for more.")
    end)
    title:SetScript("OnLeave", function()
        self.hoverTitle = false
        self:UpdateTitle()
        HideTooltip()
    end)

    local fold = CreateFrame("Button", nil, column)
    self.fold = fold
    fold:SetHeight(18)
    fold:SetPoint("LEFT", title, "RIGHT", 6, 0)
    fold.text = Text(fold, 13, GOLD)
    fold.text:SetPoint("LEFT", fold, "LEFT", 0, 0)
    fold:SetScript("OnClick", function() self:ToggleQueue() end)
    fold:SetScript("OnEnter", function()
        Tooltip(fold, "Waiting lines", self.expanded and "Click to close the list."
            or "Click to see what is waiting.")
    end)
    fold:SetScript("OnLeave", HideTooltip)
    fold:Hide()

    self.line = Text(column, 17, { 1, 1, 1 })
    self.line:SetShadowOffset(1.5, -1.5)
    if self.line.SetWordWrap then self.line:SetWordWrap(true) end
    if self.line.SetMaxLines then self.line:SetMaxLines(3) end
    self.line:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    self.line:SetAlpha(0)

    local track = column:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0, 0, 0, 0.45)
    track:SetHeight(2)
    self.track = track
    local fill = column:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(0.85, 0.71, 0.29, 0.85)
    fill:SetHeight(2)
    fill:SetPoint("TOPLEFT", track, "TOPLEFT")
    self.fill = fill
end

function TalkingHead:BuildQueue()
    local drawer = CreateFrame("Frame", nil, self.frame)
    self.drawer = drawer
    drawer:Hide()
    self.rows = {}
    self.more = Text(drawer, 12, LABEL)
end

function TalkingHead:QueueRow(index)
    local row = self.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, self.drawer)
    row:SetHeight(20)
    row.text = Text(row, 13, LABEL)
    row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
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

function TalkingHead:BuildMenu()
    local menu = CreateFrame("Frame", "SpokenSubtitlesTalkingHeadMenu", UIParent,
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
    if UISpecialFrames then table.insert(UISpecialFrames, "SpokenSubtitlesTalkingHeadMenu") end
    pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
    menu:SetScript("OnEvent", function()
        if menu:IsShown() and not MouseIsOver(menu) and not MouseIsOver(self.frame) then
            menu:Hide()
        end
    end)
    self.menuRows = {}
end

function TalkingHead:MenuRow(index)
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
-- Menu
--------------------------------------------------------------------------------

--- The rows the menu shows for the current clip: { text, fn, icon, enabled }.
function TalkingHead:MenuItems()
    local items = {}
    local controllable = CanControl()
    table.insert(items, { text = Spoken:IsPaused() and "Play (from the start)" or "Pause",
        fn = function() Spoken:TogglePause() end, enabled = controllable })
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

function TalkingHead:ToggleMenu()
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
    if (self.frame:GetBottom() or 0) < menu:GetHeight() + 20 then
        menu:SetPoint("BOTTOMLEFT", self.portrait, "TOPRIGHT", -12, -8)
    else
        menu:SetPoint("TOPLEFT", self.portrait, "BOTTOMRIGHT", -12, 8)
    end
    menu:Show()
end

--------------------------------------------------------------------------------
-- Layout and state
--------------------------------------------------------------------------------

function TalkingHead:ApplySettings()
    local frame, db = self.frame, Config()
    if not frame then return end
    local width = db.headWidth or 470
    frame:SetScale(db.headScale or 1)
    frame:SetSize(RING + GAP + width, RING)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", db.headX or 0, db.headY or 120)
    self.column:ClearAllPoints()
    self.column:SetPoint("LEFT", self.portrait, "RIGHT", GAP, 0)
    self.column:SetWidth(width)
    self.line:SetFont(Face(), db.fontSize or 17, "")
    self.line:SetWidth(width)
    self:Relayout()
end

--- Place the column: name, words, progress. With no words for this line the name and the
--- progress sit together, centred on the portrait.
function TalkingHead:Relayout()
    if not self.column then return end
    local title, track = self.title, self.track
    title:ClearAllPoints()
    track:ClearAllPoints()
    local width = self.column:GetWidth()
    self.hasWords = self.clip ~= nil and self.words[self.clip] == true
    title:SetWidth(math.max(40, (self.name:GetStringWidth() or 0) + 8
        + (self.label:GetStringWidth() or 0)))
    if self.hasWords then
        title:SetPoint("TOPLEFT", self.column, "TOPLEFT", 0, -10)
        track:SetPoint("TOPLEFT", self.line, "BOTTOMLEFT", 0, -6)
    else
        title:SetPoint("LEFT", self.column, "LEFT", 0, 6)
        track:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    end
    track:SetWidth(width)
    self:LayoutQueue()
end

--- Whether `clip` has subtitle words in the head. Display says so when the line starts.
TalkingHead.words = setmetatable({}, { __mode = "k" })
function TalkingHead:SetWords(clip, hasWords)
    if clip then
        self.words[clip] = hasWords and true or false
    end
    if clip == self.clip then
        self:Relayout()
    end
end

--- The FontString the subtitles render into, and the region that fades.
function TalkingHead:SubtitleView()
    self:Build()
    return { text = self.line, fader = self.line, head = true }
end

function TalkingHead:UpdateTitle()
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
    self.label:SetText(label)
    local color = self.hoverTitle and REMOVE or GOLD
    self.name:SetTextColor(color[1], color[2], color[3])
    self.title:SetWidth(math.max(40, (self.name:GetStringWidth() or 0) + 8
        + (self.label:GetStringWidth() or 0)))
end

function TalkingHead:UpdateControls()
    if not self.clip then return end
    local paused = Spoken:IsPaused()
    self.wash:SetShown(paused)
    local showBars = paused or (self.hoverPortrait and CanControl())
    for _, bar in ipairs(self.pauseBars) do
        bar:SetShown(showBars)
        bar:SetAlpha(paused and 0.95 or 0.6)
    end
    self.fill:SetColorTexture(paused and 0.5 or 0.85, paused and 0.46 or 0.71,
        paused and 0.34 or 0.29, 0.85)
    self:UpdateTitle()
end

function TalkingHead:ConfigurePortrait()
    local clip = self.clip
    if self.snapshot then
        self.snapshot.inUse = nil
        self.snapshot:Hide()
        self.snapshot = nil
    end
    local snapshot = ns.Portraits:Snapshot(clip)
    if snapshot then
        snapshot:SetParent(self.portrait)
        snapshot:SetDrawLayer("ARTWORK", 1)
        snapshot:ClearAllPoints()
        snapshot:SetSize(FACE, FACE)
        snapshot:SetPoint("CENTER", self.portrait, "CENTER")
        -- Round, as Spoken's own static portraits are: the painted square has corners.
        if self.mask and snapshot.AddMaskTexture and snapshot.headMask ~= self.mask then
            snapshot:AddMaskTexture(self.mask)
            snapshot.headMask = self.mask
        end
        snapshot:Show()
        snapshot.inUse = true
        self.snapshot = snapshot
        self.art:Hide()
    else
        local texture, coords = ns.Portraits:Fallback(clip)
        self.art:SetTexture(texture)
        if coords then
            self.art:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            self.art:SetTexCoord(0, 1, 0, 1)
        end
        self.art:Show()
    end
    local bullet = Spoken.GetBullet and Spoken:GetBullet(Present(clip).bullet)
    self.badge:SetTexture(bullet and bullet.texture or nil)
    self.badge:SetShown(bullet ~= nil and bullet.texture ~= nil)
end

function TalkingHead:LayoutQueue()
    local drawer = self.drawer
    if not drawer then return end
    local queue = self.clip and Spoken:GetQueue() or {}
    local waiting = math.max(0, #queue - 1)
    if waiting == 0 then self.expanded = false end
    self.fold.text:SetText(waiting > 0 and ("+" .. waiting) or "")
    self.fold:SetWidth((self.fold.text:GetStringWidth() or 0) + 4)
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
            row:SetPoint("TOPLEFT", drawer, "TOPLEFT", 0, -(index - 1) * 20)
            row:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", 0, -(index - 1) * 20)
            row:Show()
        elseif row then
            row:Hide()
            row.clip = nil
        end
    end
    local extra = waiting - shown
    self.more:ClearAllPoints()
    self.more:SetPoint("TOPLEFT", drawer, "TOPLEFT", 0, -shown * 20)
    self.more:SetText(shown > 0 and extra > 0 and ("and %d more"):format(extra) or "")
    local height = shown * 20 + (shown > 0 and extra > 0 and 16 or 0)
    drawer:SetSize(self.column:GetWidth(), math.max(1, height))
    drawer:ClearAllPoints()
    -- Near the bottom of the screen the list opens upwards, over the head.
    if (self.frame:GetBottom() or 200) < height + 16 then
        drawer:SetPoint("BOTTOMLEFT", self.column, "TOPLEFT", 0, 4)
    else
        drawer:SetPoint("TOPLEFT", self.column, "BOTTOMLEFT", 0, -2)
    end
    drawer:SetShown(shown > 0)
end

function TalkingHead:ToggleQueue()
    if Spoken:GetWaitingCount() == 0 then
        self.expanded = false
    else
        self.expanded = not self.expanded
    end
    self:LayoutQueue()
end

--- Rebuild from the queue. Cheap; called on every change the player reports.
function TalkingHead:Update()
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
        self:ConfigurePortrait()
    end
    self:SetVisible(true)
    self:UpdateControls()
    self:Relayout()
end

--- A sample line so the style can be seen without a quest: /spsub test.
function TalkingHead:Preview(clip)
    self:Build()
    self.menu:Hide()
    self.clip = clip
    self.previewUntil = GetTime() + (clip.length or 14) + 1.5
    self:ConfigurePortrait()
    self:OnClipStarted(clip)
    self:SetVisible(true)
    self:UpdateControls()
    self:Relayout()
end

--- CLIP_STARTED: the clock for the progress line starts (again, after a pause).
function TalkingHead:OnClipStarted(clip)
    self.startedClip = clip
    self.started = GetTime()
    self.frozen = nil
end

function TalkingHead:Progress()
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

function TalkingHead:SetVisible(visible, immediate)
    local frame = self.frame
    if not frame then return end
    if not visible then
        self.menu:Hide()
        if self.snapshot then self.snapshot.inUse = nil end
    end
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

function TalkingHead:Tick(elapsed)
    local frame = self.frame
    local target = self.wanted and 1 or 0
    local alpha = frame:GetAlpha()
    local step = (elapsed or 0) / self.FADE_SECONDS
    if alpha < target then alpha = math.min(target, alpha + step)
    elseif alpha > target then alpha = math.max(target, alpha - step) end
    frame:SetAlpha(alpha)
    if self.previewUntil and GetTime() >= self.previewUntil and not Spoken:GetCurrent() then
        self.previewUntil = nil
        self.wanted = false
    end
    if not self.wanted and alpha <= 0 then
        frame:Hide()
        self.clip = nil
        return
    end
    self.fill:SetWidth(math.max(0.01, self.track:GetWidth() * self:Progress()))
    self.poll = (self.poll or 0) + (elapsed or 0)
    if self.poll >= 0.2 then
        self.poll = 0
        self:UpdateControls()
    end
end

--------------------------------------------------------------------------------
-- Moving
--------------------------------------------------------------------------------

function TalkingHead:StartDrag()
    if Config().headLocked then return end
    self.menu:Hide()
    self.frame:StartMoving()
    self.dragging = true
end

function TalkingHead:StopDrag()
    if not self.dragging then return end
    self.dragging = false
    local frame = self.frame
    frame:StopMovingOrSizing()
    if frame.SetUserPlaced then frame:SetUserPlaced(false) end
    local scale = frame:GetScale()
    local centre = frame:GetCenter()
    local db = Config()
    db.headX = math.floor(centre - UIParent:GetWidth() / scale / 2 + 0.5)
    db.headY = math.floor(frame:GetBottom() + 0.5)
    self:ApplySettings()
end

--------------------------------------------------------------------------------
-- Spoken's own window
--------------------------------------------------------------------------------

local hooked = setmetatable({}, { __mode = "k" })

--- While the talking head is the style, Spoken's window is hidden whenever it shows.
--- Only this session: nothing of Spoken's settings is written.
function TalkingHead:SuppressSpoken()
    local spokenFrame = Spoken.GetPlayerFrame and Spoken:GetPlayerFrame()
    if not spokenFrame then return end
    if not hooked[spokenFrame] then
        hooked[spokenFrame] = true
        spokenFrame:HookScript("OnShow", function(shown)
            if TalkingHead:IsActive() then shown:Hide() end
        end)
    end
    if self:IsActive() and spokenFrame:IsShown() then
        spokenFrame:Hide()
    end
end

--- Back to Spoken's player: show its window for the line in progress and let it decide.
function TalkingHead:ReleaseSpoken()
    if self.frame then self:SetVisible(false, true) end
    local spokenFrame = Spoken.GetPlayerFrame and Spoken:GetPlayerFrame()
    if spokenFrame and Spoken:GetCurrent() then
        spokenFrame:Show()
    end
    if Spoken.RefreshPlayer then Spoken:RefreshPlayer() end
end

return TalkingHead
