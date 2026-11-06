-- The design tokens: every color and text size the interface uses, in one place.
-- A theme swaps the colors; widgets repaint themselves through Theme.Paint.
local _, FG = ...
local Theme = {}
FG.Theme = Theme

-- Each color is { r, g, b } or { r, g, b, a }.
local function Hex(hex, a)
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return { r, g, b, a or 1 }
end

Theme.PALETTES = {
    obsidian = {
        window = Hex("0E1116", 0.97), raised = Hex("161B22"), card = Hex("1B212A"), cardHover = Hex("242C37"),
        field = Hex("0A0D11"), line = Hex("2C3542"), lineStrong = Hex("3E4A5B"),
        text = Hex("F1F3F6"), textDim = Hex("A7B1BF"), textFaint = Hex("6F7B8B"), onAccent = Hex("17120A"),
        accent = Hex("E6B450"), accentHover = Hex("F2C873"), route = Hex("58B4FF"), routeSoft = Hex("58B4FF", 0.16),
        good = Hex("45D69B"), warn = Hex("F2B24C"), danger = Hex("FF6B5E"), dangerSoft = Hex("FF6B5E", 0.16),
        hud = Hex("0E1116", 0.86), glyph = Hex("C8D0DB"),
    },
    glacier = {
        window = Hex("0D1622", 0.97), raised = Hex("132033"), card = Hex("18283E"), cardHover = Hex("20344F"),
        field = Hex("09111B"), line = Hex("294058"), lineStrong = Hex("3C5A78"),
        text = Hex("EEF5FB"), textDim = Hex("A5B9CC"), textFaint = Hex("6C8298"), onAccent = Hex("08151F"),
        accent = Hex("6FD3E8"), accentHover = Hex("93E2F2"), route = Hex("7FB6FF"), routeSoft = Hex("7FB6FF", 0.16),
        good = Hex("56DDB0"), warn = Hex("F4C15C"), danger = Hex("FF7A70"), dangerSoft = Hex("FF7A70", 0.16),
        hud = Hex("0D1622", 0.86), glyph = Hex("C6D6E5"),
    },
    parchment = {
        window = Hex("F3ECDC", 0.98), raised = Hex("EADFC8"), card = Hex("FBF6EA"), cardHover = Hex("F1E7D2"),
        field = Hex("FFFCF4"), line = Hex("D5C7A9"), lineStrong = Hex("B9A77F"),
        text = Hex("2B2317"), textDim = Hex("5F5340"), textFaint = Hex("8A7D66"), onAccent = Hex("FFF9EC"),
        accent = Hex("9A5B13"), accentHover = Hex("B46D1B"), route = Hex("1F6FB2"), routeSoft = Hex("1F6FB2", 0.14),
        good = Hex("1E8C5B"), warn = Hex("A9720F"), danger = Hex("BE3A2C"), dangerSoft = Hex("BE3A2C", 0.12),
        hud = Hex("F3ECDC", 0.92), glyph = Hex("5F5340"),
    },
}

-- The current colors. This table's identity never changes, so widgets may hold it.
Theme.C = {}

-- Inter, as EasyFind ships it, for clean small text; the client's font where
-- Inter has no glyphs.
local FONT_DIR = "Interface\\AddOns\\EasyFind\\Fonts\\"
local CJK = { koKR = true, zhCN = true, zhTW = true }

local function Face(file)
    if CJK[GetLocale()] then return STANDARD_TEXT_FONT end
    return FONT_DIR .. file
end

Theme.FONT = {
    regular = Face("Inter-Regular.ttf"),
    medium = Face("Inter-SemiBold.ttf"),
    bold = Face("Inter-Bold.ttf"),
}

-- Text styles: { face, size }.
Theme.TEXT = {
    caption = { "medium", 10 },
    small = { "regular", 11 },
    body = { "regular", 12 },
    label = { "medium", 12 },
    heading = { "medium", 13 },
    title = { "bold", 15 },
    display = { "bold", 22 },
}

local painters = {}

-- fn(C) now and whenever the theme changes.
function Theme.Paint(fn)
    painters[#painters + 1] = fn
    fn(Theme.C)
end

function Theme.Apply(name)
    local palette = Theme.PALETTES[name] or Theme.PALETTES.obsidian
    for key, value in pairs(palette) do Theme.C[key] = value end
    for i = 1, #painters do FG.Try(painters[i], Theme.C) end
    FG.Emit("theme:changed", name)
end

Theme.Apply("obsidian")

FG.On("loaded", function() Theme.Apply(FG.db.theme) end)
