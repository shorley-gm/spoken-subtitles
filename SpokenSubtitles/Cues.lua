-- SpokenSubtitles -- turning one line of text into timed subtitle cues.
--
-- Pure: no frames, no game API, no saved variables. Everything here takes a string and
-- numbers and returns tables, so the whole file runs under a plain Lua 5.1 in the tests.
--
-- The timing is an estimate. The client cannot report how far a sound has played, and the
-- prototype has no per-line alignment data, so each cue's share of the clip is its share of
-- the text: speech rate is steady enough that the error stays around half a second. Real
-- timings per line can later replace Build's arithmetic without touching anything else.

local _, ns = ...
ns = ns or {}

local Cues = {}
ns.Cues = Cues

-- Two lines of cinematic text at the default size. Longer sentences are cut at a clause.
Cues.MAX_CHARS = 110
-- A fragment shorter than this is folded into its neighbour rather than flashed on its own.
Cues.MIN_CHARS = 30
-- Neighbours that together fit this are shown together: one comfortable read, two lines.
Cues.MERGE_CHARS = 80
-- A sentence with no clause to cut at may run this much over MAX_CHARS before it is cut at
-- a bare space: a third short line reads better than a phrase broken in the middle.
Cues.UNBROKEN_SLACK = 1.25
-- Time a pause costs, counted in characters of speech.
Cues.PARAGRAPH_PAUSE = 10
Cues.SENTENCE_PAUSE = 6
Cues.CLAUSE_PAUSE = 2
-- Stage directions ("<Ello looks at the letter.>") are shown but mostly not spoken: the
-- pipeline strips them before synthesis, so they get a fraction of their length in time.
Cues.DIRECTION_WEIGHT = 0.25

local find, sub, gsub, byte = string.find, string.sub, string.gsub, string.byte

--- Code points, not bytes: a Russian or Chinese line would otherwise count double or triple.
local function Length(s)
    local _, n = gsub(s, "[^\128-\191]", "")
    return n
end
Cues.Length = Length

-- ASCII whitespace, spelled out. %s asks the C library, and under some locales it counts
-- 0x85 and 0xA0 as space -- both of which are also UTF-8 continuation bytes, so trimming
-- with %s can cut a Chinese or Russian character in half.
local WS = "[ \t\n\r\f\v]"

local function Trim(s)
    s = gsub(s, "^" .. WS .. "+", "")
    s = gsub(s, WS .. "+$", "")
    return s
end

--- Whether the byte at `i` starts a code point (is not a UTF-8 continuation byte).
local function IsBoundary(s, i)
    local b = byte(s, i)
    return b == nil or b < 128 or b >= 192
end

-- Sentence ends that need whitespace after them, so "3.5" and "..." mid-word stay whole.
local SPACED_ENDS = {
    "[%.!%?]+[\"'%)%]]*" .. WS,
    "\226\128\166[\"'%)%]]*" .. WS,            -- … (a single-character ellipsis)
}
-- Full-width ends that CJK text puts directly against the next sentence.
local CJK_ENDS = {
    "\227\128\130",                          -- 。
    "\239\188\129",                          -- ！
    "\239\188\159",                          -- ？
}
-- Closing marks a CJK sentence end may carry.
local CJK_CLOSERS = { "\227\128\141", "\227\128\143", "\226\128\157" }  -- 」 』 ”

--- The byte index the sentence starting at `init` ends on, or nil for the rest of the text.
local function SentenceEnd(text, init)
    local best
    for _, pattern in ipairs(SPACED_ENDS) do
        local _, e = find(text, pattern, init)
        if e and (not best or e - 1 < best) then
            best = e - 1          -- the whitespace belongs to neither sentence
        end
    end
    for _, mark in ipairs(CJK_ENDS) do
        local _, e = find(text, mark, init, true)
        if e then
            for _, closer in ipairs(CJK_CLOSERS) do
                if sub(text, e + 1, e + #closer) == closer then
                    e = e + #closer
                end
            end
            if e < #text and (not best or e < best) then
                best = e
            end
        end
    end
    return best
end

local function Sentences(paragraph)
    local out, pos = {}, 1
    while pos <= #paragraph do
        local stop = SentenceEnd(paragraph, pos) or #paragraph
        local sentence = Trim(sub(paragraph, pos, stop))
        if sentence ~= "" then
            table.insert(out, sentence)
        end
        pos = stop + 1
    end
    return out
end

-- Where a long sentence may be cut, and how much of the mark stays on the left half.
-- `keep` counts bytes from the mark's start: 1 keeps ", " as "," + " ".
local CLAUSE_MARKS = {
    { mark = ", ", keep = 1 },
    { mark = "; ", keep = 1 },
    { mark = ": ", keep = 1 },
    { mark = " - ", keep = 0 },
    { mark = " \226\128\148 ", keep = 0 },   -- " — "
    { mark = "\239\188\140", keep = 3 },     -- ，
    { mark = "\227\128\129", keep = 3 },     -- 、
    { mark = "\239\188\155", keep = 3 },     -- ；
    { mark = "\239\188\154", keep = 3 },     -- ：
}

--- The byte a long piece should be cut after: a clause mark nearest the middle, else the
--- space nearest it, else the code point boundary nearest it (CJK has no spaces).
local function CutPoint(text)
    local middle = #text / 2
    local minSide = math.floor(Cues.MIN_CHARS / 2)
    local best, bestDistance

    local function Consider(cut, clause)
        if cut < 1 or cut >= #text then
            return
        end
        local left, right = sub(text, 1, cut), sub(text, cut + 1)
        if Length(Trim(left)) < minSide or Length(Trim(right)) < minSide then
            return
        end
        -- A clause mark beats a bare space unless the space is much nearer the middle.
        local distance = math.abs(cut - middle) * (clause and 1 or 2)
        if not bestDistance or distance < bestDistance then
            best, bestDistance = cut, distance
        end
    end

    for _, clause in ipairs(CLAUSE_MARKS) do
        local init = 1
        while true do
            local s = find(text, clause.mark, init, true)
            if not s then
                break
            end
            Consider(s + clause.keep - 1, true)
            init = s + 1
        end
    end
    if best then
        return best, true
    end

    local init = 1
    while true do
        local s = find(text, " ", init, true)
        if not s then
            break
        end
        Consider(s - 1, false)
        init = s + 1
    end
    if best then
        return best, false
    end

    local cut = math.floor(middle)
    while cut < #text and not IsBoundary(text, cut + 1) do
        cut = cut + 1
    end
    return cut, false
end

local function SplitLong(text, pause, out)
    if Length(text) <= Cues.MAX_CHARS then
        table.insert(out, { text = text, pause = pause })
        return
    end
    local cut, clause = CutPoint(text)
    if not clause and Length(text) <= Cues.MAX_CHARS * Cues.UNBROKEN_SLACK then
        table.insert(out, { text = text, pause = pause })
        return
    end
    local left, right = Trim(sub(text, 1, cut)), Trim(sub(text, cut + 1))
    if left == "" or right == "" then
        table.insert(out, { text = text, pause = pause })
        return
    end
    SplitLong(left, clause and Cues.CLAUSE_PAUSE or 0, out)
    SplitLong(right, pause, out)
end

--- Joined with a space, except between two pieces of CJK text, which has none.
local function Join(left, right)
    local l, r = byte(left, #left), byte(right, 1)
    if l and r and l >= 128 and r >= 128 then
        return left .. right
    end
    return left .. " " .. right
end

--- How long a piece takes to say, in characters of speech.
function Cues.Weight(text, pause)
    local directions = 0
    for direction in string.gmatch(text, "<[^<>]*>") do
        directions = directions + Length(direction)
    end
    local spoken = Length(text) - directions
    return spoken + directions * Cues.DIRECTION_WEIGHT + (pause or 0)
end

--- The text broken into display pieces: { text, pause } in order.
function Cues.Split(text)
    if type(text) ~= "string" then
        return {}
    end
    text = gsub(text, "\r\n?", "\n")
    text = gsub(text, "|", "||")   -- a stray pipe would otherwise start an escape sequence

    local pieces = {}
    for paragraph in string.gmatch(text, "[^\n]+") do
        paragraph = Trim(gsub(paragraph, WS .. "+", " "))
        if paragraph ~= "" then
            local sentences = Sentences(paragraph)
            for index, sentence in ipairs(sentences) do
                local pause = index == #sentences and Cues.PARAGRAPH_PAUSE or Cues.SENTENCE_PAUSE
                SplitLong(sentence, pause, pieces)
            end
        end
    end

    -- Fold short fragments into a neighbour while the result still fits.
    local merged = {}
    for _, piece in ipairs(pieces) do
        local last = merged[#merged]
        if last
            and ((Length(last.text) < Cues.MIN_CHARS or Length(piece.text) < Cues.MIN_CHARS)
                and Length(last.text) + 1 + Length(piece.text) <= Cues.MAX_CHARS
                or Length(last.text) + 1 + Length(piece.text) <= Cues.MERGE_CHARS) then
            -- The pause inside the joined text is still spoken, so last.weight keeps it.
            last.weight = last.weight + Cues.Weight(piece.text, piece.pause)
            last.text = Join(last.text, piece.text)
            last.pause = piece.pause
        else
            table.insert(merged, { text = piece.text, pause = piece.pause,
                weight = Cues.Weight(piece.text, piece.pause) })
        end
    end

    -- No silence follows the last words: the pipeline trims the take's tail as well.
    local last = merged[#merged]
    if last then
        last.weight = last.weight - (last.pause or 0)
        last.pause = 0
    end
    return merged
end

--- Timed cues for a clip: { text, start, stop } with times in seconds from CLIP_STARTED.
--- `delay` is the silence the player plays before the words (legacy clients only).
function Cues.Build(text, length, delay)
    local pieces = Cues.Split(text)
    delay = delay or 0
    if type(length) ~= "number" or length <= 0 or #pieces == 0 then
        return {}
    end

    local total = 0
    for _, piece in ipairs(pieces) do
        if piece.weight < 1 then
            piece.weight = 1
        end
        total = total + piece.weight
    end

    local cues, at = {}, delay
    for index, piece in ipairs(pieces) do
        local stop = index == #pieces and delay + length or at + length * piece.weight / total
        table.insert(cues, { text = piece.text, start = at, stop = stop })
        at = stop
    end
    return cues
end

--- The cue to show `elapsed` seconds in: the first cue during the initial silence, the last
--- after the end, nil for an empty list.
function Cues.At(cues, elapsed)
    local count = #cues
    if count == 0 then
        return nil
    end
    for index = 1, count do
        if elapsed < cues[index].stop then
            return index
        end
    end
    return count
end

--- Stage directions greyed. Also a direction a cue boundary cut in two, from either side.
local DIRECTION_COLOR = "|cffa9a9a9"
function Cues.Markup(text)
    text = gsub(text, "<[^<>]*>", function(direction)
        return DIRECTION_COLOR .. direction .. "|r"
    end)
    text = gsub(text, "^([^<]->)", function(tail)
        return DIRECTION_COLOR .. tail .. "|r"
    end)
    text = gsub(text, "(<[^>]*)$", function(head)
        return DIRECTION_COLOR .. head .. "|r"
    end)
    return text
end

return Cues
