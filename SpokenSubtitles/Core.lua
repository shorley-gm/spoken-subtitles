-- SpokenSubtitles -- wiring: saved settings, the player's callbacks, the slash command.
--
-- Everything this addon needs from Spoken Player is in its public API (API.lua there):
-- RegisterCallback, the queue calls, IsPaused, GetPlayerFrame, GetSettingsCategory,
-- AddSettingsLink and IsCompatible. Nothing reaches into the player's internals, so the two
-- can be released on their own schedules.

local ADDON_NAME, ns = ...

-- Bumped when a default changes in a way existing players should get once.
local SCHEMA = 2

ns.defaults = {
    schema = SCHEMA,
    style = "spoken",         -- "spoken": Spoken's own player | "band": the cinematic band
    mode = "screen",          -- with Spoken's player: "screen" | "player" (below it) | "off"
    bandMode = "player",      -- with the band: "player" (the band's words) | "off"
    language = "client",      -- only "client" exists yet
    hideWithDialog = false,   -- the words start with the voice, window open or not
    speaker = true,
    fontSize = 18,
    offsetX = 0,
    offsetY = 170,
    bandScale = 1,
    bandWidth = 760,
    bandX = 0,
    bandY = 150,
    bandLocked = false,
    bandFace = true,          -- a small face when the speaker is not your target
}

ns.SAMPLE_SPEAKER = "Eagan Peltskinner"
ns.SAMPLE_CUE = "I hate those nasty timber wolves! But I sure like eating wolf steaks..."
ns.SAMPLE_TEXT = "I hate those nasty timber wolves!  But I sure like eating wolf steaks...  "
    .. "Bring me tough wolf meat and I will exchange it for something you'll find useful."
    .. "\n\nTough wolf meat is gathered from hunting the timber wolves and young wolves "
    .. "wandering the Northshire countryside."

local PREFIX = "|cffffd100Spoken Subtitles:|r "

--- Where subtitles go for the current style. Each style keeps its own choice, so trying the
--- band does not change what Spoken's player was set to.
function ns.Mode()
    local db = ns.db or ns.defaults
    if db.style == "band" then
        return db.bandMode == "off" and "off" or "player"
    end
    return db.mode
end

function ns.SetMode(mode)
    if ns.db.style == "band" then
        ns.db.bandMode = mode == "off" and "off" or "player"
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

--- Settings from earlier versions. 0.2.0's talking head is now the band, and the words no
--- longer wait for the quest window to close -- that looked like they started mid-speech.
local function Migrate(db)
    if db.style == "head" then db.style = "band" end
    if db.headMode == "off" then db.bandMode = "off" end
    if db.headScale then db.bandScale = db.headScale end
    db.headMode, db.headScale, db.headWidth, db.headX, db.headY, db.headLocked =
        nil, nil, nil, nil, nil, nil
    if (db.schema or 1) < 2 then
        db.hideWithDialog = false
    end
    db.schema = SCHEMA
    return db
end

--------------------------------------------------------------------------------
-- The player's callbacks
--------------------------------------------------------------------------------

local Capture, Cues, Display = ns.Capture, ns.Cues, ns.Display
local Portraits, Band = ns.Portraits, ns.Band

local function StartSubtitles(clip)
    local db = ns.db
    if not db or ns.Mode() == "off" then
        Display:Finish()
        Display:SetWords(clip, false)
        return
    end
    local text = Capture:TextFor(clip)
    if not text then
        Display:Finish()
        Display:SetWords(clip, false)
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
    Band:Update()
end

local function Connect()
    Spoken:RegisterCallback("CLIP_QUEUED", function(clip)
        Capture:Remember(clip)
        Portraits:Capture(clip)
        Band:Update()
    end)
    Spoken:RegisterCallback("CLIP_STARTED", function(clip)
        StartSubtitles(clip)
        Band:OnClipStarted(clip)
        Band:Update()
    end)
    Spoken:RegisterCallback("CLIP_STOPPED", function(clip)
        Display:Finish(clip)
        Band:Update()
    end)
    Spoken:RegisterCallback("QUEUE_EMPTY", function()
        if not Display.demo then Display:Finish() end
        Band:Update()
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
    Band:ApplySettings()
    Band:Update()
end

--- Switch between Spoken's player and the band. Takes effect at once.
function ns.SetStyle(style)
    ns.db.style = style == "band" and "band" or "spoken"
    Display:Finish()
    if ns.db.style == "band" then
        Band:Update()
    else
        Band:ReleaseSpoken()
    end
    Display:Layout()
end

function ns.Preview()
    local clip = { key = "preview", length = 14, demo = true, present = {
        header = ns.SAMPLE_SPEAKER, label = "Wolves Across the Border", bullet = "quest-accept" } }
    if ns.db.style == "band" then
        Band:Preview(clip)
    end
    Display:Start(clip, Cues.Build(ns.SAMPLE_TEXT, clip.length, 0), ns.SAMPLE_SPEAKER)
end

function ns.SetUnlocked(unlocked)
    if unlocked and ns.Mode() ~= "screen" then
        ns.Print(ns.db.style == "band" and "Drag the band itself to move it."
            or "Only the screen position can be moved; the other follows the player.")
        return
    end
    Display:SetUnlocked(unlocked)
    ns.Print(unlocked and "Drag the line, then /spsub lock." or "Position saved.")
end

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

local MODES = { screen = true, player = true, off = true }
local USAGE = "/spsub band | spoken, screen | player | off, test | move | lock | reset | debug"

local function Slash(input)
    local command = string.lower(string.match(input or "", "^%s*(%S*)") or "")
    if command == "head" or command == "cinematic" then command = "band" end
    if MODES[command] then
        ns.SetMode(command)
        ns.ApplySettings()
        ns.Print("subtitles: " .. ns.Mode())
    elseif command == "band" or command == "spoken" then
        ns.SetStyle(command)
        ns.Print(command == "band" and "player style: cinematic band" or "player style: Spoken")
    elseif command == "reset" then
        ns.db.bandX, ns.db.bandY, ns.db.bandScale = ns.defaults.bandX, ns.defaults.bandY, 1
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
loader:RegisterEvent("PLAYER_TARGET_CHANGED")
for _, event in ipairs(Capture:Events()) do
    loader:RegisterEvent(event)
end

loader:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON_NAME then
            SpokenSubtitlesDB = FillDefaults(Migrate(SpokenSubtitlesDB or {}))
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
        Band:Update()
    elseif event == "PLAYER_TARGET_CHANGED" then
        if ns.connected then Band:OnTargetChanged() end
    else
        Capture:OnEvent(event)
    end
end)
