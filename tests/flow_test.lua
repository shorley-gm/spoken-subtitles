local eq, ok = Tests.eq, Tests.ok
local Display = ns.Display

local quests = { key = "quests" }
local function Clip(key, length, header)
    return { key = key, length = length, source = quests, present = { header = header } }
end

local function Frame() return _G.SpokenSubtitlesFrame end
local function Shown() return Frame() and Frame().shown and Frame().alpha > 0.99 end

-- Load and log in.
Mock.FireEvent("ADDON_LOADED", "SpokenSubtitles")
Mock.FireEvent("PLAYER_LOGIN")
eq(ns.db.mode, "screen", "default mode")
ok(ns.connected, "connected to the player")
eq(Mock.subcategory and Mock.subcategory.name, "Subtitles", "nested under Spoken")
eq(Spoken.links[1] and Spoken.links[1].text, "Subtitles settings", "settings link added")
ok(SlashCmdList.SPOKENSUBTITLES, "slash command")

-- Accept a quest: the dialog is open while the clip is queued, so the text is read live.
local wolves = "I hate those nasty timber wolves!  But I sure like eating wolf steaks...  "
    .. "Bring me tough wolf meat and I will exchange it for something you'll find useful."
Mock.quest = { id = 33, accept = wolves }
QuestFrame = Mock.NewRegion("Frame", "QuestFrame")
Mock.FireEvent("QUEST_DETAIL")
local clip = Clip("33-accept", 10, "Eagan Peltskinner")
Spoken:Fire("CLIP_QUEUED", clip)
eq(ns.Capture:TextFor(clip), wolves, "quest text captured")

-- Starts while the quest window is open: kept hidden.
Spoken:Fire("CLIP_STARTED", clip)
Mock.Advance(0.5)
ok(Display:IsActive(), "active")
eq(Frame().alpha, 0, "hidden while the quest window is open")

-- Close the window: fades in on the current cue, speaker in gold.
QuestFrame:Hide()
Mock.Advance(0.5)
ok(Shown(), "visible once the window closes")
ok(string.find(Display.text.text, "^|cffffd100Eagan Peltskinner:|r I hate"), "first cue with speaker")

-- Moves on to the second cue by its estimated time.
Mock.Advance(4.5)
ok(string.find(Display.text.text, "Bring me tough wolf meat", 1, true), "second cue")

-- Pause fades out and freezes; resume replays from the start.
Spoken.paused = true
Spoken:Fire("AUDIO_CHANGED")
Mock.Advance(0.5)
eq(Frame().alpha, 0, "hidden while paused")
Spoken.paused = false
Spoken:Fire("CLIP_STARTED", clip)
Mock.Advance(0.3)
ok(string.find(Display.text.text, "I hate", 1, true), "resume restarts at the first cue")
ok(Shown(), "visible again")

-- Finishes: holds briefly after the words, then fades and hides.
Mock.Advance(11.5)
ok(not Display:IsActive(), "cleared after the end")
eq(Frame().shown, false, "frame hidden after the end")

-- Skip: CLIP_STOPPED fades immediately.
Spoken:Fire("CLIP_QUEUED", clip)
Spoken:Fire("CLIP_STARTED", clip)
Mock.Advance(1)
Spoken:Fire("CLIP_STOPPED", clip, false)
Mock.Advance(0.5)
ok(not Display:IsActive(), "stopped clip cleared")

-- A stale early read is replaced by the settled retry.
Mock.quest = { id = 34, complete = "Stale text of the previous quest, still on the globals." }
Mock.FireEvent("QUEST_COMPLETE")
Mock.quest = { id = 34, complete = "Thank you, the farms are safe now. Take this as a reward." }
Mock.Advance(0.2)
local complete = Clip("34-complete", 4, "Eagan Peltskinner")
Mock.quest = {}   -- auto turn-in: the dialog is gone before the clip is queued
Spoken:Fire("CLIP_QUEUED", complete)
eq(ns.Capture:TextFor(complete), "Thank you, the farms are safe now. Take this as a reward.",
    "settled retry wins over the stale read")

-- Gossip: hash key, read from the open gossip window.
GossipFrame = Mock.NewRegion("Frame", "GossipFrame")
Mock.quest = { gossip = "Greetings, traveler. The light be with you." }
Mock.FireEvent("GOSSIP_SHOW")
local gossip = Clip("258744fe85450f544093d5fd17856341", 3, "Brother Paxton")
Spoken:Fire("CLIP_QUEUED", gossip)
eq(ns.Capture:TextFor(gossip), "Greetings, traveler. The light be with you.", "gossip text")
GossipFrame:Hide()

-- A gossip clip queued long after any gossip page gets nothing rather than a wrong line.
Mock.Advance(6)
local late = Clip("7df84a254c23565acaa7fc468ead3ab2", 3, "Someone")
Mock.quest = {}
Spoken:Fire("CLIP_QUEUED", late)
eq(ns.Capture:TextFor(late), nil, "old gossip not reused")
Spoken:Fire("CLIP_STARTED", late)
Mock.Advance(0.3)
ok(not Display:IsActive(), "no text, no subtitles")

-- Other sources are left alone.
local zone = { key = "z:elwynn", length = 5, source = { key = "zones" }, present = {} }
Spoken:Fire("CLIP_QUEUED", zone)
eq(ns.Capture:TextFor(zone), nil, "zones have no client text")

-- Off means off.
SlashCmdList.SPOKENSUBTITLES("off")
eq(ns.db.mode, "off", "slash off")
Mock.quest = { id = 33, accept = wolves }
Spoken:Fire("CLIP_QUEUED", clip)
Spoken:Fire("CLIP_STARTED", clip)
Mock.Advance(0.3)
ok(not Display:IsActive(), "off shows nothing")

-- Below the player; flips above when the player sits at the bottom edge.
SlashCmdList.SPOKENSUBTITLES("player")
Spoken.playerFrame.bottom = 400
Spoken:Fire("CLIP_STARTED", clip)
local point = Frame().points[1]
eq(point[1], "TOP", "below the player")
eq(point[2], Spoken.playerFrame, "anchored to the player")
Spoken.playerFrame.bottom = 10
Display:Layout()
eq(Frame().points[1][1], "BOTTOM", "above the player at the screen edge")
Spoken.playerFrame:Hide()
Display:Layout()
eq(Frame().points[1][2], UIParent, "screen position when the player is hidden")

-- Preview ignores the dialog rule and the queue.
SlashCmdList.SPOKENSUBTITLES("screen")
QuestFrame:Show()
SlashCmdList.SPOKENSUBTITLES("test")
Mock.Advance(0.5)
ok(Shown(), "preview visible with a dialog open")
Spoken:Fire("QUEUE_EMPTY")
Mock.Advance(0.3)
ok(Display:IsActive(), "preview survives an empty queue")

-- Font size follows the setting, face from the client.
ns.db.fontSize = 22
Display:Layout()
eq(Display.text.font[2], 22, "font size")
eq(Display.text.font[1], "Fonts\\FRIZQT__.TTF", "client font face")
