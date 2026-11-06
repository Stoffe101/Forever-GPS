-- What the addon can say about itself: how long work took, and what went wrong,
-- in a small ring that costs nothing when nobody looks. Read by `/fgps diag`; never
-- saved, and never printed during play.
local FG = ForeverGPS
local Metrics = {}
FG.Metrics = Metrics

local MAX_NOTES = 12

local open, last, worst, count = {}, {}, {}, {}
local notes = {}

function Metrics.Begin(name)
    open[name] = debugprofilestop()
end

function Metrics.End(name)
    local started = open[name]
    if not started then return end
    open[name] = nil
    local ms = debugprofilestop() - started
    last[name], count[name] = ms, (count[name] or 0) + 1
    if not worst[name] or ms > worst[name] then worst[name] = ms end
end

-- One measurement of something that happens too often to open and close.
function Metrics.Sample(name, ms)
    last[name], count[name] = ms, (count[name] or 0) + 1
    if not worst[name] or ms > worst[name] then worst[name] = ms end
end

-- A thing worth knowing about later: a plan that failed, an API that was missing.
function Metrics.Note(text)
    notes[#notes + 1] = text
    if #notes > MAX_NOTES then table.remove(notes, 1) end
end

function Metrics.Lines()
    local names = {}
    for name in pairs(last) do names[#names + 1] = name end
    table.sort(names)
    local out = {}
    for _, name in ipairs(names) do
        out[#out + 1] = ("%s: last %.1f ms, worst %.1f ms, %d runs"):format(name, last[name], worst[name], count[name])
    end
    return out
end

function Metrics.Notes() return notes end
function Metrics.Last(name) return last[name] end
