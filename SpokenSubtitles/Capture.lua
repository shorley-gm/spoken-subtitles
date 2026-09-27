-- SpokenSubtitles -- finding the text a clip speaks, in the client's own language.
--
-- The player's clip carries no text, and this addon does not ask Spoken Quests for any.
-- The words are on the NPC's dialog, so they are read from the same client globals Spoken
-- Quests reads, at two moments:
--
--   * the dialog events, and a few short beats after them. On Classic Era the events can
--     fire before the quest globals change, so an early read may still be the previous
--     quest; the later reads overwrite it. An auto-accept addon can close the dialog in the
--     event's own frame, and the immediate read is the only one that sees it.
--
--   * CLIP_QUEUED. Spoken Quests enqueues only once it has resolved the quest, so while the
--     dialog is still open the globals are settled here, and this read wins.
--
-- Quest clips are matched exactly: the clip key is "<questID>-<accept|progress|complete>".
-- That key shape is Spoken Quests' convention, not the player's contract, so anything that
-- does not match it is only ever given a gossip or greeting read that happened moments ago.

local _, ns = ...
ns = ns or {}

local Capture = {
    quests = {},            -- ["33-accept"] = text
    recent = nil,           -- { text, time } the last gossip or greeting page
    textByClip = setmetatable({}, { __mode = "k" }),
    sourceByClip = setmetatable({}, { __mode = "k" }),
}
ns.Capture = Capture

-- How long a gossip or greeting read may wait for its clip.
Capture.RECENT_SECONDS = 5
-- Re-reads after a dialog event, in seconds.
Capture.RETRIES = { 0.15, 0.4, 1.0 }

local function Call(fn)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn)
    if ok and type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

local function GossipText()
    return Call(_G.GetGossipText or (_G.C_GossipInfo and _G.C_GossipInfo.GetText))
end

local READERS = {
    accept = function() return Call(_G.GetQuestText) end,
    progress = function() return Call(_G.GetProgressText) end,
    complete = function() return Call(_G.GetRewardText) end,
    greeting = function() return Call(_G.GetGreetingText) end,
    gossip = GossipText,
}

local EVENT_KINDS = {
    QUEST_DETAIL = "accept",
    QUEST_PROGRESS = "progress",
    QUEST_COMPLETE = "complete",
    QUEST_GREETING = "greeting",
    GOSSIP_SHOW = "gossip",
}

local function Shown(name)
    local frame = _G[name]
    return frame and frame.IsVisible and frame:IsVisible() and true or false
end

local function QuestID()
    local id = Call(function()
        local value = _G.GetQuestID and _G.GetQuestID()
        return value and tostring(value) or nil
    end)
    return id and id ~= "0" and id or nil
end

--- Record what the dialog shows for `kind` right now.
function Capture:Read(kind)
    local text = READERS[kind] and READERS[kind]()
    if not text then
        return nil
    end
    if kind == "gossip" or kind == "greeting" then
        self.recent = { text = text, time = ns.Now(), kind = kind }
        return text
    end
    local id = QuestID()
    if id then
        self.quests[id .. "-" .. kind] = text
    end
    return text
end

function Capture:OnEvent(event)
    local kind = EVENT_KINDS[event]
    if not kind then
        return
    end
    self:Read(kind)
    if ns.After then
        for _, seconds in ipairs(self.RETRIES) do
            ns.After(seconds, function() Capture:Read(kind) end)
        end
    end
end

function Capture:Events()
    local list = {}
    for event in pairs(EVENT_KINDS) do
        table.insert(list, event)
    end
    table.sort(list)
    return list
end

local function SourceKey(clip)
    local source = clip.source
    return type(source) == "table" and source.key or nil
end

--- The quest key's parts, or nil for anything that is not a quest line.
local function QuestKey(key)
    if type(key) ~= "string" then
        return nil
    end
    local id, kind = string.match(key, "^(%d+)%-(%l+)$")
    if id and READERS[kind] and kind ~= "gossip" and kind ~= "greeting" then
        return id, kind
    end
    return nil
end

--- Called on CLIP_QUEUED: attach the clip's text while the dialog is most likely open.
function Capture:Remember(clip)
    if type(clip) ~= "table" or SourceKey(clip) ~= "quests" then
        return
    end
    local text, how
    local id, kind = QuestKey(clip.key)
    if id then
        if QuestID() == id then
            text = READERS[kind]()
            if text then
                self.quests[clip.key] = text
                how = "live"
            end
        end
        if not text and self.quests[clip.key] then
            text, how = self.quests[clip.key], "event"
        end
    else
        if Shown("GossipFrame") then
            text, how = GossipText(), "live gossip"
        elseif Shown("QuestFrameGreetingPanel") then
            text, how = READERS.greeting(), "live greeting"
        end
        local recent = self.recent
        if not text and recent and ns.Now() - recent.time <= self.RECENT_SECONDS then
            text, how = recent.text, "recent " .. recent.kind
        end
    end
    if text then
        self.textByClip[clip] = text
        self.sourceByClip[clip] = how
    end
    ns.Log(("queued %s: %s"):format(tostring(clip.key), how or "no text"))
end

--- The text for a clip, or nil when none was found.
function Capture:TextFor(clip)
    if type(clip) ~= "table" then
        return nil
    end
    -- A quest's latest read wins over the one taken at queue time: a retry after the event
    -- can only have replaced a stale read with the settled one.
    if SourceKey(clip) == "quests" and QuestKey(clip.key) and self.quests[clip.key] then
        return self.quests[clip.key]
    end
    return self.textByClip[clip]
end

return Capture
