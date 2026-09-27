-- SpokenSubtitles -- timing the cues and putting them on screen.
--
-- Two places a line can appear, called views:
--
--   screen    this file's own frame: white text with a heavy shadow, the way the game's
--             cinematic subtitles look, at the bottom of the screen or beside Spoken's
--             player.
--   head      the words line inside the talking head (TalkingHead.lua).
--
-- The clock is this addon's own. The player's timer is internal, so elapsed time starts at
-- CLIP_STARTED and a resume -- which the player implements as replaying the clip from the
-- start -- simply starts it again. A separate ticker drives it, so the clock runs whichever
-- view is showing.

local _, ns = ...
ns = ns or {}

local Display = {}
ns.Display = Display

local Cues = ns.Cues

Display.FADE_SECONDS = 0.25
-- How long the last cue stays after the words end.
Display.HOLD_SECONDS = 1.0
Display.LINE_WIDTH = 720
Display.PLAYER_LINE_WIDTH = 420
local SPEAKER_COLOR = "|cffffd100"

-- Blizzard panels that already show the words being spoken.
local DIALOGS = { "QuestFrame", "GossipFrame", "ImmersionFrame" }

local function Config()
    return ns.db or ns.defaults
end

local function DialogOpen()
    for _, name in ipairs(DIALOGS) do
        local frame = _G[name]
        if frame and frame.IsVisible and frame:IsVisible() then
            return true
        end
    end
    return false
end

--- Words go into the talking head when it is the style and the position is "player".
local function UsesHead()
    local db = Config()
    return db.style == "head" and ns.Mode() == "player" and ns.TalkingHead
        and ns.TalkingHead:IsActive()
end

function Display:Create()
    if self.frame then
        return self.frame
    end
    local frame = CreateFrame("Frame", "SpokenSubtitlesFrame", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetAlpha(0)
    frame:Hide()

    -- Shown only while the line is being placed, so there is something to grab.
    local handle = frame:CreateTexture(nil, "BACKGROUND")
    handle:SetAllPoints(frame)
    handle:SetColorTexture(0, 0, 0, 0.45)
    handle:Hide()
    self.handle = handle

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetJustifyH("CENTER")
    if text.SetWordWrap then
        text:SetWordWrap(true)
    end
    if text.SetMaxLines then
        text:SetMaxLines(3)
    end
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1.5, -1.5)
    text:SetTextColor(1, 1, 1)
    self.text = text
    self.screen = { text = text, fader = frame, frame = frame }

    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        if f.SetUserPlaced then
            f:SetUserPlaced(false)   -- the position lives in SpokenSubtitlesDB, not layout-local
        end
        local db = Config()
        local centre = f:GetCenter()
        db.offsetX = math.floor(centre - UIParent:GetWidth() / 2 + 0.5)
        db.offsetY = math.floor(f:GetBottom() + 0.5)
        Display:Layout()
    end)

    local ticker = CreateFrame("Frame")
    ticker:Hide()
    ticker:SetScript("OnUpdate", function(_, elapsed) Display:OnUpdate(elapsed) end)
    self.ticker = ticker

    self.frame = frame
    self:Layout()
    return frame
end

--- Font, width and anchor of the screen view from the settings. Cheap.
function Display:Layout()
    local frame, text, db = self.frame, self.text, Config()
    if not frame then
        return
    end
    -- The face from the client's own font object, so a Russian, Korean or Chinese client
    -- gets the font that has its glyphs; only the size is ours.
    local face, _, flags = GameFontNormalLarge:GetFont()
    text:SetFont(face, db.fontSize, flags or "")

    local lineHeight = db.fontSize * 1.35
    frame:ClearAllPoints()
    text:ClearAllPoints()

    local player = ns.Mode() == "player" and db.style ~= "head" and _G.Spoken
        and _G.Spoken.GetPlayerFrame and _G.Spoken:GetPlayerFrame()
    if player and player.IsVisible and player:IsVisible() then
        local width = self.PLAYER_LINE_WIDTH
        frame:SetSize(width, lineHeight * 3)
        text:SetWidth(width)
        -- Below the player, or above it when it sits at the bottom edge of the screen.
        if (player:GetBottom() or 0) < lineHeight * 3 + 20 then
            frame:SetPoint("BOTTOM", player, "TOP", 0, 6)
            text:SetPoint("BOTTOM", frame, "BOTTOM")
            text:SetJustifyV("BOTTOM")
        else
            frame:SetPoint("TOP", player, "BOTTOM", 0, -6)
            text:SetPoint("TOP", frame, "TOP")
            text:SetJustifyV("TOP")
        end
    else
        local width = self.LINE_WIDTH
        frame:SetSize(width, lineHeight * 3)
        text:SetWidth(width)
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", db.offsetX or 0, db.offsetY)
        text:SetPoint("BOTTOM", frame, "BOTTOM")
        text:SetJustifyV("BOTTOM")
    end
    if ns.TalkingHead and ns.TalkingHead.ApplySettings then
        ns.TalkingHead:ApplySettings()
    end
end

--- Pick the view for the next line, and park the one no longer used.
function Display:SelectView()
    local view = UsesHead() and ns.TalkingHead:SubtitleView() or self.screen
    if self.view and self.view ~= view then
        self.view.fader:SetAlpha(0)
        self.view.text:SetText("")
        if self.view.frame and not self.unlocked then self.view.frame:Hide() end
    end
    self.view = view
    return view
end

--- Begin showing `cues` for `clip`, from zero.
function Display:Start(clip, cues, speaker)
    self:Create()
    self:Layout()
    local view = self:SelectView()
    self.clip = clip
    self.cues = cues
    self.speaker = speaker
    self.elapsed = 0
    self.index = nil
    self.paused = false
    self.ending = nil
    self.demo = clip and clip.demo or false
    if view.frame then view.frame:Show() end
    if view.head then ns.TalkingHead:SetWords(clip, #cues > 0) end
    self.ticker:Show()
    self:OnUpdate(0)
end

--- Fade out now: the clip was stopped, skipped or finished, or has no words.
function Display:Finish(clip)
    if clip and clip ~= self.clip then
        return
    end
    if self.clip then
        self.ending = true
    end
end

function Display:SetPaused(paused)
    if self.clip then
        self.paused = paused and true or false
    end
end

function Display:IsActive()
    return self.clip ~= nil
end

local function Render(text, speaker, view)
    local line = Cues.Markup(text)
    -- The talking head, and Spoken's player, already name the speaker.
    if speaker and speaker ~= "" and Config().speaker and not view.head
        and Config().style ~= "head" then
        line = SPEAKER_COLOR .. string.gsub(speaker, "|", "||") .. ":|r " .. line
    end
    return line
end

function Display:OnUpdate(elapsed)
    local view = self.view
    if not view or not self.clip then
        if self.ticker then self.ticker:Hide() end
        return
    end
    if not self.paused then
        self.elapsed = self.elapsed + (elapsed or 0)
    end

    local cues = self.cues
    local index = Cues.At(cues, self.elapsed)
    if index and index ~= self.index then
        self.index = index
        view.text:SetText(Render(cues[index].text, self.speaker, view))
    end

    local last = cues[#cues]
    local over = self.ending or not last or self.elapsed > last.stop + self.HOLD_SECONDS
    local hidden = over or self.paused
        or (not self.demo and Config().hideWithDialog and DialogOpen())
    local target = hidden and 0 or 1

    local fader = view.fader
    local alpha = fader:GetAlpha()
    local step = (elapsed or 0) / self.FADE_SECONDS
    if alpha < target then
        alpha = math.min(target, alpha + step)
    elseif alpha > target then
        alpha = math.max(target, alpha - step)
    end
    fader:SetAlpha(alpha)

    if over and alpha <= 0 then
        self.clip, self.cues, self.index, self.ending = nil, nil, nil, nil
        view.text:SetText("")
        if view.frame and not self.unlocked then
            view.frame:Hide()
        end
        self.ticker:Hide()
    end
end

--- Show the line's box with a sample so it can be dragged. Screen position only.
function Display:SetUnlocked(unlocked)
    self:Create()
    self.unlocked = unlocked and true or false
    local frame = self.frame
    frame:EnableMouse(self.unlocked)
    if self.unlocked then
        self.handle:Show()
        frame:Show()
        frame:SetAlpha(1)
        if not self.clip or self.view ~= self.screen then
            self.text:SetText(Render(ns.SAMPLE_CUE, ns.SAMPLE_SPEAKER, self.screen))
        end
    else
        self.handle:Hide()
        if not self.clip or self.view ~= self.screen then
            frame:SetAlpha(0)
            frame:Hide()
        end
    end
end

return Display
