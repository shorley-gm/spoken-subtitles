local eq, ok = Tests.eq, Tests.ok
local Capture, ZoneText, Cues, Band = ns.Capture, ns.ZoneText, ns.Cues, ns.Band

Mock.FireEvent("ADDON_LOADED", "SpokenSubtitles")
Mock.FireEvent("PLAYER_LOGIN")
SlashCmdList.SPOKENSUBTITLES("band")

-- Only English and the client's language are kept.
ok(ZoneText.byLocale.enUS, "English lore loaded")
eq(ZoneText.byLocale.deDE, nil, "other languages skipped")
local elwynn = ZoneText:Get("z:1429")
ok(elwynn and string.find(elwynn, "^When the orcs came"), "Elwynn lore by clip key")
local goldshire = ZoneText:Get("s:1429:goldshire")
ok(goldshire and string.find(goldshire, "^Goldshire sits"), "subzone lore by clip key")

local zones = { key = "zones" }
local function ZoneClip(key, length, language)
    return { key = key, length = length, source = zones, pack = { language = language or "enUS" },
        present = { header = "Elwynn Forest", label = "Goldshire", bullet = "zone",
            portrait = { kind = "texture", texture = "Book" } } }
end

-- A recording that fits the text (13.5 characters a second): words, timed over its length.
local fitting = ZoneClip("s:1429:goldshire", Cues.Length(goldshire) / 13.5)
eq(Capture:TextFor(fitting), goldshire, "zone text for a fitting recording")
Spoken:Enqueue(fitting)
Spoken:StartHead()
Mock.Advance(0.5)
ok(string.find(Band.words.text, "^Goldshire sits"), "zone words in the band")
eq(Band.name.text, "Elwynn Forest", "zone name")
ok(Band.face.shown, "the zone's picture in the face slot")
local cues = Cues.Build(goldshire, fitting.length, 0)
ok(#cues >= 3, "long lore is split into several cues")
Spoken:StopAll()
Mock.Advance(1.5)

-- A recording far longer or shorter than the text: the lore changed; no words.
eq(Capture:TextFor(ZoneClip("s:1429:goldshire", Cues.Length(goldshire) / 3)), nil,
    "text too short for the recording")
eq(Capture:TextFor(ZoneClip("s:1429:goldshire", Cues.Length(goldshire) / 40)), nil,
    "text too long for the recording")
eq(Capture:TextFor(ZoneClip("z:999999", 30)), nil, "unknown zone")

-- A German pack on an English client: German is not loaded, so English stands in (and the
-- rate check still guards it).
local german = ZoneClip("z:1429", Cues.Length(elwynn) / 13.5, "deDE")
eq(Capture:TextFor(german), elwynn, "falls back to English lore")

-- Books: the page on screen is remembered by title and page.
local books = { key = "books" }
local function PageClip(id, title, label, length)
    return { key = "b:" .. id, length = length or 12, source = books,
        present = { header = title, label = label, bullet = "book",
            portrait = { kind = "texture", texture = "Book" } } }
end
ItemTextFrame = Mock.NewRegion("Frame", "ItemTextFrame")
Mock.book = { title = "A Dusty Unsent Letter", page = 1,
    text = "Dear Grelin, the mountain has been quiet. Too quiet, I fear. Write soon." }
Mock.FireEvent("ITEM_TEXT_READY")
local page1 = PageClip(16, "A Dusty Unsent Letter", "Page 1 of 2")
local page2 = PageClip(17, "A Dusty Unsent Letter", "Page 2 of 2")
Spoken:Enqueue(page1)
Spoken:Enqueue(page2)
Spoken:StartHead()
Mock.Advance(0.5)
ok(string.find(Band.words.text, "^Dear Grelin"), "book words for the open page")
eq(Capture:TextFor(page2), nil, "page 2 has no words before it is seen")

-- The reader turns to page 2 while page 1 is read: page 2 gets its words when it starts.
Mock.book = { title = "A Dusty Unsent Letter", page = 2,
    text = "P.S. Burn this letter once you have read it." }
Mock.FireEvent("ITEM_TEXT_READY")
Spoken:Skip()
Mock.Advance(0.5)
ok(string.find(Band.words.text, "^P%.S%. Burn this"), "page 2 words after turning to it")
Spoken:StopAll()
Mock.Advance(1.5)

-- A one-page letter has no label: page 1.
Mock.book = { title = "A Short Note", page = 1, text = "Meet me at the Scarlet Raven Tavern." }
Mock.FireEvent("ITEM_TEXT_READY")
eq(Capture:TextFor(PageClip(1156, "A Short Note", nil)), "Meet me at the Scarlet Raven Tavern.",
    "one-page note")

-- A German label still gives the page number.
Mock.book = { title = "Ein staubiger Brief", page = 2, text = "Seite zwei." }
Mock.FireEvent("ITEM_TEXT_READY")
eq(Capture:TextFor(PageClip(17, "Ein staubiger Brief", "Seite 2 von 2")), "Seite zwei.",
    "page number from a localised label")

-- HTML pages lose their tags, so none are read as stage directions.
Mock.book = { title = "Wanted: Hogger", page = 1,
    text = "<HTML><BODY><H1 align=\"center\">WANTED</H1><P>Hogger &amp; his gnolls.<BR/>Reward: 5 gold.</P></BODY></HTML>" }
Mock.FireEvent("ITEM_TEXT_READY")
local wanted = Capture:TextFor(PageClip(99, "Wanted: Hogger", nil))
ok(wanted and not string.find(wanted, "<", 1, true), "tags removed")
ok(string.find(wanted, "Hogger & his gnolls.", 1, true), "entities decoded")
ok(string.find(wanted, "WANTED\n", 1, true), "headings keep their line break")

-- Book words show with the book open (the option to hide them is off by default).
ItemTextFrame:Show()
local open = PageClip(1156, "A Short Note", nil)
Spoken:Enqueue(open)
Spoken:StartHead()
Mock.Advance(0.5)
ok(Band.words.alpha > 0.99, "words shown with the book open")
