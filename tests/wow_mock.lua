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

function Methods:Show() self.shown = true end
function Methods:Hide() self.shown = false end
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
