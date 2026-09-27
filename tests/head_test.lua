local eq, ok = Tests.eq, Tests.ok
local Head, Display = ns.TalkingHead, ns.Display

local wolves = "Thanks to you we know the Fargodeep Mine is infested with kobolds.  "
    .. "Now we need a scout to investigate the more distant Jasperlode Mine."
local function Clip(key, header, label, extra)
    local clip = { key = key, length = 8, source = Mock.questSource, present = {
        header = header, label = label, bullet = "quest-accept",
        portrait = { kind = "model", creatureID = 240,
            fallback = { kind = "texture", texture = "Book" } } } }
    for k, v in pairs(extra or {}) do clip[k] = v end
    return clip
end

-- Log in with Spoken's window already on screen.
local spokenFrame = Spoken.playerFrame
spokenFrame:Show()
Mock.FireEvent("ADDON_LOADED", "SpokenSubtitles")
Mock.FireEvent("PLAYER_LOGIN")
eq(ns.db.style, "spoken", "Spoken's player by default")
ok(spokenFrame.shown, "Spoken's window left alone by default")

-- Choose the talking head: Spoken's window goes, for this session only.
SlashCmdList.SPOKENSUBTITLES("head")
eq(ns.db.style, "head", "style saved")
eq(spokenFrame.shown, false, "Spoken's window hidden")
eq(ns.Mode(), "player", "head subtitles default to inside the head")
eq(ns.db.mode, "screen", "Spoken style keeps its own subtitle choice")

-- Spoken tries to show its window again: it is put straight back.
spokenFrame:Show()
eq(spokenFrame.shown, false, "Spoken's window cannot come back while the head is chosen")

-- A quest line with the NPC in the dialog: portrait captured, text read, head shown.
Mock.units.npc = { guid = "Creature-0-0-0-0-240-0000", name = "Marshal Dughan" }
Mock.quest = { id = 76, accept = wolves }
QuestFrame = Mock.NewRegion("Frame", "QuestFrame")
QuestFrame:Hide()
local first = Clip("76-accept", "Marshal Dughan", "The Jasperlode Mine")
Spoken:Enqueue(first)
Spoken:StartHead()
Mock.Advance(0.5)
local frame = _G.SpokenSubtitlesTalkingHead
ok(frame and frame.shown, "head shown")
ok(frame.alpha > 0.99, "head faded in")
eq(Head.name.text, "Marshal Dughan", "speaker name")
eq(Head.label.text, "The Jasperlode Mine", "quest title")
ok(Head.snapshot and Head.snapshot.portraitOf == "Marshal Dughan", "native portrait snapshot")
eq(Head.art.shown, false, "no fallback art with a snapshot")
eq(Head.badge.texture, Spoken.bullets["quest-accept"].texture, "badge from Spoken's bullet")
ok(string.find(Head.line.text, "^Thanks to you"), "words inside the head")
ok(Head.line.alpha > 0.99, "words faded in")
ok(Head.hasWords, "layout with words")
ok(not string.find(Head.line.text, "Marshal Dughan:", 1, true), "no name prefix in the head")
local screen = _G.SpokenSubtitlesFrame
ok(not screen or not screen.shown, "screen line unused")

-- Progress follows the clip (the second cue starts at 4.14 s of 8).
Mock.Advance(4.0)
ok(Head.fill.width > 0.4 * Head.track.width and Head.fill.width < 0.6 * Head.track.width,
    "progress about half way")
ok(string.find(Head.line.text, "Jasperlode", 1, true), "second cue")

-- Portrait click pauses: wash and bars, words fade, progress frozen.
Head.portrait:Click("LeftButton")
ok(Spoken.paused, "paused through the API")
Mock.Advance(0.5)
ok(Head.wash.shown, "pause wash")
ok(Head.pauseBars[1].shown, "pause bars")
eq(Head.line.alpha, 0, "words hidden while paused")
local frozen = Head.fill.width
Mock.Advance(1)
eq(Head.fill.width, frozen, "progress frozen while paused")

-- Click again: resumes, which Spoken does by replaying from the start.
Head.portrait:Click("LeftButton")
ok(not Spoken.paused, "resumed")
Mock.Advance(0.3)
ok(string.find(Head.line.text, "^Thanks to you"), "words restart at the first cue")
ok(Head.fill.width < frozen, "progress restarted")
eq(Head.wash.shown, false, "wash gone")

-- Two more lines queue: +2 appears, the list opens and a click removes one.
local second = Clip("77-accept", "Marshal Dughan", "Report to Goldshire")
local third = Clip("g:abc", "Guard Thomas", "Gossip", { held = "in combat" })
Spoken:Enqueue(second)
Spoken:Enqueue(third)
ok(Head.fold.shown, "queue count shown")
eq(Head.fold.text.text, "+2", "two waiting")
Head.fold:Click()
ok(Head.drawer.shown, "queue open")
ok(string.find(Head.rows[1].text.text, "Report to Goldshire", 1, true), "first waiting row")
ok(string.find(Head.rows[2].text.text, "(in combat)", 1, true), "held reason shown")
Head.rows[2]:Click()
eq(#Spoken.queue, 2, "row click removed the line")
eq(Head.fold.text.text, "+1", "one waiting")

-- Menu: pause, skip, stop, queue, the clip's Report action, settings.
local reported
first.present.actions = { { id = "report", label = "Report a problem",
    icon = "Bug", onClick = function(clip) reported = clip end },
    { id = "stopgossip", anchor = "header", create = function() end } }
Head:ToggleMenu()
ok(Head.menu.shown, "menu open")
local texts = {}
for index, row in ipairs(Head.menuRows) do
    if row.shown then texts[#texts + 1] = row.text.text end
end
eq(texts[1], "Pause", "pause row")
eq(texts[2], "Skip this line", "skip row")
eq(texts[3], "Stop everything", "stop row")
eq(texts[4], "Waiting lines (1)", "queue row")
eq(texts[5], "Report a problem", "clip action listed")
eq(texts[6], "Subtitle settings", "own settings")
eq(texts[7], "Spoken settings", "Spoken's settings")
eq(texts[8], nil, "header action not listed")
Head.menuRows[5]:Click()
eq(reported, first, "action called with the clip")
eq(Head.menu.shown, false, "menu closes on click")

-- Clicking the name skips the line; the next one takes over with its own face.
Mock.units = {}
Head.title:Click("LeftButton")
Mock.Advance(0.3)
eq(Spoken:GetCurrent(), second, "skipped to the next line")
eq(Head.label.text, "Report to Goldshire", "next title")
ok(Head.snapshot and Head.snapshot.portraitOf == "Marshal Dughan",
    "same NPC reuses the cached face")

-- A line with no dialog text: compact layout, no words.
eq(Head.hasWords, false, "no text read for a line queued with the dialog closed")
eq(Head.line.text, "", "no stale words")

-- A speaker never seen: the clip's fallback art, masked round.
Head.menu:Hide()
Spoken:StopAll()
local stranger = Clip("88-accept", "Someone Else", "Elsewhere")
stranger.present.portrait.creatureID = 999
Spoken:Enqueue(stranger)
Spoken:StartHead()
Mock.Advance(0.3)
ok(not Head.snapshot, "no snapshot for an unseen speaker")
ok(Head.art.shown, "fallback art shown")
eq(Head.art.texture, "Book", "the clip's fallback texture")

-- Held at the head (not started): shows why.
Spoken:StopAll()
local waiting = Clip("89-accept", "Held NPC", "Held quest", { held = "in combat" })
Spoken:Enqueue(waiting)
Mock.Advance(0.3)
ok(string.find(Head.label.text, "(in combat)", 1, true), "held reason beside the title")
eq(Head.fill.width < 1, true, "no progress while held")

-- Queue empties: the head fades away.
Spoken:StopAll()
Mock.Advance(0.5)
eq(frame.shown, false, "head hidden when nothing is queued")

-- Subtitles at the bottom of the screen while the head is the player.
SlashCmdList.SPOKENSUBTITLES("screen")
eq(ns.db.headMode, "screen", "head style subtitle choice")
eq(ns.db.mode, "screen", "Spoken style choice untouched")
Mock.quest = { id = 76, accept = wolves }
Mock.units.npc = { guid = "Creature-0-0-0-0-240-0000", name = "Marshal Dughan" }
local again = Clip("76-accept", "Marshal Dughan", "The Jasperlode Mine")
Spoken:Enqueue(again)
Spoken:StartHead()
Mock.Advance(0.5)
screen = _G.SpokenSubtitlesFrame
ok(screen.shown and screen.alpha > 0.99, "screen line shown")
ok(string.find(Display.text.text, "^Thanks"), "screen words without a name prefix")
eq(Head.hasWords, false, "head compact while words are on screen")
Spoken:StopAll()
Mock.Advance(1.5)

-- Back to Spoken's player: its window returns, the head goes.
SlashCmdList.SPOKENSUBTITLES("player")
local refreshed = Spoken.refreshed
Spoken:Enqueue(Clip("90-accept", "Marshal Dughan", "Back"))
SlashCmdList.SPOKENSUBTITLES("spoken")
ok(spokenFrame.shown, "Spoken's window back")
ok(Spoken.refreshed > refreshed, "Spoken asked to refresh")
eq(frame.shown, false, "head hidden")
spokenFrame:Hide()
spokenFrame:Show()
ok(spokenFrame.shown, "no longer suppressed")

-- Preview in the head style shows a sample even with nothing queued.
Spoken:StopAll()
SlashCmdList.SPOKENSUBTITLES("head")
SlashCmdList.SPOKENSUBTITLES("test")
Mock.Advance(0.5)
ok(frame.shown and frame.alpha > 0.99, "preview head visible")
eq(Head.name.text, "Eagan Peltskinner", "preview speaker")
ok(Head.line.text ~= "", "preview words")
Mock.Advance(17)
eq(frame.shown, false, "preview ends by itself")

-- Dragging saves the position; locked heads do not move.
Head:StartDrag()
Head:StopDrag()
ok(ns.db.headY ~= nil, "position saved")
ns.db.headLocked = true
Head.dragging = false
Head:StartDrag()
eq(Head.dragging, false, "locked head does not drag")
