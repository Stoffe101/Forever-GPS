-- What the account's other characters can make, as each last showed it. A character's
-- professions and recipes are only readable while it is logged in, so each one leaves a
-- small summary here for the others: its professions with skill and cap, and the items its
-- learned recipes make. Everything read from here is a copy, says whose and how old, and
-- is never mixed into this character's own figures.
local FG = ForeverGPS
local Alts = {}
FG.Alts = Alts

local function DB()
    FG.db.alts = FG.db.alts or {}
    return FG.db.alts
end

function Alts.Me()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

-- This character's summary, written whenever its professions or recipes change.
function Alts.Save()
    if not FG.char then return end
    local me = Alts.Me()
    local professions = {}
    for _, p in ipairs(FG.Professions.List()) do
        professions[#professions + 1] = { line = p.line, name = p.name, skill = p.skill, max = p.max }
    end
    local makes, n = {}, 0
    for _, r in ipairs(FG.Professions.Recipes()) do
        if r.learned and r.out then
            makes[#makes + 1] = r.out
            n = n + 1
        end
    end
    table.sort(makes)
    local _, class = UnitClass and UnitClass("player")
    DB()[me] = { name = UnitName("player"), realm = GetRealmName and GetRealmName() or "?", class = class, at = time(),
                 professions = professions, makes = table.concat(makes, ","), recipes = n }
end

FG.On("professions:changed", function() Alts.Save() end)
FG.On("recipes:changed", function() Alts.Save() end)

-- The other characters, newest first: { key, name, realm, class, at, professions, recipes }.
function Alts.List()
    local me, out = Alts.Me(), {}
    for key, a in pairs(DB()) do
        if key ~= me then
            out[#out + 1] = { key = key, name = a.name, realm = a.realm, class = a.class, at = a.at,
                              professions = a.professions or {}, recipes = a.recipes or 0 }
        end
    end
    table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
    return out
end

-- Which other characters can make an item, as they last showed it: { { key, name, at } }.
function Alts.WhoMakes(itemID)
    local me, out = Alts.Me(), nil
    local needle = tostring(itemID)
    for key, a in pairs(DB()) do
        if key ~= me and a.makes then
            for id in a.makes:gmatch("%d+") do
                if id == needle then
                    out = out or {}
                    out[#out + 1] = { key = key, name = a.name, at = a.at }
                    break
                end
            end
        end
    end
    return out
end
