local eq, ok = Tests.eq, Tests.ok
local Band, Display = ns.Band, ns.Display

local pig = "The Brackwells have a prize-winning pig, Princess.  The sow is HUGE, and she got "
    .. "that way from sneaking over here and eating my veggies!"
local function Clip(key, header, label, extra)
    local clip = { key = key, length = 8, source = Mock.questSource, present = {
        header = header, label = label, bullet = "quest-accept",
        portrait = { kind = "model", creatureID = 246,
            fallback = { kind = "texture", texture = "Book" } } } }
    for k, v in pairs(extra or {}) do clip[k] = v end
    return clip
end
local STONEFIELD = { guid = "Creature-0-0-0-0-246-0000", name = "Ma Stonefield" }

-- An earlier version's talking head becomes the band; the quest-window rule is reset once.
SpokenSubtitlesDB = { style = "head", headMode = "player", headScale = 1.2,
    hideWithDialog = true }
local spokenFrame = Spoken.playerFrame
spokenFrame:Show()
Mock.FireEvent("ADDON_LOADED", "SpokenSubtitles")
Mock.FireEvent("PLAYER_LOGIN")
eq(ns.db.style, "band", "talking head migrated to the band")
eq(ns.db.bandScale, 1.2, "size carried over")
eq(ns.db.headMode, nil, "old keys cleared")
eq(ns.db.hideWithDialog, false, "words no longer wait for the quest window")
eq(ns.db.schema, 2, "schema recorded")
eq(spokenFrame.shown, false, "Spoken's window hidden while the band is the style")
spokenFrame:Show()
eq(spokenFrame.shown, false, "and it stays hidden")

-- Accept a quest with the quest window open and the NPC targeted.
Mock.units.npc = STONEFIELD
Mock.units.target = STONEFIELD
Mock.quest = { id = 88, accept = pig }
QuestFrame = Mock.NewRegion("Frame", "QuestFrame")
local first = Clip("88-accept", "Ma Stonefield", "Princess Must Die!")
Spoken:Enqueue(first)
Spoken:StartHead()
Mock.Advance(0.5)
local frame = _G.SpokenSubtitlesBand
ok(frame and frame.shown and frame.alpha > 0.99, "band shown")
eq(Band.name.text, "Ma Stonefield", "name")
ok(string.find(Band.label.text, "Princess Must Die!$"), "title after a quiet dot")
ok(string.find(Band.label.text, "\194\183", 1, true), "dot separator")
eq(Band.badge, nil, "no quest icon in the header")
eq(_G.MouseIsOver, nil, "the client has no global MouseIsOver")
ok(string.find(Band.words.text, "^The Brackwells"), "words start with the voice")
ok(Band.words.alpha > 0.99, "words visible with the quest window open")
ok(not string.find(Band.words.text, "Ma Stonefield:", 1, true), "no name prefix")
eq(Band.face.shown, false, "no face: the target frame already shows her")
ok(Display:HasWords(first), "band sized for words")
local withWords = frame.height

-- Retarget someone else: the small face appears (the snapshot taken when queued).
Mock.units.target = { guid = "Creature-0-0-0-0-6-0000", name = "Kobold Vermin" }
Mock.FireEvent("PLAYER_TARGET_CHANGED")
ok(Band.face.shown, "small face when the speaker is not the target")
ok(Band.snapshot and Band.snapshot.portraitOf == "Ma Stonefield", "native snapshot")
Mock.units.target = STONEFIELD
Mock.FireEvent("PLAYER_TARGET_CHANGED")
eq(Band.face.shown, false, "face gone again when she is targeted")
ns.db.bandFace = false
Mock.units.target = nil
Mock.FireEvent("PLAYER_TARGET_CHANGED")
eq(Band.face.shown, false, "the face can be turned off")
ns.db.bandFace = true

-- Controls: hidden at rest, fade in on hover.
Mock.Advance(0.3)
eq(Band.skip.alpha, 0, "skip hidden at rest")
eq(Band.pause.alpha, 0, "pause hidden at rest")
Mock.mouseOver[frame] = true
Mock.Advance(0.3)
ok(Band.skip.alpha > 0.99 and Band.pause.alpha > 0.99, "controls on hover")
eq(Band.pause.icon.texture, [[Interface\AddOns\SpokenSubtitles\Media\GlyphPause]], "pause glyph")
Mock.mouseOver[frame] = nil
Mock.Advance(0.3)
eq(Band.skip.alpha, 0, "controls fade on leave")

-- Hairline follows the clip; the second cue arrives.
Mock.Advance(3)
local fill = Band.fill.width
ok(fill > 0.4 * Band.track.width and fill < 0.65 * Band.track.width, "hairline about half")
ok(string.find(Band.words.text, "HUGE", 1, true), "second cue")

-- Click the band: pause. Words dim, the play glyph stays, the hairline freezes.
frame.scripts.OnMouseUp(frame, "LeftButton")
ok(Spoken.paused, "click pauses")
Mock.Advance(0.5)
ok(math.abs(Band.words.alpha - 0.45) < 0.01, "words dimmed, still readable")
eq(Band.pause.alpha, 1, "play glyph shown while paused")
eq(Band.pause.icon.texture, [[Interface\AddOns\SpokenSubtitles\Media\GlyphPlay]], "play glyph")
eq(Band.spark.shown, false, "spark stops")
local frozen = Band.fill.width
Mock.Advance(1)
eq(Band.fill.width, frozen, "hairline frozen")

-- Click again: resumes by replaying the line.
frame.scripts.OnMouseUp(frame, "LeftButton")
ok(not Spoken.paused, "click resumes")
Mock.Advance(0.3)
ok(string.find(Band.words.text, "^The Brackwells"), "words from the first cue")
ok(Band.fill.width < frozen, "hairline restarted")
ok(Band.words.alpha > 0.99, "words bright again")

-- A drag's own button release is not a click.
Band:StartDrag()
Band:StopDrag()
frame.scripts.OnMouseUp(frame, "LeftButton")
ok(not Spoken.paused, "no pause from the end of a drag")
ok(ns.db.bandY ~= nil, "position saved")

-- Queue: +N, list above the band, click a row to remove it.
local second = Clip("89-accept", "Ma Stonefield", "Beat Back the Pig")
local third = Clip("g:abc", "Farmer Saldean", "Gossip", { held = "in combat" })
Spoken:Enqueue(second)
Spoken:Enqueue(third)
ok(Band.fold.shown, "queue count")
eq(Band.fold.text.text, "+2", "two waiting")
Band.fold:Click()
ok(Band.drawer.shown, "list open")
eq(Band.drawer.points[1][1], "BOTTOM", "list opens above the band")
ok(string.find(Band.rows[2].text.text, "(in combat)", 1, true), "held reason")
Band.rows[1]:Click()
eq(#Spoken.queue, 2, "row click removed a line")
eq(Band.fold.text.text, "+1", "one waiting")

-- Right-click menu, with the clip's Report action.
local reported
first.present.actions = { { id = "report", label = "Report a problem", icon = "Bug",
    onClick = function(clip) reported = clip end },
    { id = "stopgossip", anchor = "header", create = function() end } }
frame.scripts.OnMouseUp(frame, "RightButton")
ok(Band.menu.shown, "menu open")
local texts = {}
for _, row in ipairs(Band.menuRows) do
    if row.shown then texts[#texts + 1] = row.text.text end
end
eq(table.concat(texts, "|"), "Pause|Skip this line|Stop everything|Waiting lines (1)|"
    .. "Report a problem|Subtitle settings|Spoken settings", "menu rows")
eq(Band.menu.points[1][1], "BOTTOM", "menu opens above the band")
Band.menuRows[5]:Click()
eq(reported, first, "Report called with the clip")

-- Skip glyph: the next line takes over; no text for it, so the band shrinks.
Mock.quest = {}
Mock.mouseOver[frame] = true
Mock.Advance(0.3)
Band.skip:Click()
Mock.Advance(0.3)
eq(Spoken:GetCurrent(), third, "skipped")
ok(string.find(Band.label.text, "Gossip$"), "next title")
eq(Display:HasWords(third), false, "no words for it")
ok(frame.height < withWords, "thinner band without words")
Mock.mouseOver[frame] = nil

-- Zones bring their own picture: shown even with no target frame involved.
Spoken:StopAll()
local zone = { key = "z:goldshire", length = 5, source = { key = "zones" }, present = {
    header = "Goldshire", label = "Elwynn Forest",
    portrait = { kind = "texture", texture = "ZoneArt", texCoord = { 0, 1, 0, 1 } } } }
Spoken:Enqueue(zone)
Spoken:StartHead()
Mock.Advance(0.3)
ok(Band.face.shown, "zone picture in the face slot")
eq(Band.art.texture, "ZoneArt", "the zone's own art")
eq(Band.words.text, "", "no words for zones yet")

-- Held at the head: why, beside the title; no progress.
Spoken:StopAll()
local held = Clip("90-accept", "Ma Stonefield", "Held quest", { held = "in combat" })
Spoken:Enqueue(held)
Mock.Advance(0.3)
ok(string.find(Band.label.text, "(in combat)", 1, true), "held reason")
ok(Band.fill.width < 1, "no progress while held")

-- Empty queue: the band fades away.
Spoken:StopAll()
Mock.Advance(0.5)
eq(frame.shown, false, "hidden when nothing is queued")

-- Subtitles off in the band style: the band still plays, without words.
SlashCmdList.SPOKENSUBTITLES("off")
eq(ns.db.bandMode, "off", "band subtitle choice")
eq(ns.db.mode, "screen", "Spoken style choice untouched")
Mock.quest = { id = 88, accept = pig }
Mock.units.npc = STONEFIELD
local quiet = Clip("88-accept", "Ma Stonefield", "Princess Must Die!")
Spoken:Enqueue(quiet)
Spoken:StartHead()
Mock.Advance(0.5)
ok(frame.shown, "band shown")
eq(Band.words.text, "", "no words when subtitles are off")
SlashCmdList.SPOKENSUBTITLES("player")
Spoken:StopAll()
Mock.Advance(1.5)

-- Back to Spoken's player.
Spoken:Enqueue(Clip("91-accept", "Ma Stonefield", "Back"))
SlashCmdList.SPOKENSUBTITLES("spoken")
ok(spokenFrame.shown, "Spoken's window back")
eq(frame.shown, false, "band hidden")
spokenFrame:Hide()
spokenFrame:Show()
ok(spokenFrame.shown, "no longer suppressed")

-- Preview in the band style, with nothing queued.
Spoken:StopAll()
SlashCmdList.SPOKENSUBTITLES("band")
SlashCmdList.SPOKENSUBTITLES("test")
Mock.Advance(0.5)
ok(frame.shown and frame.alpha > 0.99, "preview visible")
eq(Band.name.text, "Eagan Peltskinner", "preview speaker")
ok(Band.words.text ~= "", "preview words")
Mock.Advance(17)
eq(frame.shown, false, "preview ends by itself")

-- Locked bands do not drag.
ns.db.bandLocked = true
Band:StartDrag()
eq(Band.dragging, false, "locked")
ns.db.bandLocked = false

-- Only the name row and the words take clicks; the shade's soft sides pass them on.
Spoken:StopAll()
Spoken:Enqueue(Clip("95-accept", "Ma Stonefield", "Short"))
Spoken:StartHead()
Mock.Advance(0.5)
local inset = frame.hitInsets and frame.hitInsets[1] or 0
ok(inset > 100, "a short line leaves the band's sides to the world")
eq(frame.hitInsets[2], inset, "on both sides")
eq(frame.mouse, true, "the shown band takes clicks")

-- A pause left behind by a skipped line does not hold the next one.
Spoken:TogglePause()
eq(Spoken.paused, true, "paused")
Spoken:Skip()
eq(Spoken.paused, false, "pause released once nothing was left to resume")
eq(frame.mouse, false, "fading out, clicks go to the world")

-- Paused from an earlier session (Spoken saves it per character): the first line plays.
Spoken.paused = true
local westfall = Clip("z:52", "Westfall", "Westfall")
Spoken:Enqueue(westfall)
eq(Spoken.paused, false, "a new line alone in the queue is not held by an old pause")
eq(Spoken:GetNowPlaying(), westfall, "and it plays")

-- A real pause with lines behind it stays.
Spoken:TogglePause()
Spoken:Enqueue(Clip("z:52:1", "Westfall", "Sentinel Hill"))
eq(Spoken.paused, true, "a pause over the playing line is kept when more arrive")
Spoken:StopAll()
eq(Spoken.paused, false, "stopping everything ends the pause too")

-- With Spoken's own window the pause is Spoken's business.
SlashCmdList.SPOKENSUBTITLES("spoken")
Spoken.paused = true
Spoken:Enqueue(Clip("z:40", "Elwynn Forest", "Elwynn Forest"))
eq(Spoken.paused, true, "Spoken's window keeps its own pause")
Spoken.paused = false
Spoken:StopAll()
SlashCmdList.SPOKENSUBTITLES("band")
