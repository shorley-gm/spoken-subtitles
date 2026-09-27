local Cues = ns.Cues
local eq, ok = Tests.eq, Tests.ok

-- Sentences split, short ones fold together, paragraphs break.
local wolves = "I hate those nasty timber wolves!  But I sure like eating wolf steaks...  "
    .. "Bring me tough wolf meat and I will exchange it for something you'll find useful."
    .. "\n\nTough wolf meat is gathered from hunting the timber wolves and young wolves "
    .. "wandering the Northshire countryside."
local pieces = Cues.Split(wolves)
eq(#pieces, 3, "wolves piece count")
eq(pieces[1].text, "I hate those nasty timber wolves! But I sure like eating wolf steaks...",
    "short sentences merged")
eq(pieces[2].text,
    "Bring me tough wolf meat and I will exchange it for something you'll find useful.",
    "second sentence")
ok(string.find(pieces[3].text, "^Tough wolf meat"), "paragraph starts a new cue")
eq(pieces[3].pause, 0, "no pause after the last words")

-- Every cue fits the limit.
local long = "The Defias Brotherhood has been causing trouble in Westfall for months, "
    .. "attacking farmers, burning fields, and stealing supplies meant for the people of "
    .. "Stormwind, and we have had enough of it; bring me their bandanas and I will pay you."
for _, piece in ipairs(Cues.Split(long)) do
    ok(Cues.Length(piece.text) <= Cues.MAX_CHARS, "long sentence cut: " .. piece.text)
end
ok(#Cues.Split(long) >= 2, "long sentence was cut")

-- Numbers and mid-word dots stay whole.
eq(#Cues.Split("It costs 3.5 gold. Pay up now or leave my shop please, friend."), 1,
    "decimal kept, short pair merged")

-- UTF-8: code points counted, never cut inside a character.
eq(Cues.Length("Привет"), 6, "cyrillic length")
eq(Cues.Length("你好"), 2, "cjk length")
local chinese = string.rep("这是一个非常长的中文句子没有任何标点符号", 8)
for _, piece in ipairs(Cues.Split(chinese)) do
    local first = string.byte(piece.text, 1)
    ok(first < 128 or first >= 192, "cjk cut on a code point boundary")
    ok(Cues.Length(piece.text) <= Cues.MAX_CHARS, "cjk piece fits")
end
local cjkSentences = Cues.Split(string.rep("狼群越来越大胆了，它们一直在骚扰附近的农场和村庄里的居民们。", 4))
ok(#cjkSentences >= 2, "cjk full stop splits")

-- Stage directions: kept, greyed, and cheap in time.
local direction = "<Ello looks at the letter...>\n\nWhat language is this?  It looks ancient...I can't read it."
local dp = Cues.Split(direction)
eq(dp[1].text, "<Ello looks at the letter...> What language is this?",
    "direction shown with the words it introduces")
ok(dp[1].weight < Cues.Length(dp[1].text), "the unspoken direction costs little time")
ok(Cues.Weight("<Ello looks at the letter...>") < 10, "direction weighs little")
ok(string.find(Cues.Markup("<Ello nods.> Hello"), "|cffa9a9a9<Ello nods.>|r", 1, true),
    "direction greyed")
ok(string.find(Cues.Markup("nods slowly.> Hello"), "^|cffa9a9a9nods slowly.>|r"),
    "cut direction tail greyed")
ok(string.find(Cues.Markup("Hello <Ello"), "|cffa9a9a9<Ello|r$"), "cut direction head greyed")
eq(Cues.Markup("Plain text."), "Plain text.", "plain untouched")

-- Pipes cannot start escape sequences.
eq(Cues.Split("A | B is fine here, really it is fine.")[1].text,
    "A || B is fine here, really it is fine.", "pipe escaped")

-- Timing: covers delay..delay+length exactly, in order, proportional.
local cues = Cues.Build(wolves, 20, 0.5)
eq(cues[1].start, 0.5, "starts after the delay")
eq(cues[#cues].stop, 20.5, "ends with the clip")
for index = 2, #cues do
    eq(cues[index].start, cues[index - 1].stop, "contiguous " .. index)
    ok(cues[index].start > cues[index - 1].start, "ordered " .. index)
end
eq(Cues.At(cues, 0), 1, "first cue during the initial silence")
eq(Cues.At(cues, 30), #cues, "last cue after the end")
eq(Cues.At(cues, cues[2].start + 0.01), 2, "second cue")
eq(#Cues.Build("", 5), 0, "empty text")
eq(#Cues.Build(wolves, 0), 0, "zero length")
eq(#Cues.Build(nil, 5), 0, "nil text")
eq(Cues.At({}, 1), nil, "no cues")
