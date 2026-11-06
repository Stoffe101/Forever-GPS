-- The ways of travel wear the map's own glyphs on every client
-- (2026-10-28): retail's square icons (an airship achievement, the
-- Dalaran portal spell, a gear) and classic's stand-ins are gone. Each
-- glyph is in every client's current build (wago.tools
-- UiTextureAtlasMember: retail, Forever, Mists, Anniversary, Era).
local H = require("Harness")

local function Read(rel)
    local f = assert(io.open(H.Path(rel), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

local tests = {}


function tests.theRouteTakesTheMapsGlyphs()
    local preview = Read("Preview.lua")
    H.assertTrue(preview:find('skyship = "skyship"') ~= nil and preview:find('portal = "portal"') ~= nil,
        "a skyship and a portal step take their own symbols")
    H.assertTrue(preview:find("PortalAtlas") == nil, "the portal symbol comes from the category table")
end

local pass, fail, failures = H.runSuite("TransportIcons", tests)
return { pass = pass, fail = fail, failures = failures }
