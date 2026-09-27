-- SpokenSubtitles -- the settings panel.
--
-- Nested under Spoken Player's own category when the player offers one, so a player finds
-- one settings tree, not two addons. Built with the SpokenLayout copy in Libs, the same
-- helper the Spoken addons use, so the panels read alike.

local _, ns = ...

local category

local STYLES = { "spoken", "head" }
local STYLE_LABELS = {
    spoken = "Spoken's player",
    head = "Talking head",
}
local MODES = { "player", "screen", "off" }

local function DescribeMode(mode)
    if mode == "player" then
        return ns.db.style == "head" and "In the talking head" or "Below Spoken's player"
    elseif mode == "screen" then
        return "Bottom of the screen"
    end
    return "Off"
end

function ns.SetupOptions()
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory) or not SpokenLayout then
        return
    end

    local panel = CreateFrame("Frame")
    panel.name = "Subtitles"
    local modeControl

    local scroller = SpokenLayout.Scroll(panel)
    local content = scroller.child

    local heading = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 20, -16)
    heading:SetJustifyH("LEFT")
    heading:SetText("Spoken Subtitles")

    local layout = SpokenLayout.New(content, 20, -42)
    layout:Note("Shows what the NPC is saying while you listen. The text is the quest text "
        .. "your game shows, timed from the length of the recording.")

    local function Get(key)
        return function() return ns.db[key] end
    end
    local function Set(key)
        return function(value) ns.db[key] = value end
    end

    layout:Section("Player")
    layout:Dropdown("Player style",
        "Talking head replaces Spoken's window with a portrait, the name and the words. "
            .. "Pause, skip, the queue and Report are on the portrait and its right-click "
            .. "menu. Spoken's window comes back as soon as you switch back or turn this "
            .. "addon off.",
        STYLES, Get("style"), function(value)
            ns.SetStyle(value)
            if modeControl and modeControl:GetScript("OnShow") then
                modeControl:GetScript("OnShow")(modeControl)
            end
        end, nil,
        function(style) return STYLE_LABELS[style] or tostring(style) end)
    layout:Indent()
    layout:Slider("Talking head size", 0.6, 1.6, 0.05, Get("headScale"), Set("headScale"),
        ns.ApplySettings, SpokenLayout.Percent)
    layout:Checkbox("Lock the talking head", "Stops it from being dragged by accident.",
        Get("headLocked"), Set("headLocked"))
    layout:Outdent()

    layout:Section("Subtitles")
    modeControl = layout:Dropdown("Show subtitles",
        "Where the words appear. Each player style remembers its own choice.",
        MODES, ns.Mode, ns.SetMode, ns.ApplySettings, DescribeMode)
    layout:Checkbox("Hide while the quest window is open",
        "The words are already on screen there. Subtitles return when you close it.",
        Get("hideWithDialog"), Set("hideWithDialog"))
    layout:Checkbox("Name the speaker at the bottom of the screen",
        "Only with Spoken's player; the talking head already shows the name.",
        Get("speaker"), Set("speaker"))
    layout:Slider("Text size", 12, 26, 1, Get("fontSize"), Set("fontSize"),
        ns.ApplySettings, SpokenLayout.Number)
    layout:Note("Language: the client's. Subtitles in the recording's language are planned.")

    layout:Section("Try it")
    layout:Button("Preview", 140, ns.Preview, "Plays a sample line in the current style.")
    layout:Button("Move the screen subtitles", 200, function()
        ns.SetUnlocked(not ns.Display.unlocked)
    end, "Drag the line to where you want it. Click again to lock it.")
    layout:Button("Reset positions", 140, function() SlashCmdList.SPOKENSUBTITLES("reset") end)

    scroller:SetContentHeight(layout:Height() + 40)

    local parent = Spoken.GetSettingsCategory and Spoken:GetSettingsCategory()
    if parent and Settings.RegisterCanvasLayoutSubcategory then
        category = Settings.RegisterCanvasLayoutSubcategory(parent, panel, "Subtitles")
    else
        panel.name = "Spoken Subtitles"
        category = Settings.RegisterCanvasLayoutCategory(panel, "Spoken Subtitles")
        Settings.RegisterAddOnCategory(category)
    end

    if Spoken.AddSettingsLink then
        Spoken:AddSettingsLink("Subtitles settings", function() ns.OpenOptions() end)
    end
end

--- Open the panel. False when the client has none.
function ns.OpenOptions()
    if not category or not (Settings and Settings.OpenToCategory) then
        return false
    end
    local id = category.GetID and category:GetID() or category.ID
    Settings.OpenToCategory(id)
    return true
end
