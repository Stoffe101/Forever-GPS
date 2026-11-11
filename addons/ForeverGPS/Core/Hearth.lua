-- The hearthstone, as a player wants to know it: where it is bound, how sure the landing is,
-- and whether it is ready. EasyFind GPS already plans with it, learning the landing from the
-- first hearth after binding and otherwise finding the bound town's spot by name. This only
-- reads that, adds the cooldown, and never shows an old landing after a rebind.
local FG = ForeverGPS
local Hearth = {}
FG.Hearth = Hearth

local Bridge = FG.Bridge
local L = FG.L

local HEARTHSTONE = 6948

local function Cooldown()
    local start, duration = FG.Item.Cooldown(HEARTHSTONE)
    if not (start and duration and duration > 2) then return 0 end
    return math.max(0, start + duration - GetTime())
end

-- { bind, sure = "learned"|"town"|"unknown", owned, ready, cooldown (seconds), spot }
function Hearth.Status()
    local bind = GetBindLocation and GetBindLocation() or nil
    local learned = Bridge.HearthSpot()
    local spot = learned and (not bind or learned.name == bind) and learned or nil
    local owned = not C_Item or not C_Item.GetItemCount or (C_Item.GetItemCount(HEARTHSTONE) or 0) > 0
    local cooldown = owned and Cooldown() or 0
    return {
        bind = bind, spot = spot, owned = owned, cooldown = cooldown, ready = owned and cooldown == 0,
        sure = spot and "learned" or bind and "town" or "unknown",
    }
end

-- One line: "Hearthstone: Lion's Pride Inn, ready" or "... in 23 min".
function Hearth.Line(s)
    s = s or Hearth.Status()
    if not s.owned then return L["HEARTH_NONE"] end
    if not s.bind then return L["HEARTH_UNKNOWN"] end
    local when = s.ready and L["HEARTH_READY"] or L["HEARTH_IN_FMT"]:format(FG.Format.Duration(s.cooldown) or "?")
    return L["HEARTH_LINE_FMT"]:format(s.bind, when)
end

-- What a plan's use of the hearth needs saying.
function Hearth.Note(steps)
    for _, step in ipairs(steps or {}) do
        if step.kind == "teleport" and step.itemID == HEARTHSTONE then
            local s = Hearth.Status()
            local note = Hearth.Line(s)
            if s.sure ~= "learned" then note = note .. " " .. L["HEARTH_NOT_LEARNED"] end
            return note
        end
    end
    return nil
end
