-- SpokenSubtitles -- wiring: saved settings, the player's callbacks, the slash command.
--
-- Everything this addon needs from Spoken Player is in its public API (API.lua there):
-- RegisterCallback, IsPaused, GetPlayerFrame, GetSettingsCategory, AddSettingsLink and
-- IsCompatible. Nothing reaches into the player's internals, so the two can be released
-- on their own schedules.

local ADDON_NAME, ns = ...

ns.defaults = {
    style = "spoken",         -- "spoken": Spoken's own player | "head": the talking head
    mode = "screen",          -- with Spoken's player: "screen" | "player" (below it) | "off"
    headMode = "player",      -- with the talking head: "player" (inside it) | "screen" | "off"
    language = "client",      -- only "client" exists yet
    hideWithDialog = true,
    speaker = true,
    fontSize = 17,
    offsetX = 0,
    offsetY = 170,
    headScale = 1,
    headWidth = 470,
    headX = 0,
    headY = 120,
    headLocked = false,
}

ns.SAMPLE_SPEAKER = "Eagan Peltskinner"
ns.SAMPLE_CUE = "I hate those nasty timber wolves! But I sure like eating wolf steaks..."
ns.SAMPLE_TEXT = "I hate those nasty timber wolves!  But I sure like eating wolf steaks...  "
    .. "Bring me tough wolf meat and I will exchange it for something you'll find useful."
    .. "\n\nTough wolf meat is gathered from hunting the timber wolves and young wolves "
    .. "wandering the Northshire countryside."

local PREFIX = "|cffffd100Spoken Subtitles:|r "

--- Where subtitles go for the current style. Each style keeps its own choice, so trying the
--- talking head does not change what Spoken's player was set to.
function ns.Mode()
    local db = ns.db or ns.defaults
    if db.style == "head" then
        return db.headMode or "player"
    end
    return db.mode
end

function ns.SetMode(mode)
    if ns.db.style == "head" then
        ns.db.headMode = mode
    else
        ns.db.mode = mode
    end
end

function ns.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(message))
end

function ns.Now()
    return GetTime()
end

function ns.After(seconds, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds, fn)
    end
end

-- The last few decisions, for /spsub debug.
local log = {}
function ns.Log(message)
    table.insert(log, ("%.1f %s"):format(ns.Now(), message))
    if #log > 20 then
        table.remove(log, 1)
    end
end

local function FillDefaults(db)
    for key, value in pairs(ns.defaults) do
        if db[key] == nil then
            db[key] = value
        end
    end
    return db
end

--------------------------------------------------------------------------------
-- The player's callbacks
--------------------------------------------------------------------------------

local Capture, Cues, Display = ns.Capture, ns.Cues, ns.Display
local Portraits, TalkingHead = ns.Portraits, ns.TalkingHead

local function StartSubtitles(clip)
    local db = ns.db
    if not db or ns.Mode() == "off" then
        Display:Finish()
        TalkingHead:SetWords(clip, false)
        return
    end
    local text = Capture:TextFor(clip)
    if not text then
        Display:Finish()
        TalkingHead:SetWords(clip, false)
        ns.Log(("started %s: no text"):format(tostring(clip and clip.key)))
        return
    end
    local cues = Cues.Build(text, clip.length, clip.delay)
    local present = type(clip.present) == "table" and clip.present or {}
    Display:Start(clip, cues, present.header)
    ns.Log(("started %s: %d cues over %.1fs"):format(tostring(clip.key), #cues,
        tonumber(clip.length) or 0))
end

local function OnAudioChanged()
    if Display:IsActive() and not Display.demo then
        Display:SetPaused(Spoken:IsPaused())
    end
    TalkingHead:Update()
end

local function Connect()
    Spoken:RegisterCallback("CLIP_QUEUED", function(clip)
        Capture:Remember(clip)
        Portraits:Capture(clip)
        TalkingHead:Update()
    end)
    Spoken:RegisterCallback("CLIP_STARTED", function(clip)
        StartSubtitles(clip)
        TalkingHead:OnClipStarted(clip)
        TalkingHead:Update()
    end)
    Spoken:RegisterCallback("CLIP_STOPPED", function(clip)
        Display:Finish(clip)
        TalkingHead:Update()
    end)
    Spoken:RegisterCallback("QUEUE_EMPTY", function()
        if not Display.demo then Display:Finish() end
        TalkingHead:Update()
    end)
    Spoken:RegisterCallback("AUDIO_CHANGED", OnAudioChanged)
end

--------------------------------------------------------------------------------
-- Public to the options panel and the slash command
--------------------------------------------------------------------------------

function ns.ApplySettings()
    if ns.Mode() == "off" then
        Display:Finish()
    end
    Display:Layout()
    TalkingHead:Update()
end

--- Switch between Spoken's player and the talking head. Takes effect at once.
function ns.SetStyle(style)
    ns.db.style = style == "head" and "head" or "spoken"
    Display:Finish()
    if ns.db.style == "head" then
        TalkingHead:Update()
    else
        TalkingHead:ReleaseSpoken()
    end
    Display:Layout()
end

function ns.Preview()
    local clip = { key = "preview", length = 14, demo = true, present = {
        header = ns.SAMPLE_SPEAKER, label = "Wolves Across the Border", bullet = "quest-accept" } }
    if ns.db.style == "head" then
        TalkingHead:Preview(clip)
    end
    Display:Start(clip, Cues.Build(ns.SAMPLE_TEXT, clip.length, 0), ns.SAMPLE_SPEAKER)
end

function ns.SetUnlocked(unlocked)
    if unlocked and ns.Mode() ~= "screen" then
        ns.Print("Only the screen position can be moved; the other follows the player.")
        return
    end
    Display:SetUnlocked(unlocked)
    ns.Print(unlocked and "Drag the line, then /spsub lock." or "Position saved.")
end

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

local MODES = { screen = true, player = true, off = true }
local USAGE = "/spsub head | spoken, screen | player | off, test | move | lock | reset | debug"

local function Slash(input)
    local command = string.lower(string.match(input or "", "^%s*(%S*)") or "")
    if MODES[command] then
        ns.SetMode(command)
        ns.ApplySettings()
        ns.Print("subtitles: " .. command)
    elseif command == "head" or command == "spoken" then
        ns.SetStyle(command)
        ns.Print(command == "head" and "player style: talking head" or "player style: Spoken")
    elseif command == "reset" then
        ns.db.headX, ns.db.headY, ns.db.headScale = ns.defaults.headX, ns.defaults.headY, 1
        ns.db.offsetX, ns.db.offsetY = ns.defaults.offsetX, ns.defaults.offsetY
        ns.ApplySettings()
        ns.Print("positions reset")
    elseif command == "test" or command == "preview" then
        ns.Preview()
    elseif command == "move" or command == "unlock" then
        ns.SetUnlocked(true)
    elseif command == "lock" then
        ns.SetUnlocked(false)
    elseif command == "debug" then
        ns.Print(("style=%s, subtitles=%s, player API %s"):format(ns.db.style, ns.Mode(),
            ns.connected and "connected" or "missing"))
        for _, line in ipairs(log) do
            DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
        end
    elseif command == "" or command == "settings" or command == "options" then
        if not ns.OpenOptions() then
            ns.Print(USAGE)
        end
    else
        ns.Print(USAGE)
    end
end

--------------------------------------------------------------------------------
-- Load
--------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
for _, event in ipairs(Capture:Events()) do
    loader:RegisterEvent(event)
end

loader:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON_NAME then
            SpokenSubtitlesDB = FillDefaults(SpokenSubtitlesDB or {})
            ns.db = SpokenSubtitlesDB
        end
    elseif event == "PLAYER_LOGIN" then
        ns.db = ns.db or FillDefaults({})
        SLASH_SPOKENSUBTITLES1 = "/spsub"
        SLASH_SPOKENSUBTITLES2 = "/subtitles"
        SlashCmdList.SPOKENSUBTITLES = Slash

        local spoken = _G.Spoken
        if not (spoken and spoken.IsCompatible and spoken:IsCompatible(1)) then
            ns.Print("Spoken Player is missing or too old; subtitles are off.")
            return
        end
        Connect()
        ns.Portraits:Watch()
        ns.connected = true
        ns.SetupOptions()
        TalkingHead:Update()
    else
        Capture:OnEvent(event)
    end
end)
