-- A small stand-in for the parts of the WoW client and Spoken Player this addon touches.
-- Frames are plain tables; unknown methods are no-ops so layout code runs unchanged.

Mock = { time = 0, timers = {}, frames = {}, chat = {}, quest = {} }

function GetTime() return Mock.time end
C_Timer = {
    After = function(seconds, fn)
        table.insert(Mock.timers, { at = Mock.time + seconds, fn = fn })
    end,
}

local Methods = {}
local function NewRegion(kind, name, parent)
    local region = { kind = kind, name = name, parent = parent, shown = true, alpha = 1,
        scripts = {}, events = {}, points = {}, text = "", width = 0, height = 0 }
    return setmetatable(region, { __index = function(_, key)
        return Methods[key] or function() end
    end })
end
Mock.NewRegion = NewRegion

function Methods:Show()
    if self.shown then return end
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
    for _, hook in ipairs(rawget(self, "hooks") or {}) do hook(self) end
end
function Methods:Hide() self.shown = false end
function Methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Methods:HookScript(name, fn)
    if name == "OnShow" then
        local hooks = rawget(self, "hooks") or {}
        rawset(self, "hooks", hooks)
        table.insert(hooks, fn)
    end
end
function Methods:SetParent(parent) rawset(self, "parent", parent) end
function Methods:SetTexture(texture) self.texture = texture end
function Methods:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Methods:SetTexCoord(...) self.texCoord = { ... } end
function Methods:GetStringWidth() return #(self.text or "") * 7 end
function Methods:GetStringHeight()
    local text = self.text or ""
    if text == "" then return 0 end
    local perLine = math.max(1, math.floor((rawget(self, "width") or 600) / 8))
    return math.ceil(#text / perLine) * 20
end
function Methods:EnableMouse(on) rawset(self, "mouse", on and true or false) end
function Methods:GetScale() return rawget(self, "scale") or 1 end
function Methods:SetScale(scale) rawset(self, "scale", scale) end
function Methods:CreateMaskTexture() return NewRegion("MaskTexture", nil, self) end
function Methods:GetHighlightTexture() return NewRegion("Texture", nil, self) end
function Methods:SetTextColor(r, g, b) self.textColor = { r, g, b } end
function Methods:Click(button)
    if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end
end
function Methods:IsShown() return self.shown end
function Methods:IsVisible()
    if not self.shown then return false end
    local parent = rawget(self, "parent")
    if parent and parent.IsVisible then return parent:IsVisible() end
    return true
end
function Methods:SetAlpha(a) self.alpha = a end
function Methods:GetAlpha() return self.alpha end
function Methods:SetScript(name, fn) self.scripts[name] = fn end
function Methods:GetScript(name) return self.scripts[name] end
function Methods:RegisterEvent(event) self.events[event] = true end
function Methods:SetText(text) self.text = text or "" end
function Methods:GetText() return self.text end
function Methods:SetFont(face, size, flags) self.font = { face, size, flags } end
function Methods:SetPoint(...) table.insert(self.points, { ... }) end
function Methods:ClearAllPoints() self.points = {} end
function Methods:SetSize(w, h) self.width, self.height = w, h end
function Methods:SetWidth(w) self.width = w end
function Methods:SetHeight(h) self.height = h end
function Methods:GetWidth() return self.width ~= 0 and self.width or 1024 end
function Methods:GetHeight() return self.height or 0 end
function Methods:GetCenter() return 612, 300 end
function Methods:GetBottom() return rawget(self, "bottom") or 240 end
function Methods:GetChecked() return self.checked end
function Methods:SetChecked(v) self.checked = v end
function Methods:CreateFontString() return NewRegion("FontString", nil, self) end
function Methods:CreateTexture() return NewRegion("Texture", nil, self) end
function Methods:GetVerticalScroll() return 0 end

function CreateFrame(kind, name, parent)
    local frame = NewRegion(kind, name, parent)
    table.insert(Mock.frames, frame)
    if name then _G[name] = frame end
    return frame
end

UIParent = NewRegion("Frame", "UIParent")
GameFontNormalLarge = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 16, "" end }
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) table.insert(Mock.chat, message) end }
SlashCmdList = {}

Settings = {
    RegisterCanvasLayoutCategory = function(_, name) return { ID = name } end,
    RegisterCanvasLayoutSubcategory = function(parent, _, name)
        Mock.subcategory = { parent = parent, name = name }
        return { ID = "sub:" .. name }
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(id) Mock.opened = id end,
}

-- Quest dialog globals.
function GetQuestID() return Mock.quest.id or 0 end
function GetQuestText() return Mock.quest.accept or "" end
function GetProgressText() return Mock.quest.progress or "" end
function GetRewardText() return Mock.quest.complete or "" end
function GetGreetingText() return Mock.quest.greeting or "" end
function GetGossipText() return Mock.quest.gossip or "" end

-- The player's public API.
Spoken = { handlers = {}, paused = false, links = {} }
Spoken.playerFrame = NewRegion("Frame", "SpokenPlayerMock")
function Spoken:IsCompatible(v) return v <= 1 end
function Spoken:RegisterCallback(event, fn)
    self.handlers[event] = self.handlers[event] or {}
    table.insert(self.handlers[event], fn)
end
function Spoken:Fire(event, a, b)
    for _, fn in ipairs(self.handlers[event] or {}) do fn(a, b) end
end
function Spoken:IsPaused() return self.paused end
function Spoken:GetPlayerFrame() return self.playerFrame end
function Spoken:GetSettingsCategory() return { ID = "Spoken" } end
function Spoken:AddSettingsLink(text, fn) table.insert(self.links, { text = text, fn = fn }) end

function Mock.FireEvent(event, ...)
    for _, frame in ipairs(Mock.frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

--- Move the clock forward in 50 ms frames, running timers and every visible OnUpdate.
function Mock.Advance(seconds)
    local steps = math.floor(seconds / 0.05 + 0.5)
    for _ = 1, steps do
        Mock.time = Mock.time + 0.05
        local due = {}
        for index = #Mock.timers, 1, -1 do
            if Mock.timers[index].at <= Mock.time + 1e-9 then
                table.insert(due, 1, table.remove(Mock.timers, index))
            end
        end
        for _, timer in ipairs(due) do timer.fn() end
        for _, frame in ipairs(Mock.frames) do
            if frame.shown and frame.scripts.OnUpdate then
                frame.scripts.OnUpdate(frame, 0.05)
            end
        end
    end
end

-- Assertions.
Tests = { passed = 0 }
function Tests.eq(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message or "eq", tostring(expected),
            tostring(actual)), 2)
    end
    Tests.passed = Tests.passed + 1
end
function Tests.ok(value, message)
    if not value then error((message or "ok") .. ": was false", 2) end
    Tests.passed = Tests.passed + 1
end

-- More of the client.
GameFontNormal = GameFontNormalLarge
GameTooltip = NewRegion("GameTooltip", "GameTooltip")
function GameTooltip:SetOwner(owner) self.owner = owner; self.lines = {} end
function GameTooltip:AddLine(text) table.insert(self.lines, text) end
-- No global MouseIsOver: the Classic client has none (Spoken keeps a private copy).
Mock.mouseOver = {}
function Methods:IsMouseOver() return Mock.mouseOver[self] == true end
UISpecialFrames = {}
function strsplit(sep, text)
    local out = {}
    for part in string.gmatch(text, "([^" .. sep .. "]+)") do table.insert(out, part) end
    return unpack(out)
end
Mock.units = {}
function UnitExists(unit) return Mock.units[unit] ~= nil end
function UnitGUID(unit) return Mock.units[unit] and Mock.units[unit].guid end
function UnitName(unit) return Mock.units[unit] and Mock.units[unit].name end
function UnitIsPlayer() return false end
function SetPortraitTexture(texture, unit) texture.portraitOf = Mock.units[unit].name end

-- The player's queue, as far as the public API shows it.
Spoken.queue = {}
Spoken.refreshed = 0
Spoken.bullets = { ["quest-accept"] = { texture = "Bullet\Accept", size = 14 } }
local function Head() return Spoken.queue[1] end
function Spoken:GetCurrent() return Head() end
function Spoken:GetNowPlaying() return Head() and Head().playing and Head() or nil end
function Spoken:GetQueue()
    local copy = {}
    for i, clip in ipairs(self.queue) do copy[i] = clip end
    return copy
end
function Spoken:GetQueueSize() return #self.queue end
function Spoken:GetWaitingCount() return math.max(0, #self.queue - 1) end
function Spoken:GetHeldReason(clip) return clip and clip.held end
function Spoken:GetBullet(id) return self.bullets[id] end
function Spoken:OpenSettings() self.openedSettings = true end
function Spoken:RefreshPlayer() self.refreshed = self.refreshed + 1 end
--- Start the head playing, as the player would.
function Spoken:StartHead()
    local head = Head()
    if not head then return end
    head.playing = true
    self:Fire("CLIP_STARTED", head)
    self:Fire("AUDIO_CHANGED")
end
function Spoken:Enqueue(clip)
    table.insert(self.queue, clip)
    self:Fire("CLIP_QUEUED", clip)
    self:Fire("AUDIO_CHANGED")
end
function Spoken:RemoveClip(clip)
    for i, queued in ipairs(self.queue) do
        if queued == clip then
            table.remove(self.queue, i)
            clip.playing = false
            self:Fire("CLIP_STOPPED", clip, false)
            if #self.queue == 0 then self:Fire("QUEUE_EMPTY") end
            self:Fire("AUDIO_CHANGED")
            if i == 1 and not self.paused then self:StartHead() end
            return true
        end
    end
end
function Spoken:TogglePause()
    if self.paused then
        self.paused = false
        self:StartHead()
    else
        self.paused = true
        if Head() then Head().playing = false end
        self:Fire("AUDIO_CHANGED")
    end
end
function Spoken:Skip() if Head() then self:RemoveClip(Head()) end end
function Spoken:StopAll()
    while Head() do self:RemoveClip(Head()) end
end
Mock.questSource = { key = "quests" }
function Mock.questSource:Remove(clip) return Spoken:RemoveClip(clip) end

-- The book reader.
Mock.book = {}
function ItemTextGetItem() return Mock.book.title end
function ItemTextGetText() return Mock.book.text end
function ItemTextGetPage() return Mock.book.page or 1 end
