-- SpokenSubtitles -- the settings panel.
--
-- Nested under Spoken Player's own category when the player offers one, so it sits beside
-- the other Spoken panels; a category of its own otherwise. Built with the SpokenLayout
-- copy in Libs, the same helper the Spoken addons use, so the panels read alike.

local _, ns = ...

local category

local MODES = { "screen", "player", "off" }
local MODE_LABELS = {
    screen = "Screen (cinematic)",
    player = "Below the player",
    off = "Off",
}

function ns.SetupOptions()
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory) or not SpokenLayout then
        return
    end

    local panel = CreateFrame("Frame")
    panel.name = "Subtitles"

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

    layout:Section("Display")
    layout:Dropdown("Position", "Where the subtitle line appears.",
        MODES, Get("mode"), Set("mode"), ns.ApplySettings,
        function(mode) return MODE_LABELS[mode] or tostring(mode) end)
    layout:Checkbox("Hide while the quest window is open",
        "The words are already on screen there. Subtitles return when you close it.",
        Get("hideWithDialog"), Set("hideWithDialog"))
    layout:Checkbox("Show the speaker's name", nil, Get("speaker"), Set("speaker"))
    layout:Slider("Text size", 12, 26, 1, Get("fontSize"), Set("fontSize"),
        ns.ApplySettings, SpokenLayout.Number)

    layout:Section("Language")
    layout:Note("Client language. Subtitles in the recording's language are planned.")

    layout:Section("Try it")
    layout:Button("Preview", 140, ns.Preview, "Plays a sample line of subtitles.")
    layout:Button("Move", 140, function()
        ns.SetUnlocked(not ns.Display.unlocked)
    end, "Drag the line to where you want it. Click again to lock it.")

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
