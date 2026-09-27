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
--
-- Books: every page the reader has open is remembered by title and page number, the pair
-- Spoken Books shows as the clip's header and label. A book is queued from the open page to
-- its last, so a page gets words once the reader has turned to it -- before or while it is
-- read out. Zones: Spoken Zones keeps its lore private, so the text comes from this addon's
-- own copy (ZoneText.lua), checked against the recording's length.

local _, ns = ...
ns = ns or {}

local Capture = {
    quests = {},            -- ["33-accept"] = text
    books = {},             -- [title .. "\001" .. page] = text
    recent = nil,           -- { text, time } the last gossip or greeting page
    textByClip = setmetatable({}, { __mode = "k" }),
    sourceByClip = setmetatable({}, { __mode = "k" }),
}
ns.Capture = Capture

-- How long a gossip or greeting read may wait for its clip.
Capture.RECENT_SECONDS = 5
-- Re-reads after a dialog event, in seconds.
Capture.RETRIES = { 0.15, 0.4, 1.0 }
-- A zone text whose speech rate falls outside this range is not the one recorded -- the
-- lore was rewritten since this addon's copy -- and is not shown. Recordings run at ~13.5.
Capture.ZONE_RATE_MIN = 8
Capture.ZONE_RATE_MAX = 22

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

--- Book pages can be HTML (letters, notices). Reduce them to plain text, so tags are not
--- mistaken for stage directions.
local function CleanBook(text)
    if not text then return nil end
    if string.find(text, "^%s*<[Hh][Tt][Mm][Ll]>") then
        text = string.gsub(text, "<[Bb][Rr]%s*/?>", "\n")
        text = string.gsub(text, "</[PpHh]%d?>", "\n")
        text = string.gsub(text, "<[^>]*>", "")
        text = string.gsub(text, "&lt;", "<")
        text = string.gsub(text, "&gt;", ">")
        text = string.gsub(text, "&quot;", '"')
        text = string.gsub(text, "&amp;", "&")
    end
    return text ~= "" and text or nil
end

local function BookKey(title, page)
    return tostring(title) .. "\001" .. tostring(page or 1)
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
    ITEM_TEXT_READY = "book",
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
    if kind == "book" then
        local title = Call(_G.ItemTextGetItem)
        local text = CleanBook(Call(_G.ItemTextGetText))
        if title and text then
            local page = _G.ItemTextGetPage and _G.ItemTextGetPage() or 1
            self.books[BookKey(title, page)] = text
        end
        return text
    end
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

--- The title and page a Spoken Books clip reads: its header, and the first number of its
--- label ("Page 2 of 5" in any language); a one-page book has no label.
local function BookPage(clip)
    local present = type(clip.present) == "table" and clip.present or {}
    local label = type(present.label) == "string" and present.label or ""
    return present.header, tonumber(string.match(label, "%d+")) or 1
end

--- The zone text for a clip, or nil when there is none or it does not fit the recording.
function Capture:ZoneTextFor(clip)
    if not ns.ZoneText then return nil end
    local language = type(clip.pack) == "table" and clip.pack.language or nil
    local text = ns.ZoneText:Get(clip.key, language)
    local length = tonumber(clip.length)
    if not text or not length or length <= 0 then
        return nil
    end
    local rate = ns.Cues.Length(text) / length
    if rate < self.ZONE_RATE_MIN or rate > self.ZONE_RATE_MAX then
        ns.Log(("zone %s: text does not fit the recording (%.1f chars/s)"):format(
            tostring(clip.key), rate))
        return nil
    end
    return text
end

--- Called on CLIP_QUEUED: attach the clip's text while the dialog is most likely open.
function Capture:Remember(clip)
    if type(clip) ~= "table" then
        return
    end
    local source = SourceKey(clip)
    if source == "books" then
        if Shown("ItemTextFrame") then self:Read("book") end
        local title, page = BookPage(clip)
        ns.Log(("queued %s: %s"):format(tostring(clip.key),
            self.books[BookKey(title, page)] and "page seen" or "page not seen yet"))
        return
    elseif source == "zones" then
        ns.Log(("queued %s: %s"):format(tostring(clip.key),
            self:ZoneTextFor(clip) and "zone text" or "no zone text"))
        return
    elseif source ~= "quests" then
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
    local source = SourceKey(clip)
    if source == "books" then
        -- Read at start, not queue: the reader may have turned to the page since.
        return self.books[BookKey(BookPage(clip))]
    elseif source == "zones" then
        return self:ZoneTextFor(clip)
    end
    -- A quest's latest read wins over the one taken at queue time: a retry after the event
    -- can only have replaced a stale read with the settled one.
    if SourceKey(clip) == "quests" and QuestKey(clip.key) and self.quests[clip.key] then
        return self.quests[clip.key]
    end
    return self.textByClip[clip]
end

return Capture
