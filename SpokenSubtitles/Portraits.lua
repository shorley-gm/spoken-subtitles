-- SpokenSubtitles -- the speaker's face for the talking head.
--
-- A native 2D portrait (SetPortraitTexture) needs a live unit token, and the speaker only
-- has one while its dialog is open or it is targeted. So the face is captured when a line
-- is queued, the moment Spoken Quests has just read that dialog, and kept.
--
-- A portrait painted by SetPortraitTexture lives in the Texture it was painted into: it
-- cannot be copied to another one. Each capture therefore gets its own Texture from a
-- small pool, and the talking head borrows that Texture while the line plays. The cache is
-- keyed by creature, so the second line from the same NPC has a face even when it was
-- queued with no dialog open.
--
-- No 3D models: in a round frame they show black bars, which is what the Minimal Classic
-- player moved away from. Without a snapshot the clip's own fallback art is used, masked
-- round, and failing that the book.

local _, ns = ...
ns = ns or {}

local Portraits = { byClip = setmetatable({}, { __mode = "k" }), byCreature = {}, order = {} }
ns.Portraits = Portraits

Portraits.CACHE_SIZE = 32
Portraits.BOOK = [[Interface\Icons\INV_Misc_Book_09]]

local UNITS = { "npc", "questnpc", "target", "mouseover", "focus" }

local function CreatureID(unit)
    local guid = UnitGUID and UnitGUID(unit)
    if type(guid) ~= "string" then
        return nil
    end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then
        return tonumber(id)
    end
    return nil
end

local function Present(clip)
    return type(clip) == "table" and type(clip.present) == "table" and clip.present or {}
end

local function WantedCreature(clip)
    local portrait = Present(clip).portrait
    return type(portrait) == "table" and tonumber(portrait.creatureID) or nil
end

--- The unit token that is this clip's speaker right now, if any.
function Portraits:FindUnit(clip)
    local creature, name = WantedCreature(clip), Present(clip).header
    for _, unit in ipairs(UNITS) do
        if UnitExists and UnitExists(unit) and not (UnitIsPlayer and UnitIsPlayer(unit)) then
            local id = CreatureID(unit)
            if creature and id == creature then
                return unit
            end
            if not creature and name and name ~= "" and UnitName(unit) == name then
                return unit
            end
        end
    end
    return nil
end

function Portraits:Holder()
    if not self.holder then
        self.holder = CreateFrame("Frame", nil, UIParent)
        self.holder:Hide()
    end
    return self.holder
end

--- A Texture for a new snapshot, evicting the oldest creature beyond CACHE_SIZE.
function Portraits:NewTexture()
    if #self.order >= self.CACHE_SIZE then
        local oldest = table.remove(self.order, 1)
        local texture = self.byCreature[oldest]
        self.byCreature[oldest] = nil
        if texture and not texture.inUse then
            -- Repainted for someone else next, so no queued line may keep pointing at it.
            for clip, held in pairs(self.byClip) do
                if held == texture then self.byClip[clip] = nil end
            end
            texture:SetTexture(nil)
            return texture
        end
    end
    return self:Holder():CreateTexture(nil, "ARTWORK")
end

--- Called on CLIP_QUEUED.
function Portraits:Capture(clip)
    local unit = self:FindUnit(clip)
    if not unit or not SetPortraitTexture then
        return false
    end
    local key = CreatureID(unit) or ("name:" .. tostring(UnitName(unit)))
    local texture = self.byCreature[key]
    if not texture then
        texture = self:NewTexture()
        self.byCreature[key] = texture
        table.insert(self.order, key)
    end
    SetPortraitTexture(texture, unit)
    self.byClip[clip] = texture
    return true
end

--- A model can still be loading when the line is queued, leaving the snapshot blank. The
--- client says when a unit's portrait changes; repaint the cached one for that creature.
function Portraits:Refresh(unit)
    if not unit or not (UnitExists and UnitExists(unit)) then return end
    local texture = self.byCreature[CreatureID(unit) or ("name:" .. tostring(UnitName(unit)))]
    if texture and SetPortraitTexture then
        SetPortraitTexture(texture, unit)
    end
end

function Portraits:Watch()
    if self.watcher then return end
    local watcher = CreateFrame("Frame")
    for _, event in ipairs({ "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED" }) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    watcher:SetScript("OnEvent", function(_, _, unit) Portraits:Refresh(unit) end)
    self.watcher = watcher
end

--- The snapshot for a clip: captured with it, or an earlier one of the same creature.
function Portraits:Snapshot(clip)
    local texture = self.byClip[clip]
    if texture then
        return texture
    end
    local creature = WantedCreature(clip)
    if creature and self.byCreature[creature] then
        return self.byCreature[creature]
    end
    local name = Present(clip).header
    return name and self.byCreature["name:" .. name] or nil
end

--- Art to draw when there is no snapshot: { texture, texCoord } from the clip, or the book.
function Portraits:Fallback(clip)
    local portrait = Present(clip).portrait
    if type(portrait) == "table" then
        if portrait.kind == "texture" and portrait.texture then
            return portrait.texture, portrait.texCoord
        end
        local fallback = portrait.fallback
        if type(fallback) == "table" and fallback.texture then
            return fallback.texture, fallback.texCoord
        end
    end
    return self.BOOK, { 0.07, 0.93, 0.07, 0.93 }
end

return Portraits
