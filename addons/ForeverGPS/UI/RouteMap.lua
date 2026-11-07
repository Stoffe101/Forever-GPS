-- A map of our own. Showing a place on the game's world map means opening it and turning
-- it from addon code, and that leaves the map's id tainted for every refresh that reads
-- it (docs/TAINT.md). This draws the same art in a frame of ours, so a preview works in a
-- fight, and the game's map is only ever moved by the player. MapPreview draws on it just
-- as it draws on a map the player opened.
local FG = ForeverGPS
local RouteMap = {}
FG.RouteMap = RouteMap

local Kit, Theme = FG.Kit, FG.Theme
local L = FG.L

local mmin, mceil = math.min, math.ceil

local WIDTH, HEIGHT, HEADER = 780, 560, 34
local PAD = 8
local ASPECT = 1.5          -- the game's map art is 3:2, and an unknown map is drawn so

local f, canvas, art
local tiles = {}
local mapID

-- ==== the art ===============================================================

local function Tile(i)
    local t = tiles[i]
    if not t then
        t = art:CreateTexture(nil, "BACKGROUND", nil, 1)
        tiles[i] = t
    end
    return t
end

-- The first layer's tiles, row by row as the game's own detail layer lays them. The last
-- row and column run past the art, so each is cut to the part that is map.
local function DrawArt()
    local layers = mapID and C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
    local layer = layers and layers[1]
    local textures = layer and C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(mapID, 1)
    local used = 0
    if textures and layer.layerWidth > 0 and layer.tileWidth > 0 and layer.tileHeight > 0 then
        local cols = mceil(layer.layerWidth / layer.tileWidth)
        local rows = mceil(layer.layerHeight / layer.tileHeight)
        local sx = canvas:GetWidth() / layer.layerWidth
        local sy = canvas:GetHeight() / layer.layerHeight
        for row = 1, rows do
            for col = 1, cols do
                local file = textures[(row - 1) * cols + col]
                if file then
                    used = used + 1
                    local t = Tile(used)
                    local tw = mmin(layer.tileWidth, layer.layerWidth - (col - 1) * layer.tileWidth)
                    local th = mmin(layer.tileHeight, layer.layerHeight - (row - 1) * layer.tileHeight)
                    t:SetTexture(file, nil, nil, "TRILINEAR")
                    t:SetTexCoord(0, tw / layer.tileWidth, 0, th / layer.tileHeight)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", art, "TOPLEFT", (col - 1) * layer.tileWidth * sx, -(row - 1) * layer.tileHeight * sy)
                    t:SetSize(tw * sx, th * sy)
                    t:Show()
                end
            end
        end
    end
    for i = used + 1, #tiles do tiles[i]:Hide() end
    return used
end

local function Fit()
    local w = f:GetWidth() - PAD * 2
    local h = f:GetHeight() - HEADER - PAD * 2
    local cw = mmin(w, h * ASPECT)
    canvas:SetSize(cw, cw / ASPECT)
    canvas:ClearAllPoints()
    canvas:SetPoint("TOP", f, "TOP", 0, -(HEADER + PAD + (h - cw / ASPECT) / 2))
end

-- ==== the window ============================================================

local function Build()
    f = CreateFrame("Frame", "ForeverGPSRouteMap", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:Hide()
    FG.Bridge.CloseOnEscape(f)
    f.back = Kit.Shape(f, 12, "BACKGROUND", 0)
    f.edge = Kit.Shape(f, 12, "BACKGROUND", 7, true)
    f.head = CreateFrame("Frame", nil, f)
    f.head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.head:SetHeight(HEADER)
    f.head:EnableMouse(true)
    f.head:RegisterForDrag("LeftButton")
    f.head:SetScript("OnDragStart", function() f:StartMoving() end)
    f.head:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.title = Kit.Text(f.head, "label", "text")
    f.title:SetPoint("LEFT", f.head, "LEFT", 14, 0)
    f.close = Kit.IconButton(f.head, "close", 10, L["ROUTEMAP_CLOSE"], function() RouteMap.Hide() end)
    f.close:SetPoint("RIGHT", f.head, "RIGHT", -6, 0)
    canvas = CreateFrame("Frame", "ForeverGPSRouteMapCanvas", f)
    art = CreateFrame("Frame", nil, canvas)
    art:SetAllPoints(canvas)
    f.ground = Kit.Shape(art, 2, "BACKGROUND", 0)
    Theme.Paint(function(c)
        f.back:SetColor(c.window)
        f.edge:SetColor(c.line)
        f.ground:SetColor(c.hover or c.line)
    end)
    f:HookScript("OnShow", function() FG.Emit("routemap:shown", true) end)
    f:HookScript("OnHide", function() FG.Emit("routemap:shown", false) end)
    Fit()
end

local function Name(id)
    local info = id and C_Map.GetMapInfo(id)
    return info and info.name or nil
end

-- ==== doors =================================================================

-- Shows a map, and that map's art if it was showing another.
function RouteMap.Show(id)
    if not f then Build() end
    f:SetScale(FG.Settings.WindowScale())
    if id and id ~= mapID then
        mapID = id
        DrawArt()
    end
    f.title:SetText(L["ROUTEMAP_TITLE_FMT"]:format(Name(mapID) or L["ROUTEMAP_TITLE"]))
    f:Show()
    return true
end

function RouteMap.SetMap(id)
    if f and f:IsShown() then RouteMap.Show(id) end
end

function RouteMap.Hide()
    if f then f:Hide() end
end

function RouteMap.Shown() return f ~= nil and f:IsShown() end
function RouteMap.MapID() return mapID end
function RouteMap.Canvas() return canvas end
function RouteMap.Frame() return f end

-- What there is to draw: what /fgps diag and a test can read.
function RouteMap.Tiles()
    local n = 0
    for i = 1, #tiles do
        if tiles[i]:IsShown() then n = n + 1 end
    end
    return n
end
