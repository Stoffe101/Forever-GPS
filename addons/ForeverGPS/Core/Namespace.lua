-- Forever-GPS: the namespace every other file builds on. The global ForeverGPS
-- exists for key bindings and the addon compartment; nothing else reaches in.
local ADDON, FG = ...
ForeverGPS = FG
FG.ADDON = ADDON

local Meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
FG.VERSION = Meta and Meta(ADDON, "Version") or "?"
FG.ART = "Interface\\AddOns\\" .. ADDON .. "\\Art\\"

local function Report(err) return geterrorhandler()(err) end

-- Runs fn; an error reaches the error frame and the caller carries on.
function FG.Try(fn, ...)
    return xpcall(fn, Report, ...)
end

-- Topics inside the addon. Listeners never break each other.
local topics = {}
function FG.On(topic, fn)
    local list = topics[topic]
    if not list then
        list = {}
        topics[topic] = list
    end
    list[#list + 1] = fn
end

function FG.Emit(topic, ...)
    local list = topics[topic]
    for i = 1, list and #list or 0 do FG.Try(list[i], ...) end
end

-- Client events, one frame for all of them.
local handlers = {}
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    for i = 1, list and #list or 0 do FG.Try(list[i], ...) end
end)

-- An event this client does not know raises; it is then simply never heard.
function FG.OnEvent(event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        if not pcall(frame.RegisterEvent, frame, event) then FG.missingEvents = (FG.missingEvents or 0) + 1 end
    end
    list[#list + 1] = fn
end

function FG.After(delay, fn)
    C_Timer.After(delay, function() FG.Try(fn) end)
end

function FG.Print(text)
    print("|cffe6b450" .. FG.L["ADDON_NAME"] .. ":|r " .. tostring(text))
end
